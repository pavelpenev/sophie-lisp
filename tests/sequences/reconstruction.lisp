(in-package #:sophie-lisp.tests)

;;;; Reconstruction and result-policy expectations.
;;;; Chapter 4 4.1.1-4.1.6; Chapter 6 6.1.1-6.1.5; Chapter 9 9.1.11.
;;;; These tests cover finite reconstruction and policy decisions. Operation
;;;; tests separately cover callback scheduling, streaming, and source activation.










;;;; A finite observation helper deliberately has no Chapter 6 dependency.
;;;; A local accumulator avoids prescribing hash/dict traversal order.
(defun policy-list (source)
  (let ((view source) (items nil))
    (loop for step below 10000
          until (sl:seq-emptyp view)
          do (push (sl:seq-first view) items)
             (setf view (sl:seq-rest view))
          finally (unless (sl:seq-emptyp view)
                    (parachute:true nil "POLICY-LIST exceeded its finite fixture bound")))
    (nreverse items)))

(defclass policy-source ()
  ((items :initarg :items :initform nil :reader policy-source-items)
   (config :initarg :config :initform nil :reader policy-config)
   ;; CAR counts sequential observations, CDR counts forbidden shortcuts.
   (reads :initarg :reads :initform (cons 0 0) :reader policy-reads)))
(defclass policy-collected (policy-source) ())
(defclass policy-child (policy-collected) ())
(defclass policy-aux (policy-source) ())
(defclass policy-dict (policy-source) ())
(defclass policy-refusing (policy-collected) ())

(defclass policy-collected-dict (policy-dict policy-collected) ())

(defclass policy-retry-source (policy-source) ())

(defmethod sl:seq-emptyp :before ((source policy-retry-source))
  (funcall (policy-config source) (car (policy-source-items source))))

(defmethod sl:seqablep ((source policy-source)) t)
(defmethod sl:seq-emptyp ((source policy-source))
  (incf (car (policy-reads source)))
  (null (policy-source-items source)))
(defmethod sl:seq-first ((source policy-source))
  (car (policy-source-items source)))
(defmethod sl:seq-rest ((source policy-source))
  (make-instance (class-of source) :items (cdr (policy-source-items source))
                 :config (policy-config source) :reads (policy-reads source)))
(defmethod sl:seq-length ((source policy-source))
  (incf (cdr (policy-reads source)))
  (call-next-method))
(defmethod sl:seq-ref ((source policy-source) index &optional default)
  (declare (ignore index default))
  (incf (cdr (policy-reads source)))
  (call-next-method))

;; A genuinely conforming, no-Collector user dict, not a DICTP-only impostor.
(defmethod sl:dictp ((source policy-dict)) t)
(defmethod sl:dict-test ((source policy-dict)) 'eq)
(defmethod sl:dict-size ((source policy-dict))
  (length (policy-source-items source)))
(defmethod sl:seq-length ((source policy-dict)) (sl:dict-size source))
(defmethod sl:dict-ref ((source policy-dict) key &optional default)
  (let ((entry (find key (policy-source-items source)
                     :key #'sl:entry-key :test #'eq)))
    (if entry (values (sl:entry-value entry) t) (values default nil))))

(defclass policy-collector ()
  ((source :initarg :source :reader policy-collector-source)
   (items :initform nil :accessor policy-collector-items)
   (result :accessor policy-collector-cached)))
(defvar *policy-events* nil)
(define-condition policy-refusal (error) ())
(defvar *policy-refusal* nil)
(defvar *policy-refusal-phase* nil)

(defmethod sl:make-collector-for ((source policy-collected) &key observer)
  (push :primary *policy-events*)
  (when observer (funcall observer source))
  (when (and (typep source 'policy-refusing)
             (eq *policy-refusal-phase* :create))
    (error *policy-refusal*))
  (make-instance 'policy-collector :source source))
(defmethod sl:make-collector-for :around ((source policy-collected) &key observer)
  (declare (ignore observer))
  (push :around-enter *policy-events*)
  (prog1 (call-next-method) (push :around-exit *policy-events*)))
(defmethod sl:make-collector-for :before ((source policy-collected) &key observer)
  (declare (ignore observer))
  (push :before *policy-events*))
(defmethod sl:make-collector-for :after ((source policy-collected) &key observer)
  (declare (ignore observer))
  (push :after *policy-events*))
(defmethod sl:make-collector-for :around ((source policy-aux) &key)
  (error "Auxiliary-only method must not be probed for participation."))
(defmethod sl:collector-accumulate ((state policy-collector) element)
  (when (and (typep (policy-collector-source state) 'policy-refusing)
             (eq *policy-refusal-phase* :accumulate))
    (error *policy-refusal*))
  (push element (policy-collector-items state))
  state)
(defmethod sl:collector-result ((state policy-collector))
  (when (and (typep (policy-collector-source state) 'policy-refusing)
             (eq *policy-refusal-phase* :result))
    (error *policy-refusal*))
  (if (slot-boundp state 'result)
      (policy-collector-cached state)
      (setf (policy-collector-cached state)
            (make-instance (class-of (policy-collector-source state))
                           :config (policy-config (policy-collector-source state))
                           :items (reverse (policy-collector-items state))))))









(parachute:define-test public-reconstruction.vector-contract
  (dolist (requested '(bit (unsigned-byte 8) single-float))
    (let* ((items (if (eq requested 'single-float) '(1.0 0.0 1.0 0.0) '(1 0 1 0)))
           (source (make-array 4 :element-type requested :initial-contents items
                               :fill-pointer 3 :adjustable t))
           (result (sl:seq-take 4 source)))
      (parachute:is equal (array-element-type source) (array-element-type result))
      (parachute:is equal (subseq items 0 3) (coerce result 'list))
      (parachute:false (eq source result))
      (parachute:is equal items (loop for i below 4 collect (aref source i))))))

(defclass into-option-target () ((items :initarg :items :reader into-option-items)))
(defclass into-option-state () ((items :initform nil :accessor into-option-buffer)
                                 (result :initform nil :accessor into-option-result)))
(defvar *into-option-events* nil)
(defvar *into-option-refusal* nil)
(defvar *into-option-state* nil)
(defmethod sophie-lisp:make-collector-for
    ((target (eql (find-class 'into-option-target))) &key token)
  (push (list :create target token) *into-option-events*)
  (setf *into-option-state* (make-instance 'into-option-state)))
(defmethod sophie-lisp:collector-accumulate ((state into-option-state) item)
  (push (list :accumulate item) *into-option-events*)
  (when (and *into-option-refusal* (= item 2)) (error *into-option-refusal*))
  (push item (into-option-buffer state))
  state)
(defmethod sophie-lisp:collector-result ((state into-option-state))
  (or (into-option-result state)
      (progn (push :finalize *into-option-events*)
             (setf (into-option-result state)
                   (make-instance 'into-option-target
                                  :items (reverse (into-option-buffer state)))))))

(defun into-option-check (construct)
  (let* ((*into-option-events* nil) (*into-option-state* nil)
         (token (list :identity))
         (result (funcall construct (list 'into-option-target :token token))))
    (parachute:true (typep result 'into-option-target))
    (parachute:is equal '(1 2 3) (into-option-items result))
    (parachute:is equal (list (list :create (find-class 'into-option-target) token)
                              '(:accumulate 1) '(:accumulate 2) '(:accumulate 3) :finalize)
                        (reverse *into-option-events*))
    (parachute:is eq token (third (car (last *into-option-events*))))))

(defun into-refusal-check (construct)
  (let* ((*into-option-events* nil) (*into-option-state* nil)
         (*into-option-refusal* (make-condition 'simple-error :format-control "late refusal"))
         (later 0))
    (parachute:is eq *into-option-refusal*
      (handler-case (funcall construct 'into-option-target (lambda () (incf later)))
        (error (c) c)))
    (parachute:is = 0 later)
    (parachute:is equal '(1) (reverse (into-option-buffer *into-option-state*)))
    (parachute:is equal (list (list :create (find-class 'into-option-target) nil)
                              '(:accumulate 1) '(:accumulate 2))
                        (reverse *into-option-events*))))


(parachute:define-test dict-convert.entry-shape-and-test-options
  (let* ((key (gensym "SHAPE-KEY-"))
         (value (list :shape-value))
         (alist (list (cons key value))))
    ;; A cons-shaped ordinary list is not implicitly an entry sequence.
    (parachute:fail
     (sophie-lisp:seq-into 'sophie-lisp:dict alist)
     type-error))
  (let* ((first-key (copy-seq "hash-key"))
         (last-key (copy-seq "hash-key"))
         (first-value (list :first))
         (last-value (list :last))
         (source (make-hash-table :test 'eq)))
    (setf (gethash first-key source) first-value
          (gethash last-key source) last-value)
    (parachute:false (eq first-key last-key))
    (let ((eq-result
            (sophie-lisp:seq-into
             (list 'hash-table :test #'eq) source))
          (equal-result
            (sophie-lisp:seq-into
             (list 'hash-table :test #'equal) source)))
      (parachute:is = 2 (hash-table-count eq-result))
      (parachute:is eq 'eq (sophie-lisp:dict-test eq-result))
      (parachute:is = 1 (hash-table-count equal-result))
      (parachute:is eq 'equal (sophie-lisp:dict-test equal-result))))
  (let* ((key (gensym "EAGER-KEY-"))
         (value (list :eager-value))
         (source (make-hash-table :test 'eq)))
    (setf (gethash key source) value)
    (let ((result (sophie-lisp:seq-into
                   (list 'hash-table :test #'eq) source)))
      ;; Materialization has completed before the call returns.
      (remhash key source)
      (parachute:true (hash-table-p result))
      (multiple-value-bind (stored present)
          (gethash key result)
        (parachute:is eq value stored)
        (parachute:true present))
      (parachute:fail
       (sophie-lisp:seq-into
        (list 'hash-table :test #'identity) source)
       type-error)
      (parachute:fail
       (sophie-lisp:seq-into (list 'hash-table :test) source)
       program-error))))

;;;; Independent construction boundary tests, appended after intact CONVERT-004.
(defun into-list (source)
  (let ((view source) (out nil))
    (loop for step below 10000
          until (sophie-lisp:seq-emptyp view)
          do (push (sophie-lisp:seq-first view) out)
             (setf view (sophie-lisp:seq-rest view))
          finally (unless (sophie-lisp:seq-emptyp view)
                    (parachute:true nil "INTO-LIST exceeded its finite fixture bound")))
    (nreverse out)))
(defun into-lazy (items visit)
  (sophie-lisp:make-lazy-seq
   (lambda () (funcall visit items)
     (if items (sophie-lisp:lazy-cons (car items) (into-lazy (cdr items) visit)) nil))))
(defclass into-target () ((items :initarg :items :reader into-items)))
(defclass into-state ()
  ((items :initform nil :accessor into-buffer)
   (result :initform nil :accessor into-result)))
(defvar *into-events* nil)
(defvar *into-refuse* nil)
(defmethod sophie-lisp:make-collector-for ((target (eql (find-class 'into-target))) &key)
  (push :create *into-events*)
  (values (make-instance 'into-state) :ignored))
(defmethod sophie-lisp:collector-accumulate ((c into-state) item)
  (push (list :accumulate item) *into-events*)
  (when *into-refuse* (error *into-refuse*))
  (push item (into-buffer c))
  (values c :ignored))
(defmethod sophie-lisp:collector-result ((c into-state))
  (unless (into-result c)
    (push :finalize *into-events*)
    (setf (into-result c) (make-instance 'into-target :items (reverse (into-buffer c)))))
  (values (into-result c) :ignored))
(defmethod sophie-lisp:seqablep ((x into-target)) t)
(defmethod sophie-lisp:seq-emptyp ((x into-target)) (null (into-items x)))
(defmethod sophie-lisp:seq-first ((x into-target)) (values (car (into-items x)) :ignored))
(defmethod sophie-lisp:seq-rest ((x into-target)) (cdr (into-items x)))

(parachute:define-test seq-into.eager-target-reconstruction
  (let* ((source (list 1 2)) (result (sophie-lisp:seq-into 'vector source)))
    (parachute:is equalp #(1 2) result)
    (parachute:is eq t (array-element-type result))
    (parachute:is equal '(1 2) source)
    (parachute:false (eq source result)))
  (let* ((source (vector 1 2)) (result (sophie-lisp:seq-into 'vector source)))
    (parachute:false (eq source result)))
  (parachute:is equal '(#\a #\b) (sophie-lisp:seq-into 'list "ab"))
  (parachute:is string= "ab" (sophie-lisp:seq-into 'string '(#\a #\b)))
  (parachute:is equalp #*101 (sophie-lisp:seq-into '(vector :element-type bit) '(1 0 1)))
  (let ((*into-events* nil) (visits 0))
    (let ((result (sophie-lisp:seq-into 'into-target
                    (into-lazy '(1 nil 2) (lambda (x) (declare (ignore x)) (incf visits))))))
      (parachute:true (typep result 'into-target))
      (parachute:is equal '(1 nil 2) (into-items result))
      (parachute:is = 4 visits)
      (parachute:is equal '(:create (:accumulate 1) (:accumulate nil) (:accumulate 2) :finalize)
                         (reverse *into-events*))))
  (parachute:is equal '(1 nil 2)
    (sophie-lisp:seq-into 'list (make-instance 'into-target :items '(1 nil 2))))
  (dolist (key '(:test :test-not :key))
    (parachute:fail (funcall #'sophie-lisp:seq-into 'list '(1) key nil) program-error))
  (into-option-check (lambda (target) (sophie-lisp:seq-into target '(1 2 3)))))

(parachute:define-test seq-into.lazy-target-reconstruction
  ;; A conforming implementation may reuse a lazy input OR wrap it.
  (dolist (target (list 'sophie-lisp:lazy-seq :lazy-seq (make-symbol "LAZY-SEQ")))
    (let* ((visits 0)
           (source (into-lazy '(1 2) (lambda (x) (declare (ignore x)) (incf visits))))
           (result (sophie-lisp:seq-into target source)))
      (parachute:true (sophie-lisp:lazy-seq-p result))
      (parachute:is = 0 visits)
      (parachute:is = 1 (sophie-lisp:seq-first result))
      (parachute:is = 1 visits)
      (parachute:is = 1 (sophie-lisp:seq-first result))))
  (let ((result (sophie-lisp:seq-into (list (make-symbol "LAZY-SEQ")) '(1 2))))
    (parachute:is equal '(1 2) (into-list result)))
  (parachute:fail (sophie-lisp:seq-into '(sophie-lisp:lazy-seq :element-type t) '(1)) program-error)
  (let ((calls 0))
    (labels ((forever (n)
               (sophie-lisp:make-lazy-seq
                (lambda () (incf calls) (sophie-lisp:lazy-cons n (forever (1+ n)))))))
      (let ((result (sophie-lisp:seq-into 'sophie-lisp:lazy-seq (forever 1))))
        (parachute:is = 0 calls)
        (parachute:is = 1 (sophie-lisp:seq-first result))
        (parachute:is = 1 calls)
        (parachute:is = 2 (sophie-lisp:seq-first (sophie-lisp:seq-rest result)))
        (parachute:is = 2 calls)))))

(parachute:define-test seq-into.unsupported-target-element-type-error
  ;; INTO-STATE resolves to a class but has no target Collector method.
  (parachute:fail
   (sophie-lisp:seq-into '(into-state :element-type t) '(1))
   type-error))

(parachute:define-test seq-into.unsupported-target-malformed-options-program-error
  ;; INTO-STATE resolves to a class but has no target Collector method.
  ;; Validate the dangling keyword before checking target support.
  (parachute:fail
   (sophie-lisp:seq-into '(into-state :element-type) '(1))
   program-error))

(parachute:define-test seq-into.validation-and-collector-errors
  (let* ((k1 (copy-seq "key")) (k2 (copy-seq "key"))
         (entries (list (sophie-lisp:map-entry k1 1) (sophie-lisp:map-entry k2 2)))
         (table (sophie-lisp:seq-into 'hash-table entries))
         (dict (sophie-lisp:seq-into 'sophie-lisp:dict entries)))
    (parachute:is eq 'equal (hash-table-test table))
    (parachute:is = 1 (hash-table-count table))
    (parachute:is = 2 (gethash k1 table))
    (parachute:is eq k2 (sophie-lisp:entry-key (sophie-lisp:seq-first dict)))
    (parachute:is = 2 (sophie-lisp:entry-value (sophie-lisp:seq-first dict))))
  (parachute:is = 2 (length (into-list (sophie-lisp:seq-into 'sophie-lisp:hash-set '(1 1 2)))))
  (parachute:fail (sophie-lisp:seq-into 'hash-table '((:a . 1))) type-error)
  (parachute:fail (sophie-lisp:seq-into 'sophie-lisp:dict '(:a 1)) type-error)
  (parachute:fail (sophie-lisp:seq-into 'string '(#\a 1)) type-error)
  (parachute:fail (sophie-lisp:seq-into 'list 42) type-error)
  (dolist (target (list 42 '(42) '(vector . :bad) '(vector :element-type)
                       '(vector element-type bit) '(sophie-lisp:lazy-seq :unknown t)
                       '(list :unknown t) '(vector :test equal)))
    (let* ((calls 0) (source (into-lazy '(1) (lambda (x) (declare (ignore x)) (incf calls)))))
      (parachute:fail (sophie-lisp:seq-into target source) program-error)
      (parachute:is = 0 calls)))
  ;; NIL is an ordinary lookup, not a spelling of LIST. The unregistered
  ;; same-name symbol is not the registered user class. INTO-STATE has no target Collector.
  (dolist (target (list nil (make-symbol "INTO-TARGET") 'into-state
                       (gensym "UNRESOLVED") '(string :element-type integer)
                       '(hash-table :test identity)))
    (let* ((calls 0) (source (into-lazy '(1) (lambda (x) (declare (ignore x)) (incf calls)))))
      (parachute:fail (sophie-lisp:seq-into target source) type-error)
      (parachute:is = 0 calls)))
  (let ((*into-events* nil)
        (*into-refuse* (make-condition 'simple-error :format-control "refuse into")))
    (parachute:is eq *into-refuse*
      (handler-case (sophie-lisp:seq-into 'into-target '(1 2)) (error (c) c)))
    (parachute:is equal '(:create (:accumulate 1)) (reverse *into-events*)))
  (into-refusal-check
    (lambda (target later)
      (sophie-lisp:seq-into target
        (sophie-lisp:lazy-cons 1
          (sophie-lisp:lazy-cons 2
            (sophie-lisp:make-lazy-seq
              (lambda () (funcall later) (sophie-lisp:lazy-cons 3 nil)))))))))

(defclass join-option-target () ((items :initarg :items :reader join-option-items)))
(defclass join-option-state () ((items :initform nil :accessor join-option-buffer)
                                 (result :initform nil :accessor join-option-result)))
(defvar *join-option-events* nil)
(defvar *join-option-refusal* nil)
(defvar *join-option-state* nil)
(defmethod sophie-lisp:make-collector-for
    ((target (eql (find-class 'join-option-target))) &key token)
  (push (list :create target token) *join-option-events*)
  (setf *join-option-state* (make-instance 'join-option-state)))
(defmethod sophie-lisp:collector-accumulate ((state join-option-state) item)
  (push (list :accumulate item) *join-option-events*)
  (when (and *join-option-refusal* (= item 2)) (error *join-option-refusal*))
  (push item (join-option-buffer state))
  state)
(defmethod sophie-lisp:collector-result ((state join-option-state))
  (or (join-option-result state)
      (progn (push :finalize *join-option-events*)
             (setf (join-option-result state)
                   (make-instance 'join-option-target
                                  :items (reverse (join-option-buffer state)))))))

(defun join-option-check (construct)
  (let* ((*join-option-events* nil) (*join-option-state* nil)
         (token (list :identity))
         (result (funcall construct (list 'join-option-target :token token))))
    (parachute:true (typep result 'join-option-target))
    (parachute:is equal '(1 2 3) (join-option-items result))
    (parachute:is equal (list (list :create (find-class 'join-option-target) token)
                              '(:accumulate 1) '(:accumulate 2) '(:accumulate 3) :finalize)
                        (reverse *join-option-events*))
    (parachute:is eq token (third (car (last *join-option-events*))))))

(defun join-refusal-check (construct)
  (let* ((*join-option-events* nil) (*join-option-state* nil)
         (*join-option-refusal* (make-condition 'simple-error :format-control "late refusal"))
         (later 0))
    (parachute:is eq *join-option-refusal*
      (handler-case (funcall construct 'join-option-target (lambda () (incf later)))
        (error (c) c)))
    (parachute:is = 0 later)
    (parachute:is equal '(1) (reverse (join-option-buffer *join-option-state*)))
    (parachute:is equal (list (list :create (find-class 'join-option-target) nil)
                              '(:accumulate 1) '(:accumulate 2))
                        (reverse *join-option-events*))))

(defun join-source-retry (outerp)
  (let* ((attempts 0) (prefix-calls 0) (later-calls 0)
         (sentinel (make-condition 'simple-error :format-control "join source retry"))
         (item (list :prefix))
         (prefix (join-lazy (list item)
                   (lambda (tail) (when tail (incf prefix-calls)))))
         (later (join-lazy '(3) (lambda (tail) (when tail (incf later-calls)))))
         (retry (sophie-lisp:make-lazy-seq
                  (lambda ()
                    (incf attempts)
                    (when (= attempts 1) (error sentinel))
                    (if outerp
                        (sophie-lisp:lazy-cons '(2) (sophie-lisp:lazy-cons later nil))
                        (sophie-lisp:lazy-cons 2 nil)))))
         (outer (if outerp (sophie-lisp:lazy-cons prefix retry)
                    (list prefix retry later)))
         (result (sophie-lisp:seq-join :lazy-seq outer :separator '(0))))
    (parachute:is = 0 attempts)
    (parachute:is eq item (sophie-lisp:seq-first result))
    (parachute:is eq sentinel (handler-case (join-list result) (error (c) c)))
    (parachute:is = 1 attempts)
    (parachute:is = 0 later-calls)
    (parachute:is eq item (sophie-lisp:seq-first result))
    (parachute:is = 1 prefix-calls)
    (parachute:is equal (list item 0 2 0 3) (join-list result))
    (parachute:is = 2 attempts)
    (parachute:is = 1 prefix-calls)
    (parachute:is = 1 later-calls)
    (parachute:is equal (list item 0 2 0 3) (join-list result))
    (parachute:is = 2 attempts)))


(defun join-list (source)
  (let ((view source) (out nil))
    (loop for step below 10000
          until (sophie-lisp:seq-emptyp view)
          do (push (sophie-lisp:seq-first view) out)
             (setf view (sophie-lisp:seq-rest view))
          finally (unless (sophie-lisp:seq-emptyp view)
                    (parachute:true nil "JOIN-LIST exceeded its finite fixture bound")))
    (nreverse out)))
(defun join-lazy (items visit)
  (sophie-lisp:make-lazy-seq
   (lambda () (funcall visit items)
     (if items (sophie-lisp:lazy-cons (car items) (join-lazy (cdr items) visit)) nil))))

(parachute:define-test seq-join.eager-target-reconstruction
  (let* ((piece (vector 1 2))
         (result (sophie-lisp:seq-join 'vector (list piece #(3) #(4)) :separator #(0))))
    (parachute:is equalp #(1 2 0 3 0 4) result)
    (parachute:false (eq piece result))
    (parachute:is eq t (array-element-type result))
    (parachute:is equalp #(1 2) piece))
  (parachute:is equalp #(1 2 3 4)
    (sophie-lisp:seq-join 'vector (list '(1 2) #(3 4))))
  (parachute:is equal '(1 2 3) (sophie-lisp:seq-join 'list (list #(1 2) #(3))))
  (parachute:is string= "ab-c" (sophie-lisp:seq-join 'string '("ab" "c") :separator "-"))
  (parachute:is equalp #*101
    (sophie-lisp:seq-join '(vector :element-type bit) '((1) (1)) :separator '(0)))
  (let ((outer 0) (first 0) (second 0) (separator 0))
    (let* ((a (join-lazy '(1 2) (lambda (x) (declare (ignore x)) (incf first))))
           (b (join-lazy '(3) (lambda (x) (declare (ignore x)) (incf second))))
           (sep (join-lazy '(0) (lambda (x) (declare (ignore x)) (incf separator))))
           (seqs (join-lazy (list a b '(4)) (lambda (x) (declare (ignore x)) (incf outer))))
           (result (sophie-lisp:seq-join 'vector seqs :separator sep)))
      (parachute:is equalp #(1 2 0 3 0 4) result)
      (parachute:is = 4 outer)
      (parachute:is = 3 first)
      (parachute:is = 2 second)
      (parachute:is = 2 separator)))
  (let ((events nil))
    (let ((a (join-lazy '(1 2) (lambda (tail) (push (list :a tail) events))))
          (b (join-lazy '(3) (lambda (tail) (push (list :b tail) events)))))
      (parachute:is equal '(1 2 3) (sophie-lisp:seq-join 'list (list a b)))
      (parachute:is equal '((:a (1 2)) (:a (2)) (:a nil) (:b (3)) (:b nil))
                         (reverse events))))
  (join-option-check (lambda (target) (sophie-lisp:seq-join target '((1) (3)) :separator '(2)))))

(parachute:define-test seq-join.lazy-forcing-and-retry
  (let ((outer 0) (piece 0) (separator 0))
    (labels ((unbounded (n)
               (sophie-lisp:make-lazy-seq
                (lambda () (incf piece) (sophie-lisp:lazy-cons n (unbounded (1+ n)))))))
      (let* ((seqs (join-lazy (list (unbounded 1) 42)
                             (lambda (x) (declare (ignore x)) (incf outer))))
             (sep (sophie-lisp:make-lazy-seq (lambda () (incf separator) (error "unreached separator"))))
             (result (sophie-lisp:seq-join (make-symbol "LAZY-SEQ") seqs :separator sep)))
        (parachute:true (sophie-lisp:lazy-seq-p result))
        (parachute:is = 0 outer)
        (parachute:is = 0 piece)
        (parachute:is = 0 separator)
        (parachute:is = 1 (sophie-lisp:seq-first result))
        (parachute:is = 1 piece)
        (parachute:is = 2 (sophie-lisp:seq-first (sophie-lisp:seq-rest result)))
        (parachute:is = 2 piece)
        (parachute:is = 1 outer)
        (parachute:is = 0 separator))))
  (let* ((attempts 0)
         (sentinel (make-condition 'simple-error :format-control "separator failure"))
         (sep (sophie-lisp:make-lazy-seq
               (lambda () (incf attempts)
                 (if (= attempts 1) (error sentinel) (sophie-lisp:lazy-cons 0 nil)))))
         (result (sophie-lisp:seq-join 'sophie-lisp:lazy-seq '((1) (2)) :separator sep)))
    (parachute:is = 0 attempts)
    (parachute:is = 1 (sophie-lisp:seq-first result))
    (parachute:is eq sentinel
      (handler-case (sophie-lisp:seq-first (sophie-lisp:seq-rest result)) (error (c) c)))
    (parachute:is equal '(1 0 2) (join-list result)))
  (join-source-retry t)
  (join-source-retry nil))

(parachute:define-test seq-join.empty-input-and-validation
  (let ((a (sophie-lisp:seq-join 'vector nil)) (b (sophie-lisp:seq-join 'vector nil)))
    (parachute:is equalp #() a)
    (parachute:false (eq a b)))
  (parachute:is equal '(1 0 2)
    (sophie-lisp:seq-join 'list '(nil (1) nil (2) nil) :separator '(0)))
  (parachute:is equal nil (sophie-lisp:seq-join 'list '(nil nil) :separator '(0)))
  (parachute:is equal '(1) (sophie-lisp:seq-join 'list '(nil (1) nil) :separator '(0)))
  (dolist (key '(:test :test-not :key :start :unknown))
    (parachute:fail (sophie-lisp:seq-join 'list '((1)) key nil) program-error))
  (parachute:fail (sophie-lisp:seq-join 'list '((1) 42)) type-error)
  (parachute:fail (sophie-lisp:seq-join 'list 42) type-error)
  (parachute:fail (sophie-lisp:seq-join (gensym "UNKNOWN") '((1))) type-error)
  (parachute:fail (sophie-lisp:seq-join '(vector :element-type) '((1))) program-error)
  (parachute:fail (sophie-lisp:seq-join '(sophie-lisp:lazy-seq :unknown t) '((1))) program-error)
  (parachute:fail (sophie-lisp:seq-join '(string :element-type integer) '((1))) type-error)
  (parachute:fail (sophie-lisp:seq-join 'string '((#\a) (1))) type-error)
  (let* ((calls 0)
         (source (join-lazy '((1)) (lambda (x) (declare (ignore x)) (incf calls)))))
    (parachute:fail (sophie-lisp:seq-join '(list :unknown t) source) program-error)
    (parachute:is = 0 calls))
  (let* ((sentinel (make-condition 'simple-error :format-control "first piece end"))
         (later 0)
         (a (join-lazy '(1) (lambda (tail) (unless tail (error sentinel)))))
         (b (join-lazy '(2) (lambda (x) (declare (ignore x)) (incf later)))))
    (parachute:is eq sentinel
      (handler-case (sophie-lisp:seq-join 'list (list a b)) (error (c) c)))
    (parachute:is = 0 later))
  (let ((result (sophie-lisp:seq-join 'sophie-lisp:lazy-seq '((1) 42))))
    (parachute:is = 1 (sophie-lisp:seq-first result))
    (parachute:fail (join-list result) type-error))
  (join-refusal-check
    (lambda (target later)
      (sophie-lisp:seq-join target
        (sophie-lisp:lazy-cons
          (sophie-lisp:lazy-cons 1
            (sophie-lisp:lazy-cons 2
              (sophie-lisp:make-lazy-seq
                (lambda () (funcall later) (sophie-lisp:lazy-cons 3 nil)))))
          (sophie-lisp:make-lazy-seq
            (lambda () (funcall later) (sophie-lisp:lazy-cons '(4) nil))))))))
