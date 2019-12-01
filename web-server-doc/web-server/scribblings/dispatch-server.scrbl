#lang scribble/doc
@(require "web-server.rkt")

@title[#:tag "dispatch-server-unit"]{Dispatching Server}
@(require (for-label web-server/private/dispatch-server-unit
                     web-server/private/dispatch-server-sig
                     web-server/private/util
                     web-server/private/connection-manager
                     web-server/web-server
                     web-server/web-server-unit
                     web-server/web-config-sig
                     web-server/safety-limits
                     web-server/lang/stuff-url
                     web-server/http/request-structs
                     net/tcp-sig
                     racket/async-channel
                     racket/tcp
                     web-server/web-server-sig))

The @web-server is just a configuration of a dispatching server.

@section{Dispatching Server Signatures}

@defmodule[web-server/private/dispatch-server-sig]{

The @racketmodname[web-server/private/dispatch-server-sig] library
provides the signatures @racket[dispatch-server^], @racket[dispatch-server-connect^],
and @racket[dispatch-server-config*^].

@defsignature[dispatch-server^ ()]{

The @racket[dispatch-server^] signature is an alias for
@racket[web-server^].

 @defproc[(serve [#:confirmation-channel confirmation-ach
                  (or/c #f (async-channel/c
                            (or/c exn? port-number?)))
                  #f])
          (-> any)]{
   Runs the server.
   The confirmation channel, if provided, will be sent an exception if one occurs
   while starting the server or the port number if the server starts successfully.
   
   Calling the returned procedure shuts down the server.
 }

 @defproc[(serve-ports [ip input-port?]
                       [op output-port?])
          any]{
 Asynchronously serves a single connection represented by the ports @racket[ip] and
 @racket[op].
 }
}

@defsignature[dispatch-server-connect^ ()]{

The @racket[dispatch-server-connect^] signature abstracts the conversion of connection
ports (e.g., to implement SSL) as used by the dispatch server.

 @defproc[(port->real-ports [ip input-port?]
                            [op output-port?])
          (values input-port? output-port?)]{
  Converts connection ports as necessary.

  The connection ports are normally TCP ports, but an alternate
  implementation of @racket[tcp^] linked to the dispatcher can supply
  different kinds of ports.
 }
}

@defsignature[dispatch-server-config*^ ()]{

  @history[#:added "1.6"]
   
 @defthing[port listen-port-number?]{
   Specifies the port to serve on.
  }
 @defthing[listen-ip (or/c string? #f)]{
   Passed to @racket[tcp-listen].
  }
 @defproc[(read-request [c connection?]
                        [p listen-port-number?]
                        [port-addresses
                         (input-port? . -> . (values string? string?))])
          (values any/c boolean?)]{
   Defines the way the server reads requests off connections to be passed
   to @sigelem[dispatch-server-config*^ dispatch].
   The @racket[port-addresses] argument should be a procedure
   like @sigelem[tcp^ tcp-addresses].
   
   The first result of @sigelem[dispatch-server-config*^ read-request] is ordinarily a @racket[request] value,
   but that is not a requirement at the dispatch-server level.
   The second result is @racket[#true] if the connection @racket[c] should be closed
   after handling this request, or @racket[#false] if the connection may be reused.
 }
 @defthing[dispatch (-> connection? any/c any)]{
   Used to handle requests.
   The second argument to @sigelem[dispatch-server-config*^ dispatch] is ordinarily a @racket[request] value,
   like the first result of @sigelem[dispatch-server-config*^ read-request],
   but that is not a requirement at the dispatch-server level.
  }
 @defthing[safety-limits safety-limits?]{
   A @tech{safety limits} value specifying the policies to be used
   while reading and handling requests.
  }
}

}

@defsignature[dispatch-server-config^ (dispatch-server-config*^)]{
 @signature-desc[@deprecated[#:what "signature" @racket[dispatch-server-config*^]]]
  
 For backwards compatability, @racket[dispatch-server-config^]
 @racket[extends] @racket[dispatch-server-config*^] and uses @racket[define-values-for-export]
 to define @sigelem[dispatch-server-config*^ safety-limits] as:
 @racketblock[
 (make-safety-limits
  #:max-waiting #,(sigelem dispatch-server-config^ max-waiting)
  #:initial-connection-timeout #,(sigelem dispatch-server-config^ initial-connection-timeout))]
  
 @history[#:changed "1.6"
          @elem{Deprecated in favor of @racket[dispatch-server-config*^].
            See @elemref["safety-limits-porting"]{compatability note}.}]
 
 @defthing[max-waiting exact-nonnegative-integer?]{
  Passed to @racket[make-safety-limits].
 }
 @defthing[initial-connection-timeout timeout/c]{
  Passed to @racket[make-safety-limits].
  @history[#:changed "1.6"
           @elem{Loosened contract for consistency with @racket[make-safety-limits].}]
 }
}


@section{Safety Limits}
@defmodule[web-server/safety-limits]

@deftogether[
 (@defproc[(safety-limits? [v any/c]) boolean?]
   @defproc[(make-safety-limits
             [#:max-waiting max-waiting exact-nonnegative-integer? 511]
             [#:initial-connection-timeout initial-connection-timeout timeout/c 60]
             [#:request-read-timeout request-read-timeout timeout/c 60]
             [#:max-request-line-length max-request-line-length nonnegative-length/c
              (code:line (* 8 1024) (code:comment #,(elem "8 KiB")))]
             [#:max-request-headers max-request-headers nonnegative-length/c 100]
             [#:max-request-header-length max-request-header-length nonnegative-length/c
              (code:line (* 8 1024) (code:comment #,(elem "8 KiB")))]
             [#:max-request-body-length max-request-body-length nonnegative-length/c
              (code:line (* 1 1024 1024) (code:comment #,(elem "1 MiB")))]
             [#:max-request-files max-request-files nonnegative-length/c 100]
             [#:max-request-file-length max-request-file-length nonnegative-length/c
              (code:line (* 10 1024 1024) (code:comment #,(elem "10 MiB")))]
             [#:request-file-memory-threshold request-file-memory-threshold nonnegative-length/c
              (code:line (* 1 1024 1024) (code:comment #,(elem "1 MiB")))]
             [#:response-timeout response-timeout timeout/c 60]
             [#:response-send-timeout response-send-timeout timeout/c 60])
            safety-limits?]
   @defthing[nonnegative-length/c flat-contract?
             #:value (or/c exact-nonnegative-integer? +inf.0)]
   @defthing[timeout/c flat-contract?
             #:value (>=/c 0)])]{
 The web server uses opaque @deftech{safety limits} values, recognized
 by the predicate @racket[safety-limits?], to encapsulate
 policies for protection against misbehaving or malicious clients and servlets.
 Construct @tech{safety limits} values using @racket[make-safety-limits],
 which supplies reasonably safe default policies that should work for most applications.
 See the @elemref["safety-limits-porting"]{compatability note} and
  @racket[make-unlimited-safety-limits] for further details.

 The arguments to @racket[make-safety-limits] are used as follows:
 @itemlist[
 @item{The @racket[max-waiting] argument is passed to @racket[tcp-listen]
   to specify the maximum number of client connections that can be waiting for acceptance.
   When @racket[max-waiting] clients are waiting for acceptance, no new client connections can be made.
   }
  @item{The @racket[initial-connection-timeout] specifies the initial timeout,
   in seconds, given to each connection.
   }
 @item{The @racket[request-read-timeout] limits how long, in seconds,
   the standard @sigelem[dispatch-server-config*^ read-request] implementation
   (e.g. from @racket[serve] or @racket[web-server@])
   will wait for request data to come in from the client
   before it closes the connection.
   If you need to support large file uploads over slow connections,
   you may need to adjust this value.
   }
 @item{The @racket[max-request-line-length] limits the length (in bytes) of the
   the first line of an HTTP request (the ``request line''),
   which specifies the request method, path, and protocol version.
   Requests with a first line longer than @racket[max-request-line-length]
   are rejected by the standard @sigelem[dispatch-server-config*^ read-request]
   implementation (e.g. from @racket[serve] or @racket[web-server@]).
   Increase this if you have very long URLs, but see also @racket[is-url-too-big?].
   }
 @item{The @racket[max-request-headers] and @racket[max-request-header-length]
   arguments limit the number of headers allowed per HTTP request
   and the length, in bytes, of an individual request header, respectively.
   Requests that exceed these limits are rejected by the standard
   @sigelem[dispatch-server-config*^ read-request]
   implementation (e.g. from @racket[serve] or @racket[web-server@]).
   }
 @item{The @racket[max-request-body-length] limits the size, in byetes,
   of HTTP request bodies---but it does not apply to multipart (file upload)
   requests: see @racket[max-request-files] and @racket[max-request-file-length], below.
   Requests with bodies longer than @racket[max-request-body-length]
   are rejected by the standard @sigelem[dispatch-server-config*^ read-request]
   implementation (e.g. from @racket[serve] or @racket[web-server@]).
   }
 @item{The @racket[max-request-files], @racket[max-request-file-length],
   and @racket[request-file-memory-threshold] arguments control the handling of
   multipart (file upload) requests by the standard
   @sigelem[dispatch-server-config*^ read-request]
   implementation (e.g. from @racket[serve] or @racket[web-server@]).
   
   The number of files per request is limited by @racket[max-request-files],
   and @racket[max-request-file-length] limits the length, in bytes,
   of each field in a multipart request (i.e. the maximum size of an individual file).
   Requests that exceed these limits are rejected.

   Files longer than @racket[request-file-memory-threshold], in bytes,
   are automatically offloaded to disk as temporary files
   to avoid running out of memory.
   }
 @item{The @racket[response-timeout] and @racket[response-send-timeout]
   arguments limit the time for which individual request handlers
   (as in @sigelem[dispatch-server-config*^ dispatch]) are allowed to run.

   The @racket[response-timeout] specifies the maximum time, in seconds,
   that a handler is allowed to run after the request has been read
   before it writes its first byte of response data.
   If no data is written within this time limit, the connection is killed.

   The @racket[response-send-timeout] specifies the maximum time, in seconds,
   that the server will wait for a chunk of response data.
   Each time a chunk of data is sent to the client, this timeout resets.
   If your application uses streaming responses or long polling,
   either adjust this value or make sure that your request handler sends
   data periodically, such as a no-op, to avoid hitting this limit.
   }]


 @elemtag["safety-limits-porting"]{@bold{Compatibility note:}}
 The @tech{safety limits} type may be extended in the future to provide
 additional protections.
 Creating @tech{safety limits} values with @racket[make-safety-limits]
 will allow applications to take advantage of reasonable default values
 for any new limits that are added.
 However, adding new limits does have the potential to break some existing
 applications: as an alternative, the @racket[make-unlimited-safety-limits]
 constructor uses default values that avoid imposing any limits that
 aren't explicitly specified. (In most cases, this means a default of @racket[+inf.0].)
 Of course, applications using @racket[make-unlimited-safety-limits]
 may remain vulnerable to threats which the values from @racket[make-safety-limits]
 would have protected against.

 The @tech{safety limits} type was introduced in version 1.6 of the
 @tt{web-server-lib} package.
 Previous versions of this library only supported the @racket[max-waiting] and
 @racket[initial-connection-timeout] limits, which were specified
 through @racket[dispatch-server-config^], @racket[web-config^], and optional
 arguments to functions like @racket[serve].
 If those limits weren't explicitly supplied, the default behavior
 was closest to using
 @racket[(make-unlimited-safety-limits #:initial-connection-timeout 60)].
 However, version 1.6 adopted @racket[make-safety-limits] as the default,
 as most applications would benefit from using reasonable protections.
 When porting from earlier versions of this library,
 if you think your application may be especially resource-intensive,
 you may prefer to use @racket[make-unlimited-safety-limits] while determining
 limits that work for your application.
     
 @history[#:added "1.6"]
}

@defproc[(make-unlimited-safety-limits
          [#:max-waiting max-waiting exact-nonnegative-integer? 511]
          [#:initial-connection-timeout initial-connection-timeout timeout/c +inf.0]
          [#:request-read-timeout request-read-timeout timeout/c +inf.0]
          [#:max-request-line-length max-request-line-length nonnegative-length/c +inf.0]
          [#:max-request-headers max-request-headers nonnegative-length/c +inf.0]
          [#:max-request-header-length max-request-header-length nonnegative-length/c +inf.0]
          [#:max-request-body-length max-request-body-length nonnegative-length/c +inf.0]
          [#:max-request-files max-request-files nonnegative-length/c +inf.0]
          [#:max-request-file-length max-request-file-length nonnegative-length/c +inf.0]
          [#:request-file-memory-threshold request-file-memory-threshold nonnegative-length/c +inf.0]
          [#:response-timeout response-timeout timeout/c +inf.0]
          [#:response-send-timeout response-send-timeout timeout/c +inf.0])
         safety-limits?]{
 Like @racket[make-safety-limits], but with default values that avoid
 imposing any limits that aren't explicitly specified,
 rather than the safer defaults of @racket[make-safety-limits].
 Think carefully before using @racket[make-unlimited-safety-limits],
 as it may leave your application vulnerable to denial of service attacks
 or other threats that the default values from @racket[make-safety-limits] would mitigate.

 Note that the default value for @racket[max-waiting] is @racket[511],
 @italic{not} @racket[+inf.0], due to the contract of @racket[tcp-listen].
      
 @history[#:added "1.6"]
}




@section{Dispatching Server Unit}

@defmodule[web-server/private/dispatch-server-unit]

The @racketmodname[web-server/private/dispatch-server-unit] module
provides the unit that actually implements a dispatching server.

@defthing[dispatch-server-with-connect@ (unit/c (import tcp^
                                                        dispatch-server-connect^
                                                        dispatch-server-config*^)
                                                (export dispatch-server^))]{
 Runs the dispatching server config in a very basic way, except that it uses
 @secref["connection-manager"] to manage connections.

 @history[#:added "1.1"
          #:changed "1.6"
          @elem{Use @racket[dispatch-server-config*^]
            rather than @racket[dispatch-server-config^].
            See @elemref["safety-limits-porting"]{compatability note}.}]
}


@defthing[dispatch-server@ (unit/c (import tcp^
                                           dispatch-server-config*^)
                                   (export dispatch-server^))]{
 Like @racket[dispatch-server-with-connect@], but using @racket[raw:dispatch-server-connect@].

 @history[#:changed "1.6"
          @elem{Use @racket[dispatch-server-config*^]
            rather than @racket[dispatch-server-config^].
            See @elemref["safety-limits-porting"]{compatability note}.}]
}


@section{Threads and Custodians}

The dispatching server runs in a dedicated thread. Every time a connection is initiated, a new thread is started to handle it.
Connection threads are created inside a dedicated custodian that is a child of the server's custodian. When the server is used to
provide servlets, each servlet also receives a new custodian that is a child of the server's custodian @bold{not} the connection
custodian.
