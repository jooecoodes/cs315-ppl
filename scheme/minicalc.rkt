#lang racket
(require racket/port)

;; MiniCalc — Functional Scheme (Racket) implementation.
;;
;; Pipeline:  tokenize → parse → eval, all pure functions over immutable data.
;; Errors are values: (cons 'ok v) | (cons 'err code). Never exceptions.
;; Environment is an alist; `let` conses a new pair and recurses, old env untouched.
;;
;; The ONE impurity in the whole program is I/O: read-line / displayln.
;; `echo` is the deliberate place where purity is broken.

;; ---------------------------------------------------------------------------
;; Character classes
;; ---------------------------------------------------------------------------
(define (ident-start? c) (or (char-alphabetic? c) (char=? c #\_)))
(define (ident-cont?  c) (or (char-alphabetic? c) (char-numeric? c) (char=? c #\_)))

(define (blank-line? s)
  (let loop ([i 0])
    (cond [(>= i (string-length s)) #t]
          [(char-whitespace? (string-ref s i)) (loop (+ i 1))]
          [else #f])))

;; ---------------------------------------------------------------------------
;; Tokenizer  : string → (cons 'ok token-list) | (cons 'err 'PARSE)
;;
;; Tokens:  (int n) (ident "x") (kw let|in|echo)
;;          (op +|-|*|/|%) (lp) (rp) (eq) (eof)
;; ---------------------------------------------------------------------------
(define (read-number s i n)
  (let loop ([j i] [acc 0])
    (cond [(and (< j n) (char-numeric? (string-ref s j)))
           (loop (+ j 1) (+ (* acc 10)
                            (- (char->integer (string-ref s j))
                               (char->integer #\0))))]
          [else (values acc j)])))

(define (read-ident s i n)
  (let loop ([j i])
    (cond [(and (< j n) (ident-cont? (string-ref s j))) (loop (+ j 1))]
          [else (values (substring s i j) j)])))

(define (classify-ident str)
  (cond [(string=? str "let")  '(kw let)]
        [(string=? str "in")   '(kw in)]
        [(string=? str "echo") '(kw echo)]
        [else                  (list 'ident str)]))

(define (tokenize str)
  (define n (string-length str))
  (let loop ([i 0] [acc '()])
    (cond
      [(>= i n) (cons 'ok (reverse (cons '(eof) acc)))]
      [else
       (let ([c (string-ref str i)])
         (cond
           [(char-whitespace? c) (loop (+ i 1) acc)]
           [(char-numeric? c)
            (let-values ([(num j) (read-number str i n)])
              (loop j (cons (list 'int num) acc)))]
           [(ident-start? c)
            (let-values ([(name j) (read-ident str i n)])
              (loop j (cons (classify-ident name) acc)))]
           [(char=? c #\+) (loop (+ i 1) (cons '(op +) acc))]
           [(char=? c #\-) (loop (+ i 1) (cons '(op -) acc))]
           [(char=? c #\*) (loop (+ i 1) (cons '(op *) acc))]
           [(char=? c #\/) (loop (+ i 1) (cons '(op /) acc))]
           [(char=? c #\%) (loop (+ i 1) (cons '(op %) acc))]
           [(char=? c #\() (loop (+ i 1) (cons '(lp) acc))]
           [(char=? c #\)) (loop (+ i 1) (cons '(rp) acc))]
           [(char=? c #\=) (loop (+ i 1) (cons '(eq) acc))]
           [else (cons 'err 'PARSE)]))])))

;; ---------------------------------------------------------------------------
;; Parser — recursive descent, pure state-passing.
;; Each rule takes the token list and returns (cons ast rest-tokens).
;; `ast` may be '(err PARSE); callers propagate.
;; ---------------------------------------------------------------------------
(define (parse-expr toks)
  (match toks
    [(cons '(kw let) _) (parse-let toks)]
    [_                  (parse-add toks)]))

(define (parse-let toks)
  (match toks
    [(cons '(kw let) rest1)
     (match rest1
       [(cons (list 'ident name) rest2)
        (match rest2
          [(cons '(eq) rest3)
           (match (parse-expr rest3)
             [(cons `(err ,code) _) (cons `(err ,code) '())]
             [(cons e1 rest4)
              (match rest4
                [(cons '(kw in) rest5)
                 (match (parse-expr rest5)
                   [(cons `(err ,code) _) (cons `(err ,code) '())]
                   [(cons e2 rest6)
                    (cons (list 'let name e1 e2) rest6)])]
                [_ (cons `(err PARSE) '())])])]
          [_ (cons `(err PARSE) '())])]
       [_ (cons `(err PARSE) '())])]
    [_ (cons `(err PARSE) '())]))

(define (parse-add toks)
  (match (parse-mul toks)
    [(cons `(err ,code) _) (cons `(err ,code) '())]
    [(cons left rest)
     (let loop ([left left] [rest rest])
       (match rest
         [(cons (list 'op op) more)
          #:when (or (eq? op '+) (eq? op '-))
          (match (parse-mul more)
            [(cons `(err ,code) _) (cons `(err ,code) '())]
            [(cons right rest2) (loop (list 'bin op left right) rest2)])]
         [_ (cons left rest)]))]))

(define (parse-mul toks)
  (match (parse-unary toks)
    [(cons `(err ,code) _) (cons `(err ,code) '())]
    [(cons left rest)
     (let loop ([left left] [rest rest])
       (match rest
         [(cons (list 'op op) more)
          #:when (or (eq? op '*) (eq? op '/) (eq? op '%))
          (match (parse-unary more)
            [(cons `(err ,code) _) (cons `(err ,code) '())]
            [(cons right rest2) (loop (list 'bin op left right) rest2)])]
         [_ (cons left rest)]))]))

(define (parse-unary toks)
  (match toks
    [(cons (list 'op '-) rest)
     (match (parse-unary rest)
       [(cons `(err ,code) _) (cons `(err ,code) '())]
       [(cons e rest2) (cons (list 'neg e) rest2)])]
    [_ (parse-primary toks)]))

(define (parse-primary toks)
  (match toks
    [(cons (list 'int n) rest)      (cons (list 'int n) rest)]
    [(cons (list 'ident name) rest) (cons (list 'var name) rest)]
    [(cons '(lp) rest)
     (match (parse-expr rest)
       [(cons `(err ,code) _) (cons `(err ,code) '())]
       [(cons e rest2)
        (match rest2
          [(cons '(rp) rest3) (cons e rest3)]
          [_ (cons `(err PARSE) '())])])]
    [_ (cons `(err PARSE) '())]))

;; statement → (echo e) | bare-expr  (with trailing EOF enforced)
(define (parse-statement toks)
  (match toks
    [(cons '(kw echo) rest)
     (match (parse-expr rest)
       [(cons `(err ,code) _) (cons `(err ,code) '())]
       [(cons e rest2)
        (match rest2
          ['((eof)) (cons (list 'echo e) '())]
          [_ (cons `(err PARSE) '())])])]
    [_ (match (parse-expr toks)
         [(cons `(err ,code) _) (cons `(err ,code) '())]
         [(cons e rest)
          (match rest
            ['((eof)) (cons e '())]
            [_ (cons `(err PARSE) '())])])]))

;; ---------------------------------------------------------------------------
;; Environment (immutable alist)  and  evaluator (pure recursion)
;; ---------------------------------------------------------------------------
(define (env-lookup name env)
  (cond [(null? env) #f]
        [(string=? (caar env) name) (car env)]
        [else (env-lookup name (cdr env))]))

(define (eval-expr env ast)
  (match ast
    [(list 'int n) (cons 'ok n)]
    [(list 'var name)
     (let ([p (env-lookup name env)])
       (if p (cons 'ok (cdr p)) (cons 'err 'UNBOUND)))]
    [(list 'neg e)
     (match (eval-expr env e)
       [(cons 'ok v)     (cons 'ok (- v))]
       [(cons 'err code) (cons 'err code)])]
    [(list 'bin op l r)
     (match (eval-expr env l)
       [(cons 'err code) (cons 'err code)]
       [(cons 'ok lv)
        (match (eval-expr env r)
          [(cons 'err code) (cons 'err code)]
          [(cons 'ok rv)
           (case op
             [(+) (cons 'ok (+ lv rv))]
             [(-) (cons 'ok (- lv rv))]
             [(*) (cons 'ok (* lv rv))]
             [(/) (if (= rv 0)
                      (cons 'err 'DIV0)
                      (cons 'ok (quotient lv rv)))]
             [(%) (if (= rv 0)
                      (cons 'err 'DIV0)
                      (cons 'ok (remainder lv rv)))])])])]
    [(list 'let name e1 e2)
     (match (eval-expr env e1)
       [(cons 'err code) (cons 'err code)]
       [(cons 'ok v)
        (eval-expr (cons (cons name v) env) e2)])]))

;; ---------------------------------------------------------------------------
;; Driver
;; ---------------------------------------------------------------------------
(define (process-line line)
  (match (tokenize line)
    [(cons 'err _) (displayln "ERROR:PARSE")]
    [(cons 'ok tokens)
     (match (parse-statement tokens)
       [(cons `(err ,_) _) (displayln "ERROR:PARSE")]
       [(cons (list 'echo e) _)
        (match (eval-expr '() e)
          [(cons 'ok v)     (displayln v)]
          [(cons 'err code) (displayln (format "ERROR:~a" code))])]
       [(cons stmt _)
        ;; Bare expression: evaluate silently, but still report runtime errors.
        (match (eval-expr '() stmt)
          [(cons 'ok _)     (void)]
          [(cons 'err code) (displayln (format "ERROR:~a" code))])])]))

(define (process-port in)
  (let loop ()
    (define line (read-line in))
    (cond [(eof-object? line) (void)]
          [(blank-line? line) (loop)]
          [else (process-line line) (loop)])))

(define (main)
  (define args (current-command-line-arguments))
  (if (zero? (vector-length args))
      (process-port (current-input-port))
      (let ([in (open-input-file (vector-ref args 0))])
        (process-port in)
        (close-input-port in))))

(main)
