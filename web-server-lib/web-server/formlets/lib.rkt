#lang web-server/base
(require racket/list
         racket/contract
         "private-guards.rkt"
         web-server/http
         web-server/private/xexpr)


(provide xexpr-forest/c
         formlet*/c
         formlet/c
         pure
         cross 
         cross* 
         tag-xexpr
         formlet-display
         formlet-process
         xml-forest 
         xml 
         text 
         )

(define (const x)
  (λ _ x))

; Combinators
(define (id x) x)

; Formlets
(define (pure x)
  (lambda (i)
    (values empty (const x) i)))

(define (cross raw-f raw-p)
  #;(-> (formlet/c procedure?)
        formlet*/c
        any)
  (let ([f (guard-formlet/c-procedure? raw-f #:error-name 'cross)]
        [p (guard-formlet*/c raw-p #:error-name 'cross)])
    (lambda (i)
      (let*-values ([(x1 a1 i) (f i)]
                    [(x2 a2 i) (p i)])
        (values (append x1 x2)
                (lambda (env)
                  (call-with-values (lambda () (a2 env)) (a1 env)))
                i)))))

;; This is gross because OCaml auto-curries
(define (cross* raw-f . raw-gs)
  #;(->* (formlet/c (unconstrained-domain-> any/c))
         (formlet/c any/c) ...
         any)
  (define f
    (guard-formlet/c-procedure->any/c raw-f #:error-name 'cross*))
  (define gs
    (map (λ (g) (guard-formlet/c-any/c g #:error-name 'cross))
         raw-gs))
  (lambda (i)
    (let*-values ([(fx fp fi) (f i)]
                  [(gs-x gs-p gs-i)
                   (let loop ([gs gs]
                              [xs empty]
                              [ps empty]
                              [i fi])
                     (if (empty? gs)
                         (values (reverse xs) (reverse ps) i)
                         (let-values ([(gx gp gi) ((first gs) i)])
                           (loop (rest gs) (list* gx xs) (list* gp ps) gi))))])
      (values (apply append fx gs-x)
              (lambda (env)
                (let ([fe (fp env)]
                      [gs-e (map (lambda (g) (g env)) gs-p)])
                  (apply fe gs-e)))
              gs-i))))

(define (xml-forest x)
  #;(-> xexpr-forest/c
        any)
  (unless (xexpr-forest/c x)
    (raise-argument-error 'xml-forest
                          "xexpr-forest/c"
                          x))
  (lambda (i)
    (values x (const id) i)))

(define (xml x)
  #;(-> pretty-xexpr/c any)
  (unless (pretty-xexpr/c x)
    (raise-argument-error 'xml
                          "pretty-xexpr/c"
                          x))
  (xml-forest (list x)))

(define (text x)
  #;(-> string? any)
  (unless (string? x)
    (raise-argument-error 'xml
                          "string?"
                          x))
  (xml x))

(define (tag-xexpr t ats raw-f)
  #;(-> symbol?
        (listof (list/c symbol? string?))
        (formlet/c any/c)
        any)
  (unless (symbol? t)
    (raise-argument-error 'tag-xexpr
                          "symbol?"
                          1
                          t ats raw-f))
  (unless ((listof (list/c symbol? string?)) ats)
    (raise-argument-error 'tag-xexpr
                          "(listof (list/c symbol? string?))"
                          2
                          t ats raw-f))
  (define f
    (guard-formlet/c-any/c raw-f #:error-name 'tag-xexpr))
  (lambda (i)
    (let-values ([(x p i) (f i)])
      (values (list (list* t ats x)) p i))))

; Helpers
(define (formlet-display raw-f)
  #;(-> formlet*/c any)
  (let ([f (guard-formlet*/c raw-f #:error-name 'formlet-display)])
    (let-values ([(x p i) (f 0)])
      x)))

(define (formlet-process raw-f r)
  #;(-> formlet*/c
        request?
        any)
  (unless (request? r)
    (raise-argument-error 'formlet-process
                          "request?"
                          2
                          raw-f r))
  (define f
    (guard-formlet*/c raw-f #:error-name 'formlet-process))
  (let-values ([(x p i) (f 0)])
    (p (request-bindings/raw r))))

; Contracts
(define xexpr-forest/c
  (listof pretty-xexpr/c))

(define-syntax-rule (formlet/c* c)
  (integer? . -> . 
            (values xexpr-forest/c
                    ((listof binding?) . -> . c)
                    integer?)))
(define formlet*/c (formlet/c* any))
(define (formlet/c . cs)
  (formlet/c* (apply values (map (λ (c) coerce-contract 'formlet/c c) cs))))

