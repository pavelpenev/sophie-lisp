;;;; Sophie Lisp ASDF system definition.
(asdf:defsystem "sophie-lisp"
  :description "Purely additive Common Lisp extensions."
  :version "1.0.0"
  :licence "MIT"
  :author "Pavel Penev"
  ;; BORDEAUX-THREADS and TRIVIAL-GARBAGE carry the implementation seam in
  ;; src/core/support.lisp: portable locks for identity hashing and portable
  ;; weak hash tables for identity retention.
  :depends-on ("named-readtables" "closer-mop" "alexandria"
               "bordeaux-threads" "trivial-garbage")
  :serial t
  :components ((:file "src/packages")
               (:module "src/core"
                :serial t
                :components ((:file "protocols")
                             (:file "support")
                             (:file "collectors")
                             (:file "traversal")
                             (:file "eager-traversal")
                             (:file "sources")
                             (:file "values")))
               (:module "src/containers"
                :serial t
                :components ((:file "trie")
                             (:file "providers")
                             (:file "set")
                             (:file "integration")
                             (:file "ordered-dictionary")
                             (:file "conversions")
                             (:file "operations")))
               (:module "src/sequences"
                :serial t
                :components ((:file "reconstruction")
                             (:file "aggregation")
                             (:file "transforms")
                             (:file "queries")
                             (:file "selection")
                             (:file "structure")))
               (:module "src/syntax"
                :serial t
                :components ((:file "reader")
                             (:file "patterns")
                             (:file "binding")
                             (:file "functions"))))
  :in-order-to ((asdf:test-op (asdf:test-op "sophie-lisp/tests"))))

(asdf:defsystem "sophie-lisp/tests"
  :depends-on ("sophie-lisp" "parachute")
  :serial t
  :components ((:file "tests/package")
               (:module "tests/core"
                :serial t
                :components ((:file "collectors")
                             (:file "traversal")
                             (:file "eager-traversal")
                             (:file "sources")
                             (:file "values")))
               (:module "tests/containers"
                :serial t
                :components ((:file "trie")
                             (:file "providers")
                             (:file "set")
                             (:file "integration")
                             (:file "ordered-dictionary")
                             (:file "conversions")
                             (:file "operations")))
               (:module "tests/sequences"
                :serial t
                :components ((:file "reconstruction")
                             (:file "aggregation")
                             (:file "transforms")
                             (:file "queries")
                             (:file "selection")
                             (:file "structure")))
               (:module "tests/syntax"
                :serial t
                :components ((:file "reader")
                             (:file "patterns")
                             (:file "binding")
                             (:file "functions")))
               (:module "tests/integration"
                :serial t
                :components ((:file "api")
                             (:file "core")
                             (:file "extensions")
                             (:file "complexity")
                             (:file "work-bounds")
                             (:file "claim-census")
                             (:file "acceptance"))))
  :perform (asdf:test-op (operation system)
             (declare (ignore operation system))
             (let ((report (uiop:symbol-call :parachute :test :sophie-lisp.tests)))
               (unless (eq :passed (uiop:symbol-call :parachute :status report))
                 (error "Sophie Lisp tests failed.")))))

(asdf:defsystem "sophie-lisp/benchmarks"
  ;; NAMED-READTABLES is listed directly because the reader benches reference
  ;; its package; SOPHIE-LISP already loads it transitively.
  :depends-on ("sophie-lisp" "named-readtables" "alexandria" "trivial-garbage")
  :serial t
  :components ((:file "benchmarks/package")
               (:file "benchmarks/host")
               (:file "benchmarks/harness")
               (:file "benchmarks/core/work-counters")
               (:file "benchmarks/core/hashing")
               (:file "benchmarks/containers/dict")
               (:file "benchmarks/containers/set")
               (:file "benchmarks/containers/ordered-dict")
               (:file "benchmarks/sequences/lazy")
               (:file "benchmarks/sequences/generic")
               (:file "benchmarks/core/facade")
               (:file "benchmarks/syntax/reader")
               (:file "benchmarks/syntax/macros")
               (:file "benchmarks/calibration")))
