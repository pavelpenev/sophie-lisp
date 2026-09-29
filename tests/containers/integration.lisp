;;;; Independent D-CONTAINER-SEQ acceptance, Chapters 4 and 9.
;;;; SEQ-DICT-004 is defined by D-PROJECTIONS, which consumes the CSEQ helpers.
;;;; PLIST-003/004 traversal obligations are covered by SEQ-DICT-001/003.
;;;; No container EQUALS/COMPARE/HASH-CODE oracle or assumed unordered order.
;;;; Non-traversing built-in length and private cursor usage also need source
;;;; review; subclass sentinels below observe public primitive dispatch only.
(in-package #:sophie-lisp.tests)

(defclass cseq-set-child (sl:hash-set) ())
(defclass cseq-plist-child (sl:plist-dict-view) ())
(defvar *cseq-forbid-traversal* nil)

(defmethod sl:seq-first :before ((source cseq-set-child))
  (when *cseq-forbid-traversal* (error "LENGTH traversed set FIRST")))
(defmethod sl:seq-rest :before ((source cseq-set-child))
  (when *cseq-forbid-traversal* (error "LENGTH traversed set REST")))
(defmethod sl:seq-first :before ((source cseq-plist-child))
  (when *cseq-forbid-traversal* (error "LENGTH traversed plist FIRST")))
(defmethod sl:seq-rest :before ((source cseq-plist-child))
  (when *cseq-forbid-traversal* (error "LENGTH traversed plist REST")))

(defun cseq-drain (view expected-count)
  ;; Never wait for an accidentally circular result; permit exactly the known
  ;; number of elements and one end observation. Expectations come from CL data.
  (let ((items nil))
    (dotimes (i (1+ expected-count))
      (declare (ignorable i))
      (when (sl:seq-emptyp view)
        (parachute:is eq nil (sl:seq-first view))
        (parachute:is eq nil (sl:seq-rest view))
        (return-from cseq-drain (nreverse items)))
      (push (sl:seq-first view) items)
      (setf view (sl:seq-rest view)))
    (parachute:true nil "Traversal exceeded its independent finite bound")
    (nreverse items)))

(defun cseq-ref-values (source index default expected present-p &optional entries-p)
  (let ((values (multiple-value-list (sl:seq-ref source index default))))
    (parachute:is = 2 (length values))
    ;; Independent public traversals may allocate distinct MAP-ENTRY wrappers.
    (if (and present-p entries-p)
        (progn
          (parachute:true (typep (first values) 'sl:map-entry))
          (parachute:is eq (sl:entry-key expected) (sl:entry-key (first values)))
          (parachute:is eq (sl:entry-value expected) (sl:entry-value (first values))))
        (parachute:is eq expected (first values)))
    (parachute:is eq present-p (not (null (second values))))))

(defun cseq-check-associations (entries expected)
  (parachute:is = (length expected) (length entries))
  (dolist (entry entries)
    (parachute:true (typep entry 'sl:map-entry))
    (parachute:false (sl:seqablep entry))
    (let ((pair (assoc (sl:entry-key entry) expected :test #'eq)))
      (parachute:true pair "Every entry has an independently expected resident key")
      (parachute:is eq (cdr pair) (sl:entry-value entry))))
  (dolist (pair expected)
    (parachute:is = 1 (count (car pair) entries :key #'sl:entry-key :test #'eq))))

(defun cseq-check-view (source expected entries-p)
  (parachute:true (sl:seqablep source))
  (parachute:is eq (null expected) (not (null (sl:seq-emptyp source))))
  (let ((items (cseq-drain source (length expected))))
    (parachute:is = (length expected) (length items))
    (loop for item in items for index from 0 do
      (cseq-ref-values source index :unused item t entries-p))
    (if entries-p
        (progn
          (cseq-check-associations items expected)
          (cseq-check-associations (cseq-drain source (length expected)) expected))
        (dolist (observed (list items (cseq-drain source (length expected))))
          (parachute:is = (length expected) (length observed))
          (dolist (element expected)
            (parachute:is = 1 (count element observed :test #'eq)))))
    ;; Direct FIRST and REST are independent views. Never concatenate them or
    ;; assert either equality or freshness of independently created entries.
    (if expected
        (progn
          (if entries-p
              (parachute:true (typep (sl:seq-first source) 'sl:map-entry))
              (parachute:true (member (sl:seq-first source) expected :test #'eq)))
          (parachute:true (sl:seqablep (sl:seq-rest source)))
          (parachute:is = (1- (length expected))
            (length (cseq-drain (sl:seq-rest source) (1- (length expected))))))
        (progn
          (parachute:is eq nil (sl:seq-first source))
          (parachute:is eq nil (sl:seq-rest source))))))

(parachute:define-test container-seq.traversal
  (let* ((key (copy-seq "resident")) (value (list :resident-value))
         (expected (list (cons key value) (cons :nil nil) (cons :other :value)))
         (dict (sl:dict key value :nil nil :other :value))
         (plist (sl:plist-dict-view (list key value :nil nil :other :value))))
    (cseq-check-view dict expected t)
    (cseq-check-view plist expected t)
    (cseq-check-view (sl:hash-set nil key :other) (list nil key :other) nil))
  (dolist (source (list (sl:dict) (sl:hash-set) (sl:plist-dict-view nil)))
    (cseq-check-view source nil (not (sl:hash-set-p source))))
  ;; A singleton NIL element is nonempty, unlike an empty set.
  (let ((source (sl:hash-set nil)))
    (parachute:false (sl:seq-emptyp source))
    (parachute:is eq nil (sl:seq-first source))
    (cseq-ref-values source 0 :absent nil t)))

(parachute:define-test container-seq.length-and-index
  (dolist (source (list (sl:dict) (sl:dict :a nil :b :value)
                        (sl:hash-set) (sl:hash-set nil :value)
                        (sl:plist-dict-view nil)
                        (sl:plist-dict-view '(:a nil :b :value :a :hidden))))
    (let* ((count (if (sl:hash-set-p source)
                      (sl:set-size source)
                      (sl:dict-size source)))
           (default (list :default)))
      (parachute:is = count (sl:seq-length source))
      (parachute:is = count
        (length (cseq-drain source count)))
      (cseq-ref-values source count nil nil nil)
      (cseq-ref-values source (+ count 3) default default nil)
      (parachute:fail (sl:seq-ref source count) type-error)
      (dolist (index '(1/2 1.0 nil :invalid))
        (parachute:fail (sl:seq-ref source index) type-error)
        (parachute:fail (sl:seq-ref source index default) type-error))
      (if (plusp count)
          (let ((values (multiple-value-list (sl:seq-ref source -1 default))))
            (parachute:is = 2 (length values))
            (parachute:true (second values)))
          (progn
            (parachute:is equal (list default nil)
                          (multiple-value-list (sl:seq-ref source -1 default)))
            (parachute:fail (sl:seq-ref source -1) type-error)))
      (dolist (index '(0 -1 :invalid))
        (parachute:fail (setf (sl:seq-ref source index) :new) simple-error)
        (parachute:fail (setf (sl:seq-ref source index default) :new) simple-error))
      (parachute:is = count (sl:seq-length source))))
  ;; CHANGE-CLASS preserves provider storage without inventing a public
  ;; MAKE-INSTANCE interface. DICT is sealed and is deliberately not subclassed.
  (let ((set (change-class (sl:hash-set nil :x) 'cseq-set-child))
        (plist (change-class (sl:plist-dict-view '(:a nil :b :x)) 'cseq-plist-child)))
    (let ((*cseq-forbid-traversal* t))
      (parachute:is = 2 (sl:seq-length set))
      (parachute:is = 2 (sl:seq-length plist)))
    (cseq-check-view set '(nil :x) nil)
    (cseq-check-view plist '((:a) (:b . :x)) t)))

(parachute:define-test container-seq.persistent-views
  ;; EQ-distinct but CL:EQUAL strings must remain TWO canonical plist keys.
  (let* ((a (copy-seq "same")) (b (copy-seq "same"))
         (value (list :shared))
         (expected (list (cons a nil) (cons b value) (cons nil :nil-key)))
         (source (sl:plist-dict-view
                  (list a nil b value a :hidden nil :nil-key b :also-hidden))))
    (parachute:false (eq a b))
    (parachute:true (equal a b))
    (cseq-check-view source expected t)
    (parachute:is = 3 (sl:dict-size source))
    (parachute:is = 3 (sl:seq-length source))
    (dolist (entry (cseq-drain source 3))
      (let ((values (multiple-value-list (sl:dict-ref source (sl:entry-key entry)))))
        (parachute:is = 2 (length values))
        (parachute:true (second values))
        (parachute:is eq (sl:entry-value entry) (first values)))))
  ;; A retained public REST result stays bound to the original persistent dict.
  ;; SL:DICT traversal order is unspecified (Chapter 9) and follows host
  ;; SXHASH, so HEAD is whichever entry the host visits first; the head and
  ;; tail expectations are derived from the observed keys instead of
  ;; assuming :a comes first.
  (let* ((value (list :old))
         (dict (sl:dict :a value :b nil))
         (head (sl:seq-first dict))
         (tail (sl:seq-rest dict))
         (new (sl:dict-set dict :a :new))
         (removed (sl:dict-without new :b))
         (head-key (sl:entry-key head))
         (tail-key (sl:entry-key (sl:seq-first tail)))
         (value-of (lambda (key) (if (eq key :a) value nil))))
    (cseq-check-associations (list head)
                             (list (cons head-key (funcall value-of head-key))))
    (cseq-check-associations (cseq-drain tail 1)
                             (list (cons tail-key (funcall value-of tail-key))))
    (cseq-check-associations (cseq-drain dict 2)
                             (list (cons :a value) (cons :b nil)))
    (cseq-check-view dict (list (cons :a value) (cons :b nil)) t)
    (cseq-check-view new '((:a . :new) (:b)) t)
    (cseq-check-view removed '((:a . :new)) t))
  (let* ((set (sl:hash-set nil :old))
         (new (sl:set-add :new set)))
    (parachute:is = 2 (length (cseq-drain set 2)))
    (cseq-check-view set '(nil :old) nil)
    (cseq-check-view new '(nil :old :new) nil)))

(parachute:define-test container-seq.dict-boundary
  (let* ((pair (cons :a :b)) (entry (sl:map-entry :a :b))
         (alist (list pair)) (plist (list :a :b))
         (entries (list entry)) (set (sl:hash-set pair)))
    (dolist (source (list alist plist entries set nil))
      (parachute:true (sl:seqablep source))
      (parachute:false (sl:dictp source))
      (parachute:fail (sl:dict-ref source :a) type-error))
    (parachute:is eq pair (sl:seq-first alist))
    (parachute:is eq :a (sl:seq-first plist))
    (parachute:is eq entry (sl:seq-first entries))
    (parachute:is eq pair (sl:seq-first set))
    (parachute:false (typep (sl:seq-first set) 'sl:map-entry))
    (parachute:is eq (cdr plist) (sl:seq-rest plist))
    (parachute:is = 2 (sl:seq-length plist))
    (cseq-check-view set (list pair) nil)
    (dolist (source (list (sl:dict :a :b) (sl:plist-dict-view plist)))
      (parachute:true (sl:dictp source))
      (parachute:true (typep (sl:seq-first source) 'sl:map-entry)))))

;; Public assertions moved unchanged from ADAPTER-003/004. The helper
;; ADAPTER-TABLE-ASSOCIATION is loaded through D-HASH-ADAPTER.
(parachute:define-test dict-collect.hash-table-last-wins
  (let* ((source (make-hash-table :test 'equal))
         (first-key (copy-seq "same-key"))
         (last-key (copy-seq "same-key"))
         (first-value (list :first))
         (last-value (list :last))
         (entries (list (sophie-lisp:map-entry first-key first-value)
                        (sophie-lisp:map-entry last-key last-value)))
         (result (sophie-lisp:dict-collect source entries :test 'equal)))
    (parachute:false (eq first-key last-key))
    (parachute:false (eq source result))
    (parachute:is eq 'equal (sophie-lisp:dict-test result))
    (parachute:is = 1 (hash-table-count result))
    (parachute:is = 0 (hash-table-count source))
    (multiple-value-bind (key value)
        (adapter-table-association result
                                   (lambda (candidate candidate-value)
                                     (and (equal candidate last-key)
                                          (eq candidate-value last-value))))
      (parachute:is eq last-key key)
      (parachute:is eq last-value value))
    (multiple-value-bind (value present)
        (sophie-lisp:dict-ref result (copy-seq "same-key"))
      (parachute:is eq last-value value)
      (parachute:true present)))
  (let* ((source (make-hash-table :test 'equal))
         (result (sophie-lisp:dict-collect source nil)))
    (parachute:true (hash-table-p result))
    (parachute:is eq 'eql (sophie-lisp:dict-test result))
    (parachute:is = 0 (hash-table-count result)))
  (let ((table (make-hash-table :test 'equal)))
    (dolist (bad-test '(nil not-a-standard-test))
      (parachute:fail
       (sophie-lisp:dict-collect table nil :test bad-test)
       type-error))
    (parachute:fail
     (sophie-lisp:dict-collect table nil :test #'identity)
     type-error)))

(parachute:define-test plist-dict-view.collect-refusal
  ;; The PLIST-004 default batch refusal needs the later batch API.
  (let* ((raw (list :key :value))
         (view (sophie-lisp:plist-dict-view raw)))
    (parachute:fail (sophie-lisp:dict-collect view nil) type-error)
    (parachute:is equal '(:key :value) raw)
    (parachute:is eq :value (sophie-lisp:dict-ref view :key))))

(defvar *batch-events* nil)
(defvar *batch-forbid-traversal* nil)

(defclass batch-readonly ()
  ((pairs :initarg :pairs :initform nil :reader batch-pairs)
   (test :initarg :test :initform 'eql :reader batch-test)
   (tag :initarg :tag :initform nil :reader batch-tag)))
(defclass batch-configurable (batch-readonly) ())
(defclass batch-child (batch-configurable) ())
(defclass batch-aux-only (batch-readonly) ())

(defmethod sl:dictp ((source batch-readonly)) t)
(defmethod sl:dict-test ((source batch-readonly)) (batch-test source))
(defmethod sl:dict-size ((source batch-readonly)) (length (batch-pairs source)))
(defmethod sl:dict-ref ((source batch-readonly) key &optional default)
  (let ((pair (assoc key (batch-pairs source) :test (batch-test source))))
    (if pair (values (cdr pair) t) (values default nil))))
(defmethod sl:seqablep ((source batch-readonly)) t)
(defmethod sl:seq-length ((source batch-readonly)) (length (batch-pairs source)))
(defmethod sl:seq-emptyp ((source batch-readonly))
  (when *batch-forbid-traversal* (error "Prototype was traversed"))
  (null (batch-pairs source)))
(defmethod sl:seq-first ((source batch-readonly))
  (when *batch-forbid-traversal* (error "Prototype was traversed"))
  (let ((pair (car (batch-pairs source))))
    (when pair (sl:map-entry (car pair) (cdr pair)))))
(defmethod sl:seq-rest ((source batch-readonly))
  (when *batch-forbid-traversal* (error "Prototype was traversed"))
  (mapcar (lambda (pair) (sl:map-entry (car pair) (cdr pair)))
          (cdr (batch-pairs source))))

(defun batch-model-collect (source entries test)
  ;; Independent finite association-list model, not a Sophie construction oracle.
  (let ((pairs nil))
    (loop until (sl:seq-emptyp entries) do
      (let ((entry (sl:seq-first entries)))
        (check-type entry sl:map-entry)
        (let ((key (sl:entry-key entry)) (value (sl:entry-value entry)))
          (setf pairs (remove key pairs :key #'car :test test))
          (push (cons key value) pairs)))
      (setf entries (sl:seq-rest entries)))
    (make-instance (class-of source) :pairs (nreverse pairs)
                   :test test :tag (batch-tag source))))

(defmethod sl:dict-collect ((source batch-configurable) entries &key (test 'eql))
  (push (list :primary source test) *batch-events*)
  (batch-model-collect source entries test))
(defmethod sl:dict-collect :before ((source batch-aux-only) entries &key (test 'eql))
  (declare (ignore source entries test))
  (push :before *batch-events*))
(defmethod sl:dict-collect :after ((source batch-aux-only) entries &key (test 'eql))
  (declare (ignore source entries test))
  (push :after *batch-events*))
(defmethod sl:dict-collect :around ((source batch-aux-only) entries &key (test 'eql))
  (declare (ignore source entries test))
  (push :around *batch-events*)
  (call-next-method))

(defun batch-check-one (result key value)
  (parachute:true (sl:dictp result))
  (parachute:is = 1 (sl:dict-size result))
  (let ((values (multiple-value-list (sl:dict-ref result key))))
    (parachute:is = 2 (length values))
    (parachute:is eq value (first values))
    (parachute:true (second values)))
  (let ((entry (sl:seq-first result)))
    (parachute:is eq key (sl:entry-key entry))
    (parachute:is eq value (sl:entry-value entry))
    (parachute:true (sl:seq-emptyp (sl:seq-rest result)))))


(parachute:define-test dict-collect.generic-function-contract
  (let* ((gf #'sl:dict-collect)
         (lambda-list (closer-mop:generic-function-lambda-list gf)))
    (parachute:true (typep gf 'generic-function))
    (parachute:is equal '("SOURCE" "ENTRIES" "&KEY" "TEST")
      (mapcar #'symbol-name lambda-list))
    (dolist (class '(sl:dict hash-table t))
      (let* ((method (find-method gf nil (list (find-class class) (find-class t))))
             (ll (closer-mop:method-lambda-list method))
             (key (second (member '&key ll))))
        (parachute:true method)
        (parachute:true (consp key))
        (parachute:is equal '(quote eql) (second key)))))
  (let* ((source (make-instance 'batch-child :test 'equal :tag :configuration))
         (result (sl:dict-collect source nil)))
    (parachute:is eq (class-of source) (class-of result))
    (parachute:is eq 'eql (sl:dict-test result))
    (parachute:is eq :configuration (batch-tag result)))
  (parachute:fail (sl:dict-collect :not-a-dict nil) type-error)
  (parachute:fail (sl:dict-collect (make-instance 'batch-readonly) nil) type-error))

(parachute:define-test dict-collect.entry-validation-and-laziness
  (dolist (prototype (list (sl:dict :prototype :ignored)
                          (let ((table (make-hash-table :test 'equal)))
                            (setf (gethash :prototype table) :ignored) table)))
    (let* ((first-key (copy-seq "duplicate")) (last-key (copy-seq "duplicate"))
           (first-value (list :first)) (last-value (list :last))
           (events nil))
      (labels ((entries (items)
                 (sl:lazy-seq
                  (progn (push (if items :entry :end) events)
                         (when items (sl:lazy-cons (car items) (entries (cdr items))))))))
        (let* ((input (list (sl:map-entry first-key first-value)
                            (sl:map-entry last-key last-value)))
               (result (sl:dict-collect prototype (entries input) :test 'equal)))
          (parachute:is equal '(:end :entry :entry) events)
          (batch-check-one result last-key last-value)
          (parachute:is = 1 (sl:dict-size prototype))
          (parachute:is eq :ignored (sl:dict-ref prototype :prototype))
          (parachute:is eq first-key (sl:entry-key (first input)))
          (parachute:is eq first-value (sl:entry-value (first input))))))
    (parachute:fail (sl:dict-collect prototype 123) type-error)
    (dolist (bad (list nil :atom (cons :k :v)))
      (let* ((tail-calls 0)
             (tail (sl:lazy-seq (progn (incf tail-calls)
                                              (error "Past invalid batch entry"))))
             (input (sl:lazy-cons (sl:map-entry :valid :value)
                                  (sl:lazy-cons bad tail))))
        (parachute:fail (sl:dict-collect prototype input) type-error)
        (parachute:is = 0 tail-calls)))
    (parachute:fail
     (sl:dict-collect prototype (cons (sl:map-entry :key :value) :dotted-tail))
     type-error)
    (let ((tag (gensym "BATCH-ESCAPE-")))
      (parachute:is eq :escaped
        (catch tag (sl:dict-collect prototype
                                  (sl:lazy-cons (sl:map-entry :key :value)
                                                (sl:lazy-seq (throw tag :escaped))))
                   :returned))))
  (batch-check-one (sl:dict-collect (sl:dict) (vector (sl:map-entry nil nil))) nil nil))

(parachute:define-test dict-collect.result-test-selection
  (let* ((key (copy-seq "resident")) (value (list :value))
         (entries (vector (sl:map-entry key value)))
         (prototype (sl:dict :old :old)))
    (dolist (ignored (list nil 'eq #'identity :not-a-test))
      (let ((result (sl:dict-collect prototype entries :test ignored)))
        (parachute:true (typep result 'sl:dict))
        (parachute:is eq #'sl:equals (sl:dict-test result))
        (batch-check-one result key value)))
    (dolist (test '(eq eql equal equalp))
      (dolist (designator (list test (symbol-function test)))
        (let* ((source (make-hash-table :test 'equalp))
               (result (sl:dict-collect source entries :test designator)))
          (parachute:true (hash-table-p result))
          (parachute:false (eq source result))
          (parachute:is eq test (sl:dict-test result))
          (parachute:is = 0 (hash-table-count source))
          (batch-check-one result key value))))
    (let* ((source (make-hash-table :test 'equal))
           (default (sl:dict-collect source nil)))
      (parachute:is eq 'eql (sl:dict-test default))
      (parachute:false (eq source default))
      (parachute:is = 0 (hash-table-count default)))
    (dolist (bad (list nil :bogus #'identity 'sl:equals #'sl:equals))
      (let ((calls 0))
        (parachute:fail
         (sl:dict-collect (make-hash-table)
                          (sl:lazy-seq (progn (incf calls) nil)) :test bad)
         type-error)
        (parachute:is = 0 calls))))
  ;; Numeric key equivalence follows the result test, not the prototype's test.
  (let ((entries (list (sl:map-entry 1 :integer) (sl:map-entry 1.0 :float))))
    (parachute:is = 1 (sl:dict-size (sl:dict-collect (sl:dict) entries :test 'eql)))
    (parachute:is = 2 (sl:dict-size (sl:dict-collect (make-hash-table :test 'equalp)
                                                  entries)))
    (parachute:is = 1 (sl:dict-size (sl:dict-collect (make-hash-table)
                                                  entries :test 'equalp)))))



(defun bridge-make (target &optional options)
  (apply #'sl:make-collector-for target options))

(defvar *bridge-batches* nil)


(defclass bridge-retry-key ()
  ((escape-p :initform t :accessor bridge-retry-escape-p)))

(defmethod sl:hash-code ((key bridge-retry-key))
  ;; Installed before any collection exists; every normal return is stable.
  ;; The first attempt escapes before this key can become resident.
  (when (bridge-retry-escape-p key)
    (setf (bridge-retry-escape-p key) nil)
    (throw 'bridge-retry :escaped))
  101)

(parachute:define-test make-collector-for.deferred-batch
  (let* ((collector (bridge-make (find-class 'sl:dict)))
         (key1 (copy-seq "key")) (key2 (copy-seq "key"))
         (value (list :last)) (result nil) (*bridge-batches* nil)
         (method nil))
    (unwind-protect
         (progn
           (setf method
                 (eval '(defmethod sl:dict-collect :around
                            ((source sl:dict) entries &key (test 'eql))
                          (push (list source entries :test test) *bridge-batches*)
                          (call-next-method))))
           (parachute:is eq collector
             (sl:collector-accumulate collector (sl:map-entry key1 :first)))
           (parachute:is eq collector
             (sl:collector-accumulate collector (sl:map-entry key2 value)))
           (parachute:false *bridge-batches*)
           (setf result (sl:collector-result collector))
           (parachute:is eq result (sl:collector-result collector))
           (parachute:is = 1 (length *bridge-batches*)))
      (when method (remove-method #'sl:dict-collect method)))
    (let* ((arguments (first *bridge-batches*)) (prototype (first arguments))
           (entries (second arguments)))
      (parachute:true (typep prototype 'sl:dict))
      (parachute:is = 0 (sl:dict-size prototype))
      (parachute:true (vectorp entries))
      (parachute:is = 2 (length entries))
      (parachute:is eq key1 (sl:entry-key (aref entries 0)))
      (parachute:is eq key2 (sl:entry-key (aref entries 1)))
      (parachute:is eq #'sl:equals (getf (cddr arguments) :test)))
    (parachute:true (typep result 'sl:dict))
    (parachute:is eq #'sl:equals (sl:dict-test result))
    (parachute:is = 1 (sl:dict-size result))
    (parachute:is eq value (sl:dict-ref result key1))
    (parachute:is eq key2 (sl:entry-key (sl:seq-first result)))
    ;; A failed batch is not a finalization: retry the entire retained sequence.
    (let* ((collector (sl:make-collector-for (find-class 'sl:dict)))
           (key (make-instance 'bridge-retry-key))
           (value (list :identity))
           (entries (vector (sl:map-entry :before :retained)
                            (sl:map-entry key value)
                            (sl:map-entry :after :also-retained)))
           (*bridge-batches* nil)
           (method nil))
      (unwind-protect
           (progn
             (setf method
                   (eval '(defmethod sl:dict-collect :around
                              ((source sl:dict) entries &key (test 'eql))
                            (push (list source entries :test test) *bridge-batches*)
                            (call-next-method))))
             (loop for entry across entries do
               (parachute:is eq collector (sl:collector-accumulate collector entry)))
             (parachute:false *bridge-batches*)
             (parachute:true (bridge-retry-escape-p key))
             (parachute:is eq :escaped
               (catch 'bridge-retry (sl:collector-result collector)))
             (parachute:false (bridge-retry-escape-p key))
             (parachute:is = 1 (length *bridge-batches*))
             (let ((result (sl:collector-result collector)))
               (parachute:is = 2 (length *bridge-batches*))
               (parachute:is = 3 (sl:dict-size result))
               (parachute:is eq :retained (sl:dict-ref result :before))
               (parachute:is eq value (sl:dict-ref result key))
               (parachute:is eq :also-retained (sl:dict-ref result :after))
               (parachute:is eq result (sl:collector-result collector))
               (parachute:is eq result (sl:collector-result collector))
               (parachute:is = 2 (length *bridge-batches*)))
             (dolist (arguments *bridge-batches*)
               (let ((batch (second arguments)))
                 (parachute:true (vectorp batch))
                 (parachute:is = 3 (length batch))
                 (loop for entry across entries for i from 0 do
                   (parachute:is eq entry (aref batch i))))))
        (when method (remove-method #'sl:dict-collect method))))))

(parachute:define-test make-collector-for.target-validation
  (dolist (target (list (find-class 'sl:dict) (sl:dict :ignored :old)))
    (let ((collector (sl:make-collector-for target)))
      (sl:collector-accumulate collector (sl:map-entry :before :retained))
      (dolist (bad (list nil :atom '(:key . :value) '(:key :value) #(:key :value)))
        (parachute:fail (sl:collector-accumulate collector bad) type-error))
      (parachute:is eq collector
        (sl:collector-accumulate collector (sl:map-entry nil nil)))
      (let ((result (sl:collector-result collector)))
        (parachute:is = 2 (sl:dict-size result))
        (parachute:is eq :retained (sl:dict-ref result :before))
        (parachute:true (nth-value 1 (sl:dict-ref result nil)))
        (parachute:false (nth-value 1 (sl:dict-ref result :ignored))))))
  (dolist (target (list (find-class 'sl:hash-set) (sl:hash-set :ignored)))
    (let ((collector (sl:make-collector-for target)))
      (dolist (element (list nil 1 1.0 '(a . b) (sl:map-entry :k :v)))
        (parachute:is eq collector (sl:collector-accumulate collector element)))
      (let ((result (sl:collector-result collector)))
        (parachute:true (sl:hash-set-p result))
        (parachute:is = 4 (sl:seq-length result))
        (parachute:false (sl:dictp result))
        (parachute:is eq result (sl:collector-result collector)))))
  (let* ((backing (list :key :value)) (view (sl:plist-dict-view backing)))
    (parachute:fail (sl:make-collector-for view) type-error)
    (parachute:is equal '(:key :value) backing)))

(parachute:define-test make-collector-for.options-validation
  (dolist (target (list (find-class 'sl:dict) (sl:dict)
                        (find-class 'sl:hash-set) (sl:hash-set)))
    (dolist (options (list '(:test eql) '(:unknown t) '(:test)))
      (parachute:fail (bridge-make target options) program-error))
    (parachute:fail (sl:make-collector-for target :test 'eql) program-error)))

(parachute:define-test make-collector-for.reconstruction
  ;; S-COLLECT-* fixtures are defined in tests/core/collectors.lisp, loaded first.
  ;; Later accumulation uses new reconstruction state. Accumulation after
  ;; finalization of the SAME state is undefined (Chapter 4.1.6).
  (dolist (name '(sl:dict sl:hash-set))
    ;; No public API resolves target symbols to class objects.
    (let* ((target (sophie-lisp.internal::resolve-target-designator name))
           (collector (bridge-make target))
           (element (if (eq name 'sl:dict) (sl:map-entry :key :value) :value)))
      (parachute:is eq (find-class name) target)
      (sl:collector-accumulate collector element)
      (let* ((result (sl:collector-result collector))
             (later (sl:make-collector-for result)))
        (sl:collector-accumulate later
          (if (eq name 'sl:dict) (sl:map-entry :new :new) :new))
        (parachute:is = 1 (sl:seq-length (sl:collector-result later)))
        (parachute:is eq result (sl:collector-result collector))
        (parachute:is = 1 (sl:seq-length result))
        (parachute:true (typep result name))
        (when (eq name 'sl:dict)
          (parachute:is eq :value (sl:dict-ref result :key))
          (parachute:false (nth-value 1 (sl:dict-ref result :new)))))))
  (parachute:fail
   (sl:make-collector-for (gensym "UNREGISTERED-"))
   type-error)
  ;; The bridge must not change ordinary EQL/inherited-primary precedence,
  ;; options, or CALL-NEXT-METHOD. Fixtures come from the S-COLLECT dependency.
  (let* ((source (make-instance 's-collect-child :metadata :config :items '(:old)))
         (events nil))
    (s-collect-with-methods
        (list `(defmethod sl:make-collector-for ((target (eql ',source)) &key observer)
                 (when observer (funcall observer :eql target))
                 (call-next-method)))
      (let* ((collector (bridge-make source (list :observer
                                               (lambda (kind target)
                                                 (parachute:is eq source target)
                                                 (push kind events)))))
             (ignored (sl:collector-accumulate collector :new))
             (result (sl:collector-result collector)))
        (declare (ignore ignored))
        (parachute:is equal '(:base :eql) events)
        (parachute:is eq (class-of source) (class-of result))
        (parachute:is eq :config (s-collect-metadata result))
        (parachute:is equal '(:new) (s-collect-source-items result))
        (parachute:is equal '(:old) (s-collect-source-items source))))))
  ;; Dual-role class-object cases and qualifier-only exclusion additionally
  ;; remain mandatory F-HOST-001/002 and S-COLLECT-001 cross-owner cases.

(defun cv-relation (expected a b)
  (parachute:is eq expected (not (null (sl:equals a b))))
  (parachute:is eq expected (not (null (sl:equals b a))))
  (parachute:is eq (if expected :equal :unequal) (sl:compare a b))
  (parachute:is eq (if expected :equal :unequal) (sl:compare b a)))

(defun cv-hash-pair (a b)
  (let ((ha (sl:hash-code a)) (hb (sl:hash-code b)))
    ;; The approved implementation choice is unsigned 64 bits. No particular
    ;; mixing output, collision freedom, or interprocess stability is assumed.
    (parachute:true (typep ha '(unsigned-byte 64)))
    (parachute:true (typep hb '(unsigned-byte 64)))
    (parachute:is = ha hb)))

(defclass cv-value () ((id :initarg :id :reader cv-id)))
(defclass cv-inherited-value (cv-value) ())
(defvar *cv-hash-visits* nil)
(defvar *cv-equality-visits* 0)
(defmethod sl:equals ((a cv-value) (b cv-value))
  (incf *cv-equality-visits*)
  (= (cv-id a) (cv-id b)))
(defmethod sl:hash-code ((object cv-value))
  (push object *cv-hash-visits*)
  ;; Deliberate full-hash collisions, including unequal objects.
  17)
(defmethod sl:compare ((a cv-value) (b cv-value))
  (if (= (cv-id a) (cv-id b)) :equal :unequal))
(defun cv-value (id)
  (make-instance 'cv-inherited-value :id id))

(defclass cv-set-subclass (sl:hash-set) ())
(defclass cv-set-inherited (cv-set-subclass) ())
(defvar *cv-set-hashes* 0)
(defvar *cv-set-equalities* 0)
(defvar *cv-set-comparisons* 0)
(defmethod sl:hash-code :around ((object cv-set-subclass))
  (incf *cv-set-hashes*)
  (call-next-method))
(defmethod sl:equals :around ((a cv-set-subclass) (b sl:hash-set))
  (incf *cv-set-equalities*)
  (call-next-method))
(defmethod sl:compare :around ((a cv-set-subclass) (b sl:hash-set))
  (incf *cv-set-comparisons*)
  (call-next-method))

(defclass cv-oriented-value ()
  ((side :initarg :side :reader cv-oriented-side)
   (id :initarg :id :reader cv-oriented-id)))

(defvar *cv-oriented-calls* nil)

(defmethod sl:equals ((left cv-oriented-value) (right cv-oriented-value))
  (push (list (cv-oriented-side left) (cv-oriented-side right)) *cv-oriented-calls*)
  (= (cv-oriented-id left) (cv-oriented-id right)))

(defun cv-canonical-fixtures ()
  ;; All indicators are fresh: A and B are EQ-distinct but EQUALS. Thus
  ;; [(a,1),(b,2)] matches [(d,2),(c,1)], NOT [(c,1),(d,1)].
  (let ((a (copy-seq "key")) (b (copy-seq "key"))
        (c (copy-seq "key")) (d (copy-seq "key")))
    (list (sl:plist-dict-view (list a 1 b 2 a :hidden b :hidden))
          (sl:plist-dict-view (list d 2 c 1 c :also-hidden))
          (sl:plist-dict-view (list c 1 d 1))
          (sl:plist-dict-view (list c 1)))))

(parachute:define-test container-values.trie-equality-regressions
  (let ((left (sl:dict :a (sl:dict :x 1 :y (sl:hash-set 2 3))
                       :b (sl:dict :z 4)))
        (right (sl:dict :b (sl:dict :z 4d0)
                        :a (sl:dict :y (sl:hash-set 3d0 2d0) :x 1d0))))
    (parachute:true (sl:equals left right))
    (parachute:false (sl:equals left
                                (sl:dict :a (sl:dict :x 1 :y (sl:hash-set 2 3))
                                         :b (sl:dict :z 5)))))
  (let* ((a (cv-value 1))
         (b (cv-value 2))
         (small-dict (sl:dict a :value))
         (large-dict (sl:dict a :value b :other))
         (small-set (sl:hash-set a))
         (large-set (sl:hash-set a b))
         (*cv-equality-visits* 0))
    (parachute:false (sl:equals small-dict large-dict))
    (parachute:false (sl:equals small-set large-set))
    (parachute:is = 0 *cv-equality-visits*))
  (let ((left (sl:dict :a (make-instance 'cv-oriented-value :side :left :id 1)))
        (right (sl:dict :a (make-instance 'cv-oriented-value :side :right :id 1)))
        (*cv-oriented-calls* nil))
    (parachute:true (sl:equals left right))
    (parachute:is equal '((:left :right)) *cv-oriented-calls*))
  (let ((left (sl:hash-set (cv-value 1) (cv-value 2)))
        (right (sl:hash-set (cv-value 2) (cv-value 1)))
        (other (sl:hash-set (cv-value 1) (cv-value 3))))
    (parachute:true (sl:equals left right))
    (parachute:false (sl:equals left other))))

(parachute:define-test container-values.dict-equality-probe
  ;; Above +EQUALITY-PROBE-THRESHOLD+ selects the trie-probing equality path.
  (let* ((count (* 2 sophie-lisp.internal::+equality-probe-threshold+))
         (last (1- count))
         (left (sl:dict)) (right (sl:dict)))
    (dotimes (key count)
      (setf left (sl:dict-set left key key)))
    (loop for key downfrom last to 0 do
      (setf right (sl:dict-set right key key)))
    (parachute:true (> count sophie-lisp.internal::+equality-probe-threshold+))
    (parachute:is = count (sl:dict-size left))
    (parachute:is = count (sl:dict-size right))
    (cv-relation t left right)
    (cv-relation nil left (sl:dict-set (sl:dict-without right last) count count))
    (cv-relation nil left (sl:dict-set right last :different))
    (let ((nested-left (sl:dict-set left last (sl:dict :inner (sl:dict :x 1 :y 2))))
          (nested-right (sl:dict-set right last (sl:dict :inner (sl:dict :y 2 :x 1)))))
      (cv-relation t nested-left nested-right)
      (cv-relation nil nested-left
                   (sl:dict-set nested-right last
                                (sl:dict :inner (sl:dict :x 1 :y 3)))))))

(parachute:define-test container-values.set-equality-probe
  (let* ((count (* 2 sophie-lisp.internal::+equality-probe-threshold+))
         (last (1- count))
         (left (sl:hash-set)) (right (sl:hash-set)))
    (dotimes (element count)
      (setf left (sl:set-add element left)))
    (loop for element downfrom last to 0 do
      (setf right (sl:set-add element right)))
    (parachute:true (> count sophie-lisp.internal::+equality-probe-threshold+))
    (parachute:is = count (sl:set-size left))
    (parachute:is = count (sl:set-size right))
    (cv-relation t left right)
    (cv-relation nil left (sl:set-add count (sl:set-remove last right)))))

(parachute:define-test container-values.equality
  ;; 17 relation checks * 4, plus three canonical-count assertions.
  (cv-relation t (sl:dict) (sl:dict))
  (cv-relation t (sl:hash-set) (sl:hash-set))
  (cv-relation t (sl:plist-dict-view nil) (sl:plist-dict-view nil))
  (cv-relation t (sl:dict :a 1 :b #(2 3))
                 (sl:dict :b #(2.0 3d0) :a 1d0))
  (cv-relation t (sl:hash-set 1 "ab" nil)
                 (sl:hash-set (sl:lazy-seq nil) #(#\a #\b) 1d0 1))
  (destructuring-bind (a b wrong short) (cv-canonical-fixtures)
    (parachute:is = 2 (sl:dict-size a))
    (parachute:is = 2 (sl:dict-size b))
    (parachute:is = 2 (sl:dict-size wrong))
    (cv-relation t a a)
    (cv-relation t a b)
    (cv-relation nil a wrong)
    (cv-relation nil a short))
  ;; Same keys and same value multiset do not suffice: association matters.
  (cv-relation nil (sl:plist-dict-view '(:a 1 :b 2))
                   (sl:plist-dict-view '(:b 1 :a 2)))
  (cv-relation t (sl:plist-dict-view '(:a nil :a :ignored))
                 (sl:plist-dict-view (list :a (sl:lazy-seq nil))))
  ;; Two identical canonical pairs are two associations, not a deduped one.
  (let* ((a (copy-seq "k")) (b (copy-seq "k"))
         (c (copy-seq "k")) (d (copy-seq "k"))
         (two (sl:plist-dict-view (list a 1 b 1)))
         (other (sl:plist-dict-view (list d 1d0 c 1.0)))
         (one (sl:plist-dict-view (list c 1 c 1))))
    (cv-relation t two other)
    (cv-relation nil two one))
  ;; First-EQ wins, even if a hidden component would escape when traversed.
  (let* ((hidden (sl:lazy-seq (error "Hidden duplicate was traversed")))
         (view (sl:plist-dict-view (list :a 1 :a hidden))))
    (cv-relation t view (sl:plist-dict-view '(:a 1))))
  (cv-relation nil (sl:dict :a 1) (sl:dict :a 1 :b 2))
  (cv-relation nil (sl:hash-set 1) (sl:hash-set 1 2))
  (cv-relation nil (sl:hash-set 1 2) (sl:hash-set 1 3)))

(parachute:define-test container-values.nested-equality
  (cv-relation nil (sl:dict :a 1 :b 2) (sl:dict :a 2 :b 1))
  (cv-relation nil (sl:dict :a 1) (sl:dict :b 1))
  ;; COMPARE of unordered containers uses EQUALS, not recursively coarser
  ;; component COMPARE (distinct symbols can have identical names).
  (let ((a (make-symbol "SAME")) (b (make-symbol "SAME")))
    (cv-relation nil (sl:dict :key a) (sl:dict :key b))
    (cv-relation nil (sl:hash-set a) (sl:hash-set b))
    (cv-relation nil (sl:plist-dict-view (list :key a))
                     (sl:plist-dict-view (list :key b))))
  ;; Numeric equality is CL mathematical equality, including zero-imaginary
  ;; complex values; this does not order unequal unordered containers.
  (cv-relation t (sl:dict 1 #c(2.0 0.0)) (sl:dict 1d0 2))
  (cv-relation nil (sl:dict :x #c(1.0 0.0)) (sl:dict :x 2))
  ;; Every representation can itself be a resident key and a resident element.
  ;; Only primitives in this unit's dependency closure are used: no SET-SIZE,
  ;; SET-MEMBER, traversal, or future conversion dependency is smuggled in.
  (dolist (pair (list (list (sl:dict :a 1 :b 2) (sl:dict :b 2d0 :a 1.0))
                     (list (sl:hash-set 1 2) (sl:hash-set 2d0 1.0))
                     (subseq (cv-canonical-fixtures) 0 2)))
    (destructuring-bind (a b) pair
      (let ((outer (sl:dict a :first b nil)))
        (parachute:is = 1 (sl:dict-size outer))
        (parachute:is equal '(nil t) (multiple-value-list (sl:dict-ref outer a)))
        (parachute:is equal '(nil t) (multiple-value-list (sl:dict-ref outer b)))
        (cv-relation t (sl:hash-set a b) (sl:hash-set b))
        (cv-relation t (sl:dict :nested a) (sl:dict :nested b))
        (cv-hash-pair (sl:dict :nested a) (sl:dict :nested b))
        ;; Resident composite keys traverse container values through Chapter 7.
        (dolist (wrap (list (lambda (x) (list x))
                           (lambda (x) (vector x))
                           (lambda (x) (sl:map-entry :key x))))
          (let ((left (funcall wrap a)) (right (funcall wrap b)))
            (parachute:is equal '(:found t)
              (multiple-value-list (sl:dict-ref (sl:dict left :found) right)))
            (cv-relation t (sl:hash-set left right) (sl:hash-set right)))))))
  ;; Deep heterogeneous nesting, not merely a container at the top level.
  (let ((a (sl:dict (sl:hash-set (sl:plist-dict-view '(:x 1)))
                    (sl:hash-set (sl:dict :z #(1 2)))))
        (b (sl:dict (sl:hash-set (sl:plist-dict-view '(:x 1d0 :x :ignored)))
                    (sl:hash-set (sl:dict :z #(1d0 2.0))))))
    (cv-relation t a b)
    (cv-hash-pair a b)
    (parachute:is equal '(:deep t)
      (multiple-value-list (sl:dict-ref (sl:dict a :deep) b))))
  ;; 28 + 3*(3+4+4+3+3*5) + 8 = 123; extra cardinality matrix: 3*7.
  (dolist (pair (list (list (sl:dict) (sl:dict nil nil))
                     (list (sl:hash-set) (sl:hash-set nil))
                     (list (sl:plist-dict-view nil)
                           (sl:plist-dict-view '(nil nil)))))
    (cv-relation nil (first pair) (second pair))
    (cv-hash-pair (first pair) (first pair))))

(defclass cv-escaping-hash () ())

(defvar *cv-hash-exit* nil)

(defvar *cv-escape-visits* 0)

(defmethod sl:hash-code ((object cv-escaping-hash))
  (declare (ignore object))
  (incf *cv-escape-visits*)
  (ecase *cv-hash-exit*
    (:throw (throw 'cv-hash-escape :escaped))
    (:error (error 'simple-error :format-control "Component hash escape"))))

(defun cv-depth-chain (leaf edges)
  ;; Each dictionary value and each vector cell is ONE structural edge.
  ;; No chain component becomes a resident key or set element.
  (dotimes (i edges leaf)
    (setf leaf (if (evenp i) (sl:dict :child leaf) (vector leaf)))))

(defun cv-hash-depth-regressions ()
  ;; Closing this DICT -> vector -> same DICT cycle mutates only a value,
  ;; never a resident key/element or a dict slot. Each lap crosses late methods.
  (let* ((back-edge (vector nil)) (dict (sl:dict :cycle back-edge)))
    (setf (aref back-edge 0) dict)
    (cv-hash-pair dict dict))
  ;; Approved 16-edge budget: truncate BEFORE public dispatch at depth zero.
  ;; The 15-edge control proves the observer works; 16/17/20 cover the boundary
  ;; and beyond. No particular mixing output or unequal hash is assumed.
  (dolist (edges '(15 16 17 20))
    (let* ((observer (cv-value 100))
           (object (cv-depth-chain observer edges))
           (*cv-hash-visits* nil))
      (parachute:true (typep (sl:hash-code object) '(unsigned-byte 64)))
      (parachute:is eq (< edges 16)
        (not (null (member observer *cv-hash-visits* :test #'eq))))
      (cv-hash-pair object (cv-depth-chain (cv-value 100) edges)))
    ;; NIL/empty-lazy normalization through and beyond the same boundary.
    (cv-hash-pair (cv-depth-chain nil edges)
                  (cv-depth-chain (sl:lazy-seq nil) edges)))
  ;; Catch OUTSIDE the complete hash after a component exits across multiple
  ;; container/array boundaries. An independent 15-edge graph must subsequently
  ;; reach its observer with a fresh budget. No private depth-state oracle.
  (dolist (exit '(:throw :error))
    (let* ((*cv-hash-exit* exit)
           (*cv-escape-visits* 0)
           (escaping (cv-depth-chain (make-instance 'cv-escaping-hash) 9))
           (observer (cv-value 101))
           (independent (cv-depth-chain observer 15))
           (expected (sl:hash-code independent)))
      (parachute:is eq :escaped
        (ecase exit
          (:throw (catch 'cv-hash-escape
                    (sl:hash-code escaping)
                    :unexpected-return))
          (:error (handler-case
                      (progn (sl:hash-code escaping) :unexpected-return)
                    (simple-error () :escaped)))))
      (parachute:is = 1 *cv-escape-visits*)
      (let* ((*cv-hash-visits* nil)
             (hash (sl:hash-code independent)))
        (parachute:true (typep hash '(unsigned-byte 64)))
        (parachute:is = expected hash)
        (parachute:true (member observer *cv-hash-visits* :test #'eq))))))

(parachute:define-test container-values.hashing
  (destructuring-bind (a b wrong short) (cv-canonical-fixtures)
    (declare (ignore wrong short))
    (cv-hash-pair a b))
  ;; Reverse insertion in a full-hash collision bucket guarantees genuinely
  ;; different resident order, not just different constructor argument order.
  (let* ((keys (loop for i below 80 collect (cv-value i)))
         (aliases (loop for i below 80 collect (cv-value i)))
         (a (sl:dict)) (b (sl:dict)))
    (loop for k in keys for i from 0 do (setf a (sl:dict-set a k i)))
    (loop for k in (reverse aliases) for i downfrom 79 do
      (setf b (sl:dict-set b k i)))
    (cv-relation t a b)
    (cv-hash-pair a b)
    (cv-hash-pair (apply #'sl:hash-set keys)
                  (apply #'sl:hash-set (reverse aliases)))
    (cv-hash-pair
     (sl:plist-dict-view (loop for k in keys for i from 0 append (list k i)))
     (sl:plist-dict-view
      (loop for k in (reverse aliases) for i downfrom 79 append (list k i)))))
  ;; Do not require different hashes for unequal values: collisions are legal.
  ;; Instead observe user HASH-CODE on every canonical EQ-distinct key and
  ;; value. This checks multiplicity and the approved all-unordered-entries
  ;; traversal policy without prescribing the mixing formula.
  (let* ((a (cv-value 1)) (b (cv-value 1))
         (v (cv-value 2)) (w (cv-value 2)) (hidden (cv-value 99))
         (view (sl:plist-dict-view (list a v b w a hidden b hidden))))
    (let ((*cv-hash-visits* nil))
      (parachute:true (typep (sl:hash-code view) '(unsigned-byte 64)))
      (dolist (object (list a b v w))
        (parachute:true (member object *cv-hash-visits* :test #'eq)))
      (parachute:false (member hidden *cv-hash-visits* :test #'eq))))
  ;; Every finite cycle is finished BEFORE it becomes a resident element/key.
  ;; Never compare these cycles for equality or wait for permitted comparison
  ;; nontermination. Bounded hashing is required; the process deadline is only
  ;; a failure guard, not an oracle for EQUALS/COMPARE.
  (let ((cons-cycle (list :cycle)) (array-cycle (vector nil)))
    (setf (cdr cons-cycle) cons-cycle (aref array-cycle 0) array-cycle)
    (dolist (cycle (list cons-cycle array-cycle))
      (dolist (object (list (sl:dict :cycle cycle)
                            (sl:dict cycle :value)
                            (sl:hash-set cycle)
                            (sl:plist-dict-view (list :cycle cycle))
                            (sl:plist-dict-view (list cycle :value))))
        (cv-hash-pair object object))))
  ;; Shared versus duplicated acyclic graphs must hash alike at varying
  ;; depth. Include NIL/empty-lazy normalization at truncation boundaries.
  (dotimes (depth 6)
    (let ((a nil) (b (sl:lazy-seq nil)))
      (dotimes (i depth)
        (setf a (sl:dict :child (sl:hash-set a))
              b (sl:dict :child (sl:hash-set b))))
      (cv-hash-pair (sl:dict :a a :b a)
                    (sl:dict :b b :a b))))
  (let ((shared (sl:dict :a #(1 2))))
    (cv-hash-pair (sl:dict :x shared :y shared)
                  (sl:dict :y (sl:dict :a #(1d0 2d0))
                           :x (sl:dict :a #(1.0 2.0)))))
  ;; Original 3 + 13 + 6 + 30 + 18 + 3 + 20 = 93, all retained.
  (dotimes (i 5)
    (let ((a (sl:dict :left i :right (+ i 1)))
          (b (sl:dict :right (+ i 1) :left i)))
      (cv-relation t a b)))
  ;; W1: cycle 3 + four depths * 8 + two exceptional exits * 5 = 45.
  (cv-hash-depth-regressions))

(parachute:define-test container-values.cross-representation
  ;; Two 6-representation pairwise matrices: 2 * 15 * 4 = 120.
  (dolist (objects
           (list (list (sl:dict) (sl:hash-set) (sl:plist-dict-view nil)
                       (make-hash-table) nil #())
                 (let ((table (make-hash-table)))
                   (setf (gethash :a table) 1)
                   (list (sl:dict :a 1) (sl:hash-set (sl:map-entry :a 1))
                         (sl:plist-dict-view '(:a 1)) table
                         (list (sl:map-entry :a 1)) (vector (sl:map-entry :a 1))))))
    (loop for tail on objects do
      (dolist (other (cdr tail)) (cv-relation nil (car tail) other))))
  ;; Methods were installed before residency. Three makers * 15 = 45.
  (let ((a (cv-value 4)) (b (cv-value 4)) (c (cv-value 5)))
    (dolist (maker (list (lambda (x) (sl:dict x x))
                        (lambda (x) (sl:hash-set x))
                        (lambda (x) (sl:plist-dict-view (list x x)))))
      (let ((left (funcall maker a)) (right (funcall maker b))
            (wrong (funcall maker c)))
        (let ((*cv-equality-visits* 0))
          (cv-relation t left right)
          (cv-relation nil left wrong)
          (parachute:true (plusp *cv-equality-visits*)))
        (let ((*cv-hash-visits* nil))
          (cv-hash-pair left right)
          (parachute:true (member a *cv-hash-visits* :test #'eq))
          (parachute:true (member b *cv-hash-visits* :test #'eq)))
        (parachute:is equal '(:hit t)
          (multiple-value-list (sl:dict-ref (sl:dict left :hit) right))))))
  ;; CL CHANGE-CLASS preserves inherited container slots, on fresh nonresident
  ;; sets only. No private slot/initarg or MAKE-INSTANCE contract is assumed.
  ;; Observing methods CALL-NEXT-METHOD and preserve set value semantics.
  ;; 10 + 6*8 + 5 = 63 subclass assertions.
  (let ((a (change-class (sl:hash-set 1 2) 'cv-set-inherited))
        (b (change-class (sl:hash-set 2d0 1d0) 'cv-set-inherited))
        (plain (sl:hash-set 2 1)))
    (let ((*cv-set-equalities* 0) (*cv-set-comparisons* 0))
      (cv-relation t a b)
      (cv-relation t a plain)
      (parachute:true (plusp *cv-set-equalities*))
      (parachute:true (plusp *cv-set-comparisons*)))
    (dolist (wrap (list #'identity
                       (lambda (x) (sl:dict :x x))
                       (lambda (x) (sl:hash-set x))
                       (lambda (x) (sl:plist-dict-view (list :x x)))
                       (lambda (x) (vector x))
                       (lambda (x) (sl:map-entry :x x))))
      (let ((left (funcall wrap a)) (right (funcall wrap b)))
        (let ((*cv-set-hashes* 0))
          (cv-hash-pair left right)
          (parachute:true (plusp *cv-set-hashes*)))
        (cv-relation t left right)))
    (parachute:is equal '(:subclass t)
      (multiple-value-list (sl:dict-ref (sl:dict a :subclass) b)))
    (cv-relation t (sl:hash-set a b) (sl:hash-set plain))))
;;;; Independent X-REF acceptance: Chapters 8, 4, and 9.
;;;; No standardized method is replaced and no future syntax unit is required.
(in-package #:sophie-lisp.tests)

(defvar *xref-calls* nil)
(defvar *xref-condition* nil)
(define-condition xref-sentinel (error) ())

(defun xref-observe (route default supplied-p)
  (push (list route default supplied-p) *xref-calls*)
  (when *xref-condition* (error *xref-condition*)))

(defun xref-values (actual value present-p)
  (parachute:is = 2 (length actual))
  (parachute:is eql value (first actual))
  (parachute:is eq present-p (not (null (second actual)))))

;; Entirely private keyed storage; not a seq or dict participant. Thus a direct
;; method is the only legal access route, including for inherited instances.
(defclass xref-direct ()
  ((table :initform (make-hash-table :test #'eql) :reader xref-table)))
(defclass xref-direct-child (xref-direct) ())
(defmethod sl:ref ((object xref-direct) key &optional (default nil supplied-p))
  (xref-observe :direct-read default supplied-p)
  (gethash key (xref-table object) default))
(defmethod (setf sl:ref) (value (object xref-direct) key &optional default)
  (declare (ignore default))
  (xref-observe :direct-write nil nil)
  (setf (gethash key (xref-table object)) value)
  (values value))

;; Full sequence participant, with real primitives and inherited fallback.
(defclass xref-sequence ()
  ((items :initarg :items :initform nil :accessor xref-items)))
(defclass xref-indexed (xref-sequence) ())
(defclass xref-writable (xref-indexed) ())
(defclass xref-sequence-direct (xref-writable) ())
(defmethod sl:seqablep ((object xref-sequence)) t)
(defmethod sl:seq-emptyp ((object xref-sequence)) (null (xref-items object)))
(defmethod sl:seq-first ((object xref-sequence)) (first (xref-items object)))
(defmethod sl:seq-rest ((object xref-sequence)) (rest (xref-items object)))
(defmethod sl:seq-ref ((object xref-indexed) index &optional (default nil supplied-p))
  (xref-observe :seq-read default supplied-p)
  (if supplied-p
      (sl:seq-ref (xref-items object) index default)
      (sl:seq-ref (xref-items object) index)))
(defmethod (setf sl:seq-ref) (value (object xref-writable) index &optional default)
  (declare (ignore default))
  (xref-observe :seq-write nil nil)
  (setf (sl:seq-ref (xref-items object) index) value))
(defmethod sl:ref ((object xref-sequence-direct) key &optional (default nil supplied-p))
  (push :direct *xref-calls*)
  (if supplied-p (sl:seq-ref object key default) (sl:seq-ref object key)))
(defmethod (setf sl:ref) (value (object xref-sequence-direct) key &optional default)
  (declare (ignore default))
  (push :direct *xref-calls*)
  (setf (sl:seq-ref object key) value))

;; Full dict participant. Its integer keys intentionally differ from positional
;; entries. No optional writer on the base class: refusal must be PROGRAM-ERROR.
(defclass xref-dictionary ()
  ((table :initform (make-hash-table :test #'eql) :reader xref-table)))
(defclass xref-mutable-dictionary (xref-dictionary) ())
(defmethod sl:dictp ((object xref-dictionary)) t)
(defmethod sl:dict-test ((object xref-dictionary)) 'eql)
(defmethod sl:dict-size ((object xref-dictionary)) (hash-table-count (xref-table object)))
(defmethod sl:dict-ref ((object xref-dictionary) key &optional (default nil supplied-p))
  (xref-observe :dict-read default supplied-p)
  (gethash key (xref-table object) default))
(defmethod sl:seqablep ((object xref-dictionary)) t)
(defmethod sl:seq-length ((object xref-dictionary)) (sl:dict-size object))
(defmethod sl:seq-emptyp ((object xref-dictionary)) (zerop (sl:dict-size object)))
(defun xref-entries (object)
  (loop for key being the hash-keys of (xref-table object) using (hash-value value)
        collect (sl:map-entry key value)))
(defmethod sl:seq-first ((object xref-dictionary)) (first (xref-entries object)))
(defmethod sl:seq-rest ((object xref-dictionary)) (rest (xref-entries object)))
(defmethod (setf sl:dict-ref) (value (object xref-mutable-dictionary) key &optional default)
  (declare (ignore default))
  (xref-observe :dict-write nil nil)
  (setf (gethash key (xref-table object)) value)
  (values value))

;; A host-traversable wrapper deliberately does NOT claim seq participation.
;; Defining partial Sophie protocol methods would be a nonconforming fixture.
(defclass xref-traversable () ((items :initform '(a b) :reader xref-items)))

(parachute:define-test ref.direct-dispatch
  (parachute:true (typep (fdefinition 'sl:ref) 'generic-function))
  (parachute:true (typep (fdefinition '(setf sl:ref)) 'generic-function))
  (dolist (class '(xref-direct xref-direct-child))
    (let ((object (make-instance class)) (*xref-calls* nil))
      (parachute:false (sl:dictp object))
      (parachute:false (sl:seqablep object))
      (parachute:is equal '(:new) (multiple-value-list (setf (sl:ref object 0) :new)))
      (xref-values (multiple-value-list (sl:ref object 0)) :new t)
      (parachute:is equal '((:direct-read nil nil) (:direct-write nil nil)) *xref-calls*)))
  (let ((object (make-instance 'xref-sequence-direct :items (list nil)))
        (*xref-calls* nil))
    (xref-values (multiple-value-list (sl:ref object 0 nil)) nil t)
    (parachute:is equal '((:seq-read nil t) :direct) *xref-calls*)
    (setf *xref-calls* nil)
    (parachute:is equal '(:new) (multiple-value-list (setf (sl:ref object 0 nil) :new)))
    (parachute:is equal '((:seq-write nil nil) :direct) *xref-calls*)
    (parachute:is equal '(:new) (xref-items object))))

(parachute:define-test ref.argument-evaluation-order-and-notinline-dispatch
  (let ((counts (list 0 0 0)))
    (flet ((object () (incf (first counts)) (vector :a :b))
           (index () (incf (second counts)) -1)
           (default () (incf (third counts)) :missing))
      (parachute:is equal '(:b t)
                    (multiple-value-list (sl:ref (object) (index) (default))))
      (parachute:is equal '(1 1 1) counts)))
  (let ((table (make-hash-table)))
    (parachute:is equal '(:missing nil)
                  (multiple-value-list (sl:ref table :absent :missing))))
  (let ((object (make-instance 'xref-direct)))
    (parachute:is equal '(:default nil)
                  (multiple-value-list (sl:ref object 0 :default))))
  ;; NOTINLINE still calls the generic function.
  (let ((table (make-hash-table)))
    (locally (declare (notinline sl:ref))
      (parachute:is equal '(nil nil)
                    (multiple-value-list (sl:ref table :absent))))))

(parachute:define-test ref.dictionary-lookup
  (let ((table (make-hash-table)) (custom (make-instance 'xref-dictionary))
        (direct (make-instance 'xref-direct)) (default (list :default)))
    (setf (gethash 0 table) nil (gethash 0 (xref-table custom)) nil
          (gethash 0 (xref-table direct)) nil)
    (dolist (object (list table custom direct (sl:dict 0 nil)
                          (sl:plist-dict-view (list 0 nil))))
      (xref-values (multiple-value-list (sl:ref object 0)) nil t)
      (xref-values (multiple-value-list (sl:ref object 1)) nil nil)
      (xref-values (multiple-value-list (sl:ref object 1 nil)) nil nil)
      (xref-values (multiple-value-list (sl:ref object 1 default)) default nil))
    ;; A dictionary is also seqable, but integer zero denotes its KEY, not an entry.
    (parachute:true (sl:seqablep custom))
    (parachute:true (typep (sl:seq-ref custom 0) 'sl:map-entry))))

(parachute:define-test ref.sequence-indexing
  (dolist (object (list nil (list nil :b) (vector nil :b) (copy-seq "ab")
                        (sl:lazy-cons nil (sl:lazy-cons :b nil))
                        (make-instance 'xref-sequence :items (list nil :b))))
    (dolist (key '(1/2 1.0 nil :bad #\a))
      (parachute:fail (sl:ref object key) type-error)
      (parachute:fail (sl:ref object key nil) type-error))
    (parachute:fail (sl:ref object 2) type-error)
    (xref-values (multiple-value-list (sl:ref object 2 nil)) nil nil)
    (xref-values (multiple-value-list (sl:ref object 100 :missing)) :missing nil))
  ;; Negative indices address positions for sequences, including through REF.
  (dolist (spec (list (list (list nil :b) :b) (list (vector nil :b) :b)
                      (list (copy-seq "ab") #\b)
                      (list (sl:lazy-cons nil (sl:lazy-cons :b nil)) :b)
                      (list (make-instance 'xref-sequence :items (list nil :b)) :b)))
    (destructuring-bind (object expected) spec
      (xref-values (multiple-value-list (sl:seq-ref object -1)) expected t)
      (xref-values (multiple-value-list (sl:seq-ref object -1 :unused)) expected t)))
  (parachute:fail (sl:seq-ref nil -1) type-error)
  (xref-values (multiple-value-list (sl:seq-ref nil -1 :empty)) :empty nil)
  (xref-values (multiple-value-list (sl:seq-ref (list :a :b :c) -2)) :b t)
  (xref-values (multiple-value-list (sl:seq-ref (list :a :b :c) -3)) :a t)
  (parachute:is eq :c (sl:ref #(-1 :a :b :c) -1))
  (parachute:is = 99 (sl:ref (sl:dict -1 99 :a 1) -1))
  (parachute:is eq :c
                   (sl:entry-key (sl:seq-ref (sl:ordered-dict :a 1 :b 2 :c 3) -1)))
  (let ((dotted (cons :a :tail)))
    (dolist (key '(1 3))
      (parachute:fail (sl:ref dotted key) type-error)
      (parachute:fail (sl:ref dotted key nil) type-error)
      (parachute:fail (setf (sl:ref dotted key nil) :new) type-error))
    (parachute:is equal '(:a . :tail) dotted))
  ;; Successful negative writes need independent sources from rejection checks.
  (dolist (object (list (list :a :b) (vector :a :b) (copy-seq "ab")))
    (parachute:is equal '(#\z) (multiple-value-list (setf (sl:seq-ref object -1) #\z)))
    (parachute:is equal '(#\z) (multiple-value-list (setf (sl:seq-ref object -1 :ignored) #\z))))
  (dolist (object (list nil #() (list :a :b) (vector :a :b) (copy-seq "ab")))
    (let ((before (copy-seq object)))
      (dolist (key '(:bad 1/2 2 100))
        (parachute:fail (setf (sl:ref object key) #\z) type-error)
        (parachute:fail (setf (sl:ref object key nil) #\z) type-error))
      (when (or (null object) (and (vectorp object) (zerop (length object))))
        (parachute:fail (setf (sl:seq-ref object -1) #\z) type-error))
      (parachute:is equalp before object))))

(parachute:define-test ref.host-storage
  (let ((vector (make-array 4 :initial-contents '(a b hidden hidden) :fill-pointer 2))
        (string (make-array 4 :element-type 'character :initial-contents "abcd" :fill-pointer 2)))
    (dolist (object (list vector string))
      (xref-values (multiple-value-list (sl:ref object 1)) (aref object 1) t)
      (parachute:fail (sl:ref object 2) type-error)
      (xref-values (multiple-value-list (sl:ref object 2 :absent)) :absent nil)
      (parachute:fail (setf (sl:ref object 2 :ignored) #\z) type-error)
      (parachute:is = 2 (fill-pointer object)))
    (setf (sl:ref vector 1) :new (sl:ref string 1) #\z)
    (parachute:is eq :new (aref vector 1))
    (parachute:is char= #\z (char string 1))
    (parachute:is eq 'hidden (aref vector 2))
    (parachute:is char= #\c (aref string 2))
    (parachute:fail (setf (sl:ref string 0) 42) type-error)
    (parachute:is char= #\a (char string 0)))
  (let ((bits (make-array 2 :element-type 'bit :initial-contents '(0 1))))
    (parachute:fail (setf (sl:ref bits 0) 2) type-error)
    (parachute:is equalp #*01 bits)
    (parachute:is equal '(1) (multiple-value-list (setf (sl:ref bits 0) 1))))
  (dolist (test '(eq eql equal equalp))
    (let* ((table (make-hash-table :test test)) (key (copy-seq "Key"))
           (probe (copy-seq "Key")))
      (setf (gethash key table) :resident)
      (multiple-value-bind (value present) (gethash probe table :default)
        (xref-values (multiple-value-list (sl:ref table probe :default)) value (not (null present)))))))

(parachute:define-test ref.write-evaluation-order
  (dolist (object (list (list :old) (vector :old) (make-hash-table)
                        (make-instance 'xref-writable :items (list :old))
                        (make-instance 'xref-mutable-dictionary)))
    (let ((events nil) (new (list :new)))
      (parachute:is equal (list new)
        (multiple-value-list
         (setf (sl:ref (progn (push :object events) object)
                       (progn (push :key events) 0)
                       (progn (push :default events) (values :ignored :extra)))
               (progn (push :value events) (values new :discarded)))))
      (parachute:is equal '(:object :key :default :value) (nreverse events))
      (xref-values (multiple-value-list (sl:ref object 0)) new t)))
  (let ((table (make-hash-table)))
    (parachute:is equal '(nil) (multiple-value-list (setf (sl:ref table :a nil) nil)))
    (parachute:is = 1 (hash-table-count table))
    (parachute:is equal '(:new) (multiple-value-list (setf (sl:ref table :a) :new)))
    (parachute:is = 1 (hash-table-count table))
    (parachute:is eq :new (gethash :a table)))
  ;; A default that exits must prevent evaluating the new value and writing.
  (let ((object (list :old)) (events nil))
    (parachute:is eq :escaped
      (catch 'xref-exit
        (setf (sl:ref object 0 (throw 'xref-exit :escaped))
              (progn (push :value events) :new))))
    (parachute:is equal '(:old) object)
    (parachute:is eq nil events)))

(parachute:define-test ref.lazy-write-refusal
  (let ((forces 0))
    (let ((node (sl:make-lazy-seq (lambda () (incf forces) (sl:lazy-cons :old nil)))))
      (dolist (key '(0 1 100 -1 nil :bad 1/2))
        (parachute:fail (setf (sl:ref node key) :new) simple-error)
        (parachute:fail (setf (sl:ref node key :ignored) :new) simple-error))
      (parachute:is = 0 forces)
      (xref-values (multiple-value-list (sl:ref node 0)) :old t)
      (parachute:is = 1 forces)
      (parachute:fail (setf (sl:ref node 0) :new) simple-error)
      (xref-values (multiple-value-list (sl:ref node 0)) :old t)))
  (parachute:fail (setf (sl:ref (sl:make-lazy-seq (lambda () nil)) 0) :new) simple-error)
  (parachute:fail (setf (sl:ref nil 0) :new) type-error))

(parachute:define-test ref.unsupported-objects
  (let ((wrapper (make-instance 'xref-traversable)))
    (parachute:is equal '(a b) (mapcar #'identity (xref-items wrapper)))
    (dolist (object (list wrapper 42 :unsupported (sl:map-entry :a :b) (make-array '(2 2))))
      (parachute:false (sl:seqablep object))
      (parachute:false (sl:dictp object))
      (parachute:fail (sl:ref object 0) type-error)
      (parachute:fail (sl:ref object 0 nil) type-error)
      (parachute:fail (setf (sl:ref object 0 :ignored) :new) type-error)))
  (dolist (spec '((xref-direct :direct-read) (xref-dictionary :dict-read)
                  (xref-indexed :seq-read)))
    (let ((object (make-instance (first spec))) (*xref-calls* nil))
      (if (eq (first spec) 'xref-indexed)
          (parachute:fail (sl:ref object 0) type-error)
          (xref-values (multiple-value-list (sl:ref object 0)) nil nil))
      (xref-values (multiple-value-list (sl:ref object 0 nil)) nil nil)
      (xref-values (multiple-value-list (sl:ref object 0 :default)) :default nil)
      (parachute:is equal
        (list (list (second spec) :default t) (list (second spec) nil t)
              (list (second spec) nil nil)) *xref-calls*))))

(parachute:define-test ref.error-propagation
  (dolist (object (list (make-instance 'xref-direct-child)
                        (make-instance 'xref-mutable-dictionary)
                        (make-instance 'xref-writable :items (list :old))))
    (let ((*xref-condition* (make-condition 'xref-sentinel)))
      (dolist (thunk (list (lambda () (sl:ref object 0))
                           (lambda () (sl:ref object 0 nil))
                           (lambda () (setf (sl:ref object 0 :ignored) :new))))
        (parachute:is eq *xref-condition*
          (handler-case (funcall thunk) (xref-sentinel (condition) condition)))))
    (if (typep object 'xref-writable)
        (parachute:is equal '(:old) (xref-items object))
        (parachute:is = 0 (hash-table-count (xref-table object)))))
  (let ((dict (make-instance 'xref-dictionary))
        (sequence (make-instance 'xref-sequence :items (list :old))))
    (dolist (key '(0 -1 :bad))
      (parachute:fail (setf (sl:ref dict key) :new) program-error)
      (parachute:fail (setf (sl:ref dict key :ignored) :new) program-error)
      (parachute:fail (setf (sl:ref sequence key) :new) simple-error)
      (parachute:fail (setf (sl:ref sequence key :ignored) :new) simple-error))
    (parachute:is = 0 (sl:dict-size dict))
    (parachute:is equal '(:old) (xref-items sequence)))
  (let ((dict (sl:dict 0 :old)))
    (parachute:fail (setf (sl:ref dict 0 nil) :new) simple-error)
    (xref-values (multiple-value-list (sl:ref dict 0)) :old t))
  (let ((*xref-condition* (make-condition 'xref-sentinel)))
    (let ((node (sl:make-lazy-seq (lambda () (error *xref-condition*)))))
      (parachute:is eq *xref-condition*
        (handler-case (sl:ref node 0 :default) (xref-sentinel (condition) condition))))))

;;;; Shared UPDATE-MODEL fixture for the earlier ordered-dictionary unit and
;;;; the later dict-update operation tests.
(defclass update-model ()
  ((table :initarg :table :initform (make-hash-table :test 'equal)
          :reader update-model-table)))

(defclass update-model-child (update-model) ())

(defmethod sl:dictp ((source update-model)) t)

(defun update-model-key= (left right)
  (check-type left symbol)
  (check-type right symbol)
  (eq left right))

(defmethod sl:dict-test ((source update-model)) #'update-model-key=)

(defmethod sl:dict-size ((source update-model))
  (hash-table-count (update-model-table source)))

(defmethod sl:dict-ref ((source update-model) key &optional default)
  (unless (symbolp key) (error 'type-error :datum key :expected-type 'symbol))
  (gethash key (update-model-table source) default))

(defmethod sl:dict-set ((source update-model) key value)
  (unless (symbolp key) (error 'type-error :datum key :expected-type 'symbol))
  (let ((copy (make-hash-table :test 'equal)))
    (maphash (lambda (k v) (setf (gethash k copy) v)) (update-model-table source))
    (setf (gethash key copy) value)
    (make-instance (class-of source) :table copy)))

(defmethod sl:seqablep ((source update-model)) t)

(defmethod sl:seq-length ((source update-model)) (sl:dict-size source))

(defmethod sl:seq-emptyp ((source update-model)) (zerop (sl:dict-size source)))

(defun update-model-entries (source)
  (loop for k being the hash-keys of (update-model-table source) using (hash-value v)
        collect (sl:map-entry k v)))

(defmethod sl:seq-first ((source update-model)) (first (update-model-entries source)))

(defmethod sl:seq-rest ((source update-model)) (rest (update-model-entries source)))

;;; B2 characterization: reconstruction is ordered, success-only, and dispatches
;;; public insertion even though the ordinary DICT constructor need not do so.
(defclass bulk-characterization-key ()
  ((hash :initarg :hash :reader bulk-characterization-hash)
   (fail-p :initform nil :accessor bulk-characterization-fail-p)))

(defvar *bulk-characterization-events* nil)
(defvar *bulk-characterization-reenter* nil)

(define-condition bulk-hash-refusal (error) ())
(define-condition bulk-tail-forced (error) ())

(defmethod sl:hash-code ((key bulk-characterization-key))
  (push (bulk-characterization-hash key) *bulk-characterization-events*)
  (when *bulk-characterization-reenter*
    (let ((*bulk-characterization-reenter* nil))
      (parachute:is eq :nested
                    (sl:dict-ref (sl:dict-collect (sl:dict)
                                                  (list (sl:map-entry :nested :nested))) :nested))))
  (when (bulk-characterization-fail-p key)
    (error 'bulk-hash-refusal))
  (bulk-characterization-hash key))

(parachute:define-test dict-collect.bulk-characterization
  (let* ((first (copy-seq "duplicate"))
         (last (copy-seq "duplicate"))
         (value (list :last))
         (result (sl:dict-collect (sl:dict)
                                  (list (sl:map-entry first :first)
                                        (sl:map-entry last value)) :test 'eq)))
    (parachute:is = 1 (sl:dict-size result))
    (parachute:is eq last (sl:entry-key (sl:seq-first result)))
    (parachute:is eq value (sl:dict-ref result first)))
  (let* ((a (make-instance 'bulk-characterization-key :hash 17))
         (b (make-instance 'bulk-characterization-key :hash 17))
         (mutable (copy-seq "old"))
         (entry (sl:map-entry mutable :old))
         (*bulk-characterization-events* nil)
         (*bulk-characterization-reenter* t))
    (let ((result (sl:dict-collect (sl:dict)
                                   (list (sl:map-entry a :a)
                                         (sl:map-entry b :b) entry))))
      (parachute:is = 3 (sl:dict-size result))
      (parachute:is equal '(17 17) (reverse *bulk-characterization-events*))
      (setf (char mutable 0) #\O)
      (parachute:is eq mutable
        (sl:entry-key (find mutable (sl:seq-into 'list result)
                            :key #'sl:entry-key :test #'eq)))
      (parachute:is eq :a (sl:dict-ref result a))
      (parachute:is eq :b (sl:dict-ref result b))))
  (let* ((key (make-instance 'bulk-characterization-key :hash 29))
         (collector (sl:make-collector-for (find-class 'sl:dict)))
         (*bulk-characterization-events* nil))
    (sl:collector-accumulate collector (sl:map-entry :before :before))
    (sl:collector-accumulate collector (sl:map-entry key :key))
    (sl:collector-accumulate collector (sl:map-entry :after :after))
    (parachute:false *bulk-characterization-events*)
    (setf (bulk-characterization-fail-p key) t)
    (parachute:fail (sl:collector-result collector) bulk-hash-refusal)
    (parachute:is = 3 (length (sophie-lisp.internal::dict-collector-entries collector)))
    (setf (bulk-characterization-fail-p key) nil)
    (let ((result (sl:collector-result collector)))
      (parachute:is = 3 (sl:dict-size result))
      (parachute:is eq :after (sl:dict-ref result :after))
      (parachute:is eq result (sl:collector-result collector))))
  (let ((key (make-instance 'bulk-characterization-key :hash 31))
        (*bulk-characterization-events* nil))
    (setf (bulk-characterization-fail-p key) t)
    ;; Distinct conditions expose a premature tail force as a different error.
    (parachute:fail
     (sl:dict-collect (sl:dict)
                      (sl:lazy-cons (sl:map-entry key :bad)
                                    (sl:lazy-seq (error 'bulk-tail-forced))))
     bulk-hash-refusal)
    (parachute:is equal '(31) *bulk-characterization-events*)))

(parachute:define-test dict-collect.bulk-method-dispatch
  (let ((events nil) (method nil))
    (unwind-protect
         (progn
           (setf method
                 (eval '(defmethod sl:dict-set :before
                            ((dict sl:dict) (key string) value)
                          (declare (ignore dict value))
                          (push key *bulk-characterization-events*))))
           (let ((*bulk-characterization-events* nil))
             (sl:dict-collect (sl:dict)
                              (vector (sl:map-entry "one" 1)
                                      (sl:map-entry :other 2)
                                      (sl:map-entry "two" 3)))
             (setf events (reverse *bulk-characterization-events*)))
           (parachute:is equal '("one" "two") events))
      (when method (remove-method #'sl:dict-set method)))))
