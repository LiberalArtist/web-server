#lang racket/base
(require racket/list
         racket/contract
         syntax/parse
         (for-template racket/base
                       "http-expanders.rkt"))

(provide dispatch-clause
         dispatch-pattern+method)

; A dispatch pattern is either
; - a string
; - a bidi match expander application
; - a bidi match expander application folowed by (~datum ...)

(define-syntax-class dispatch-clause
  #:description "dispatch clause"
  #:attributes (rhs
                request-pat [arg-going-in-id 1]
                [arg-going-out-pat 1] string-list-expr)
  (pattern [:dispatch-pattern+method rhs:expr]))

(define-splicing-syntax-class dispatch-pattern+method
  #:description "url dispatch pattern followed by optional #:method declaration"
  #:attributes (request-pat [arg-going-in-id 1]
                            [arg-going-out-pat 1] string-list-expr)
  (pattern (~seq :dispatch-pattern
                 (~optional (~seq #:method (~describe "method pattern"
                                                      method-pat:expr))))
           #:with request-pat #'(request/url (~? method-pat) url-pat)))

(define-syntax-class dispatch-pattern
  #:description "url dispatch pattern"
  #:attributes (url-pat [arg-going-in-id 1]
                        [arg-going-out-pat 1] string-list-expr)
  (pattern (part:dispatch-pattern-part ...)
           #:with url-pat
           (syntax/loc this-syntax
             (url/paths (~@ part.pat-going-in ...) ...))
           #:with (arg-going-in-id ...) #'((~? part.arg-going-in-id) ...)
           #:with (arg-going-out-pat ...) #'((~? part.pat-going-out) ...)
           #:with string-list-expr
           (syntax/loc this-syntax
             (~? (list part.string-expr ...)
                 (append part.string-list-expr ...)))))

(define-splicing-syntax-class dispatch-pattern-part
  #:description #f
  ;; string-expr attribute is unbound for ellipsis variant
  ;; arg-going-in-expr & pat-going-out are unbound for string literal variant
  #:attributes ([pat-going-in 1] arg-going-in-id
                                 pat-going-out string-expr string-list-expr)
  (pattern (~seq s:str)
           #:with (pat-going-in ...) #'(s)
           #:attr arg-going-in-id #f
           #:attr pat-going-out #f
           #:with string-expr (syntax/loc #'s 's)
           #:with string-list-expr (syntax/loc #'s '(s)))
  (pattern (~seq base:bidi-use)
           #:with (pat-going-in ...) #'(base.pat-going-in)
           #:with arg-going-in-id #'base.id-going-in
           #:with pat-going-out #'base.pat-going-out
           #:with string-expr #'base.id-going-out
           #:with string-list-expr (syntax/loc #'base (list base.id-going-out)))
  (pattern (~describe "bidi match expander application with ellipsis"
                      (~seq base:bidi-use (~datum ...)))
           #:with (pat-going-in ...) #'(base.pat-going-in (... ...))
           #:with arg-going-in-id #'base.id-going-in
           #:with pat-going-out
           (syntax/loc #'base
             (list base.pat-going-out (... ...)))
           #:attr string-expr #f
           #:with string-list-expr #'base.id-going-out))

(define-syntax-class bidi-use
  #:description "bidi match expander application"
  #:attributes [id-going-in id-going-out pat-going-in pat-going-out]
  (pattern (bidi:id sub ...)
           #:with (id-going-in:id id-going-out:id)
           (generate-temporaries '(id-going-in id-going-out))
           #:with pat-going-in
           (syntax/loc this-syntax (bidi sub ... id-going-in))
           #:with pat-going-out
           (syntax/loc this-syntax (bidi sub ... id-going-out))))
