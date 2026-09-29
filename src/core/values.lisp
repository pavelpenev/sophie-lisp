;;;; Extensible structural equality. No representation conversion or cycle proof.

(in-package #:sophie-lisp.internal)

(defmethod sl:equals ((left-object t) (right-object t))
  (eql left-object right-object))

(defmethod sl:equals ((left-object standard-object) (right-object standard-object))
  (eq left-object right-object))

(defmethod sl:equals ((left-object structure-object) (right-object structure-object))
  (eql left-object right-object))

(defmethod sl:equals ((left-object number) (right-object number))
  (= left-object right-object))

(defmethod sl:equals ((left-object character) (right-object character))
  (char= left-object right-object))

(defmethod sl:equals ((left-object string) (right-object string))
  (string= left-object right-object))

(defmethod sl:equals ((left-object cons) (right-object cons))
  ;; Iterate the cdr chain explicitly: an unbounded traversal must stay in
  ;; bounded stack on hosts without tail-call optimization. Every component
  ;; still reaches the public generic function, not a type switch; only the
  ;; intermediate cons-cons tail pairs skip the redundant dispatch round-trip.
  (declare (optimize (speed 1) (debug 1)))
  (loop
    (unless (sl:equals (car left-object) (car right-object))
      (return nil))
    (let ((left-tail (cdr left-object))
          (right-tail (cdr right-object)))
      (if (and (consp left-tail) (consp right-tail))
          (setf left-object left-tail
                right-object right-tail)
          (return (sl:equals left-tail right-tail))))))

(defmethod sl:equals ((left-object array) (right-object array))
  (let ((rank (array-rank left-object)))
    (and (= rank (array-rank right-object))
         (if (= rank 1)
             (and (= (length left-object) (length right-object))
                  (loop for i below (length left-object)
                        always (sl:equals (aref left-object i) (aref right-object i))))
             (and (equal (array-dimensions left-object) (array-dimensions right-object))
                  (loop for i below (array-total-size left-object)
                        always (sl:equals (row-major-aref left-object i)
                                          (row-major-aref right-object i))))))))

(defmethod sl:equals ((left-object hash-table) (right-object hash-table))
  ;; Native lookup cannot implement this relation: distinct native keys may
  ;; be EQUALS, and a match must include the value and preserve multiplicity.
  (let ((count (hash-table-count left-object)))
    (unless (= count (hash-table-count right-object))
      (return-from sl:equals nil))
    (let ((right (make-array count))
          (edges (make-array count :initial-element nil))
          (owners (make-array count :initial-element nil))
          (index 0))
      (maphash (lambda (key value)
                 (setf (aref right index) (cons key value))
                 (incf index))
               right-object)
      (labels ((augment (left seen)
                 (dolist (candidate (aref edges left) nil)
                   (unless (aref seen candidate)
                     (setf (aref seen candidate) t)
                     (let ((owner (aref owners candidate)))
                       (when (or (null owner) (augment owner seen))
                         (setf (aref owners candidate) left)
                         (return t)))))))
        (setf index 0)
        (maphash
         (lambda (key value)
           ;; Compare each candidate pair once. Augmenting paths subsequently
           ;; use only this finite graph, never repeat user equality callbacks.
           (setf (aref edges index)
                 (loop for candidate across right
                       for j from 0
                       when (and (sl:equals key (car candidate))
                                 (sl:equals value (cdr candidate)))
                         collect j))
           (unless (augment index (make-array count :initial-element nil))
             (return-from sl:equals nil))
           (incf index))
         left-object)
        t))))

(defmethod sl:equals ((left-object sl:lazy-seq) (right-object sl:lazy-seq))
  (declare (optimize (speed 1) (debug 1)))
  (multiple-value-bind (left-empty left-element left-rest) (lazy-step left-object)
    (multiple-value-bind (right-empty right-element right-rest) (lazy-step right-object)
      (if (or left-empty right-empty)
          (and left-empty right-empty)
          (and (sl:equals left-element right-element)
               (sl:equals left-rest right-rest))))))

(defmethod sl:equals ((left-object sl:lazy-seq) (right-object null))
  (nth-value 0 (lazy-step left-object)))

(defmethod sl:equals ((left-object null) (right-object sl:lazy-seq))
  (nth-value 0 (lazy-step right-object)))

(defmethod sl:equals ((left-object sl:map-entry) (right-object sl:map-entry))
  (declare (optimize (speed 1) (debug 1)))
  (and (sl:equals (sl:entry-key left-object) (sl:entry-key right-object))
       (sl:equals (sl:entry-value left-object) (sl:entry-value right-object))))

(defmethod sl:compare ((left-object t) (right-object t))
  (if (sl:equals left-object right-object) :equal :unequal))

(defmethod sl:compare ((left-object number) (right-object number))
  (cond ((= left-object right-object) :equal)
        ((and (realp left-object) (realp right-object))
         (if (< left-object right-object) :less :greater))
        (t :unequal)))

(defmethod sl:compare ((left-object character) (right-object character))
  (cond ((char= left-object right-object) :equal)
        ((char< left-object right-object) :less)
        (t :greater)))

(defmethod sl:compare ((left-object symbol) (right-object symbol))
  (cond ((null left-object) (if (null right-object) :equal :unequal))
        ((null right-object) :unequal)
        (t (let ((left (symbol-name left-object)) (right (symbol-name right-object)))
             (cond ((string= left right) :equal)
                   ((string< left right) :less)
                   (t :greater))))))

(defun compare-cdrs (left-tail right-tail)
  ;; Empty-tail precedence is contextual, including opposite dotted atoms.
  ;; Resolve lazy nodes left-to-right without observing a nonempty node's rest.
  (declare (optimize (speed 1) (debug 1)))
  (let* ((left-lazy (typep left-tail 'sl:lazy-seq))
         (right-lazy (typep right-tail 'sl:lazy-seq))
         (left-empty (or (null left-tail) (and left-lazy (nth-value 0 (lazy-step left-tail)))))
         (right-empty (or (null right-tail) (and right-lazy (nth-value 0 (lazy-step right-tail))))))
    (cond (left-empty (if right-empty :equal :less))
          (right-empty :greater)
          ((or left-lazy right-lazy) (sl:compare left-tail right-tail))
          ((not (eq (consp left-tail) (consp right-tail))) :unequal)
          (t (sl:compare left-tail right-tail)))))

(defmethod sl:compare ((left-object cons) (right-object cons))
  ;; Iterate the cdr chain explicitly: an unbounded traversal must stay in
  ;; bounded stack on hosts without tail-call optimization. Every component
  ;; still reaches the public generic function, not a type switch.
  (declare (optimize (speed 1) (debug 1)))
  (loop
    (let ((result (sl:compare (car left-object) (car right-object))))
      (unless (eq result :equal)
        (return result)))
    (let ((left-tail (cdr left-object))
          (right-tail (cdr right-object)))
      (if (and (consp left-tail) (consp right-tail))
          (setf left-object left-tail
                right-object right-tail)
          (return (compare-cdrs left-tail right-tail))))))

(defmethod sl:compare ((left-object vector) (right-object vector))
  (let ((left-length (length left-object)) (right-length (length right-object)))
    (loop for i below (min left-length right-length)
          for result = (sl:compare (aref left-object i) (aref right-object i))
          unless (eq result :equal) do (return-from sl:compare result))
    (cond ((< left-length right-length) :less)
          ((> left-length right-length) :greater)
          (t :equal))))

(defmethod sl:compare ((left-object array) (right-object array))
  ;; Rank-one pairs select VECTOR above. Other ranks have no ordering,
  ;; including arrays with unequal dimensions or unequal sole elements.
  (if (sl:equals left-object right-object) :equal :unequal))

(defmethod sl:compare ((left-object hash-table) (right-object hash-table))
  (if (sl:equals left-object right-object) :equal :unequal))

(defmethod sl:compare ((left-object sl:lazy-seq) (right-object sl:lazy-seq))
  (declare (optimize (speed 1) (debug 1)))
  (multiple-value-bind (left-empty left-element left-rest) (lazy-step left-object)
    (multiple-value-bind (right-empty right-element right-rest) (lazy-step right-object)
      (cond (left-empty (if right-empty :equal :less))
            (right-empty :greater)
            (t (let ((result (sl:compare left-element right-element)))
                 (if (eq result :equal)
                     (sl:compare left-rest right-rest)
                     result)))))))

(defmethod sl:compare ((left-object sl:lazy-seq) (right-object null))
  (if (nth-value 0 (lazy-step left-object)) :equal :greater))

(defmethod sl:compare ((left-object null) (right-object sl:lazy-seq))
  (if (nth-value 0 (lazy-step right-object)) :equal :less))

(defmethod sl:compare ((left-object sl:map-entry) (right-object sl:map-entry))
  (declare (optimize (speed 1) (debug 1)))
  (let ((result (sl:compare (sl:entry-key left-object) (sl:entry-key right-object))))
    (if (eq result :equal)
        (sl:compare (sl:entry-value left-object) (sl:entry-value right-object))
        result)))

(defun ordered-comparison (left-object right-object)
  (let ((result (sl:compare left-object right-object)))
    (when (eq result :unequal)
      ;; Do not print operands: doing so could inspect an untouched tail.
      (error "The objects are incomparable."))
    result))

(defun sl:lt (left-object right-object)
  "Return true if (SL:COMPARE LEFT-OBJECT RIGHT-OBJECT) is :LESS. Signal SIMPLE-ERROR if incomparable."
  (eq (ordered-comparison left-object right-object) :less))

(defun sl:lte (left-object right-object)
  "Return true if (SL:COMPARE LEFT-OBJECT RIGHT-OBJECT) is :LESS or :EQUAL. Signal SIMPLE-ERROR if incomparable."
  (not (null (member (ordered-comparison left-object right-object) '(:less :equal)))))

(defun sl:gt (left-object right-object)
  "Return true if (SL:COMPARE LEFT-OBJECT RIGHT-OBJECT) is :GREATER. Signal SIMPLE-ERROR if incomparable."
  (eq (ordered-comparison left-object right-object) :greater))

(defun sl:gte (left-object right-object)
  "Return true if (SL:COMPARE LEFT-OBJECT RIGHT-OBJECT) is :GREATER or :EQUAL. Signal SIMPLE-ERROR if incomparable."
  (not (null (member (ordered-comparison left-object right-object) '(:greater :equal)))))
