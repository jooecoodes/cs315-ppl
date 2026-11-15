# How to Use

This guide walks you through running MiniCalc from scratch — assuming you've never installed a compiler or any of the four target languages (C, C++, Racket/Scheme, SWI-Prolog).

You only need **Docker Desktop**. The container has all four toolchains inside, and `run.sh` / `run.bat` handles everything — including entering the container for you.

## What you need

- Docker Desktop (Windows / macOS) or Docker Engine (Linux)
- A terminal (Terminal.app on macOS, cmd/PowerShell on Windows, any shell on Linux)
- Nothing else

You do **not** need `gcc`, `g++`, `racket`, or `swipl` installed on your machine. The Docker image ships with all four.

---

## Step 1 — Get the project files

Pick one:

### Option A — Download as ZIP (no tools required)

1. Open the project on GitHub
2. Click the green **Code** button → **Download ZIP**
3. Extract it somewhere easy to find (e.g. Desktop)
4. Open the extracted folder — you should see:

```
run.sh      run.bat      Dockerfile
spec.txt    tests.txt    expected.txt
c/  cpp/  scheme/  prolog/
```

### Option B — Clone with git (if git is installed)

```bash
git clone <repo-url>
cd mini-calc
```

---

## Step 2 — Install Docker Desktop

### Windows / macOS

1. Go to [https://www.docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop)
2. Download and install Docker Desktop
3. Launch it and wait until the whale icon stops animating — that means the daemon is ready
4. **Windows note:** Docker Desktop defaults to Linux containers, which is what you want. If you ever see `unknown instruction: RUN` when building, switch back: right-click the tray icon → "Switch to Linux containers…"

### Linux (Ubuntu / Debian)

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"
# log out, log back in, then verify:
docker --version
```

---

## Step 3 — Open a terminal in the project folder

| OS | How |
|---|---|
| Windows | Open the project folder in Explorer → click the address bar → type `cmd` → press Enter |
| macOS | Right-click the folder → Services → New Terminal at Folder |
| Linux | `cd` into the folder in your terminal |

Confirm you're in the right place:

```bash
ls      # macOS / Linux
dir     # Windows
```

You should see `run.sh`, `run.bat`, `tests.txt`, `expected.txt`, and the four implementation folders.

---

## Step 4 — Run the tests

### Windows

```bat
run.bat
```

### macOS / Linux

```bash
chmod +x run.sh    # first time only
./run.sh
```

First run takes 1–3 minutes — Docker builds the image (installs gcc, g++, Racket, SWI-Prolog). Every run after that is instant.

> **How the magic works:** you run `./run.sh` on your machine. If the four toolchains aren't installed locally, `run.sh` automatically re-execs itself inside the `minicalc` Docker container, runs there, and hands the output back to you. You never type `docker run` yourself. All you have to do is have Docker running.

---

## Step 5 — See the results

You should see:

```
  MiniCalc
  file: tests.txt  (13 statements)
  ──────────────────────────────────────────
  C        ✓ PASS
  C++      ✓ PASS
  Scheme   ✓ PASS
  Prolog   ✓ PASS
  ──────────────────────────────────────────
  4/4 implementations match expected.txt
```

All four PASS = everything works.

---

## Try your own test file

Create `my_tests.txt` in the same folder — one expression per line:

```
echo 1 + 2 * 3
echo let x = 5 in x * x
echo -10/3
echo let x = 1 in (let x = 2 in x) + x
```

Run it:

```bash
./run.sh my_tests.txt      # macOS / Linux
run.bat my_tests.txt       # Windows
```

The script runs all four implementations against your file and **cross-checks them**:

- **All four agree** → your file is valid across all four paradigms
- **One differs** → that one has a bug. Add `--verbose` to see exactly which lines differ

Example output:

```
  MiniCalc
  file: my_tests.txt  (4 statements)
  ──────────────────────────────────────────
  C        ✓
  C++      ✓
  Scheme   ✓
  Prolog   ✓
  ──────────────────────────────────────────
  All four implementations agree.
```

---

## Run a one-off expression (no file needed)

The `-e` flag lets you evaluate a single expression without creating a file.

```bash
./run.sh -e "echo 1 + 2 * 3"
```

```
  MiniCalc
  expr:
    echo 1 + 2 * 3
  ──────────────────────────────────────────
  C        ✓
  C++      ✓
  Scheme   ✓
  Prolog   ✓
  ──────────────────────────────────────────
  All four implementations agree.
  output:
    7
```

Combine with a single-implementation flag for raw output:

```bash
./run.sh c -e "echo let x = 5 in x * x"       → 25
./run.sh scheme -e "echo -10/3"                → -3
./run.sh prolog -e "echo let x = 1 in (let x = 2 in x) + x"   → 3
```

Stack multiple expressions:

```bash
./run.sh -e "echo 1 + 2" -e "echo 3 * 4" -e "echo 10/3"
```

Test error handling and the "silent bare expression" rule:

```bash
./run.sh -e "echo 1/0"       → ERROR:DIV0
./run.sh -e "echo x"         → ERROR:UNBOUND
./run.sh -e "5"              → (no output — bare expressions don't print)
```

> **Windows note:** in `cmd.exe`, `%` is a special character. If your expression contains modulo, write it as `%%`:
>
> ```bat
> run.bat c -e "echo 10 %% 3"
> ```
>
> On macOS/Linux, use `%` normally: `./run.sh c -e "echo 10 % 3"`.

---

## Run a single implementation

Useful when you want raw output for one language (pipes, diffing, debugging):

```bash
./run.sh c                 # C only, against tests.txt
./run.sh cpp               # C++ only
./run.sh scheme            # Scheme only
./run.sh prolog            # Prolog only

./run.sh c my_tests.txt    # C only, against my_tests.txt
```

Output is raw — pipe-friendly:

```bash
./run.sh c -e "echo 1+1" | diff - <(echo 2) && echo "C agrees"
```

---

## Full command reference

| Command | What it does |
|---|---|
| `./run.sh` | Verify all four against `tests.txt` |
| `./run.sh my_tests.txt` | Cross-check all four against your file |
| `./run.sh -e "echo 1 + 2"` | Cross-check all four against a single expression |
| `./run.sh c` | Run C only against `tests.txt` |
| `./run.sh c my_tests.txt` | Run C only against your file |
| `./run.sh c -e "echo 1 + 2"` | Run C only against a one-off expression |
| `./run.sh cpp` / `scheme` / `prolog` | Same as above, for each language |
| `./run.sh --verbose` | Show diffs on failure |
| `./run.sh build` | Rebuild the C and C++ binaries |
| `./run.sh clean` | Delete `build/` and `build-docker/` |
| `./run.sh --help` | Print usage |

Argument order doesn't matter — `./run.sh c my.txt` and `./run.sh my.txt c` are equivalent.

---

## Windows: `run.bat` vs `./run.sh`

On Windows, `run.sh` won't work in `cmd` or PowerShell — those shells don't understand bash. Use `run.bat` instead. It forwards everything to `run.sh` inside the container.

| Shell | How to call |
|---|---|
| `cmd.exe` (double-click "Command Prompt" or Win+R → `cmd`) | `run.bat c -e "echo 1 + 2"` |
| PowerShell (Win+X → "Terminal") | `.\run.bat c -e "echo 1 + 2"` — note the `.\`, not `./` |
| Double-click in Explorer | Runs `run.bat` with no args → default verify mode |
| Drag-and-drop a `.txt` onto `run.bat` | Same as `run.bat myfile.txt` |
| Git Bash / WSL | Use `./run.sh` instead — Git Bash understands it |

All `-e` expressions and flags work identically through `run.bat`. The only Windows-specific rule is that `%` becomes `%%` inside expressions (`cmd.exe` eats `%` otherwise).

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `docker: command not found` | Docker Desktop isn't installed, or your terminal was opened before installation. Close all terminals, open a new one, retry. |
| `Cannot connect to the Docker daemon` | Docker Desktop is installed but not running. Launch it, wait for the whale icon, retry. |
| `permission denied: ./run.sh` | Run `chmod +x run.sh` once, then retry. |
| `racket: command not found` (on host) | You're running `run.sh` on a machine missing Racket. The auto-Docker block should have caught this — if it didn't, ensure Docker is running, then retry. |
| `GLIBC_2.xx not found` | A binary was built for the wrong environment (e.g. on host, then moved into a container with older glibc). Run `./run.sh clean`, then retry — it rebuilds for the current environment. |
| `bash: ./run.sh: /bin/bash^M: bad interpreter` | `run.sh` has Windows (CRLF) line endings. In VS Code, click the CRLF in the bottom-right corner → change to LF → save. Or run `sed -i 's/\r$//' run.sh` once. |
| Window closes instantly on Windows (double-click) | Open `cmd` first, then type `run.bat` from there — that keeps the window open. |
| Window closes instantly after drag-drop | Same fix — open `cmd`, `cd` to the folder, then `run.bat myfile.txt`. |
| Anything looks broken | Run `./run.sh --verbose` (or `run.bat --verbose`) for a line-by-line diff. |

---

## How it works under the hood (optional reading)

You never need to know this to use MiniCalc — but if you're curious:

1. `run.sh` first checks if it's inside a Docker container (looks for `/.dockerenv`).
2. If inside a container, it just runs the four implementations directly. Done.
3. If on the host, it checks for `cc`, `g++`, `racket`, `swipl`. If all four exist, it runs locally. Fast, no Docker involved.
4. If any are missing, it re-launches itself inside the `minicalc` Docker container:

```bash
docker run --rm -v "$PWD:/app" -w /app minicalc bash ./run.sh "$@"
```

Same script, same arguments, now with all four toolchains available. When it finishes, the container is deleted (`--rm`). You get the output back on your terminal.

C and C++ binaries are written to `build/` on the host, `build-docker/` inside the container — kept separate so a binary built for one environment never accidentally runs in the other (which would cause `GLIBC_2.xx not found` errors).

That's the entire trick. One script, one command, works everywhere Docker works.

---

## File format for your test files

One statement per line. Blank lines are ignored. Same grammar as `spec.txt`:

```
echo 1 + 2 * 3
echo let x = 5 in x * x
echo -10/3
echo let x = 1 in (let x = 2 in x) + x
```

**Rules:**

- `echo <expr>` → prints the value
- bare expression (no `echo`) → evaluated, output discarded
- Error in any line → prints `ERROR:PARSE` / `ERROR:UNBOUND` / `ERROR:DIV0`, continues to next line
- Environment resets at the start of each line — nothing carries over
- No loops, no user-defined functions, no booleans, no strings, no floats

See `spec.txt` for the full language.

---

## One-line summary

```bash
./run.sh                # verify everything (default tests)
./run.sh my.txt         # check any file across all four paradigms
./run.sh -e "echo 1+2"  # check a one-off expression
./run.sh c              # inspect just the C implementation
```

On Windows, replace `./run.sh` with `run.bat` (or `.\run.bat` in PowerShell).
