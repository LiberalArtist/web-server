#lang racket/base
(require racket/contract
         racket/match
         syntax/parse/define
         (for-syntax racket/base))

(provide define-coercion-match-expander
         define-try-match-expander
         (contract-out
          [make-coerce-safe? (-> (-> any/c any/c)
                                 (any/c boolean?))]
          ))

(define ((make-coerce-safe? coerce) x)
  (with-handlers ([exn:fail? (lambda (x) #f)])
    (and (coerce x) #t)))

(define-syntax-parser define-coercion-match-expander
  [(_ expander-id:id test?:expr coerce:expr)
   (syntax/loc this-syntax
     ;; FIXME should we define temporaries for `test?` and `coerce`
     ;; to prevent repeated evaluation?
     ;; But the docs say "(id x)" expands to "(? test? (app coerce x))".
     (define-match-expander expander-id
       (syntax-parser
         [(_ pat:expr)
          (syntax/loc this-syntax
            (? test? (app coerce pat)))])))])

(define-syntax-parser define-try-match-expander
  [(_ name:id
      test?-e:expr try-coerce-e:expr
      (~optional (~seq #:check check-pat:expr)))
   (syntax/loc this-syntax
     (begin
       (define-try-match-expander inner
         try-coerce-e (~? (~@ #:check check-pat)))
       (define test? test?-e)
       (define-match-expander name
         (syntax-parser
           [(_ pat:expr)
            (syntax/loc this-syntax
              (? test? (inner pat)))]))))]
  [(_ name:id try-coerce-e:expr (~optional (~seq #:check check-pat:expr)))
   (syntax/loc this-syntax
     (begin
       (define try-coerce try-coerce-e)
       (define-match-expander name
         (syntax-parser
           [(_ pat:expr)
            (syntax/loc this-syntax
              (app try-coerce (and (~? check-pat (not #f))
                                   pat)))]))))])

