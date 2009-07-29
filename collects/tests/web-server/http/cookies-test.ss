#lang scheme
(require schemeunit
         net/url
         web-server/http/request-structs
         web-server/http/response-structs
         web-server/http/cookie
         web-server/http/cookie-parse)
(provide cookies-tests)

(define (header-equal? h1 h2)
  (and (bytes=? (header-field h1)
                (header-field h2))
       (bytes=? (header-value h1)
                (header-value h2))))

(define (set-header->read-header h)
  (make-header #"Cookie" (header-value h)))

(define cookies-tests
  (test-suite
   "Cookies"
   
   (test-suite
    "cookie.ss"
    
    (test-suite
     "cookie->header and make-cookie"
     (test-check "Simple" header-equal?
                 (cookie->header (make-cookie "name" "value"))
                 (make-header #"Set-Cookie" #"name=value; Version=1"))
     
     (test-equal? "Comment"
                  (header-value (cookie->header (make-cookie "name" "value" #:comment "comment")))
                  #"name=value; Comment=comment; Version=1")
     
     (test-equal? "Domain"
                  (header-value (cookie->header (make-cookie "name" "value" #:domain ".domain")))
                  #"name=value; Domain=.domain; Version=1")
     
     (test-equal? "max-age"
                  (header-value (cookie->header (make-cookie "name" "value" #:max-age 24)))
                  #"name=value; Max-Age=24; Version=1")
     
     (test-equal? "path"
                  (header-value (cookie->header (make-cookie "name" "value" #:path "path")))
                  #"name=value; Path=path; Version=1")
     
     (test-equal? "secure? #t"
                  (header-value (cookie->header (make-cookie "name" "value" #:secure? #t)))
                  #"name=value; Secure; Version=1")
     
     (test-equal? "secure? #f"
                  (header-value (cookie->header (make-cookie "name" "value" #:secure? #f)))
                  #"name=value; Version=1"))
    
    (test-suite
     "xexpr-response/cookies"
     (test-equal? "Simple"
                  (response/full-body (xexpr-response/cookies empty `(html)))
                  (list #"<html />"))
     
     (test-equal? "One (body)"
                  (response/full-body (xexpr-response/cookies (list (make-cookie "name" "value")) `(html)))
                  (list #"<html />"))
     
     (test-equal? "One (headers)"
                  (map (lambda (h) (cons (header-field h) (header-value h)))
                       (response/basic-headers (xexpr-response/cookies (list (make-cookie "name" "value")) `(html))))
                  (list (cons #"Set-Cookie" #"name=value; Version=1")))))
   
   (test-suite
    "cookie-parse.ss"
    
    (test-equal? "None"
                 (request-cookies 
                  (make-request 
                   #"GET" (string->url "http://test.com/foo")
                   empty empty #f
                   "host" 80 "client"))
                 empty)
    
    (test-equal? "Simple"
                 (request-cookies 
                  (make-request 
                   #"GET" (string->url "http://test.com/foo")
                   (list (make-header #"Cookie" #"$Version=\"1\"; name=\"value\""))
                   empty #f
                   "host" 80 "client"))
                 (list (make-client-cookie "name" "value" #f #f)))
    
    (test-equal? "Path"
                 (request-cookies 
                  (make-request 
                   #"GET" (string->url "http://test.com/foo")
                   (list (make-header #"Cookie" #"$Version=\"1\"; name=\"value\"; $Path=\"/acme\""))
                   empty #f
                   "host" 80 "client"))
                 (list (make-client-cookie "name" "value" #f "/acme")))
    
    (test-equal? "Domain"
                 (request-cookies 
                  (make-request 
                   #"GET" (string->url "http://test.com/foo")
                   (list (make-header #"Cookie" #"$Version=\"1\"; name=\"value\"; $Domain=\".acme\""))
                   empty #f
                   "host" 80 "client"))
                 (list (make-client-cookie "name" "value" ".acme" #f)))
    
    (test-equal? "Multiple"
                 (request-cookies 
                  (make-request 
                   #"GET" (string->url "http://test.com/foo")
                   (list (make-header #"Cookie" #"$Version=\"1\"; key1=\"value1\"; key2=\"value2\""))
                   empty #f
                   "host" 80 "client"))
                 (list (make-client-cookie "key1" "value1" #f #f)
                       (make-client-cookie "key2" "value2" #f #f)))
    
    (test-equal? "Multiple w/ paths & domains"
                 (request-cookies 
                  (make-request 
                   #"GET" (string->url "http://test.com/foo")
                   (list (make-header #"Cookie" #"$Version=\"1\"; key1=\"value1\"; $Path=\"/acme\"; key2=\"value2\"; $Domain=\".acme\""))
                   empty #f
                   "host" 80 "client"))
                 (list (make-client-cookie "key1" "value1" #f "/acme")
                       (make-client-cookie "key2" "value2" ".acme" #f)))
    
    )))