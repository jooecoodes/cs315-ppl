#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <errno.h>

#define MAX_LINE   65536
#define MAX_TOKENS 16384
#define ENV_MAX    16384

/* ---------- Tokens ---------- */

typedef enum {
    T_LET, T_ECHO, T_IN,
    T_PLUS, T_MINUS, T_STAR, T_SLASH, T_PERCENT, T_EQ,
    T_LPAREN, T_RPAREN,
    T_INT, T_IDENT,
    T_EOF
} TokKind;

typedef struct {
    TokKind kind;
    long    value;
    char    name[64];
} Token;

/* ---------- AST ---------- */

typedef enum {
    N_INT, N_VAR, N_NEG,
    N_ADD, N_SUB, N_MUL, N_DIV, N_MOD,
    N_LET
} NodeKind;

typedef struct Node {
    NodeKind kind;
    long     value;
    char     name[64];
    struct Node *a;
    struct Node *b;
} Node;

typedef struct {
    Token *toks;
    int    count;
    int    pos;
} Parser;

/* ---------- Environment / Result ---------- */

typedef struct {
    char name[64];
    long value;
} Binding;

typedef struct {
    Binding stack[ENV_MAX];
    int     top;
} Env;

typedef struct {
    int         is_err;
    const char *code;
    long        value;
} Result;

static Result eval(Node *n, Env *env);

static Result ok_result(long v) {
    Result r;
    r.is_err = 0;
    r.code   = NULL;
    r.value  = v;
    return r;
}

static Result err_result(const char *c) {
    Result r;
    r.is_err = 1;
    r.code   = c;
    r.value  = 0;
    return r;
}

/* ---------- Node lifecycle ---------- */

static void free_node(Node *n) {
    if (!n) return;
    free_node(n->a);
    free_node(n->b);
    free(n);
}

static Node *new_node(NodeKind k) {
    Node *n = calloc(1, sizeof *n);
    if (n) n->kind = k;
    return n;
}

/* ---------- Tokenizer ---------- */

static int tokenize(const char *s, Token *toks, int *out_count) {
    int n = 0;
    while (*s) {
        if (isspace((unsigned char)*s)) { s++; continue; }
        if (n >= MAX_TOKENS - 1) return 0;

        Token *t = &toks[n];
        t->value  = 0;
        t->name[0] = 0;

        if (*s >= '0' && *s <= '9') {
            char *end;
            errno = 0;
            long v = strtol(s, &end, 10);
            if (errno == ERANGE) return 0;
            t->kind  = T_INT;
            t->value = v;
            n++;
            s = end;
            continue;
        }

        if (isalpha((unsigned char)*s) || *s == '_') {
            int i = 0;
            while (isalnum((unsigned char)*s) || *s == '_') {
                if (i < 63) t->name[i++] = *s;
                s++;
            }
            t->name[i] = 0;
            if      (strcmp(t->name, "let")  == 0) t->kind = T_LET;
            else if (strcmp(t->name, "echo") == 0) t->kind = T_ECHO;
            else if (strcmp(t->name, "in")   == 0) t->kind = T_IN;
            else                                    t->kind = T_IDENT;
            n++;
            continue;
        }

        switch (*s) {
            case '+': t->kind = T_PLUS;    break;
            case '-': t->kind = T_MINUS;   break;
            case '*': t->kind = T_STAR;    break;
            case '/': t->kind = T_SLASH;   break;
            case '%': t->kind = T_PERCENT; break;
            case '=': t->kind = T_EQ;      break;
            case '(': t->kind = T_LPAREN;  break;
            case ')': t->kind = T_RPAREN;  break;
            default:  return 0;
        }
        n++;
        s++;
    }
    toks[n].kind = T_EOF;
    toks[n].value = 0;
    toks[n].name[0] = 0;
    n++;
    *out_count = n;
    return 1;
}

/* ---------- Recursive-descent parser ---------- */

static Node *parse_expr(Parser *p);

static Node *parse_primary(Parser *p) {
    Token *t = &p->toks[p->pos];
    if (t->kind == T_INT) {
        Node *n = new_node(N_INT);
        if (!n) return NULL;
        n->value = t->value;
        p->pos++;
        return n;
    }
    if (t->kind == T_IDENT) {
        Node *n = new_node(N_VAR);
        if (!n) return NULL;
        strcpy(n->name, t->name);
        p->pos++;
        return n;
    }
    if (t->kind == T_LPAREN) {
        p->pos++;
        Node *n = parse_expr(p);
        if (!n) return NULL;
        if (p->toks[p->pos].kind != T_RPAREN) {
            free_node(n);
            return NULL;
        }
        p->pos++;
        return n;
    }
    return NULL;
}

static Node *parse_unary(Parser *p) {
    if (p->toks[p->pos].kind == T_MINUS) {
        p->pos++;
        Node *operand = parse_unary(p);
        if (!operand) return NULL;
        Node *n = new_node(N_NEG);
        if (!n) { free_node(operand); return NULL; }
        n->a = operand;
        return n;
    }
    return parse_primary(p);
}

static Node *parse_mul(Parser *p) {
    Node *left = parse_unary(p);
    if (!left) return NULL;
    for (;;) {
        TokKind k = p->toks[p->pos].kind;
        NodeKind nk;
        if      (k == T_STAR)    nk = N_MUL;
        else if (k == T_SLASH)   nk = N_DIV;
        else if (k == T_PERCENT) nk = N_MOD;
        else break;

        p->pos++;
        Node *right = parse_unary(p);
        if (!right) { free_node(left); return NULL; }
        Node *n = new_node(nk);
        if (!n) { free_node(left); free_node(right); return NULL; }
        n->a = left;
        n->b = right;
        left = n;
    }
    return left;
}

static Node *parse_add(Parser *p) {
    Node *left = parse_mul(p);
    if (!left) return NULL;
    for (;;) {
        TokKind k = p->toks[p->pos].kind;
        NodeKind nk;
        if      (k == T_PLUS)  nk = N_ADD;
        else if (k == T_MINUS) nk = N_SUB;
        else break;

        p->pos++;
        Node *right = parse_mul(p);
        if (!right) { free_node(left); return NULL; }
        Node *n = new_node(nk);
        if (!n) { free_node(left); free_node(right); return NULL; }
        n->a = left;
        n->b = right;
        left = n;
    }
    return left;
}

static Node *parse_expr(Parser *p) {
    if (p->toks[p->pos].kind == T_LET) {
        p->pos++;
        if (p->toks[p->pos].kind != T_IDENT) return NULL;
        char name[64];
        strcpy(name, p->toks[p->pos].name);
        p->pos++;
        if (p->toks[p->pos].kind != T_EQ) return NULL;
        p->pos++;

        Node *init = parse_expr(p);
        if (!init) return NULL;

        if (p->toks[p->pos].kind != T_IN) { free_node(init); return NULL; }
        p->pos++;

        Node *body = parse_expr(p);
        if (!body) { free_node(init); return NULL; }

        Node *n = new_node(N_LET);
        if (!n) { free_node(init); free_node(body); return NULL; }
        strcpy(n->name, name);
        n->a = init;
        n->b = body;
        return n;
    }
    return parse_add(p);
}

/* ---------- Evaluator ---------- */

static Result eval_bin(Node *n, Env *env) {
    Result a = eval(n->a, env);
    if (a.is_err) return a;
    Result b = eval(n->b, env);
    if (b.is_err) return b;

    switch (n->kind) {
        case N_ADD: return ok_result(a.value + b.value);
        case N_SUB: return ok_result(a.value - b.value);
        case N_MUL: return ok_result(a.value * b.value);
        case N_DIV:
            if (b.value == 0) return err_result("ERROR:DIV0");
            return ok_result(a.value / b.value);
        case N_MOD:
            if (b.value == 0) return err_result("ERROR:DIV0");
            return ok_result(a.value % b.value);
        default:
            return err_result("ERROR:PARSE");
    }
}

static Result eval(Node *n, Env *env) {
    switch (n->kind) {
        case N_INT:
            return ok_result(n->value);

        case N_VAR: {
            int i;
            for (i = env->top - 1; i >= 0; i--) {
                if (strcmp(env->stack[i].name, n->name) == 0)
                    return ok_result(env->stack[i].value);
            }
            return err_result("ERROR:UNBOUND");
        }

        case N_NEG: {
            Result r = eval(n->a, env);
            if (r.is_err) return r;
            return ok_result(-r.value);
        }

        case N_ADD:
        case N_SUB:
        case N_MUL:
        case N_DIV:
        case N_MOD:
            return eval_bin(n, env);

        case N_LET: {
            Result r = eval(n->a, env);
            if (r.is_err) return r;
            if (env->top >= ENV_MAX) return err_result("ERROR:PARSE");

            Binding *b = &env->stack[env->top++];
            strcpy(b->name, n->name);
            b->value = r.value;

            Result body = eval(n->b, env);
            env->top--;
            return body;
        }
    }
    return err_result("ERROR:PARSE");
}

/* ---------- Driver ---------- */

int main(int argc, char **argv) {
    FILE *f = stdin;
    if (argc > 1) {
        f = fopen(argv[1], "r");
        if (!f) {
            fprintf(stderr, "minicalc: cannot open %s\n", argv[1]);
            return 1;
        }
    }

    static char  line[MAX_LINE];
    static Token toks[MAX_TOKENS];
    static Env   env;

    while (fgets(line, sizeof line, f)) {
        size_t len = strlen(line);

        if (len == sizeof line - 1 && line[len - 1] != '\n') {
            int c = fgetc(f);
            if (c != EOF && c != '\n') {
                while ((c = fgetc(f)) != EOF && c != '\n') ;
                fputs("ERROR:PARSE\n", stdout);
                continue;
            }
        }

        while (len > 0 && (line[len - 1] == '\n' || line[len - 1] == '\r'))
            line[--len] = 0;

        int blank = 1;
        for (size_t i = 0; i < len; i++) {
            if (!isspace((unsigned char)line[i])) { blank = 0; break; }
        }
        if (blank) continue;

        int ntok;
        if (!tokenize(line, toks, &ntok)) {
            fputs("ERROR:PARSE\n", stdout);
            continue;
        }

        Parser p;
        p.toks  = toks;
        p.count = ntok;
        p.pos   = 0;

        int is_echo = 0;
        if (p.toks[p.pos].kind == T_ECHO) {
            is_echo = 1;
            p.pos++;
        }

        Node *ast = parse_expr(&p);
        if (!ast) {
            fputs("ERROR:PARSE\n", stdout);
            continue;
        }
        if (p.pos >= p.count || p.toks[p.pos].kind != T_EOF) {
            free_node(ast);
            fputs("ERROR:PARSE\n", stdout);
            continue;
        }

        env.top = 0;
        Result r = eval(ast, &env);
        free_node(ast);

        if (r.is_err) {
            fputs(r.code, stdout);
            fputc('\n', stdout);
        } else if (is_echo) {
            printf("%ld\n", r.value);
        }
    }

    if (f != stdin) fclose(f);
    return 0;
}
