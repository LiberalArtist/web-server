#lang racket/base
(require racket/match
         "coercion.rkt"
         "bidi-match.rkt"
         syntax/parse/define
         (for-syntax racket/base))

(provide number-arg
         integer-arg
         real-arg
         string-arg
         symbol-arg)

(define-syntax define-bidi-match-expander/coercions
  (syntax-rules ()
    [(_ id in-test? in out-test? out)
     (begin (define-coercion-match-expander in/m in-test? in)
            (define-coercion-match-expander out/m out-test? out)
            (define-bidi-match-expander id in/m out/m))]))

; number arg
(define-try-match-expander number-arg/in
  ; string->number already returns #f on failure
  string? string->number)
(define-coercion-match-expander number-arg/out
  number? number->string)
(define-bidi-match-expander number-arg
  number-arg/in number-arg/out)

; integer arg
(define-try-match-expander integer-arg/in
  ; let match's optimizer see duplicate app and ? patterns
  string? string->number #:check (? integer?))
(define-coercion-match-expander integer-arg/out
  integer? number->string)
(define-bidi-match-expander integer-arg
  integer-arg/in integer-arg/out)

; real arg
(define-try-match-expander real-arg/in
  ; let match's optimizer see duplicate app and ? patterns
  string? string->number #:check (? real?))
(define-coercion-match-expander real-arg/out
  real? number->string)
(define-bidi-match-expander real-arg
  real-arg/in real-arg/out)

; string arg
(define-match-expander string->string/m
  (syntax-parser
    [(_ pat:expr)
     #'(? string? pat)]))

(define-bidi-match-expander string-arg string->string/m string->string/m)

; symbol arg
(define-bidi-match-expander/coercions symbol-arg
  string? string->symbol
  symbol? symbol->string)
