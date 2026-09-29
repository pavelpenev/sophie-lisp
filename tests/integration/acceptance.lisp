;;;; Acceptance tests: host, ASDF, and dependency verification.
(in-package #:sophie-lisp.tests)








(parachute:define-test acceptance.host-dependencies-and-conversions
  ;; The supported-host set is pinned here: SBCL (reference), CCL, and ECL.
  (parachute:true (member (lisp-implementation-type)
                          '("SBCL" "Clozure Common Lisp" "ECL")
                          :test #'string=))
  (parachute:true (asdf:asdf-version))
  (dolist (system '("named-readtables" "closer-mop" "parachute"))
    (parachute:true (asdf:component-version (asdf:find-system system))))
  (parachute:is equal '(#\x)
                (integration-list (sl:seq-trim (coerce (append (mapcar #'code-char '(9 10 11 12 13 32))
                                                      '(#\x) (mapcar #'code-char '(9 10 11 12 13 32)))
                                             'string))))
  (parachute:is equal '(1 2) (sl:seq-into 'list #(1 2)))
  (parachute:is equalp #(1 2) (sl:seq-into 'vector '(1 2)))
  (parachute:is string= "ab" (sl:seq-into 'string '(#\a #\b)))
  (parachute:fail (sl:seq-into '(sl:lazy-seq :element-type t) '(1)) program-error)
  (parachute:fail (sl:seq-into 'extension-cache '(1)) type-error))
