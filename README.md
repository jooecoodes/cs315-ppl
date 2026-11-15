# MiniCalc

A tiny expression interpreter written four times — in **C**, **C++**, **Scheme**, and **Prolog**.

One language. Four paradigms. Same output, byte for byte.

```
echo 1 + 2 * 3
echo let x = 5 in x * x
echo -10 / 3
```

→ `7` · `25` · `-3`

---

## What it is

MiniCalc evaluates integer expressions with `let`-bindings and prints results via `echo`.

No functions. No loops. No floats. Just arithmetic, scoping, and three error codes:

| Code | Meaning |
|------|---------|
| `ERROR:PARSE` | Lexing or syntax failure |
| `ERROR:UNBOUND` | Variable used without a binding |
| `ERROR:DIV0` | Division or modulo by zero |

Every line starts with a clean environment. Nothing carries over.

---

## Quick start

You only need **Docker Desktop**.

```bash
# macOS / Linux
chmod +x run.sh
./run.sh

# Windows
run.bat
```

All four implementations run against the shared test suite and must match `expected.txt` exactly.

---

## Learn more

- **[HOW_TO_USE.md](HOW_TO_USE.md)** — full setup, custom tests, one-off expressions, troubleshooting
- **[SPEC.md](SPEC.md)** — frozen language specification

---

## Layout

```
c/          C implementation
cpp/        C++ implementation
scheme/     Scheme (Racket) implementation
prolog/     Prolog (SWI) implementation
tests.txt   Shared test input
expected.txt  Exact expected output
run.sh / run.bat   Cross-platform runner
```

---

Four languages. One contract. No surprises.
