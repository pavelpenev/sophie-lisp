;;;; Lazy nodes: successful resolution is the only cached outcome.

(in-package #:sophie-lisp.internal)

(defstruct (sl:lazy-seq
             (:constructor allocate-lazy-node
                           (&key thunk (state :unresolved) element rest))
             (:conc-name lazy-node-)
             (:predicate lazy-node-p)
             (:copier nil))
  "A lazy sequence node with deferred computation, resolved on demand."
  (state :unresolved :type (member :unresolved :forcing :empty :value))
  thunk
  element
  rest)

(defun lazy-valid-result-p (value)
  "Recognize a lazy sequence without observing its contents."
  (or (null value) (lazy-node-p value)))

(defun sl:lazy-seq-p (object)
  "Return true if OBJECT is NIL or an SL:LAZY-SEQ node, without forcing OBJECT."
  (lazy-valid-result-p object))

(defun make-lazy-node (thunk)
  "Construct an unresolved node, retaining a function object, not a designator."
  (unless (functionp thunk)
    (raise-type-error thunk 'function))
  (allocate-lazy-node :thunk thunk))

(defun sl:make-lazy-seq (thunk)
  "Create a lazy sequence whose contents are produced by THUNK.
THUNK must be a function object returning exactly one value: NIL or an
SL:LAZY-SEQ node. Successful forcing memoizes the result; a failed force
leaves the node retryable."
  (make-lazy-node thunk))

(defmacro sl:lazy-seq (&rest forms)
  "Defer exactly one form in its lexical environment."
  (unless (and (consp forms) (null (cdr forms)))
    (raise-program-error))
  `(sl:make-lazy-seq (lambda () ,(car forms))))

(defun sl:lazy-cons (element rest)
  "Create a lazy sequence node containing ELEMENT followed by REST.
REST must be NIL or an SL:LAZY-SEQ node; it is not forced or deferred."
  (unless (lazy-valid-result-p rest)
    (raise-type-error rest '(or null sl:lazy-seq)))
  (allocate-lazy-node :state :value :element element :rest rest))

(defun lazy-step (node)
  "Return exactly EMPTY-P, ELEMENT and REST, without forcing a fixed tail."
  (let ((current node)
        (pending nil)
        (empty-p nil)
        (element nil)
        (rest nil))
    ;; Do not intercept conditions: SIGNAL and resumed CERROR can complete
    ;; normally. Only an actual unwind resets unfinished nodes owned here.
    (unwind-protect
         (progn
           (loop
            (unless (lazy-valid-result-p current)
              (raise-type-error current '(or null sl:lazy-seq)))
            (when (null current)
              (setf empty-p t)
              (return))
            (ecase (lazy-node-state current)
              (:empty
               (setf empty-p t)
               (return))
              (:value
               (setf empty-p nil
                     element (lazy-node-element current)
                     rest (lazy-node-rest current))
               (return))
              (:forcing
               (raise-program-error))
              (:unresolved
               (push current pending)
               (setf (lazy-node-state current) :forcing)
               (let ((results (multiple-value-list
                               (funcall (lazy-node-thunk current)))))
                 (unless (and (consp results) (null (cdr results)))
                   (raise-type-error results
                                     '(cons (or null sl:lazy-seq) null)))
                 (setf current (car results))))))
           ;; PENDING is innermost first because each newly claimed wrapper is
           ;; pushed while descending.
           (dolist (pending-node pending)
             (setf (lazy-node-element pending-node) element
                   (lazy-node-rest pending-node) rest
                   (lazy-node-state pending-node) (if empty-p :empty :value)
                   (lazy-node-thunk pending-node) nil))
           (values empty-p element rest))
      (dolist (pending-node pending)
        (when (eq :forcing (lazy-node-state pending-node))
          (setf (lazy-node-state pending-node) :unresolved))))))

(defun active-vector-end (vector)
  (length vector))

(defmethod seqablep ((object t)) nil)

(defmethod seqablep ((object list)) t)

(defmethod seqablep ((object vector)) t)

(defmethod seqablep ((object hash-table)) t)

(defmethod seqablep ((object sl:lazy-seq)) t)

(defmethod seqablep ((object sl:map-entry)) nil)

(defun require-seqable (source)
  (unless (seqablep source)
    (raise-type-error source '(satisfies seqablep)))
  source)

(defun vector-view (vector index end)
  (when (< index end)
    (make-lazy-node
     (lambda ()
       (sl:lazy-cons (aref vector index)
                     (vector-view vector (1+ index) end))))))

(defun list-view (tail)
  ;; Validation of a dotted tail belongs to demand for that position, not
  ;; demand for the preceding car. No proper-list scan occurs here.
  (when tail
    (make-lazy-node
     (lambda ()
       (unless (listp tail) (raise-type-error tail 'list))
       (sl:lazy-cons (car tail) (list-view (cdr tail)))))))

(declaim (ftype (function (t) (values t &optional)) open-view))

(defun protocol-view (source)
  (make-lazy-node
   (lambda ()
     (require-seqable source)
     (unless (seq-emptyp source)
       (sl:lazy-cons
        (seq-first source)
        ;; An extension's REST may itself read the next position. Do not
        ;; perform it until that position is demanded; failures stay retryable.
        (make-lazy-node
         (lambda ()
           (open-view (seq-rest source)))))))))

(defun open-view (source)
  "Open one lazy traversal without consuming or forcing SOURCE."
  (require-seqable source)
  (typecase source
    (null nil)
    (sl:lazy-seq source)
    (list (list-view source))
    (vector (vector-view source 0 (active-vector-end source)))
    (hash-table
     (make-lazy-node
      (lambda ()
        ;; MAPHASH completes inside this demand. No iterator escapes its
        ;; dynamic extent. Only a successful snapshot is memoized by the node.
        (let ((entries (make-array (hash-table-count source))) (index 0))
          (maphash (lambda (key value)
                     (setf (aref entries index) (make-map-entry key value))
                     (incf index))
                   source)
          (vector-view entries 0 index)))))
    (t (protocol-view source))))

(defun view-step (view)
  "Return EMPTY-P, ELEMENT, REST from one retained lazy view."
  (lazy-step view))

(defmethod seq-emptyp ((source t))
  (raise-type-error source '(satisfies seqablep)))

(defmethod seq-first ((source t))
  (raise-type-error source '(satisfies seqablep)))

(defmethod seq-rest ((source t))
  (raise-type-error source '(satisfies seqablep)))

(defmethod seq-emptyp ((source list)) (null source))

(defmethod seq-first ((source list)) (car source))

(defmethod seq-rest ((source list))
  (let ((tail (cdr source)))
    (unless (listp tail) (raise-type-error tail 'list))
    tail))

(defmethod seq-emptyp ((source vector))
  (zerop (active-vector-end source)))

(defmethod seq-first ((source vector))
  (unless (seq-emptyp source) (aref source 0)))

(defmethod seq-rest ((source vector))
  (vector-view source 1 (active-vector-end source)))

(defmethod seq-emptyp ((source hash-table))
  (zerop (hash-table-count source)))

(defmethod seq-first ((source hash-table))
  (nth-value 1 (view-step (open-view source))))

(defmethod seq-rest ((source hash-table))
  (nth-value 2 (view-step (open-view source))))

(defmethod seq-emptyp ((source sl:lazy-seq))
  (nth-value 0 (lazy-step source)))

(defmethod seq-first ((source sl:lazy-seq))
  (nth-value 1 (lazy-step source)))

(defmethod seq-rest ((source sl:lazy-seq))
  (nth-value 2 (lazy-step source)))

(defun check-seq-index (index)
  (unless (typep index '(integer 0 *))
    (raise-type-error index '(integer 0 *)))
  index)

(defun missing-seq-index (index end default supplied-p)
  (if supplied-p
      (values default nil)
      (raise-type-error index
                   (if (zerop end)
                       '(integer 1 0)
                       `(or (integer 0 ,(1- end)) (integer ,(- end) -1))))))

(defun normalize-ref-index (source index)
  (unless (integerp index)
    (raise-type-error index 'integer))
  (if (minusp index)
      (let ((length (seq-length source)))
        (unless length
          (raise-simple-error "Negative SEQ-REF indices require a finite source."))
        (+ length index))
      index))

(defun traversal-ref (source index default default-supplied-p)
  (let ((position (normalize-ref-index source index))
        (view (open-view source)))
    (loop for current-position from 0
          do (multiple-value-bind (empty-p element rest) (view-step view)
               (when empty-p
                 (return (missing-seq-index index current-position default
                                             default-supplied-p)))
               (when (= current-position position) (return (values element t)))
               (setf view rest)))))

(defmethod seq-ref ((source t) index &optional (default nil supplied-p))
  (traversal-ref source index default supplied-p))

(defmethod seq-ref ((source list) index &optional (default nil supplied-p))
  (let ((position (normalize-ref-index source index)))
    (loop with tail = source
          for current-position from 0
          do (when (null tail)
               (return (missing-seq-index index current-position default supplied-p)))
             (when (= current-position position) (return (values (car tail) t)))
             (setf tail (seq-rest tail)))))

(defmethod seq-ref ((source vector) index &optional (default nil supplied-p))
  (let ((position (normalize-ref-index source index))
        (end (active-vector-end source)))
    (if (and (<= 0 position) (< position end))
        (values (aref source position) t)
        (missing-seq-index index end default supplied-p))))

(defmethod seq-ref ((source hash-table) index &optional (default nil supplied-p))
  (traversal-ref source index default supplied-p))

(defmethod seq-ref ((source sl:lazy-seq) index &optional (default nil supplied-p))
  (traversal-ref source index default supplied-p))

(defmethod (setf seq-ref) (new-value (source t) index &optional default)
  (declare (ignore new-value source index default))
  (raise-simple-error "This source has no SEQ-REF writer."))

(defmethod (setf seq-ref) (new-value (source sl:lazy-seq) index &optional default)
  (declare (ignore new-value source index default))
  (raise-simple-error "Lazy sequences are not writable."))

(defmethod (setf seq-ref) (new-value (source list) index &optional default)
  (declare (ignore default))
  (let ((position (normalize-ref-index source index)))
    (loop with tail = source
          for current-position from 0
          do (when (null tail) (missing-seq-index index current-position nil nil))
             (when (= current-position position) (return (setf (car tail) new-value)))
             (setf tail (seq-rest tail)))))

(defmethod (setf seq-ref) (new-value (source vector) index &optional default)
  (declare (ignore default))
  (let ((position (normalize-ref-index source index))
        (end (active-vector-end source)))
    (unless (and (<= 0 position) (< position end))
      (missing-seq-index index end nil nil))
    (unless (typep new-value (array-element-type source))
      (raise-type-error new-value (array-element-type source)))
    (setf (aref source position) new-value)))

(defun traversal-length (source)
  "Count in one forward pass, using Brent's constant-space cycle detection."
  (require-seqable source)
  (loop with cursor = source
        with checkpoint = source
        with power = 1
        with distance = 0
        with count = 0
        do (when (seq-emptyp cursor) (return count))
           (setf cursor (seq-rest cursor))
           (incf count)
           (incf distance)
           (when (eq cursor checkpoint) (return nil))
           (when (= distance power)
             (setf checkpoint cursor distance 0 power (* 2 power)))))

(defmethod seq-length ((source t)) (traversal-length source))

(defmethod seq-length ((source list))
  ;; ANSI LIST-LENGTH already detects cycles in constant auxiliary space and
  ;; rejects dotted lists; unlike LENGTH it is bounded on circular inputs.
  (list-length source))

(defmethod seq-length ((source vector)) (active-vector-end source))

(defmethod seq-length ((source hash-table)) (hash-table-count source))

(defmethod seq-length ((source sl:lazy-seq)) (traversal-length source))
