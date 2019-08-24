#lang racket/base
(require racket/match
         racket/stxparam
         net/url
         (only-in web-server/dispatchers/dispatch
                  next-dispatcher)
         "bidi-match.rkt"
         syntax/parse/define
         (for-syntax racket/base
                     "exptime.rkt"))

(provide dispatch-case
         dispatch-url
         dispatch-applies
         dispatch-rules
         dispatch-rules+applies)

;; TODO:
;;   - should rhs functions be let-bound?

(module+ test
  (require rackunit))

(define (string-list->url strlist)
  (url->string
   (make-url #f #f #f #f #t
             (if (null? strlist)
                 (list (path/param "" null))
                 (map (lambda (s) (path/param s null))
                      strlist))
             null #f)))

(module+ test
  (check-equal? (string-list->url (list))
                "/")
  (check-equal? (string-list->url (list "foo"))
                "/foo")
  (check-equal? (string-list->url (list ""))
                "/")
  (check-equal? (string-list->url (list "" ""))
                "//")
  (check-equal? (string-list->url (list "" "gonzo"))
                "//gonzo")
  (check-equal? (string-list->url (list "gonzo" ""))
                "/gonzo/")
  (check-equal? (string-list->url (list "baked" "beans"))
                "/baked/beans"))

(begin-for-syntax
  (define-syntax-class else-clause
    #:description "else clause"
    #:attributes [else-fun]
    #:literals [else]
    (pattern [else else-fun:expr])))

(define-syntax-parser dispatch-case
  #:track-literals
  [(_ :dispatch-clause ...
      (~optional :else-clause))
   (syntax/loc this-syntax
     (λ (the-req)
       (syntax-parameterize ([bidi-match-going-in? #t])
         (match the-req
           [request-pat
            (rhs the-req arg-going-in-id ...)]
           ...
           [_ (~? (else-fun the-req)
                  (next-dispatcher))]))))])

(define-syntax-parser dispatch-url
  ;; CHANGED to allow (but ignore) #:method
  #:track-literals
  [(_ :dispatch-clause ...)
   ;; n.b. does not accept else-clause
   (syntax/loc this-syntax
     (syntax-parameterize ([bidi-match-going-in? #f])
       (match-lambda*
         [(list (? (λ (x) (eq? x rhs))) arg-going-out-pat ...)
          (string-list->url string-list-expr)]
         ...)))])

(define-syntax-parser dispatch-applies
  #:track-literals
  [(_ :dispatch-clause ... :else-clause)
   (syntax/loc this-syntax
     (λ (req) #t))]
  [(_ :dispatch-clause ...)
   (syntax/loc this-syntax
     (syntax-parameterize ([bidi-match-going-in? #t])
       (match-lambda
         [request-pat #t] ...
         [_ #f])))])

(define-syntax-parser dispatch-rules
  #:track-literals
  [(_ clause:dispatch-clause ...
      (~optional the-else:else-clause))
   (syntax/loc this-syntax
     (values
      (dispatch-case clause ... (~? the-else))
      (dispatch-url clause ...)))])

(define-syntax-parser dispatch-rules+applies
  #:track-literals
  [(_ clause:dispatch-clause ...
      (~optional the-else:else-clause))
   (syntax/loc this-syntax
     (values
      (dispatch-case clause ... (~? the-else))
      (dispatch-url clause ...)
      (dispatch-applies clause ... (~? the-else))))])
