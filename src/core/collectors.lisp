;;;; Immutable keyed entries.

(in-package #:sophie-lisp.internal)

(defstruct (sl:map-entry
             (:constructor make-map-entry (key value))
             (:conc-name map-entry-)
             (:predicate map-entry-p)
             (:copier nil))
  "An immutable key-value entry used as the canonical element of keyed collection traversal."
  (key nil :read-only t)
  (value nil :read-only t))

(defun sl:map-entry (key value)
  "Construct an immutable keyed entry without copying either field."
  (make-map-entry key value))

(defun sl:entry-key (entry)
  "Return ENTRY's key; signal TYPE-ERROR if ENTRY is not an SL:MAP-ENTRY."
  (unless (map-entry-p entry)
    (raise-type-error entry 'sl:map-entry))
  (map-entry-key entry))

(defun sl:entry-value (entry)
  "Return ENTRY's value; signal TYPE-ERROR if ENTRY is not an SL:MAP-ENTRY."
  (unless (map-entry-p entry)
    (raise-type-error entry 'sl:map-entry))
  (map-entry-value entry))

(defun resolve-target-designator (designator)
  "Resolve a registered target class name.
The caller parses compound designators and handles LAZY-SEQ before this call."
  (or (find-class designator nil)
      (raise-type-error designator '(satisfies registered-collector-target-p))))

(defun registered-collector-target-p (object)
  (and (symbolp object)
       (find-class object nil)
       t))

(defun validate-collector-options (options &optional (accepted nil supplied-p))
  ;; LIST-LENGTH detects cycles without retaining a table of conses.
  (let ((length (handler-case (list-length options) (type-error () nil))))
    (unless (and length (evenp length))
      (raise-program-error)))
  (loop for (key) on options by #'cddr
        do (unless (and (keywordp key)
                        (or (not supplied-p) (member key accepted :test #'eq)))
             (raise-program-error)))
  options)

(defun make-collector (target options)
  "Invoke the unfiltered generic function on the actual TARGET."
  (validate-collector-options options)
  (apply #'make-collector-for target options))

(defclass collector ()
  ((finalized-p :initform nil :accessor collector-finalized-p)
   (result :accessor collector-cached-result)))

(defclass list-collector (collector)
  ((items :initform nil :accessor collector-items)))

(defclass vector-collector (collector)
  ((element-type :initarg :element-type :reader collector-element-type)
   (storage-element-type :initarg :storage-element-type
                         :reader collector-storage-element-type)
   ;; General geometric-growth staging also supports the empty element type.
   (buffer :initform (make-array 16 :adjustable t :fill-pointer 0)
           :reader collector-buffer)))

(defclass hash-collector (collector)
  ((table :initarg :table :reader collector-table)))

(defun cache-collector-result (collector thunk)
  "Cache only a normally returned primary value, including NIL."
  ;; Keep this success-only finalization protocol aligned with ENTRY-BUILDER-FINISH.
  (if (collector-finalized-p collector)
      (collector-cached-result collector)
      (let ((result (funcall thunk)))
        (setf (collector-cached-result collector) result
              (collector-finalized-p collector) t)
        result)))

(defun new-vector-collector (element-type string-target-p)
  ;; Retain the upgrade result so validation cannot be dead-code eliminated.
  ;; Translate only host type-specifier diagnostics, never dispatch conditions.
  (let ((upgraded
          (handler-case (upgraded-array-element-type element-type)
            (error () (raise-type-error element-type
                                   '(satisfies array-element-type-p))))))
    (when (and string-target-p (not (character-element-type-p element-type)))
      (raise-type-error element-type '(satisfies character-element-type-p)))
    (make-instance 'vector-collector :element-type element-type
                   :storage-element-type upgraded)))

(defun array-element-type-p (object)
  (handler-case
      (arrayp (make-array 0 :element-type (upgraded-array-element-type object)))
    (error () nil)))

(defun character-element-type-p (object)
  (and (array-element-type-p object)
       (handler-case (subtypep object 'character) (error () nil))))

(defmethod make-collector-for ((target t) &rest options &key element-type)
  (declare (ignore options element-type))
  ;; A removed vector/string primary still reaches this fallback with :ELEMENT-TYPE.
  (raise-type-error target '(satisfies registered-collector-target-p)))

(defmethod make-collector-for ((target (eql (find-class 'list)))
                               &rest options &key)
  (validate-collector-options options nil)
  (make-instance 'list-collector))

(defmethod make-collector-for ((target list) &rest options &key)
  (validate-collector-options options nil)
  (make-instance 'list-collector))

(defmethod make-collector-for ((target (eql (find-class 'vector)))
                               &rest options &key (element-type t))
  (validate-collector-options options '(:element-type))
  (new-vector-collector element-type nil))

(defmethod make-collector-for ((target vector)
                               &rest options &key (element-type t))
  ;; Type-preserving callers explicitly supply ARRAY-ELEMENT-TYPE. The source's
  ;; active end is traversal state, never a Collector option or initial content.
  (validate-collector-options options '(:element-type))
  (new-vector-collector element-type nil))

(defmethod make-collector-for ((target (eql (find-class 'string)))
                               &rest options &key (element-type 'character))
  (validate-collector-options options '(:element-type))
  (new-vector-collector element-type t))

(defmethod make-collector-for ((target string)
                               &rest options &key (element-type 'character))
  (validate-collector-options options '(:element-type))
  (new-vector-collector element-type t))

(defmethod make-collector-for ((target (eql (find-class 'hash-table)))
                               &rest options &key (test 'equal))
  (validate-collector-options options '(:test))
  (make-instance 'hash-collector
                 :table (make-hash-table :test (standard-hash-test test))))

(defmethod make-collector-for ((target hash-table)
                               &rest options &key (test 'equal))
  (validate-collector-options options '(:test))
  (make-instance 'hash-collector
                 :table (make-hash-table :test (standard-hash-test test))))

(defmethod collector-accumulate ((collector t) element)
  (declare (ignore element))
  (raise-type-error collector 'collector))

(defmethod collector-result ((collector t))
  (raise-type-error collector 'collector))

(defmethod collector-accumulate :before ((collector collector) element)
  (declare (ignore element))
  (when (collector-finalized-p collector)
    (raise-simple-error "Cannot accumulate into a finalized Collector.")))

(defmethod collector-accumulate ((collector list-collector) element)
  (push element (collector-items collector))
  collector)

(defmethod collector-result ((collector list-collector))
  (cache-collector-result
   collector (lambda () (reverse (collector-items collector)))))

(defmethod collector-accumulate ((collector vector-collector) element)
  (unless (typep element (collector-element-type collector))
    (raise-type-error element (collector-element-type collector)))
  (let ((buffer (collector-buffer collector)))
    (vector-push-extend element buffer (max 1 (array-total-size buffer))))
  collector)

(defmethod collector-result ((collector vector-collector))
  (cache-collector-result
   collector
   (lambda ()
     (let* ((buffer (collector-buffer collector))
            (result (make-array (length buffer)
                                :element-type (collector-storage-element-type collector))))
       (replace result buffer)
       result))))

(defmethod collector-accumulate ((collector hash-collector) element)
  (unless (map-entry-p element)
    (raise-type-error element 'sl:map-entry))
  (let ((key (map-entry-key element))
        (value (map-entry-value element))
        (table (collector-table collector)))
    ;; Native SETF GETHASH need not replace an equivalent key representative.
    (remhash key table)
    (setf (gethash key table) value))
  collector)

(defmethod collector-result ((collector hash-collector))
  (cache-collector-result collector (lambda () (collector-table collector))))

(defparameter *vector-collector-protocol-methods* nil
  "Method objects for the vector-relevant built-in Collector signatures;
captured by signature, never by adopting arbitrary user methods.")

(defun capture-vector-collector-protocol ()
  "Capture built-in vector Collector method objects by their definition signatures.
Manually calling this internal function after redefining a built-in signature
would bless that replacement; such deliberate misuse is outside the guard."
  (setf *vector-collector-protocol-methods*
        (loop for (generic qualifiers specializers)
                in `((,#'sl:make-collector-for nil (t))
                     (,#'sl:make-collector-for nil (vector))
                     (,#'sl:make-collector-for nil (string))
                     (,#'sl:collector-accumulate nil (t t))
                     (,#'sl:collector-accumulate (:before) (collector t))
                     (,#'sl:collector-accumulate nil (vector-collector t))
                     (,#'sl:collector-result nil (t))
                     (,#'sl:collector-result nil (vector-collector)))
              collect (cons generic
                            (find-method generic qualifiers
                                         (mapcar #'find-class specializers))))))

(eval-when (:load-toplevel :execute)
  (capture-vector-collector-protocol))
