(defpackage #:sophie-lisp.benchmarks
  (:use #:cl #:sophie-lisp-extensions)
  (:export #:host-name
           #:measure-timer-resolution
           #:full-gc
           #:gc-count
           #:bench-compiled-p
           #:default-size-cap
           #:with-allocation-bytes
           #:define-bench
           #:find-bench
           #:registered-benches
           #:run-benchmarks
           #:run-allocation-pass
           #:default-measurement-params
           #:compare-runs)
  (:documentation "Sophie Lisp benchmark suite."))
