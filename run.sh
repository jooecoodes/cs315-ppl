#!/usr/bin/env bash
# MiniCalc — run all four implementations against a test file or expression.
#
# Usage:
#   ./run.sh                        run default tests.txt, diff vs expected.txt
#   ./run.sh my_tests.txt           run your file, cross-check the 4 impls
#   ./run.sh -e "echo 1 + 2 * 3"    run a one-off expression
#   ./run.sh c -e "echo 1 + 2 * 3"  same, but C only
#   ./run.sh c|cpp|scheme|prolog    run a single implementation
#   ./run.sh build                  compile C and C++ into build/
#   ./run.sh clean                  remove build directories
#   ./run.sh --verbose ...          show diffs on failure
#   ./run.sh --help
#
set -euo pipefail
cd "$(dirname "$0")"

ORIG_ARGS=("$@")

# ─── argument parsing ────────────────────────────────────────────────────
MODE="all"
VERBOSE=0
TESTS=""
EXPR=""
EXPR_MODE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--verbose) VERBOSE=1; shift ;;
        -h|--help)    sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -e|--expr)
            if [[ $# -lt 2 ]]; then
                echo "error: -e/--expr requires an argument" >&2
                exit 2
            fi
            if [[ -n "$EXPR" ]]; then
                EXPR=$(printf "%s\n%s" "$EXPR" "$2")
            else
                EXPR="$2"
            fi
            EXPR_MODE=1
            shift 2
            ;;
        build|clean|c|cpp|scheme|prolog|all) MODE="$1"; shift ;;
        -*) echo "unknown flag: $1" >&2; exit 2 ;;
        *)  TESTS="$1"; shift ;;
    esac
done
TESTS="${TESTS:-tests.txt}"

# ─── auto-Docker: if on host and tools are missing, re-exec inside the container ───
CONTAINER_IMAGE=minicalc
CONTAINER_DIR=/app

if [[ ! -f /.dockerenv ]]; then
    missing=()
    for tool in cc g++ racket swipl; do
        command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
    done

    if (( ${#missing[@]} > 0 )); then
        command -v docker >/dev/null 2>&1 \
            || { echo "missing tools: ${missing[*]} — and Docker is not installed." >&2; exit 1; }
        docker info >/dev/null 2>&1 \
            || { echo "missing tools: ${missing[*]} — and Docker daemon isn't running." >&2; exit 1; }

        if ! docker image inspect "$CONTAINER_IMAGE" >/dev/null 2>&1; then
            echo "  building $CONTAINER_IMAGE (first run)..." >&2
            docker build -t "$CONTAINER_IMAGE" . \
                || { echo "docker build failed" >&2; exit 1; }
        fi

        exec docker run --rm \
            -v "$PWD:$CONTAINER_DIR" -w "$CONTAINER_DIR" \
            "$CONTAINER_IMAGE" bash ./run.sh "${ORIG_ARGS[@]}"
    fi
fi

# ─── expr mode: write EXPR to a temp file so the rest of the pipeline is unchanged ───
TMPFILE=""
cleanup() { [[ -n "$TMPFILE" ]] && rm -f "$TMPFILE" || true; }
trap cleanup EXIT

if [[ $EXPR_MODE -eq 1 ]]; then
    TMPFILE=$(mktemp "${TMPDIR:-/tmp}/minicalc.XXXXXX")
    printf "%s\n" "$EXPR" > "$TMPFILE"
    TESTS="$TMPFILE"
fi

# ─── source paths ────────────────────────────────────────────────────────
SRC_C=c/minicalc.c
SRC_CPP=cpp/minicalc.cpp
SRC_SCHEME=scheme/minicalc.rkt
SRC_PROLOG=prolog/minicalc.pro

if [[ -f /.dockerenv ]]; then
    BUILD=build-docker
else
    BUILD=build
fi
BIN_C=$BUILD/minicalc_c
BIN_CPP=$BUILD/minicalc_cpp

# ─── colors ──────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'
    D=$'\033[2m';  B=$'\033[1m';  Z=$'\033[0m'
else
    G=; R=; Y=; D=; B=; Z=
fi

die() { echo "${R}error:${Z} $*" >&2; exit 1; }

# ─── build ───────────────────────────────────────────────────────────────
build_c()   { mkdir -p "$BUILD"; cc  -std=c99   -O2 -Wall -Wextra -o "$BIN_C"   "$SRC_C"; }
build_cpp() { mkdir -p "$BUILD"; g++ -std=c++17 -O2 -Wall -Wextra -o "$BIN_CPP" "$SRC_CPP"; }
build_all() { build_c; build_cpp; }
clean()     { rm -rf build build-docker; echo "  removed build/ and build-docker/"; }

ensure_built() {
    mkdir -p "$BUILD"
    [[ -x "$BIN_C"   && "$BIN_C"   -nt "$SRC_C"   ]] || build_c
    [[ -x "$BIN_CPP" && "$BIN_CPP" -nt "$SRC_CPP" ]] || build_cpp
}

# ─── run implementations ─────────────────────────────────────────────────
run_c()      { "$BIN_C"   "$TESTS"; }
run_cpp()    { "$BIN_CPP" "$TESTS"; }
run_scheme() { racket "$SRC_SCHEME" "$TESTS"; }
run_prolog() { swipl -q -g "main(['$TESTS']),halt" -t halt "$SRC_PROLOG"; }

# ─── early-exit modes ────────────────────────────────────────────────────
case "$MODE" in
    build) build_all; echo "  built: $BIN_C"; echo "  built: $BIN_CPP"; exit 0 ;;
    clean) clean; exit 0 ;;
esac

[[ -f "$TESTS" ]] || die "test file not found: $TESTS"
ensure_built

# ─── single-implementation modes ─────────────────────────────────────────
case "$MODE" in
    c)      run_c ;;
    cpp)    run_cpp ;;
    scheme) run_scheme ;;
    prolog) run_prolog ;;
esac
[[ "$MODE" != "all" ]] && exit 0

# ─── run all four, capture output ────────────────────────────────────────
NAMES=(C "C++" Scheme Prolog)
OUTPUTS=(
    "$(run_c      2>&1)"
    "$(run_cpp    2>&1)"
    "$(run_scheme 2>&1)"
    "$(run_prolog 2>&1)"
)

NONBLANK=$(grep -cve '^[[:space:]]*$' "$TESTS" || true)
echo
echo "  ${B}MiniCalc${Z}"
if [[ $EXPR_MODE -eq 1 ]]; then
    echo "  ${D}expr:${Z}"
    printf "%s\n" "$EXPR" | sed 's/^/    /'
else
    echo "  ${D}file:${Z} $TESTS  ${D}($NONBLANK statements)${Z}"
fi
echo "  ──────────────────────────────────────────"

if [[ "$TESTS" == "tests.txt" && -f expected.txt ]]; then
    EXPECTED="$(cat expected.txt)"
    PASS=0
    for i in 0 1 2 3; do
        if [[ "${OUTPUTS[$i]}" == "$EXPECTED" ]]; then
            printf "  %-8s ${G}✓ PASS${Z}\n" "${NAMES[$i]}"
            PASS=$((PASS+1))
        else
            printf "  %-8s ${R}✗ FAIL${Z}\n" "${NAMES[$i]}"
            [[ $VERBOSE -eq 1 ]] && diff -u <(echo "$EXPECTED") <(echo "${OUTPUTS[$i]}") \
                | sed 's/^/           /' | head -15
        fi
    done
    echo "  ──────────────────────────────────────────"
    if [[ $PASS -eq 4 ]]; then
        echo "  ${G}${B}4/4 implementations match expected.txt${Z}"
    else
        echo "  ${Y}${PASS}/4 match${Z} — run with ${B}--verbose${Z} for details"
        exit 1
    fi
else
    REF="${OUTPUTS[0]}"
    AGREE=0
    for i in 0 1 2 3; do
        if [[ "${OUTPUTS[$i]}" == "$REF" ]]; then
            printf "  %-8s ${G}✓${Z}\n" "${NAMES[$i]}"
            AGREE=$((AGREE+1))
        else
            printf "  %-8s ${R}✗ differs${Z}\n" "${NAMES[$i]}"
            [[ $VERBOSE -eq 1 ]] && diff -u <(echo "$REF") <(echo "${OUTPUTS[$i]}") \
                | sed 's/^/           /' | head -15
        fi
    done
    echo "  ──────────────────────────────────────────"
    if [[ $AGREE -eq 4 ]]; then
        echo "  ${G}${B}All four implementations agree.${Z}"
        if [[ $EXPR_MODE -eq 1 ]]; then
            echo
            echo "  ${D}output:${Z}"
            if [[ -n "$REF" ]]; then
                printf "%s\n" "$REF" | sed 's/^/    /'
            else
                echo "    ${D}(no output — bare expressions don't print)${Z}"
            fi
        else
            echo "  ${D}Your file is consistent across all four paradigms.${Z}"
        fi
    else
        echo "  ${Y}Implementations disagree${Z} — see ${B}--verbose${Z}"
        echo "  ${D}One of them has a bug (or your expression uses unsupported syntax).${Z}"
        exit 1
    fi
fi
echo
