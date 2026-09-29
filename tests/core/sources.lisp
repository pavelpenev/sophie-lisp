;;;; Independent S-SOURCES-CALLBACK acceptance: REPEATEDLY and ITERATE.
(in-package #:sophie-lisp.tests)

(defun sources-callback-step (node)
  (if (sl:seq-emptyp node)
      (list t nil nil)
      (list nil (sl:seq-first node) (sl:seq-rest node))))

(defun sources-callback-check-step (node empty-p &optional value rest)
  (let ((values (sources-callback-step node)))
    (parachute:is eq empty-p (first values))
    (unless empty-p
      (parachute:is eql value (second values))
      (parachute:is eq rest (third values)))))

(parachute:define-test repeatedly-and-iterate.input-validation
  (dolist (bad (list nil t 17 "callback" '(lambda () nil)
                    (gensym "UNBOUND-CALLBACK-")))
    (parachute:fail (sl:repeatedly bad) type-error)
    (parachute:fail (sl:iterate bad :initial) type-error))
  (dolist (bad-count (list -1 1.5d0 :not-an-integer t))
    (parachute:fail
     (sl:repeatedly (lambda () :value) :count bad-count)
     type-error)))

(parachute:define-test repeatedly-and-iterate.lazy-construction-and-state-isolation
  (let ((calls 0)
        (initial (list :initial)))
    (flet ((zero-argument ()
             (incf calls)
             :generated)
           (one-argument (value)
             (declare (ignore value))
             (incf calls)
             :advanced))
      (let ((repeated (sl:repeatedly #'zero-argument :count 0))
            (iterated (sl:iterate #'one-argument initial)))
        (parachute:true (typep repeated 'sl:lazy-seq))
        (parachute:true (typep iterated 'sl:lazy-seq))
        (parachute:is = 0 calls)
        (sources-callback-check-step repeated t)
        (sources-callback-check-step iterated nil initial
                                      (third (sources-callback-step iterated)))
        ;; ITERATE's initial element is not a transition.
        (parachute:is = 0 calls))))
  ;; Two calls retain independent lazy state and memoization, even when they
  ;; retain the same function object.
  (let ((calls 0))
    (let* ((function-object (lambda () (incf calls) :same))
           (left (sl:repeatedly function-object :count 2))
           (right (sl:repeatedly function-object :count 2))
           (left-rest (third (sources-callback-step left)))
           (right-rest (third (sources-callback-step right))))
      (parachute:false (eq left right))
      (parachute:is = 2 calls)
      (sources-callback-check-step left-rest nil :same
                                   (third (sources-callback-step left-rest)))
      (sources-callback-check-step right-rest nil :same
                                   (third (sources-callback-step right-rest)))
      (parachute:is = 4 calls))))

(parachute:define-test repeatedly.callback-laziness-memoization-and-unbounded
  (let ((calls 0))
    (let* ((node
             (sl:repeatedly
              (lambda ()
                (incf calls)
                (values (list :value calls) :ignored-secondary-value))
              :count 2))
           (first-values (sources-callback-step node))
           (rest (third first-values)))
      (parachute:is = 1 calls)
      (parachute:is equal '(:value 1) (second first-values))
      (parachute:is eq rest (third (sources-callback-step node)))
      (parachute:is = 1 calls)
      (let* ((second-values (sources-callback-step rest))
             (empty (third second-values)))
        (parachute:is = 2 calls)
        (parachute:is equal '(:value 2) (second second-values))
        (sources-callback-check-step empty t)
        (parachute:is = 2 calls))))
  ;; NIL count is unbounded, but only the demanded prefix invokes the callback.
  (let ((calls 0))
    (let ((node (sl:repeatedly (lambda () (incf calls) :unbounded))))
      (parachute:is = 0 calls)
      (sources-callback-check-step node nil :unbounded
                                   (third (sources-callback-step node)))
      (parachute:is = 1 calls))))

(parachute:define-test repeatedly.symbol-resolution-at-force-time
  (let ((callback (gensym "REDEFINABLE-CALLBACK-")))
    (unwind-protect
         (progn
           (setf (symbol-function callback) (lambda () :first-definition))
           (let ((node (sl:repeatedly callback :count 1)))
             (setf (symbol-function callback)
                   (lambda () :second-definition))
             (parachute:is eql :second-definition
                           (second (sources-callback-step node))))
           ;; A symbol is usable when constructed while bound, but lookup is
           ;; still deferred until force time.
           (let ((node (sl:repeatedly callback :count 1))
                 (condition nil))
             (fmakunbound callback)
             (setf condition
                   (handler-case
                       (progn (sources-callback-step node) nil)
                     (undefined-function (caught) caught)))
             (parachute:true (typep condition 'undefined-function))
             (setf (symbol-function callback) (lambda () :rebound-definition))
             (parachute:is eql :rebound-definition
                           (second (sources-callback-step node))))
           ;; A function object is retained as that object, rather than being
           ;; replaced by any later global definition of a related symbol.
           (let ((function-object (lambda () :captured-function-object))
                 (node nil))
             (setf node (sl:repeatedly function-object :count 1))
             (setf (symbol-function callback) (lambda () :unrelated-definition))
             (parachute:is eql :captured-function-object
                           (second (sources-callback-step node)))))
      (when (fboundp callback)
        (fmakunbound callback)))))

(parachute:define-test repeatedly-and-iterate.callback-arity-retry
  (let ((callback (gensym "ARITY-CALLBACK-"))
        (condition nil))
    (unwind-protect
         (progn
           (setf (symbol-function callback) (lambda (argument)
                                              (declare (ignore argument))
                                              :wrong-arity))
           (let ((node (sl:repeatedly callback :count 1)))
             (setf condition
                   (handler-case
                       (progn (sources-callback-step node) nil)
                     (program-error (caught) caught)))
             (parachute:true (typep condition 'program-error))
             (setf (symbol-function callback)
                   (lambda () (values :recovered :secondary)))
             (sources-callback-check-step node nil :recovered
                                          (third (sources-callback-step node))))
           ;; The same force-time arity rule applies to ITERATE, but its first
           ;; node is the supplied initial object and does not invoke the fn.
           (setf (symbol-function callback) (lambda () :wrong-arity))
           (let* ((initial (list :initial))
                  (node (sl:iterate callback initial))
                  (rest (third (sources-callback-step node))))
             (setf condition
                   (handler-case
                       (progn (sources-callback-step rest) nil)
                     (program-error (caught) caught)))
             (parachute:true (typep condition 'program-error))
             (setf (symbol-function callback)
                   (lambda (value) (declare (ignore value)) :iterated-recovery))
             (sources-callback-check-step rest nil :iterated-recovery
                                          (third (sources-callback-step rest)))))
      (when (fboundp callback)
        (fmakunbound callback)))))

(parachute:define-test iterate.callback-failure-retry-retains-current
  (dolist (failure '(:condition :exit))
    (let* ((tag (gensym "ITERATE-CALLBACK-ESCAPE-"))
           (initial (list :initial))
           (condition (make-condition 'simple-error
                                      :format-control "callback failure"))
           (phase failure)
           (arguments nil)
           (node
             (sl:iterate
              (lambda (value)
                (push value arguments)
                (ecase phase
                  (:condition (error condition))
                  (:exit (throw tag condition))
                  (:success (list :next value))))
              initial))
           (rest (third (sources-callback-step node))))
      (let ((caught
              (ecase failure
                (:condition
                 (handler-case
                     (progn (sources-callback-step rest) nil)
                   (simple-error (caught) caught)))
                (:exit
                 (catch tag
                   (sources-callback-step rest)
                   :normal-completion)))))
        (parachute:is eq condition caught))
      ;; A failed transition leaves CURRENT unchanged, regardless of how it
      ;; escapes, so the successful retry receives INITIAL again.
      (setf phase :success)
      (let ((successful (sources-callback-step rest)))
        (parachute:is equal (list :next initial) (second successful))
        (sources-callback-check-step rest nil (second successful)
                                      (third successful))
        (parachute:is equal (list initial initial) (nreverse arguments))))))

(parachute:define-test iterate.initial-and-transition-sequence
  (let ((calls 0)
        (initial (list :opaque-initial)))
    (let* ((node
             (sl:iterate
              (lambda (value)
                (incf calls)
                (values (list :next value) :secondary))
              initial))
           (first-values (sources-callback-step node)))
      (parachute:false (first first-values))
      (parachute:is eq initial (second first-values))
      (parachute:is = 0 calls)
      (let* ((rest (third first-values))
             (second-values (sources-callback-step rest)))
        (parachute:is equal '(:next (:opaque-initial)) (second second-values))
        (parachute:is = 1 calls)
        (let* ((rest2 (third second-values))
               (third-values (sources-callback-step rest2)))
          (parachute:is equal '(:next (:next (:opaque-initial)))
                        (second third-values))
          (parachute:is = 2 calls)
          (parachute:true (typep (third third-values) 'sl:lazy-seq)))))))

(parachute:define-test repeatedly.callback-failure-retry-and-memoization
  (dolist (failure '(:error :throw))
    (let* ((tag (gensym "CALLBACK-ESCAPE-"))
           (condition (make-condition 'simple-error
                                      :format-control "callback failure"))
           (phase failure)
           (events nil)
           (node
             (sl:repeatedly
              (lambda ()
                (push phase events)
                (ecase phase
                  (:error (error condition))
                  (:throw (throw tag condition))
                  (:success (values (list :successful) :secondary))))
              :count 2)))
      (let ((caught
              (ecase failure
                (:error
                 (handler-case
                     (progn (sources-callback-step node) nil)
                   (simple-error (condition) condition)))
                (:throw
                 (catch tag
                   (sources-callback-step node)
                   :normal-completion)))))
        (parachute:is eq condition caught))
      ;; The current node is retried after either kind of escape.  The second
      ;; attempt uses the other escape mechanism before a successful retry.
      (setf phase (if (eq failure :error) :throw :error))
      (let ((caught
              (ecase phase
                (:error
                 (handler-case
                     (progn (sources-callback-step node) nil)
                   (simple-error (condition) condition)))
                (:throw
                 (catch tag
                   (sources-callback-step node)
                   :normal-completion)))))
        (parachute:is eq condition caught))
      (setf phase :success)
      (let* ((successful (sources-callback-step node))
             (saved (second successful)))
        (parachute:is equal '(:successful) saved)
        (parachute:is equal
                      (if (eq failure :error)
                          '(:error :throw)
                          '(:throw :error))
                      (reverse (cdr events)))
        ;; A successful retry is memoized; it does not call the callback again.
        (parachute:is eq saved (second (sources-callback-step node)))
        (let* ((rest (third successful))
               (rest-values (sources-callback-step rest))
               (rest-saved (second rest-values)))
          (parachute:false (first rest-values))
          (parachute:is equal '(:successful) rest-saved)
          (parachute:is eq rest-saved
                        (second (sources-callback-step rest)))
          (parachute:is = 4 (length events)))))))

(parachute:define-test repeatedly-and-iterate.single-value-results
  ;; This case checks primary-value collapse and the exact private force shape
  ;; rather than relying on printed output.
  (let ((calls 0)
        (initial (list :initial)))
    (flet ((advance (value)
             (incf calls)
             (values (list :advanced value) :ignored)))
      (let* ((repeated-raw
               (multiple-value-list
                (sl:repeatedly (lambda () (values :repeated :ignored))
                               :count 1)))
             (iterated-raw
               (multiple-value-list (sl:iterate #'advance initial)))
             (repeated (first repeated-raw))
             (iterated (first iterated-raw)))
        (parachute:is = 1 (length repeated-raw))
        (parachute:is = 1 (length iterated-raw))
        (parachute:is eql :repeated
                      (second (sources-callback-step repeated)))
        (sources-callback-check-step iterated nil initial
                                     (third (sources-callback-step iterated)))
        (parachute:is = 0 calls)))))

(defun sources-range-step (node)
  (if (sl:seq-emptyp node)
      (list t nil nil)
      (list nil (sl:seq-first node) (sl:seq-rest node))))

(defun sources-range-check-step (node empty-p &optional element rest)
  (let ((values (sources-range-step node)))
    (parachute:is eq empty-p (first values))
    (unless empty-p
      (parachute:is eql element (second values))
      (parachute:is eq rest (third values)))))

(parachute:define-test range.input-validation-and-lazy-construction
  ;; Construction itself must not perform the addition which would overflow.
  #+sbcl
  (let ((old (sb-int:get-floating-point-modes)))
    (unwind-protect
         (progn
           (sb-int:set-floating-point-modes :traps '(:overflow))
           (let ((values
                   (multiple-value-list
                    (sl:range :start most-positive-double-float
                              :step most-positive-double-float))))
             (parachute:is = 1 (length values))
             (parachute:true (typep (first values) 'sl:lazy-seq))))
      (apply #'sb-int:set-floating-point-modes old)))
  #-sbcl
  (let ((values (multiple-value-list (sl:range))))
    (parachute:is = 1 (length values))
    (parachute:true (typep (first values) 'sl:lazy-seq)))
  (dolist (bad (list :not-a-real "end" #(1)))
    (parachute:fail (sl:range :start bad) type-error))
  (parachute:fail (sl:range :end :not-a-real) type-error)
  (dolist (bad-step (list 0 0.0d0 "step"))
    (parachute:fail (sl:range :step bad-step) type-error)))

(parachute:define-test range.bounded-positive-negative-and-empty
  (let* ((positive (sl:range :start 0 :end 5 :step 2))
         (p1 (third (sources-range-step positive)))
         (p2 (third (sources-range-step p1)))
         (p3 (third (sources-range-step p2))))
    (sources-range-check-step positive nil 0 p1)
    (sources-range-check-step p1 nil 2 p2)
    (sources-range-check-step p2 nil 4 p3)
    (sources-range-check-step p3 t))
  (let* ((negative (sl:range :start 5 :end 0 :step -2))
         (n1 (third (sources-range-step negative)))
         (n2 (third (sources-range-step n1)))
         (n3 (third (sources-range-step n2))))
    (sources-range-check-step negative nil 5 n1)
    (sources-range-check-step n1 nil 3 n2)
    (sources-range-check-step n2 nil 1 n3)
    (sources-range-check-step n3 t))
  ;; An empty result is still a lazy node, rather than NIL itself.
  (let ((empty (sl:range :start 5 :end 5 :step 1)))
    (parachute:true (typep empty 'sl:lazy-seq))
    (sources-range-check-step empty t))
  ;; A bounded range is empty when START lies beyond END in STEP's direction.
  (let ((empty (sl:range :start 5 :end 0 :step 1)))
    (sources-range-check-step empty t))
  (let ((empty (sl:range :start 0 :end 5 :step -1)))
    (sources-range-check-step empty t))
)

(parachute:define-test range.unbounded-laziness-and-memoization
  (let* ((node (sl:range :start 10 :step 3))
         (first (sources-range-step node))
         (rest (third first))
         (rest-again (third (sources-range-step node)))
         (second (sources-range-step rest))
         (third-node (third second)))
    (parachute:is eq nil (first first))
    (parachute:is = 10 (second first))
    (parachute:is eq rest rest-again)
    (parachute:is = 13 (second second))
    (parachute:is = 16 (second (sources-range-step third-node)))
    (parachute:true (typep third-node 'sl:lazy-seq)))
  ;; The first element of an end-NIL range needs no addition, and a demand
  ;; does not precompute its successor.
  #+sbcl
  (let ((old (sb-int:get-floating-point-modes)))
    (unwind-protect
         (progn
           (sb-int:set-floating-point-modes :traps '(:overflow))
           (let* ((node (sl:range :start most-positive-double-float
                                  :step most-positive-double-float))
                  (values (sources-range-step node)))
             (parachute:is = 1 (length (multiple-value-list (sl:range))))
             (parachute:is eql most-positive-double-float (second values))))
      (apply #'sb-int:set-floating-point-modes old)))
  #-sbcl
  (parachute:true (typep (sl:range :start 1 :step 1) 'sl:lazy-seq)))

(parachute:define-test range.overflow-retry
  ;; SBCL can expose deferred floating-point overflow as an arithmetic
  ;; condition.  The normative retry obligation is exercised on the initial
  ;; host.
  #+sbcl
  (let ((old (sb-int:get-floating-point-modes)))
    (unwind-protect
         (let* ((node (sl:range :start most-positive-double-float
                                :step most-positive-double-float))
                (first nil) (rest nil) (caught nil))
           (sb-int:set-floating-point-modes :traps '(:overflow))
           (setf first (sl:seq-first node)
                 rest (sl:seq-rest node))
           (parachute:false (sl:seq-emptyp node))
           (parachute:is eql most-positive-double-float first)
           (parachute:true (typep rest 'sl:lazy-seq))
           (setf caught
                 (handler-case
                     (progn
                       (sl:seq-first rest)
                       nil)
                   (arithmetic-error (condition) condition)))
           (parachute:true (typep caught 'arithmetic-error))
           ;; A retry with the arithmetic trap masked must resolve the same
           ;; node; it must not be permanently poisoned by the failed force.
           (sb-int:set-floating-point-modes :traps nil)
           (let ((retry (sl:seq-first rest))
                 (retry-rest (sl:seq-rest rest))
                 (again (sl:seq-first rest))
                 (again-rest (sl:seq-rest rest)))
             (parachute:is eql retry again)
             (parachute:is eq retry-rest again-rest)))
      (apply #'sb-int:set-floating-point-modes old))))

(parachute:define-test range.floating-point-stagnation
  ;; 2^-53 is the positive double-float increment which rounds away at 1.0
  ;; under the ordinary nearest-even mode.  Repeated addition therefore
  ;; stagnates; the source must not silently switch to an index calculation or
  ;; manufacture a finite end.
  (let* ((start 1.0d0)
         (step double-float-negative-epsilon)
         (node (sl:range :start start :end 2.0d0 :step step))
         (one (sources-range-step node))
         (rest (third one))
         (two (sources-range-step rest))
         (rest2 (third two))
         (three (sources-range-step rest2)))
    (parachute:is = 1 (second one))
    (parachute:is eql 1.0d0 (second two))
    (parachute:is eql 1.0d0 (second three))
    (parachute:true (typep rest2 'sl:lazy-seq))
    (parachute:is eq rest2 (third (sources-range-step rest)))))

(parachute:define-test range.single-value-and-step-shapes
  ;; The same case is selected by both fresh-source and compiled runners.  It
  ;; records the exact public primary-value and private decomposition shapes
  ;; so neither runner can pass by observing only a printed value.
  (let* ((constructed (multiple-value-list
                       (sl:range :start 1 :end 4 :step 1)))
         (node (first constructed))
         (first-values (sources-range-step node))
         (same-values (sources-range-step node)))
    (parachute:is = 1 (length constructed))
    (parachute:true (typep node 'sl:lazy-seq))
    (parachute:is eql (second first-values) (second same-values))
    (parachute:is eq (third first-values) (third same-values)))
  (let ((empty (sl:range :start 9 :end 0 :step 1)))
    (parachute:is eq t (first (sources-range-step empty)))))

(defvar *sources-cycle-events* nil)
(defvar *sources-cycle-phase* :success)

(defclass sources-cycle-user-seq ()
  ((items :initarg :items :reader sources-cycle-items)
   (position :initarg :position :initform 0 :reader sources-cycle-position)
   (failure-position :initarg :failure-position :initform nil
                     :reader sources-cycle-failure-position)
   (failure-tag :initarg :failure-tag :initform nil
                :reader sources-cycle-failure-tag)))

(defmethod sl:seqablep ((source sources-cycle-user-seq))
  (declare (ignore source))
  (push :seqablep *sources-cycle-events*)
  t)

(defmethod sl:seq-emptyp ((source sources-cycle-user-seq))
  (push (list :empty (sources-cycle-position source)) *sources-cycle-events*)
  (null (sources-cycle-items source)))

(defmethod sl:seq-first ((source sources-cycle-user-seq))
  (push (list :first (sources-cycle-position source)) *sources-cycle-events*)
  (when (and (eql (sources-cycle-position source)
                  (sources-cycle-failure-position source))
             (eq *sources-cycle-phase* :throw))
    (throw (sources-cycle-failure-tag source)
           :sources-cycle-forcing-failure))
  (car (sources-cycle-items source)))

(defmethod sl:seq-rest ((source sources-cycle-user-seq))
  (push (list :rest (sources-cycle-position source)) *sources-cycle-events*)
  (when (sources-cycle-items source)
    (make-instance (class-of source)
                   :items (cdr (sources-cycle-items source))
                   :position (1+ (sources-cycle-position source))
                   :failure-position (sources-cycle-failure-position source)
                   :failure-tag (sources-cycle-failure-tag source))))

(defun sources-cycle-step (node)
  (if (sl:seq-emptyp node)
      (list t nil nil)
      (list nil (sl:seq-first node) (sl:seq-rest node))))

(defun sources-cycle-walk (node count)
  (let ((elements nil))
    (dotimes (ignored count (values (nreverse elements) node))
      (declare (ignore ignored))
      (let ((step (sources-cycle-step node)))
        (push (second step) elements)
        (setf node (third step))))))

(defun sources-cycle-catch (tag thunk)
  (catch tag
    (funcall thunk)
    :sources-cycle-no-escape))

(parachute:define-test cycle.input-validation-and-construction-laziness
  ;; The fallback T SEQABLEP method rejects this at call time; the condition is
  ;; caught here rather than being left for the quiet Parachute report to catch.
  (let ((condition
          (handler-case (progn (sl:cycle 42) nil)
            (type-error (caught) caught))))
    (parachute:true (typep condition 'type-error))
    (parachute:false (sl:seqablep 42)))
  ;; A conforming user method is consulted at construction, but traversal is
  ;; still deferred until the returned node is demanded, even for an empty
  ;; source.
  (let ((*sources-cycle-events* nil)
        (source (make-instance 'sources-cycle-user-seq :items nil)))
    (let ((node (sl:cycle source)))
      (parachute:true (typep node 'sl:lazy-seq))
      (parachute:is equal '(:seqablep) *sources-cycle-events*)))
  ;; NIL is an empty seqable source, but CYCLE still returns a node.
  (parachute:true (typep (sl:cycle nil) 'sl:lazy-seq)))

(parachute:define-test cycle.hash-table-view-isolation
  ;; Hash-table order is deliberately not asserted.  The cycle must retain its
  ;; own coherent view even when direct FIRST/REST calls establish other views.
  (let ((table (make-hash-table :test #'equal)))
    (dolist (key '("a" "b" "c" "d"))
      (setf (gethash key table) (list :value key)))
    (let* ((cycle (sl:cycle table))
           (first-step (sources-cycle-step cycle))
           (cursor (third first-step)))
      (parachute:false (first first-step))
      (parachute:true (typep (second first-step) 'sl:map-entry))
      (let ((direct-first (sl:seq-first table))
            (direct-rest (sl:seq-rest table)))
        (parachute:true (typep direct-first 'sl:map-entry))
        (parachute:true (typep direct-rest 'sl:lazy-seq)))
      (multiple-value-bind (remaining ignored)
          (sources-cycle-walk cursor 3)
        (declare (ignore ignored))
        (let ((entries (cons (second first-step) remaining)))
          (parachute:is = 3 (length remaining))
          (parachute:true (every (lambda (entry)
                                   (typep entry 'sl:map-entry))
                                 entries))
          (parachute:is = 4
                        (length (remove-duplicates
                                 entries :key #'sl:entry-key :test #'equal)))
          (parachute:true
           (every (lambda (entry)
                    (multiple-value-bind (value present-p)
                        (gethash (sl:entry-key entry) table)
                      (and present-p
                           (eq value (sl:entry-value entry)))))
                  entries)))))))

(parachute:define-test cycle.replay-preserves-element-identity
  ;; Opaque ordinary objects, including a MAP-ENTRY, are replayed by identity.
  (let* ((left (list :left))
         (entry (sl:map-entry (list :key) (list :value)))
         (right (list :right))
         (cycle (sl:cycle (list left entry right))))
    (multiple-value-bind (first-view cursor) (sources-cycle-walk cycle 3)
      (multiple-value-bind (second-view ignored)
          (sources-cycle-walk cursor 3)
        (declare (ignore ignored))
        (parachute:is = 3 (length first-view))
        (parachute:is = 3 (length second-view))
        (parachute:true (every #'eq first-view second-view))
        (parachute:true (typep (second first-view) 'sl:map-entry))
        (parachute:is eq entry (second first-view))
        (parachute:is eq entry (second second-view))
        (parachute:is eq (sl:entry-key entry)
                      (sl:entry-key (second second-view)))
        (parachute:is eq (sl:entry-value entry)
                      (sl:entry-value (second second-view)))
        (parachute:false (sl:seqablep entry)))))
  ;; For an unordered source, only the retained view's order is meaningful;
  ;; replay positions still have exact identity and the key set is invariant.
  (let ((table (make-hash-table :test #'equal)))
    (dolist (key '("x" "y" "z"))
      (setf (gethash key table) (list :payload key)))
    (let ((cycle (sl:cycle table)))
      (multiple-value-bind (first-view cursor) (sources-cycle-walk cycle 3)
        (multiple-value-bind (second-view ignored)
            (sources-cycle-walk cursor 3)
          (declare (ignore ignored))
          (parachute:is = 3 (length first-view))
          (parachute:is = 3 (length second-view))
          (parachute:true (every #'eq first-view second-view))
          (parachute:true
           (every (lambda (entry) (typep entry 'sl:map-entry)) first-view))
          (parachute:is = 3
                        (length (remove-duplicates
                                 first-view :key #'sl:entry-key :test #'equal)))
          (parachute:true
           (every (lambda (entry)
                    (multiple-value-bind (value present-p)
                        (gethash (sl:entry-key entry) table)
                      (and present-p
                           (eq value (sl:entry-value entry)))))
                  first-view)))))))

(parachute:define-test cycle.empty-sources
  (dolist (source (list nil #() (make-hash-table)
                        (make-instance 'sources-cycle-user-seq :items nil)))
    (let ((node (sl:cycle source)))
      (parachute:true (typep node 'sl:lazy-seq))
      (let ((step (sources-cycle-step node)))
        (parachute:true (first step))
        (parachute:is eq nil (second step))
        (parachute:is eq nil (third step)))
      (parachute:is = 0 (sl:seq-length node)))))

(parachute:define-test cycle.unbounded-source-demand
  ;; Each demanded source node is a finite-prefix sentinel: forcing one more
  ;; position increments FORCES once.  No end check may force beyond the prefix.
  (let ((forces 0))
    (labels ((unbounded (number)
               (sl:make-lazy-seq
                (lambda ()
                  (incf forces)
                  (sl:lazy-cons number (unbounded (1+ number)))))))
      (let* ((source (unbounded 1))
             (cycle (sl:cycle source)))
        (parachute:true (typep cycle 'sl:lazy-seq))
        (parachute:is = 0 forces)
        (multiple-value-bind (values ignored)
            (sources-cycle-walk cycle 5)
          (declare (ignore ignored))
          (parachute:is equal '(1 2 3 4 5) values))
        (parachute:is = 5 forces)))))

(parachute:define-test cycle.dotted-tail-and-escaped-forcing-retry
  ;; A dotted tail is reached only when its position is demanded.  Both the
  ;; captured prefix and the failed position survive repeated observations.
  (let* ((a (list :a))
         (b (list :b))
         (source (list* a b :dotted-tail))
         (cycle (sl:cycle source))
         (one (sources-cycle-step cycle))
         (two (sources-cycle-step (third one)))
         (dotted (third two))
         (first-failure
           (handler-case (progn (sources-cycle-step dotted) nil)
             (type-error (condition) condition)))
         (second-failure
           (handler-case (progn (sources-cycle-step dotted) nil)
             (type-error (condition) condition))))
    (parachute:false (first one))
    (parachute:is eq a (second one))
    (parachute:false (first two))
    (parachute:is eq b (second two))
    (parachute:true (typep first-failure 'type-error))
    (parachute:true (typep second-failure 'type-error))
    (let ((retry (sources-cycle-walk cycle 2)))
      (parachute:is = 2 (length retry))
      (parachute:is eq a (first retry))
      (parachute:is eq b (second retry)))
    (let ((again (sources-cycle-step cycle)))
      (parachute:is eq (third one) (third again))
      (parachute:is eq a (second again))))
  ;; An escaped non-local exit from a user SEQ-FIRST leaves the same position
  ;; unresolved.  After the phase changes, that position is retried, not
  ;; skipped.
  (let* ((tag (gensym "SOURCES-CYCLE-ESCAPE-"))
         (a (list :a))
         (b (list :b))
         (*sources-cycle-events* nil)
         (*sources-cycle-phase* :throw)
         (source (make-instance 'sources-cycle-user-seq
                                :items (list a b)
                                :failure-position 1
                                :failure-tag tag))
         (cycle (sl:cycle source)))
    (parachute:is equal '(:seqablep) *sources-cycle-events*)
    (let* ((one (sources-cycle-step cycle))
           (caught (sources-cycle-catch
                    tag (lambda ()
                          (sources-cycle-step (third one))))))
      (parachute:false (first one))
      (parachute:is eq a (second one))
      (parachute:is eq :sources-cycle-forcing-failure caught)
      (parachute:is = 1
                    (count-if (lambda (event)
                                (equal '(:first 1) event))
                              *sources-cycle-events*))
      (setf *sources-cycle-phase* :success)
      (let ((second (sources-cycle-step (third one))))
        (parachute:false (first second))
        (parachute:is eq b (second second))
        (parachute:is = 2
                      (count-if (lambda (event)
                                  (equal '(:first 1) event))
                                *sources-cycle-events*))
        (let ((replay (sources-cycle-step (third second))))
          (parachute:false (first replay))
          (parachute:is eq a (second replay)))))))

(parachute:define-test cycle.captures-finite-prefix-before-mutation
  ;; Do not observe the source mutation until the successful end observation
  ;; has completed.  The Chapter 4 undefined mutation window is therefore not
  ;; used as an oracle; all captured and already-forced nodes must remain fixed.
  (let* ((a (list :a))
         (b (list :b))
         (c (list :c))
         (source (list a b c))
         (cycle (sl:cycle source))
         (one (sources-cycle-step cycle))
         (two (sources-cycle-step (third one)))
         (three (sources-cycle-step (third two)))
         ;; This demand observes the finite end and enters replay.
         (replay-one (sources-cycle-step (third three)))
         (replay-tail (third replay-one)))
    (parachute:is eq a (second one))
    (parachute:is eq b (second two))
    (parachute:is eq c (second three))
    (parachute:false (first replay-one))
    (parachute:is eq a (second replay-one))
    (setf (car source) :changed-a
          (cadr source) :changed-b
          (caddr source) :changed-c)
    (let ((again-one (sources-cycle-step cycle))
          (again-two (sources-cycle-step (third one)))
          (again-three (sources-cycle-step (third two))))
      (parachute:is eq a (second again-one))
      (parachute:is eq b (second again-two))
      (parachute:is eq c (second again-three)))
    (multiple-value-bind (replay-rest ignored)
        (sources-cycle-walk replay-tail 2)
      (declare (ignore ignored))
      (parachute:true (every #'eq (list b c) replay-rest)))
    (parachute:is equal '(:changed-a :changed-b :changed-c) source)))

(parachute:define-test cycle.escaped-forcing-retry-and-memoization
  ;; This case is intentionally ordinary Lisp and is selected unchanged by
  ;; fresh-source and compiled runners.  It combines force timing, an escaped
  ;; condition, side-effect counts, and replay identity.
  (let* ((phase :throw)
         (tag (gensym "SOURCES-CYCLE-COMPILED-"))
         (forces 0)
         (object (list :object))
         (source
           (sl:make-lazy-seq
            (lambda ()
              (incf forces)
              (if (eq phase :throw)
                  (throw tag :sources-cycle-escaped)
                  (sl:lazy-cons object nil)))))
         (constructed (multiple-value-list (sl:cycle source)))
         (cycle (first constructed)))
    (parachute:is = 1 (length constructed))
    (parachute:is = 0 forces)
    (parachute:true (typep cycle 'sl:lazy-seq))
    (let ((caught (sources-cycle-catch
                   tag (lambda () (sources-cycle-step cycle)))))
      (parachute:is eq :sources-cycle-escaped caught)
      (parachute:is = 1 forces))
    (setf phase :success)
    (let ((first-step (sources-cycle-step cycle)))
      (parachute:false (first first-step))
      (parachute:is eq object (second first-step))
      (parachute:is = 2 forces)
      (let ((replay-step (sources-cycle-step (third first-step))))
        (parachute:false (first replay-step))
        (parachute:is eq object (second replay-step))
        (parachute:is = 2 forces))
      ;; The successful retry is memoized, including its retained rest node.
      (let ((again (sources-cycle-step cycle)))
        (parachute:is eq object (second again))
        (parachute:is eq (third first-step) (third again))))))
