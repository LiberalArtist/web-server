#lang racket/base
(require (for-syntax racket/base)
         syntax/parse/define
         racket/match
         racket/stxparam)

(provide bidi-match-going-in?
         define-bidi-match-expander)

(define-syntax-parameter bidi-match-going-in? #t)

(define-syntax-parser define-bidi-match-expander
  [(_ bidi-id:id in-expander:id out-expander:id)
   (syntax/loc this-syntax
     (define-match-expander bidi-id
       (syntax-parser
         [(_ arg (... ...) id)
          (if (syntax-parameter-value #'bidi-match-going-in?)
              (syntax/loc this-syntax (in-expander arg (... ...) id))
              (syntax/loc this-syntax (out-expander arg (... ...) id)))])))])
