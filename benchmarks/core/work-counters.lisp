;;;; Work counters: HASH-CODE and EQUALS dispatch counting, kept strictly
;;;; separate from timed runs.
;;;;
;;;; The counters answer "how much protocol work does this operation perform?"
;;;; outside every timed region. WITH-WORK-COUNTERS attaches counting :BEFORE
;;;; methods to the SL generics HASH-CODE and EQUALS for the dynamic extent of
;;;; its body and detaches them on any exit, so nothing survives the form and
;;;; timed benches never see instrumentation. The counting methods increment
;;;; the counters only while the dynamic flag *WORK-COUNTERS-ACTIVE* is
;;;; bound. The attach/detach cycle is portable ANSI CLOS (DEFMETHOD,
;;;; FIND-METHOD, ADD-METHOD, REMOVE-METHOD); no reader feature conditionals
;;;; appear in this file.
;;;;
;;;; The counters measure dispatches, not full recursive computations: a
;;;; :BEFORE method runs on every generic invocation of HASH-CODE or EQUALS,
;;;; including invocations whose result the structural-hash memoization then
;;;; serves from the per-invocation table without recursive descent.
;;;; Memoization stays fully active while counting: HASH-CODE's T-specialized
;;;; :AROUND method (the memoization entry point defined in
;;;; src/containers/trie.lisp) is never suspended or displaced, and the
;;;; counting methods carry :BEFORE qualifiers, so no method definition is
;;;; ever replaced and no host reports a duplicate method. The memoization
;;;; payoff is visible in the counts: a shared-substructure DAG dispatches
;;;; each shared object again but never re-descends into it, so its dispatch
;;;; count grows with the unique objects, not the node references.

(in-package #:sophie-lisp.benchmarks)

(eval-when (:compile-toplevel :load-toplevel :execute)
  ;; The package definition lives in benchmarks/package.lisp. Exporting here as
  ;; well keeps the work-counter API usable with single-colon qualification
  ;; even when the package definition does not list these symbols.
  (export '(with-work-counters reset-work-counters hash-call-count
            equals-call-count work-count-check)))

;;; Counters and state.

(defvar *hash-calls* 0
  "Number of HASH-CODE dispatches counted inside WITH-WORK-COUNTERS.")
(defvar *equals-calls* 0
  "Number of EQUALS dispatches counted inside WITH-WORK-COUNTERS.")
(defvar *work-counters-active* nil
  "Bound to true inside WITH-WORK-COUNTERS; the counting methods increment
the counters only while this flag is bound.")
(defvar *work-counter-depth* 0
  "Dynamic nesting depth of WITH-WORK-COUNTERS forms; only the outermost form
attaches and detaches the counting methods.")
(defvar *hash-code-counter-method* nil
  "The counting :BEFORE method for HASH-CODE, captured at load time and
attached per WITH-WORK-COUNTERS entry.")
(defvar *equals-counter-method* nil
  "The counting :BEFORE method for EQUALS, captured at load time and attached
per WITH-WORK-COUNTERS entry.")

(defun t-specialized-before-method (generic-function argument-count)
  "Return the T-specialized :BEFORE method of GENERIC-FUNCTION, which must
have ARGUMENT-COUNT required arguments, or NIL when there is none.
FIND-METHOD signals an error when no method matches, so the lookup is
guarded."
  (ignore-errors
    (find-method generic-function '(:before)
                 (make-list argument-count :initial-element (find-class 't)))))

;;; The counting :BEFORE methods.
;;;
;;; A :BEFORE method runs inside HASH-CODE's memoization :AROUND (defined in
;;; src/containers/trie.lisp) and before the primary method, so it observes
;;; every dispatch while memoization remains fully active: a dispatch whose
;;; result the memoization table serves without recursive descent is still
;;; counted, and the dispatch count is therefore the count of generic
;;; invocations, not of full recursive hash computations. The :BEFORE
;;; qualifiers match no method the implementation defines, so defining,
;;; capturing, and re-attaching these methods displaces nothing and no host
;;; reports a duplicate method definition. The methods are defined at load
;;; time, captured, and detached immediately; WITH-WORK-COUNTERS re-attaches
;;; them per entry.

(defmethod hash-code :before ((object t))
  "Count one HASH-CODE dispatch while the work counters are active."
  (when *work-counters-active*
    (incf *hash-calls*)))

(defmethod equals :before ((object1 t) (object2 t))
  "Count one EQUALS dispatch while the work counters are active."
  (when *work-counters-active*
    (incf *equals-calls*)))

(defun capture-work-counter-methods ()
  "Capture the counting :BEFORE methods defined above and detach them. After
this file loads, neither generic function carries any instrumentation; the
implementation's own methods, including HASH-CODE's memoization :AROUND, are
never touched."
  (setf *hash-code-counter-method* (t-specialized-before-method #'hash-code 1)
        *equals-counter-method* (t-specialized-before-method #'equals 2))
  (remove-method #'hash-code *hash-code-counter-method*)
  (remove-method #'equals *equals-counter-method*)
  (values))

(capture-work-counter-methods)

;;; Attach and detach. ADD-METHOD replaces any method with the same
;;; qualifiers and specializers; the counting :BEFORE methods match no
;;; existing method, so attaching them displaces nothing and there is
;;; nothing to restore on detach.

(defun attach-work-counter-methods ()
  "Attach the counting :BEFORE methods to HASH-CODE and EQUALS. Nothing is
suspended: the counting methods carry qualifiers no implementation method
uses, so ADD-METHOD displaces nothing and HASH-CODE's memoization :AROUND
stays active. Nested WITH-WORK-COUNTERS forms attach nothing; the outermost
form owns the attach/detach cycle."
  (when (= *work-counter-depth* 1)
    (add-method #'hash-code *hash-code-counter-method*)
    (add-method #'equals *equals-counter-method*))
  (values))

(defun detach-work-counter-methods ()
  "Detach the counting :BEFORE methods, leaving no instrumentation on either
generic function and every implementation method, including HASH-CODE's
memoization :AROUND, attached. Nested WITH-WORK-COUNTERS forms detach
nothing; the outermost form owns the attach/detach cycle."
  (when (= *work-counter-depth* 1)
    (remove-method #'hash-code *hash-code-counter-method*)
    (remove-method #'equals *equals-counter-method*))
  (values))

(defmacro with-work-counters (&body body)
  "Run BODY with the HASH-CODE and EQUALS work counters active and return the
values of BODY. The counting :BEFORE methods are attached for the dynamic
extent of BODY and detached on any exit, so nothing persists after the form
and timed benches never see instrumentation. The counters count every
HASH-CODE and EQUALS dispatch, including dispatches served from the
per-invocation memoization table without recursive descent; memoization
itself stays active throughout. The counters are not reset on entry; call
RESET-WORK-COUNTERS first when a fresh count is wanted. Nested
WITH-WORK-COUNTERS forms keep the outermost form's attach/detach cycle."
  `(let ((*work-counters-active* t)
         (*work-counter-depth* (1+ *work-counter-depth*)))
     (unwind-protect
          (progn
            (attach-work-counter-methods)
            ,@body)
       (detach-work-counter-methods))))

;;; Counter access.

(defun reset-work-counters ()
  "Zero both work counters."
  (setf *hash-calls* 0 *equals-calls* 0)
  (values))

(defun hash-call-count ()
  "Return the number of HASH-CODE dispatches counted so far."
  *hash-calls*)

(defun equals-call-count ()
  "Return the number of EQUALS dispatches counted so far."
  *equals-calls*)

;;; Self check.

(defun work-count-check ()
  "Verify the work-counter instrumentation end to end and return T, or signal
an error. Outside WITH-WORK-COUNTERS the counters must not move. Inside, a
flat HASH-CODE or EQUALS call must count exactly one dispatch with no
cross-talk, the known 3-element list must count the expected structural
amount: at least four HASH-CODE dispatches (the list and each element) and
at least two EQUALS dispatches (the pair and the first element pair), and
memoization must stay active: hashing a shape with shared substructure must
count strictly fewer HASH-CODE dispatches than hashing the same shape built
from fresh copies, because the shared object is dispatched again but served
from the per-invocation memoization table without recursive descent. After
the form exits, both generic functions must still work, the counters must be
frozen again, and the hash of the known list must equal the hash taken before
instrumentation was ever attached."
  ;; Outside the form: no counting.
  (reset-work-counters)
  (let ((outside-hash (hash-code '(1 2 3))))
    (equals '(1 2 3) '(1 2 3))
    (unless (and (zerop (hash-call-count)) (zerop (equals-call-count)))
      (error "Work counters moved outside WITH-WORK-COUNTERS: ~D hash and ~D equals."
             (hash-call-count) (equals-call-count)))
    (with-work-counters
      ;; Flat calls: exactly one dispatch each, and no cross-talk.
      (reset-work-counters)
      (hash-code 42)
      (unless (and (= 1 (hash-call-count)) (zerop (equals-call-count)))
        (error "HASH-CODE on a fixnum counted ~D dispatches, expected exactly 1."
               (hash-call-count)))
      (reset-work-counters)
      (equals 42 42)
      (unless (and (zerop (hash-call-count)) (= 1 (equals-call-count)))
        (error "EQUALS on two fixnums counted ~D dispatches, expected exactly 1."
               (equals-call-count)))
      ;; Known structure: the 3-element list must reach HASH-CODE for itself
      ;; and each element, and EQUALS for the pair and the first element pair.
      (reset-work-counters)
      (hash-code '(1 2 3))
      (unless (>= (hash-call-count) 4)
        (error "Hashing a 3-element list counted ~D HASH-CODE dispatches, ~
                expected at least 4."
               (hash-call-count)))
      (unless (zerop (equals-call-count))
        (error "Hashing a list counted ~D EQUALS dispatches, expected 0."
               (equals-call-count)))
      (reset-work-counters)
      (equals '(1 2 3) '(1 2 3))
      (unless (>= (equals-call-count) 2)
        (error "Comparing two 3-element lists counted ~D EQUALS dispatches, ~
                expected at least 2."
               (equals-call-count)))
      (unless (zerop (hash-call-count))
        (error "Comparing lists counted ~D HASH-CODE dispatches, expected 0."
               (hash-call-count)))
      ;; Memoization stays active while counting: the shared substructure is
      ;; dispatched again but served from the per-invocation memoization
      ;; table, so it must count strictly fewer HASH-CODE dispatches than the
      ;; same shape built from fresh, structurally equal copies.
      (reset-work-counters)
      (let ((shared (list 1 2 3)))
        (hash-code (cons shared shared)))
      (let ((shared-count (hash-call-count)))
        (reset-work-counters)
        (hash-code (cons (list 1 2 3) (list 1 2 3)))
        (unless (< shared-count (hash-call-count))
          (error "Memoization is not active inside WITH-WORK-COUNTERS: ~
                  shared substructure counted ~D HASH-CODE dispatches ~
                  against ~D for fresh copies."
                 shared-count (hash-call-count)))))
    ;; After the form: instrumentation gone, generic functions still work.
    (reset-work-counters)
    (unless (integerp (hash-code '(1 2 3)))
      (error "HASH-CODE stopped working after WITH-WORK-COUNTERS exited."))
    (unless (equals '(1 2 3) '(1 2 3))
      (error "EQUALS stopped working after WITH-WORK-COUNTERS exited."))
    (unless (and (zerop (hash-call-count)) (zerop (equals-call-count)))
      (error "Work counters moved after WITH-WORK-COUNTERS exited: ~D hash ~
              and ~D equals."
             (hash-call-count) (equals-call-count)))
    (unless (= outside-hash (hash-code '(1 2 3)))
      (error "HASH-CODE changed results after WITH-WORK-COUNTERS exited.")))
  t)
