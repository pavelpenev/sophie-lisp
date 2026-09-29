;;;; Demand-driven callback sources.

(in-package #:sophie-lisp.internal)

(defstruct (repeatedly-state
             (:constructor make-repeatedly-state (remaining)))
  remaining)

(defstruct (iterate-state
             (:constructor make-iterate-state (current started-p)))
  current
  started-p)

(defun source-function (designator)
  "Resolve a retained callback designator at invocation time."
  (cond
    ((functionp designator)
     designator)
    ((symbolp designator)
     (when (or (macro-function designator)
               (special-operator-p designator))
       (raise-type-error designator '(or function symbol)))
     ;; FDEFINITION supplies the required UNDEFINED-FUNCTION condition when a
     ;; symbol that was valid at construction has since become unbound.
     (fdefinition designator))
    (t
     (raise-type-error designator '(or function symbol)))))

(defun invoke-source-function (designator arguments)
  "Invoke DESIGNATOR with ARGUMENTS and retain only its primary value."
  ;; Force-time arity conformance relies on the host condition from APPLY: SBCL
  ;; signals SIMPLE-PROGRAM-ERROR (a PROGRAM-ERROR) for wrong-arity invocations.
  (values (apply (source-function designator) arguments)))

(defun callback-source-node (designator state)
  "Construct the next unresolved node for a callback source."
  (sl:make-lazy-seq
   (lambda ()
     (cond
       ((typep state 'repeatedly-state)
        (let ((remaining (repeatedly-state-remaining state)))
          (if (and (integerp remaining) (zerop remaining))
              nil
              (let ((value (invoke-source-function designator nil)))
                ;; State advances only after a successful callback invocation.
                (when (integerp remaining)
                  (decf (repeatedly-state-remaining state)))
                (sl:lazy-cons
                 value
                 (callback-source-node designator state))))))
       ((typep state 'iterate-state)
        (if (not (iterate-state-started-p state))
            (progn
              (setf (iterate-state-started-p state) t)
              (sl:lazy-cons
               (iterate-state-current state)
               (callback-source-node designator state)))
            (let ((value
                    (invoke-source-function
                     designator
                     (list (iterate-state-current state)))))
              ;; A failed/non-local callback leaves CURRENT unchanged, so the
              ;; unresolved node retries the same transition.
              (setf (iterate-state-current state) value)
              (sl:lazy-cons
               value
               (callback-source-node designator state)))))
       (t
        (raise-program-error "Invalid callback source state ~S." state))))))

(defun sl:repeatedly (function &key count)
  "Return a lazy source of successive zero-argument callback values. When COUNT
is a non-negative integer, the source is bounded; when COUNT is NIL (the
default), the source is unbounded. FUNCTION is a usable function designator; a
symbol is resolved to its current global definition at each demand. An unbound
symbol signals UNDEFINED-FUNCTION when demanded; a function that does not
accept zero arguments signals PROGRAM-ERROR when called."
  (let ((designator (usable-function function)))
    (unless (or (null count)
                (and (integerp count) (not (minusp count))))
      (raise-type-error count '(or null (integer 0 *))))
    (callback-source-node
     designator
     (make-repeatedly-state count))))

(defun sl:iterate (function initial)
  "Return a lazy sequence starting with INITIAL. Later elements are successive
applications of FUNCTION to the preceding primary value. FUNCTION is a usable
function designator, resolved at each demand-time invocation; an unbound
symbol signals UNDEFINED-FUNCTION when demanded, and a function that does not
accept one argument signals PROGRAM-ERROR when called."
  (let ((designator (usable-function function)))
    (callback-source-node
     designator
     (make-iterate-state initial nil))))

(defun range-in-bounds-p (current end step)
  "Return true when CURRENT is an element of the exclusive range."
  (or (null end)
      (if (plusp step)
          (< current end)
          (> current end))))

(defun range-node (current end step)
  "Construct one unresolved range node without doing the next addition."
  (sl:make-lazy-seq
   (lambda ()
     (if (range-in-bounds-p current end step)
         (sl:lazy-cons
          current
          ;; The addition belongs to the successor's force, not to this
          ;; node's construction or force.
          (sl:make-lazy-seq
           (lambda ()
             (range-node (+ current step) end step))))
         nil))))

(defun sl:range (&key (start 0) end (step 1))
  "Return a lazy arithmetic progression from START (default 0) with step STEP (default 1).
END is exclusive; when END is NIL (the default), the source is unbounded."
  (unless (realp start)
    (raise-type-error start 'real))
  (unless (or (null end) (realp end))
    (raise-type-error end '(or null real)))
  (unless (and (realp step) (not (zerop step)))
    (raise-type-error step '(and real (not (satisfies zerop)))))
  (range-node start end step))

(defstruct (cycle-state (:constructor make-cycle-state (source)))
  source
  view
  (view-established-p nil)
  ;; Adjustable vectors provide amortized-linear growth without rebuilding a
  ;; captured prefix on every demand.  The prefix is retained even though the
  ;; output nodes also retain the values, because it is the cycle's explicit
  ;; replay record.
  (prefix (make-array 16 :adjustable t :fill-pointer 0))
  ;; One output node is made for each demanded position.  In the finite case,
  ;; the first replay node points back to position 1, making the resolved
  ;; output an actual lazy-node cycle that SEQ-LENGTH can recognize.
  (nodes (make-array 16 :adjustable t :fill-pointer 0)))

(declaim (ftype (function (t t) t) cycle-node cycle-demand))

(defun cycle-node (state position)
  "Return the memoized output node for POSITION, creating it if necessary."
  (let ((nodes (cycle-state-nodes state)))
    (if (< position (fill-pointer nodes))
        (aref nodes position)
        (progn
          ;; Nodes are allocated in traversal order.  A finite replay may
          ;; request an already existing position (position 1), which is the
          ;; branch above and does not allocate another node.
          (unless (= position (fill-pointer nodes))
            (raise-program-error "Invalid cycle output position ~S." position))
          (vector-push-extend
           (sl:make-lazy-seq
            (lambda () (cycle-demand state position)))
           nodes)
          (aref nodes position)))))

(defun cycle-establish-view (state)
  "Open the cycle's one source view, without forcing its first position."
  (unless (cycle-state-view-established-p state)
    ;; CYCLE performs its required call-time validation before this state is
    ;; created.  OPEN-VIEW establishes the retained traversal representation;
    ;; its own protocol validation is deliberately still allowed to occur at
    ;; first demand for the normal traversal boundary.
    (setf (cycle-state-view state)
          (open-view (cycle-state-source state))
          (cycle-state-view-established-p state) t))
  (cycle-state-view state))

(defun cycle-demand (state position)
  "Resolve one output position, capturing or entering replay as appropriate."
  (let ((view (cycle-establish-view state)))
    (multiple-value-bind (empty-p element rest) (view-step view)
      (if empty-p
          ;; The first empty observation is the end of a finite view.  Its
          ;; position is the first replay node; its rest is the already-created
          ;; node at position 1, so replay is stable by EQ and does not revisit
          ;; the source.  NIL at position zero remains a lazy empty result.
          (if (zerop (fill-pointer (cycle-state-prefix state)))
              nil
              (sl:lazy-cons
               (aref (cycle-state-prefix state) 0)
               (cycle-node state 1)))
          (progn
            ;; Only a successful source step changes the retained view and
            ;; prefix.  An escaped condition therefore leaves this position
            ;; unresolved and retryable with the prior prefix intact.
            (vector-push-extend element (cycle-state-prefix state))
            (setf (cycle-state-view state) rest)
            (sl:lazy-cons element (cycle-node state (1+ position))))))))

(defun sl:cycle (source)
  "Return a lazy sequence repeating one traversal view of SOURCE: empty when the
view is empty, unbounded replaying the captured elements when the view is
finite and nonempty, and unbounded without replay when the view is unbounded."
  ;; This is intentionally the only construction-time observation.  In
  ;; particular, no view is opened and no source position is demanded here.
  (unless (seqablep source)
    (raise-type-error source '(satisfies seqablep)))
  (let* ((state (make-cycle-state source))
         (root (cycle-node state 0)))
    root))
