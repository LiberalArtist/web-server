#lang racket/base
(require racket/match
         net/url
         web-server/http
         syntax/parse/define
         (for-syntax racket/base))

(provide url/path
         url/paths
         request/url)

(define-match-expander url/path
  (syntax-parser
    [(_ path-pat:expr)
     ; url = scheme, user, host, port, absolute?, path, query, fragment
     #'(url _ _ _ _ _ path-pat _ _)]))

(define-match-expander url/paths
  (syntax-parser
    [(_ path-elem-pat:expr ...)
     #'(url/path (list (path/param path-elem-pat _) ...))]))

(define (method-downcase x)
  (cond
    [(string? x)
     (string-downcase x)]
    [(bytes? x)
     (method-downcase (bytes->string/utf-8 x))]
    [else 
     x]))

(define-match-expander request/url
  (syntax-parser
    [(_ url-pat:expr)
     ; req = method, url, headers, bindings, post-data, host-ip, host-port, client-ip
     #'(request/url (or #f "get") url-pat)]
    [(_ method-pat:expr url-pat)
     ; req = method, url, headers, bindings, post-data, host-ip, host-port, client-ip
     #'(request (app method-downcase method-pat)
                url-pat _ _ _ _ _ _)]))
