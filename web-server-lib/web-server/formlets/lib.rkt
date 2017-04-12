#lang web-server/base
(require racket/list
         racket/contract
         web-server/http
         web-server/private/xexpr)

(provide xexpr-forest/c
         formlet*/c
         formlet/c
         pure
         cross
         cross*
         xml-forest
         xml
         text
         tag-xexpr
         formlet-display
         formlet-process
         )

(define (const x)
  (λ _ x))

; Combinators
(define (id x) x)

; Formlets
(define (pure x)
  (lambda (i)
    (values empty (const x) i)))

(define (cross f p)
  (lambda (i)
    (let*-values ([(x1 a1 i) (f i)]
                  [(x2 a2 i) (p i)])
      (values (append x1 x2)
              (lambda (env)
                (call-with-values (lambda () (a2 env)) (a1 env)))
              i))))

;; This is gross because OCaml auto-curries
(define (cross* f . gs)
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
  (lambda (i)
    (values x (const id) i)))

(define (xml x)
  (xml-forest (list x)))

(define (text x)
  (xml x))

(define (tag-xexpr t ats f)
  (lambda (i)
    (let-values ([(x p i) (f i)])
      (values (list (list* t ats x)) p i))))

; Helpers
(define (formlet-display f)
  (let-values ([(x p i) (f 0)])
    x))

(define (formlet-process f r)
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

#|
(define alpha any/c)
(define beta any/c)

(provide/contract
 [xexpr-forest/c contract?]
 [formlet*/c contract?]
 [formlet/c (() () #:rest (listof any/c) . ->* . contract?)]
 [pure (alpha
        . -> . (formlet/c alpha))]
 [cross ((formlet/c procedure?) formlet*/c . -> . formlet*/c)]
 [cross* (((formlet/c (unconstrained-domain-> beta)))
          () #:rest (listof (formlet/c alpha))
          . ->* . (formlet/c beta))]
 [xml-forest (xexpr-forest/c . -> . (formlet/c procedure?))]
 [xml (pretty-xexpr/c . -> . (formlet/c procedure?))] 
 [text (string? . -> . (formlet/c procedure?))]
 [tag-xexpr (symbol? (listof (list/c symbol? string?)) (formlet/c alpha) . -> . (formlet/c alpha))]
 [formlet-display ((formlet/c alpha) . -> . xexpr-forest/c)]
 [formlet-process (formlet*/c request? . -> . any)])
|#
