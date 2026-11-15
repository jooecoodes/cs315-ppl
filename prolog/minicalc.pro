% MiniCalc - Prolog implementation (SWI-Prolog)
% Run: swipl -q -g "main(['tests.txt']), halt" -t "halt" minicalc.pl
%
% Design:
%   * Tokenizer: char codes -> token list
%   * Parser:    pure DCG over the token list
%   * Evaluator: eval(Env, Expr, Value), one clause per AST node
%   * Errors:    ordinary terms error(PARSE|UNBOUND|DIV0), never exceptions
%   * Arithmetic: // and rem (truncate toward zero / sign of dividend)

% ===================== Driver =====================

main(Argv) :-
    (   Argv = [File|_]
    ->  open(File, read, In),
        process_lines(In),
        close(In)
    ;   process_lines(user_input)
    ).

process_lines(In) :-
    read_line_to_codes(In, Codes),
    (   Codes = end_of_file
    ->  true
    ;   run_line(Codes),
        process_lines(In)
    ).

run_line(Codes) :-
    (   is_blank(Codes)
    ->  true
    ;   (   tokenize(Codes, Toks),
            phrase(statement(Stmt), Toks)
        ->  execute(Stmt)
        ;   print_error(parse)
        )
    ).

is_blank([]).
is_blank([C|Cs]) :- code_type(C, space), is_blank(Cs).

% ===================== Tokenizer =====================

tokenize([], []).
tokenize([C|Cs], Toks)  :- code_type(C, space), !, tokenize(Cs, Toks).
tokenize([0'=|Cs], [eq|Toks])    :- !, tokenize(Cs, Toks).
tokenize([0'+|Cs], [plus|Toks])  :- !, tokenize(Cs, Toks).
tokenize([0'-|Cs], [minus|Toks]) :- !, tokenize(Cs, Toks).
tokenize([0'*|Cs], [star|Toks])  :- !, tokenize(Cs, Toks).
tokenize([0'/|Cs], [slash|Toks]) :- !, tokenize(Cs, Toks).
tokenize([0'%|Cs], [pct|Toks])   :- !, tokenize(Cs, Toks).
tokenize([0'(|Cs], [lp|Toks])    :- !, tokenize(Cs, Toks).
tokenize([0')|Cs], [rp|Toks])    :- !, tokenize(Cs, Toks).
tokenize([C|Cs], [int(N)|Toks])  :-
    code_type(C, digit), !,
    take_while(Cs, digit_char, Digits, Rest),
    number_codes(N, [C|Digits]),
    tokenize(Rest, Toks).
tokenize([C|Cs], [Tok|Toks])     :-
    ident_start(C), !,
    take_while(Cs, ident_char, Cont, Rest),
    atom_codes(A, [C|Cont]),
    keyword_token(A, Tok),
    tokenize(Rest, Toks).

digit_char(C) :- code_type(C, digit).
ident_start(C) :- code_type(C, alpha).
ident_start(0'_).
ident_char(C)  :- code_type(C, alnum).
ident_char(0'_).

take_while([C|Cs], Pred, [C|Rest], Tail) :-
    call(Pred, C), !,
    take_while(Cs, Pred, Rest, Tail).
take_while(Rest, _, [], Rest).

keyword_token(let,  kw_let)  :- !.
keyword_token(in,   kw_in)   :- !.
keyword_token(echo, kw_echo) :- !.
keyword_token(A,    id(A)).

% ===================== Parser (DCG) =====================

statement(echo(E)) --> [kw_echo], expr(E).
statement(E)       --> expr(E).

expr(let(X, E1, E2)) -->
    [kw_let], ident(X), [eq], expr(E1), [kw_in], expr(E2).
expr(E) -->
    add_expr(E).

ident(X) --> [id(X)].

add_expr(E) --> mul_expr(A), add_rest(A, E).

add_rest(A, E) --> [plus],  !, mul_expr(B), add_rest(bin('+', A, B), E).
add_rest(A, E) --> [minus], !, mul_expr(B), add_rest(bin('-', A, B), E).
add_rest(A, A) --> [].

mul_expr(E) --> unary(A), mul_rest(A, E).

mul_rest(A, E) --> [star],  !, unary(B), mul_rest(bin('*', A, B), E).
mul_rest(A, E) --> [slash], !, unary(B), mul_rest(bin('/', A, B), E).
mul_rest(A, E) --> [pct],   !, unary(B), mul_rest(bin('%', A, B), E).
mul_rest(A, A) --> [].

unary(neg(E)) --> [minus], !, unary(E).
unary(E)      --> primary(E).

primary(int(N)) --> [int(N)].
primary(var(X)) --> [id(X)].
primary(E)      --> [lp], expr(E), [rp].

% ===================== Evaluator =====================

eval(_, int(N), N).

eval(Env, var(X), V) :-
    memberchk(X-V, Env), !.
eval(_, var(_), error('UNBOUND')).

eval(Env, let(X, E1, E2), V) :-
    eval(Env, E1, V1),
    (   V1 = error(_)
    ->  V = V1
    ;   eval([X-V1|Env], E2, V)
    ).

eval(Env, bin(Op, L, R), V) :-
    eval(Env, L, VL),
    (   VL = error(_)
    ->  V = VL
    ;   eval(Env, R, VR),
        (   VR = error(_)
        ->  V = VR
        ;   apply_bin(Op, VL, VR, V)
        )
    ).

eval(Env, neg(E), V) :-
    eval(Env, E, V1),
    (   V1 = error(_)
    ->  V = V1
    ;   V is -V1
    ).

apply_bin('+', A, B, V) :- V is A + B.
apply_bin('-', A, B, V) :- V is A - B.
apply_bin('*', A, B, V) :- V is A * B.
apply_bin('/', _, 0, error('DIV0')) :- !.
apply_bin('/', A, B, V) :- V is A // B.
apply_bin('%', _, 0, error('DIV0')) :- !.
apply_bin('%', A, B, V) :- V is A rem B.

% ===================== Statement Execution =====================

execute(echo(E)) :-
    eval([], E, V),
    (   V = error(C)
    ->  print_error(C)
    ;   format("~w~n", [V])
    ).

execute(E) :-                       % bare expression: value discarded
    eval([], E, V),
    (   V = error(C)
    ->  print_error(C)
    ;   true
    ).

print_error(parse)     :- !, format("ERROR:PARSE~n").
print_error('UNBOUND') :- !, format("ERROR:UNBOUND~n").
print_error('DIV0')    :- !, format("ERROR:DIV0~n").
