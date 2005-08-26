(module dispatch-servlets mzscheme
  (require (lib "url.ss" "net")
           (lib "unitsig.ss")
           (lib "list.ss"))
  (require "dispatch.ss"
           "web-server-structs.ss"
           "connection-manager.ss"
           "configuration-structures.ss"
           "response.ss"
           "request-parsing.ss"
           "servlet-tables.ss"
           "servlet.ss"
           "sig.ss"
           "timer.ss"
           "util.ss")  
  (provide interface-version
           gen-dispatcher)
  
  (define interface-version 'v1)
  (define (gen-dispatcher host-info config:instances config:scripts config:scripts-lock config:make-servlet-namespace)
    ;; ************************************************************
    ;; ************************************************************
    ;; SERVING SERVLETS
    
    ;; servlet-content-producer: connection request host -> void
    (define (servlet-content-producer conn req host-info)
      (let ([meth (request-method req)])
        (if (eq? meth 'head)
            (output-response/method
             conn
             (make-response/full
              200 "Okay" (current-seconds) TEXT/HTML-MIME-TYPE
              '() (list "ignored"))
             meth)
            (let ([uri (request-uri req)])
              (set-request-bindings/raw!
               req
               (read-bindings/handled conn meth uri (request-headers req)
                                      host-info))
              
              (cond
                [(continuation-url? uri)
                 => (lambda (k-ref)
                      (invoke-servlet-continuation conn req k-ref host-info))]
                [else
                 (servlet-content-producer/path conn req host-info uri)])))))
    
    ;; read-bindings/handled: connection symbol url headers host -> (listof (list (symbol string))
    ;; read the bindings and handle any exceptions
    (define (read-bindings/handled conn meth uri headers host-info)
      (with-handlers ([exn? (lambda (e)
                              (output-response/method
                               conn
                               ;((responders-protocol (host-responders host-info))
                               ; (exn-message e))
                               ((responders-servlet-loading (host-responders
                                                             host-info))
                                uri e)
                               
                               
                               meth)
                              '())])
        (read-bindings conn meth uri headers)))
    
    ;; servlet-content-producer/path: connection request host url -> void
    ;; This is not a continuation url so the loading behavior is determined
    ;; by the url path. Build the servlet path and then load the servlet
    (define (servlet-content-producer/path conn req host-info uri)
      (with-handlers (;; couldn't find the servlet
                      [exn:fail:filesystem:exists:servlet?
                       (lambda (the-exn)
                         (output-response/method
                          conn
                          ((responders-file-not-found (host-responders
                                                       host-info))
                           (request-uri req))
                          (request-method req)))]
                      ;; servlet won't load (e.g. syntax error)
                      [(lambda (x) #t)
                       (lambda (the-exn)
                         (output-response/method
                          conn
                          ((responders-servlet-loading (host-responders
                                                        host-info)) uri
                                                                    the-exn)
                          (request-method req)))])
        
        (let ([sema (make-semaphore 0)]
              [last-inst (thread-cell-ref current-servlet-instance)])
          (let/cc suspend
            (let* ([servlet-custodian (make-servlet-custodian)]
                   [inst (create-new-instance!
                          config:instances servlet-custodian
                          (make-execution-context
                           conn req (lambda () (suspend #t)))
                          sema
                          (start-timer 0 (lambda () (void))))]
                   [real-servlet-path (url-path->path
                                       (paths-servlet (host-paths host-info))
                                       (url-path->string (url-path uri)))]
                   [servlet-exit-handler (make-servlet-exit-handler inst)])
              (parameterize ([current-directory (get-servlet-base-dir real-servlet-path)]
                             [current-custodian servlet-custodian]
                             [exit-handler servlet-exit-handler])
                (thread-cell-set! current-servlet-instance inst)
                (let-values (;; timer thread must be within the dynamic extent of
                             ;; servlet custodian
                             [(time-bomb) (start-timer (timeouts-default-servlet
                                                        (host-timeouts host-info))
                                                       (lambda ()
                                                         (servlet-exit-handler #f)))]
                             ;; any resources (e.g. threads) created when the
                             ;; servlet is loaded should be within the dynamic
                             ;; extent of the servlet custodian
                             [(servlet-program servlet-namespace) (cached-load real-servlet-path)])
                  (parameterize ([current-namespace servlet-namespace])
                    (set-servlet-instance-timer! inst time-bomb)
                    (with-handlers ([(lambda (x) #t)
                                     (make-servlet-exception-handler inst host-info)])
                      ;; Two possibilities:
                      ;; - module servlet. start : Request -> Void handles
                      ;;   output-response via send/finish, etc.
                      ;; - unit/sig or simple xexpr servlet. These must produce a
                      ;;   response, which is then output by the server.
                      ;; Here, we do not know if the servlet was a module,
                      ;; unit/sig, or Xexpr; we do know whether it produces a
                      ;; response.
                      (let ([r (servlet-program req)])
                        (when (response? r)
                          (send/back r)))))))))
          (thread-cell-set! current-servlet-instance last-inst)
          (semaphore-post sema))))
    
    ;; make-servlet-exit-handler: servlet-instance -> alpha -> void
    ;; exit handler for a servlet
    (define (make-servlet-exit-handler inst)
      (lambda (x)
        (remove-instance! config:instances inst)
        (kill-connection!
         (execution-context-connection
          (servlet-instance-context inst)))
        (custodian-shutdown-all (servlet-instance-custodian inst))))
    
    ;; make-servlet-exception-handler: host -> exn -> void
    ;; This exception handler traps all unhandled servlet exceptions
    ;; * Must occur within the dynamic extent of the servlet
    ;;   custodian since several connection custodians will typically
    ;;   be shutdown during the dynamic extent of a continuation
    ;; * Use the connection from the current-servlet-context in case
    ;;   the exception is raised while invoking a continuation.
    ;; * Use the suspend from the servlet-instanct-context which is
    ;;   closed over the current tcp ports which may need to be
    ;;   closed for an http 1.0 request.
    ;; * Also, suspend will post to the semaphore so that future
    ;;   requests won't be blocked.
    ;; * This fixes PR# 7066
    (define (make-servlet-exception-handler inst host-info)
      (lambda (the-exn)
        (let* ([ctxt (servlet-instance-context inst)]
               [req (execution-context-request ctxt)]
               [resp ((responders-servlet (host-responders
                                           host-info))
                      (request-uri req)
                      the-exn)])
          ;; Don't handle twice
          (with-handlers ([exn:fail? (lambda (exn) (void))])
            (output-response/method
             (execution-context-connection ctxt)
             resp (request-method req)))
          ((execution-context-suspend ctxt)))))
    
    ;; path -> path
    ;; The actual servlet's parent directory.
    (define (get-servlet-base-dir servlet-path)
      (let loop ((path servlet-path))
        (let-values ([(base name must-be-dir?) (split-path path)])
          (if must-be-dir?
              (or (and (directory-exists? path) path)
                  (loop base))
              (or (and (directory-exists? base) base)
                  (loop base))))))
    
    
    ;; invoke-servlet-continuation: connection request continuation-reference
    ;;                              host -> void
    ;; pull the continuation out of the table and apply it
    (define (invoke-servlet-continuation conn req k-ref host-info)
      (with-handlers ([exn:servlet-instance?
                       (lambda (the-exn)
                         (output-response/method
                          conn
                          ((responders-file-not-found (host-responders
                                                       host-info))
                           (request-uri req))
                          (request-method req)))]
                      [exn:servlet-continuation?
                       (lambda (the-exn)
                         (output-response/method
                          conn
                          ((responders-file-not-found (host-responders
                                                       host-info))
                           (request-uri req))
                          (request-method req)))])
        (let* ([last-inst (thread-cell-ref current-servlet-instance)]
               [inst 
                (hash-table-get config:instances (first k-ref)
                                (lambda ()
                                  (raise
                                   (make-exn:servlet-instance
                                    "" (current-continuation-marks)))))]
               [k-table
                (servlet-instance-k-table inst)])
          (let/cc suspend
            ; We don't use call-with-semaphore or dynamic-wind because we
            ; always call a continuation. The exit-handler above ensures that
            ; the post is done.
            (semaphore-wait (servlet-instance-mutex inst))
            (thread-cell-set! current-servlet-instance inst)
            (set-servlet-instance-context!
             inst
             (make-execution-context
              conn req (lambda () (suspend #t))))
            (increment-timer (servlet-instance-timer inst)
                             (timeouts-default-servlet
                              (host-timeouts host-info)))
            (let ([k*salt
                   (hash-table-get k-table (second k-ref)
                                   (lambda ()
                                     (raise
                                      (make-exn:servlet-continuation
                                       "" (current-continuation-marks)))))])
              (if (= (second k*salt) (third k-ref))
                  ((first k*salt) req)
                  (raise
                   (make-exn:servlet-continuation
                    "" (current-continuation-marks))))))
          (thread-cell-set! current-servlet-instance last-inst)
          (semaphore-post (servlet-instance-mutex inst))
          )))
    
    ;; ************************************************************
    ;; ************************************************************
    ;; Paul's ugly loading code:
    (define make-cache-entry cons)
    (define cache-entry-servlet car)
    (define cache-entry-namespace cdr)
    
    ;; cached-load : str -> script, namespace
    ;; timestamps are no longer checked for performance.  The cache must be explicitly
    ;; refreshed (see dispatch).
    (define (cached-load name)
      (let ([e
             (call-with-semaphore config:scripts-lock
                                  (lambda ()
                                    (hash-table-get (unbox config:scripts)
                                                    name
                                                    (lambda () (reload-servlet-script name)))))])
        (values (cache-entry-servlet e)
                (cache-entry-namespace e))))
    
    ;; exn:i/o:filesystem:servlet-not-found =
    ;; (make-exn:fail:filesystem:exists:servlet str continuation-marks str sym)
    (define-struct (exn:fail:filesystem:exists:servlet
                    exn:fail:filesystem:exists) ())
    
    ;; reload-servlet-script : str -> cache-entry
    ;; The servlet is not cached in the servlet-table, so reload it from the filesystem.
    (define (reload-servlet-script servlet-filename)
      (cond
        [(load-servlet/path servlet-filename)
         => (lambda (entry)
              ; This is only called from cached-load, so config:scripts is locked
              (hash-table-put! (unbox config:scripts)
                               servlet-filename
                               entry)
              entry)]
        [else
         (raise (make-exn:fail:filesystem:exists:servlet
                 (string->immutable-string (format "Couldn't find ~a" servlet-filename))
                 (current-continuation-marks) ))]))
    
    ;; load-servlet/path path -> (union #f cache-entry)
    ;; given a string path to a filename attempt to load a servlet
    ;; A servlet-file will contain either
    ;;;; A signed-unit-servlet
    ;;;; A module servlet, currently only 'v1
    ;;;;;; (XXX: I don't know what 'typed-model-split-store0 was, so it was removed.)
    ;;;; A response
    (define (load-servlet/path a-path)
      (parameterize ([current-namespace (config:make-servlet-namespace)])
        (and (file-exists? a-path)
             (let ([s (load/use-compiled a-path)])
               (cond
                 ;; signed-unit servlet
                 ; MF: I'd also like to test that s has the correct import signature.
                 [(unit/sig? s) 
                  (make-cache-entry (lambda (initial-request)
                                      (invoke-unit/sig s servlet^))
                                    (current-namespace))]
                 ; FIX - reason about exceptions from dynamic require (catch and report if not already)
                 ;; module servlet
                 [(void? s)
                  (let* ([module-name `(file ,(path->string a-path))]
                         [version (dynamic-require module-name 'interface-version)])
                    (case version
                      [(v1)
                       (let ([timeout (dynamic-require module-name 'timeout)]
                             [start (dynamic-require module-name 'start)])
                         (make-cache-entry
                          (lambda (initial-request)
                            (adjust-timeout! timeout)
                            (start initial-request))
                          (current-namespace)))]
                      [else
                       (raise (format "unknown servlet version ~e" version))]))]
                 ;; response
                 [(response? s)
                  (letrec ([go (lambda ()
                                 (begin
                                   (set! go (lambda () (load/use-compiled a-path)))
                                   s))])
                    (make-cache-entry (lambda (initial-request) (go))
                                      (current-namespace)))]
                 [else
                  (raise 'load-servlet/path "Loading ~e produced ~n~e~n instead of a servlet." a-path s)])))))
    
    
      (define servlet-bin?
        (let ([svt-bin-re (regexp "^/servlets/.*")])
          (lambda (str)
            (regexp-match svt-bin-re str))))
    
    ;; return dispatcher
    (lambda (conn req)
      (let-values ([(uri method path) (decompose-request req)])
        (cond [(string=? "/conf/refresh-servlets" path)
                ;; more here - this is broken - only out of date or specifically mentioned
                ;; scripts should be flushed.  This destroys persistent state!
                (call-with-semaphore config:scripts-lock
                                     (lambda ()
                                       (set-box! config:scripts (make-hash-table 'equal))))
                (output-response/method
                 conn
                 ((responders-servlets-refreshed (host-responders host-info)))
                 method)]
              [(servlet-bin? path)
               (adjust-connection-timeout!
                conn
                (timeouts-servlet-connection (host-timeouts host-info)))
               ;; more here - make timeouts proportional to size of bindings
               (servlet-content-producer conn req host-info)]
              [else
               (next-dispatcher)])))))