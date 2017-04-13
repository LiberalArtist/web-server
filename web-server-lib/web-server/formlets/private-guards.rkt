#lang web-server/base

(require web-server/http
         xml/xexpr
         racket/match
         racket/contract
         (only-in racket/function arity=?)
         )

(provide guard-formlet*/c
         guard-formlet/c-any/c
         guard-formlet/c-procedure?
         guard-formlet/c-procedure->any/c
         )
         

(define (guard-formlet*/c formlet #:error-name error-name)
  (unless (and (procedure? formlet)
               (procedure-arity-includes? formlet 1)
               (let ([rslt-arity (procedure-result-arity formlet)])
                 (or (not rslt-arity)
                     (arity=? rslt-arity 3))))
    (raise-argument-error error-name "formlet*/c" formlet))
  (λ (i)
    (unless (integer? i)
      (raise-argument-error (object-name formlet) "integer?" i))
    (match (call-with-values (λ () (formlet i)) list)
      [(list (and xs (? (listof xexpr/c)))
             (and p (? (λ (p)
                         (and (procedure? p)
                              (procedure-arity-includes? p 1)))))
             (and new-i (? integer?)))
       (values xs p new-i)]
      [_ (raise-argument-error error-name "formlet*/c" formlet)])))

(define (guard-formlet/c-any/c formlet
                               #:error-name error-name
                               #:p-result-proj [p-result-proj (λ (x) x)])
  (define guarded
    (guard-formlet*/c formlet #:error-name error-name))
  (λ (i)
    (define-values (xs p new-i)
      (guarded i))
    (values xs
            (λ (bindings)
              (match bindings
                [(list (? binding?) ...)
                 (match (call-with-values (λ () (p bindings)) list)
                   [(list it)
                    (p-result-proj it)]
                   [_ (raise-argument-error error-name
                                            "(formlet/c any/c)"
                                            formlet)])]
                [_ (raise-argument-error (object-name formlet)
                                         "(listof binding?)"
                                         bindings)]))
            new-i)))

(define (guard-formlet/c-procedure? formlet #:error-name error-name)
  (guard-formlet/c-any/c
   formlet
   #:error-name error-name
   #:p-result-proj
   (λ (p-rslt)
     (unless (procedure? p-rslt)
       (raise-argument-error error-name "(formlet/c procedure?)" formlet))
     p-rslt)))

(define (guard-formlet/c-procedure->any/c formlet
                                          #:error-name error-name)
  (guard-formlet/c-any/c
   formlet
   #:error-name error-name
   #:p-result-proj
   (λ (p-rslt)
     (unless (procedure? p-rslt)
       (raise-argument-error error-name
                             "(formlet/c (unconstrained-domain-> any/c))"
                             formlet))
     (define rslt-arity
       (procedure-result-arity p-rslt))
     (cond
       [rslt-arity
        (unless (arity=? 1 rslt-arity)
          (raise-argument-error
           error-name
           "(formlet/c (unconstrained-domain-> any/c))"
           formlet))
        p-rslt]
       [else
        (λ args
          (match (call-with-values (λ () (apply p-rslt args)) list)
            [(list it) it]
            [_ (raise-argument-error
                error-name
                "(formlet/c (unconstrained-domain-> any/c))"
                formlet)]))]))))





