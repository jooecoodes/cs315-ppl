# MiniCalc — Language Specification (frozen)

This document defines the MiniCalc language. All four implementations
(C, C++, Scheme, Prolog) must follow this spec exactly. The output of
every implementation must match byte-for-byte on the shared test file.

**Do not modify this spec. Do not add features. If something is unclear,
ask before guessing.**

---

## 1. WHAT MINICALC IS

MiniCalc is a mini expression interpreter. It reads a plain-text file
(one statement per line), evaluates each statement, and prints only
what `echo` asks it to print.

It has three keywords: `let`, `in`, `echo`.

It has **NO**:

- user-defined functions
- recursion
- loops
- assignment statements (no `x = 5` on its own)
- booleans, comparisons, conditionals
- strings, floats, lists

Values are integers only.

---

## 2. GRAMMAR (frozen)

```
program   -> statement EOF
statement -> "echo" expr | expr
expr      -> "let" IDENT "=" expr "in" expr
           | addExpr
addExpr   -> mulExpr (("+" | "-") mulExpr)*
mulExpr   -> unary (("*" | "/" | "%") unary)*
unary     -> "-" unary | primary
primary   -> INT | IDENT | "(" expr ")"
```

**Precedence, low to high:**

`let`  →  `+` `-`  →  `*` `/` `%`  →  unary `-`  →  atoms

---

## 3. ECHO IS A STATEMENT, NOT A FUNCTION

`echo` can appear **ONLY** at the start of a line. It cannot appear
inside an expression.

```
echo echo 1          -> ERROR:PARSE
let x = echo 5 in x  -> ERROR:PARSE
```

This is a grammar guarantee, not a runtime check. No nesting is
possible because the grammar has no rule that produces `echo` inside
`expr`.

A bare expression (one without `echo`) is still evaluated, but its
value is discarded — nothing is printed. Errors still print.

---

## 4. SEMANTICS

### Values

Integers only, signed. Implementations should use a 64-bit signed
integer type where the language allows (C: `long`; C++: `long long`;
Scheme: exact integer; Prolog: integer).

### Arithmetic

| Operator | Meaning |
|----------|---------|
| `+` | addition |
| `-` | subtraction |
| `*` | multiplication |
| `/` | integer division, **TRUNCATES TOWARD ZERO** |
| `%` | remainder, **SIGN FOLLOWS THE DIVIDEND** |

**Division examples:**

```
10/3 = 3
-10/3 = -3
10/-3 = -3
-10/-3 = 3
```

**Remainder examples:**

```
10%3 = 1
-10%3 = -1
10%-3 = 1
-10%-3 = -1
```

**Note for non-C implementations:** many languages' `/` and `%` do **NOT**
follow these rules. Specifically:

- **Python:** use `int(a/b)` and `a - int(a/b)*b`, not `//` and `%`
- **Haskell:** use `quot` and `rem`, not `div` and `mod`
- **Scheme:** use `quotient` and `remainder`, not `modulo`
- **Prolog:** use `//` and `rem`, not `mod`

C and C++ already do the right thing natively.

### Unary minus

`- expr` negates the value. Binds tighter than `*` and `/`.

### let

```
let x = E1 in E2
```

Evaluate `E1`, bind the name `x` to the result, evaluate `E2` in the
extended environment, then discard the binding.

Shadowing is allowed and follows normal scoping:

```
let x = 1 in let x = 2 in x                   -> 2
let x = 1 in (let x = 2 in x) + x             -> 3
let x = 5 in let x = x + 1 in x               -> 6
```

The right side of a `let` binding sees the **OUTER** environment,
not the new binding. That is why the third example gives 6 (the
inner `x + 1` uses the outer `x = 5`, then binds inner `x = 6`).

### Identifiers

Start with a letter or underscore. Continue with letters, digits,
or underscores. Case-sensitive. `let`, `in`, and `echo` are
reserved words and cannot be used as identifiers.

### Integers

Written in decimal, no leading `+`, no leading zeros required.
Negative literals do not exist — `-5` is unary minus applied to `5`.

---

## 5. ERROR CODES (frozen strings)

When a statement cannot be evaluated, print exactly:

| Code | Meaning |
|------|---------|
| `ERROR:PARSE` | lexing failed, or the statement does not parse |
| `ERROR:UNBOUND` | a variable is used but not bound by any enclosing `let` |
| `ERROR:DIV0` | division or modulo by zero |

Nothing else. No exceptions escaping to the shell, no stack traces,
no error messages of any other form. The string must match exactly —
any deviation fails the test diff.

Errors are per line. An error on one line does **NOT** stop the program;
the next line is processed normally.

---

## 6. I/O CONTRACT

### Input

A plain-text file. One statement per line. Blank lines (lines that
are entirely whitespace) are skipped and produce no output.

The file path is passed as the first command-line argument.
If no argument is given, read from standard input.

### Output

Standard output only. One line per input line that is not blank,
in this form:

- If the line is `echo <expr>` and evaluation succeeds:  
  one line containing the integer value, e.g. `42`
- If the line is a bare expression and evaluation succeeds:  
  **NO** output line at all (value is discarded)
- If the line fails for any reason:  
  one line: `ERROR:PARSE` / `ERROR:UNBOUND` / `ERROR:DIV0`

No prompts. No banners. No logs. No blank lines between results.
No trailing spaces. Use `\n` line endings.

### Exit code

Always `0`. Errors are per-line results, not program failures.

---

## 7. PER-LINE MEMORY

Every line starts fresh. The environment is empty at the start of
each line. The tokenizer state is fresh at the start of each line.
Nothing carries over from the previous line.

```
echo let x = 5 in x       -> 5
echo x                    -> ERROR:UNBOUND   (x did not survive)
```

This is a deliberate design choice. It makes each line a
self-contained test, and lets you reorder or delete lines without
affecting other lines.

---

## 8. TESTS (acceptance criteria)

Two shared files are provided:

- `tests.txt` — one statement per line, the input
- `expected.txt` — the exact expected output, one line per input line

An implementation is correct if and only if this command produces
no differences (using the build command for your language):

```bash
./minicalc tests.txt | diff - expected.txt
```

Every implementation must pass this same diff. There is no partial
credit — the output must match byte-for-byte.

### Sample tests (illustrative)

| INPUT | EXPECTED OUTPUT |
|-------|-----------------|
| `echo 1 + 2 * 3` | `7` |
| `echo (1+2)*3` | `9` |
| `echo -10/3` | `-3` |
| `echo -10%3` | `-1` |
| `echo let x = 1 in let x = 2 in x` | `2` |
| `echo let x = 1 in (let x = 2 in x)+x` | `3` |
| `echo x` | `ERROR:UNBOUND` |
| `echo 1/0` | `ERROR:DIV0` |
| `echo 1 +` | `ERROR:PARSE` |
| `5` | *(no output line)* |

(The full `tests.txt` is provided separately and is the authoritative
test set. The examples above are just to illustrate the contract.)

---

## 9. WHAT NOT TO DO

- Do not extend the grammar.
- Do not add keywords, comments, strings, floats, or booleans.
- Do not use the host language's own `eval` or built-in parser.
- Do not print anything except what is defined above.
- Do not read the source of another implementation.
- Do not let environment or tokenizer state carry across lines.

---

## 10. SHARED FILES

Each implementation receives exactly these files:

- `spec.txt` — this document
- `tests.txt` — the input test file
- `expected.txt` — the expected output

These are the **ONLY** shared files. Source code is **NOT** shared between
implementations. Each dev builds independently from this spec.
