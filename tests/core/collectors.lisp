(in-package #:sophie-lisp.tests)


(parachute:define-test map-entry.construction-and-accessors
  (let* ((key (list :entry-key))
         (value (vector :entry-value))
         (entry (sophie-lisp:map-entry key value))
         (nil-entry (sophie-lisp:map-entry nil nil)))
    (parachute:true (typep entry 'sophie-lisp:map-entry))
    (parachute:true (typep nil-entry 'sophie-lisp:map-entry))
    (parachute:is eq key (sophie-lisp:entry-key entry))
    (parachute:is eq value (sophie-lisp:entry-value entry))
    (parachute:is eq nil (sophie-lisp:entry-key nil-entry))
    (parachute:is eq nil (sophie-lisp:entry-value nil-entry))))

(parachute:define-test map-entry.accessor-type-errors-and-immutability
  (dolist (accessor (list #'sophie-lisp:entry-key #'sophie-lisp:entry-value))
    (let ((condition
            (handler-case
                (progn (funcall accessor :not-an-entry) nil)
              (condition (caught) caught))))
      (parachute:true (typep condition 'type-error))))
  (dolist (bad '(42 nil "x" (a . b)))
    (parachute:fail (sophie-lisp:entry-key bad) type-error)
    (parachute:fail (sophie-lisp:entry-value bad) type-error))
  (parachute:false (fboundp '(setf sophie-lisp:entry-key)))
  (parachute:false (fboundp '(setf sophie-lisp:entry-value)))
  (let* ((key (list :immutable-key))
         (value (list :immutable-value))
         (entry (sophie-lisp:map-entry key value)))
    ;; No mutation is attempted through an interface the specification leaves
    ;; undefined; the absence of SETF accessors is the sealed public contract.
    (parachute:is eq key (sophie-lisp:entry-key entry))
    (parachute:is eq value (sophie-lisp:entry-value entry))))


(parachute:define-test map-entry.single-value-results
  (let* ((key (gensym "ENTRY-KEY-"))
         (value (gensym "ENTRY-VALUE-"))
         (entry (sophie-lisp:map-entry key value))
         (entry-values (multiple-value-list (sophie-lisp:map-entry key value)))
         (key-values (multiple-value-list (sophie-lisp:entry-key entry)))
         (value-values (multiple-value-list (sophie-lisp:entry-value entry))))
    (parachute:is = 1 (length entry-values))
    (parachute:is = 1 (length key-values))
    (parachute:is = 1 (length value-values))
    (parachute:is eq key (sophie-lisp:entry-key (first entry-values)))
    (parachute:is eq key (first key-values))
    (parachute:is eq value (first value-values))
    (parachute:true (typep (first entry-values) 'sophie-lisp:map-entry))))

;;;; Independent Chapter 4 Collector acceptance. No SEQ-INTO or traversal owner
;;;; is needed: the two caller contracts below are deliberately test-only.
;;;; D-BATCH-COLLECT/D-COLLECT-BRIDGE, public S-INTO/S-JOIN composition,
;;;; LAZY-SEQ designator handling, and Z-INTEGRATION remain deferred obligations.
;;;; Never accumulate after finalization (undefined), or demand fresh NIL.

(defclass s-collect-state ()
  ((factory :initarg :factory :reader s-collect-factory)
   (items :initform nil :accessor s-collect-items)
   (result :accessor s-collect-cached)))

(defmethod sl:collector-accumulate ((state s-collect-state) element)
  (push element (s-collect-items state))
  state)

(defmethod sl:collector-result ((state s-collect-state))
  (if (slot-boundp state 'result)
      (s-collect-cached state)
      (setf (s-collect-cached state)
            (funcall (s-collect-factory state)
                     (reverse (s-collect-items state))))))

(defclass s-collect-source ()
  ((metadata :initarg :metadata :reader s-collect-metadata)
   (items :initarg :items :initform nil :reader s-collect-source-items)))
(defclass s-collect-child (s-collect-source) ())
(defclass s-collect-auxiliary () ())
(defclass s-collect-late (s-collect-source) ())
(define-condition s-collect-sentinel (error) ())

(defmethod sl:seqablep ((source s-collect-source)) t)
(defmethod sl:seq-emptyp ((source s-collect-source))
  (null (s-collect-source-items source)))
(defmethod sl:seq-first ((source s-collect-source))
  (car (s-collect-source-items source)))
(defmethod sl:seq-rest ((source s-collect-source))
  (make-instance (class-of source) :metadata (s-collect-metadata source)
                 :items (cdr (s-collect-source-items source))))

(defmethod sl:make-collector-for ((source s-collect-source) &key observer)
  (when observer (funcall observer :base source))
  (make-instance 's-collect-state
                 :factory (lambda (items)
                            (make-instance (class-of source)
                                           :metadata (s-collect-metadata source)
                                           :items items))))

(defun s-collect-target (name)
  (find-class name))

(defun s-collect-make (target &optional options)
  (apply #'sl:make-collector-for target options))

(defun s-collect-invalid-type-p (specifier)
  "Whether the host's type-specifier parser rejects SPECIFIER.
CCL upgrades unknown-symbol specifiers to T instead of diagnosing them;
the collector contract translates host diagnostics, so only host-rejected
specifiers must signal TYPE-ERROR."
  (handler-case (progn (upgraded-array-element-type specifier) nil)
    (error () t)))

(defun s-collect-participates-p (target &optional options)
  (handler-case
      (let ((options (copy-list options)))
        (when (getf options :observer)
          (setf (getf options :observer)
                (lambda (&rest ignored)
                  (declare (ignore ignored)))))
        (apply #'sl:make-collector-for target options)
        t)
    (error () nil)))

(defun s-collect-fill (collector elements)
  (dolist (element elements collector)
    (parachute:is eq collector (sl:collector-accumulate collector element))))

(defmacro s-collect-with-methods (forms &body body)
  ;; Only new specializers/qualifiers are installed, with unwind-safe cleanup.
  (let ((installed (gensym "METHODS-"))
        (form (gensym "FORM-"))
        (method (gensym "METHOD-")))
    `(let ((,installed nil))
       (unwind-protect
            (progn
              (dolist (,form ,forms)
                (push (eval ,form) ,installed))
              ,@body)
         (dolist (,method ,installed)
           (remove-method (closer-mop:method-generic-function ,method) ,method))))))

(parachute:define-test make-collector.target-designators-and-eql-dispatch
  ;; STANDARD-CLASS is self-instantiating, unlike an ordinary test DEFCLASS.
  ;; A fresh instance satisfies TYPEP target and exact CLASS-OF source alike.
  ;; These non-enumerated specializers exist only in this empty-source fixture;
  ;; no permanent methods on CL metaobjects or global class aliases remain.
  (s-collect-with-methods
      '((defmethod sl:seqablep ((x standard-class)) t)
        (defmethod sl:seq-emptyp ((x standard-class)) t)
        (defmethod sl:seq-first ((x standard-class)) nil)
        (defmethod sl:seq-rest ((x standard-class)) nil)
        (defmethod sl:make-collector-for ((target standard-class) &key observer)
          (funcall observer :class target)
          (make-instance 's-collect-state
                         :factory (lambda (items)
                                    (assert (null items))
                                    (make-instance 'standard-class))))
        (defmethod sl:make-collector-for
            ((target (eql (find-class 'standard-class))) &key observer)
          (funcall observer :eql target)
          (call-next-method)))
    (let* ((target (s-collect-target 'standard-class))
           (source target)
           (results nil))
      (parachute:is eq (find-class 'standard-class) target)
      (parachute:true (sl:seqablep source))
      (parachute:true (sl:seq-emptyp source))
      (dolist (actual (list target source))
        (let* ((events nil)
               (observer (lambda (event object) (push (list event object) events)))
               (options (list :observer observer))
               (collector (s-collect-make actual options))
               (result (sl:collector-result collector)))
          (parachute:true (s-collect-participates-p actual options))
          (parachute:is equal '(:eql :class) (mapcar #'car (reverse events)))
          (parachute:is eq actual (second (first events)))
          (parachute:is eq actual (second (second events)))
          (parachute:true (typep result target))
          (parachute:is eq (class-of source) (class-of result))
          (parachute:false (eq source result))
          (parachute:is eq result (sl:collector-result collector))
          (push result results)))
      (parachute:false (eq (first results) (second results)))))
  (dolist (name '(list vector string hash-table))
    (parachute:is eq (find-class name) (s-collect-target name)))
  ;; Same spelling, different symbol: no package-name guessing.
  (parachute:fail (s-collect-target (make-symbol "VECTOR")) error))

(parachute:define-test make-collector.option-and-target-validation
  (dolist (target (list (s-collect-target 'list) (list :old)))
    (dolist (options (list '(:unknown t) '(:element-type t) '(:test eq)
                          '(:unknown) '(not-a-key 1)))
      (parachute:fail (s-collect-make target options) program-error)))
  (dolist (name '(vector string hash-table))
    (parachute:fail (s-collect-make (s-collect-target name) '(:unknown t))
                    program-error))
  (dolist (name '(vector string))
    ;; Only host-rejected specifiers must signal: CCL upgrades the gensym
    ;; fixture to T instead of diagnosing it (see S-COLLECT-INVALID-TYPE-P).
    (dolist (bad (remove-if-not #'s-collect-invalid-type-p
                                (list 42 '(unsigned-byte -1)
                                      (gensym "INVALID-TYPE-"))))
      (parachute:fail
       (s-collect-make (s-collect-target name) (list :element-type bad)) type-error)))
  (dolist (bad '(t integer (or character integer)))
    (parachute:fail (s-collect-make (s-collect-target 'string)
                                   (list :element-type bad)) type-error))
  (dolist (bad (list nil :equal #'identity (make-symbol "EQUAL")))
    (parachute:fail (s-collect-make (s-collect-target 'hash-table)
                                   (list :test bad)) type-error))
  (dolist (bad (list 42 :unsupported (find-class 's-collect-auxiliary)))
    (parachute:fail (s-collect-make bad) type-error)
    (parachute:fail (sl:make-collector-for bad) type-error)
    (parachute:fail (sl:collector-accumulate bad :x) type-error)
    (parachute:fail (sl:collector-result bad) type-error))
  (dolist (name '(list vector string hash-table))
    (parachute:fail (sl:make-collector-for (s-collect-target name) :unknown t)
                    program-error)
    (parachute:fail (sl:make-collector-for (s-collect-target name) :unknown)
                    program-error)))

(parachute:define-test make-collector.list-results-and-isolation
  (let* ((opaque (list :opaque))
         (entry (sl:map-entry nil opaque))
         (elements (list nil opaque entry #'identity)))
    (dolist (target (list (s-collect-target 'list) elements))
      (let* ((collector (s-collect-make target))
             (other (s-collect-make target))
             (result (sl:collector-result (s-collect-fill collector elements))))
        (parachute:false (eq collector other))
        (parachute:true (listp result))
        (parachute:is equal elements result)
        (parachute:false (eq elements result))
        (loop for expected in elements for actual in result
              do (parachute:is eq expected actual))
        (parachute:is eq result (sl:collector-result collector))
        (parachute:is eq nil (sl:collector-result other))))
    (parachute:is eq nil (sl:collector-result (s-collect-make nil)))))

(parachute:define-test make-collector.vector-element-types-and-isolation
  (let ((source (make-array 5 :element-type '(unsigned-byte 8)
                             :initial-contents '(9 8 7 6 5) :fill-pointer 2)))
    (dolist (target (list (s-collect-target 'vector) source))
      (let* ((type (array-element-type source))
             (collector (s-collect-make target (list :element-type type))))
        (s-collect-fill collector '(1 2))
        (parachute:fail (sl:collector-accumulate collector 256) type-error)
        (parachute:fail (sl:collector-accumulate collector :bad) type-error)
        (s-collect-fill collector '(3))
        (let ((result (sl:collector-result collector)))
          (parachute:true (vectorp result))
          (parachute:is equalp #(1 2 3) result)
          (parachute:is equal (upgraded-array-element-type type)
                        (array-element-type result))
          (parachute:false (eq source result))
          (parachute:is eq result (sl:collector-result collector)))
        (parachute:fail (s-collect-make target '(:length 2)) program-error)))
    (parachute:is = 2 (fill-pointer source))
    (parachute:is equalp #(9 8) source))
  (let* ((object (list :arbitrary))
         (collector (s-collect-make (s-collect-target 'vector)))
         (result (sl:collector-result (s-collect-fill collector (list object nil)))))
    (parachute:is eq t (array-element-type result))
    (parachute:is eq object (aref result 0))
    (parachute:is eq nil (aref result 1))
    (parachute:is = 2 (length result))))

(parachute:define-test make-collector.string-element-types-and-isolation
  (let ((source (copy-seq "old")))
    (dolist (target (list (s-collect-target 'string) source))
      (dolist (options '(nil (:element-type base-char)))
        (let ((collector (s-collect-make target options)))
          (s-collect-fill collector '(#\A))
          (parachute:fail (sl:collector-accumulate collector 65) type-error)
          (parachute:fail (sl:collector-accumulate collector "B") type-error)
          (s-collect-fill collector '(#\B))
          (let ((result (sl:collector-result collector)))
            (parachute:true (stringp result))
            (parachute:is string= "AB" result)
            (parachute:false (eq result source))
            (parachute:is eq result (sl:collector-result collector))
            ;; CCL's UPGRADED-ARRAY-ELEMENT-TYPE says BASE-CHAR but its own
            ;; MAKE-ARRAY with that element type reports CHARACTER, so the
            ;; honest oracle is the element type the host itself produces.
            (parachute:is equal
                          (array-element-type
                           (make-array 0
                                       :element-type
                                       (if options 'base-char 'character)))
                          (array-element-type result))))))
    (parachute:is string= "old" source)))

(parachute:define-test make-collector.hash-table-test-and-entry-validation
  (dolist (test '(eq eql equal equalp))
    (dolist (designator (list test (symbol-function test)))
      (let* ((first-key (copy-seq "Key"))
             (last-key (case test
                         ((eq eql) first-key)
                         (equal (copy-seq "Key"))
                         (equalp (copy-seq "kEY"))))
             (old-value (list :old))
             (new-value (list :new))
             (source (make-hash-table :test test))
             (collector (s-collect-make source (list :test designator))))
        (setf (gethash :untouched source) old-value)
        (s-collect-fill collector (list (sl:map-entry first-key old-value)))
        (dolist (bad (list (cons first-key new-value) (vector first-key new-value) nil))
          (parachute:fail (sl:collector-accumulate collector bad) type-error))
        (s-collect-fill collector (list (sl:map-entry last-key new-value)))
        (let ((result (sl:collector-result collector)))
          (parachute:true (hash-table-p result))
          (parachute:is eq test (hash-table-test result))
          (parachute:is = 1 (hash-table-count result))
          (parachute:is eq new-value (gethash first-key result))
          (parachute:false (eq source result))
          (parachute:is eq result (sl:collector-result collector))
          (parachute:is = 1 (hash-table-count source))
          (parachute:is eq old-value (gethash :untouched source))))))
  (let* ((collector (s-collect-make (s-collect-target 'hash-table)))
         (table (sl:collector-result
                 (s-collect-fill collector (list (sl:map-entry nil nil))))))
    (parachute:is eq 'equal (hash-table-test table))
    (parachute:is equal '(nil t) (multiple-value-list (gethash nil table)))))

(parachute:define-test collector.accumulation-failure-recovery-and-result-caching
  (dolist (spec '((vector (:element-type bit) 0 :bad 1)
                  (string nil #\A :bad #\B)))
    (destructuring-bind (name options first refused last) spec
      (let ((collector (s-collect-make (s-collect-target name) options)))
        (s-collect-fill collector (list first))
        (parachute:fail (sl:collector-accumulate collector refused) type-error)
        (s-collect-fill collector (list last))
        (let ((result (sl:collector-result collector)))
          (parachute:is equal (list first last) (coerce result 'list))
          (parachute:is eq result (sl:collector-result collector))
          (parachute:fail (sl:collector-accumulate collector last) simple-error)
          (parachute:is eq result (sl:collector-result collector)))))))

(parachute:define-test make-collector.method-combination-and-auxiliary-exclusion
  (s-collect-with-methods
      '((defmethod sl:make-collector-for :around
            ((source s-collect-child) &key observer)
          (funcall observer :around-in source)
          (prog1 (call-next-method) (funcall observer :around-out source)))
        (defmethod sl:make-collector-for :before
            ((source s-collect-child) &key observer)
          (funcall observer :before source))
        (defmethod sl:make-collector-for :after
            ((source s-collect-child) &key observer)
          (funcall observer :after source))
        (defmethod sl:make-collector-for ((source s-collect-child) &key observer)
          (funcall observer :child source)
          (call-next-method)))
    (let* ((metadata (list :configuration))
           (source (make-instance 's-collect-child :metadata metadata))
           (events nil)
           (observer (lambda (event object)
                       (push event events)
                       (parachute:is eq source object)))
           (collector (s-collect-make source (list :observer observer))))
      (parachute:true (s-collect-participates-p source (list :observer observer)))
      (parachute:is equal '(:around-in :before :child :base :after :around-out)
                    (reverse events))
      (s-collect-fill collector '(nil :item))
      (let ((result (sl:collector-result collector)))
        (parachute:is eq (class-of source) (class-of result))
        (parachute:is eq metadata (s-collect-metadata result))
        (parachute:is equal '(nil :item) (s-collect-source-items result))
        (parachute:false (eq source result)))
      (let ((condition (make-condition 's-collect-sentinel)))
        (parachute:is eq condition
                      (handler-case
                          (s-collect-make source
                                          (list :observer
                                                (lambda (&rest ignored)
                                                  (declare (ignore ignored))
                                                  (error condition))))
                        (s-collect-sentinel (caught) caught))))))
  (dolist (qualifier '(:before :after :around))
    (s-collect-with-methods
        (list `(defmethod sl:make-collector-for ,qualifier
                   ((source s-collect-auxiliary) &key)
                 ,(if (eq qualifier :around) '(call-next-method) nil)))
      (parachute:false (s-collect-participates-p
                        (make-instance 's-collect-auxiliary))))))

(parachute:define-test make-collector.dynamic-method-participation
  (let* ((source (make-instance 's-collect-auxiliary))
         (metadata (list :metadata))
         (child (make-instance 's-collect-late :metadata metadata)))
    (parachute:false (s-collect-participates-p source))
    (s-collect-with-methods
        '((defmethod sl:make-collector-for ((source s-collect-auxiliary) &key)
            (make-instance 's-collect-state :factory #'copy-list)))
      (parachute:true (s-collect-participates-p source))
      (let ((collector (s-collect-make source)))
        (s-collect-fill collector '(:late))
        (parachute:is equal '(:late) (sl:collector-result collector))))
    (parachute:false (s-collect-participates-p source))
    (parachute:fail (s-collect-make source) type-error)
    (parachute:true (s-collect-participates-p child))
    (s-collect-with-methods
        '((defmethod sl:make-collector-for ((source s-collect-late) &key observer)
            (when observer (funcall observer :override source))
            (call-next-method)))
      (let ((events nil))
        (s-collect-make child (list :observer (lambda (event object)
                                              (declare (ignore object))
                                              (push event events))))
        (parachute:is equal '(:override :base) (reverse events))))
    (let* ((collector (s-collect-make child))
           (other (s-collect-make child))
           (result (sl:collector-result collector)))
      (parachute:true (s-collect-participates-p child))
      (parachute:is eq (class-of child) (class-of result))
      (parachute:is eq metadata (s-collect-metadata result))
      (parachute:false (eq child result))
      (parachute:false (eq result (sl:collector-result other)))
      (parachute:is eq result (sl:collector-result collector))))
  ;; With no applicable class primary, this EQL primary alone must opt in.
  ;; Also exercise a test-owned, nonempty registered-target result contract.
  (let ((target (s-collect-target 's-collect-source))
        (metadata (list :target-metadata)))
    (parachute:false (s-collect-participates-p target))
    (s-collect-with-methods
        '((defmethod sl:make-collector-for
              ((target (eql (find-class 's-collect-source))) &key metadata)
            (make-instance 's-collect-state
                           :factory (lambda (items)
                                      (make-instance target :metadata metadata
                                                            :items items)))))
      (parachute:true (s-collect-participates-p target))
      (let* ((collector (s-collect-make target (list :metadata metadata)))
             (result (sl:collector-result
                      (s-collect-fill collector '(nil :registered)))))
        (parachute:true (typep result target))
        (parachute:is eq metadata (s-collect-metadata result))
        (parachute:is equal '(nil :registered) (s-collect-source-items result))
        (parachute:is eq result (sl:collector-result collector))))
    (parachute:false (s-collect-participates-p target))
    (parachute:fail (s-collect-make target) type-error)))

(parachute:define-test collector.evaluation-order-and-fresh-empty-results
  ;; Verify collector evaluation order and single-value results.
  (let* ((events nil)
         (object (list :primary))
         (collector (s-collect-make (s-collect-target 'list)))
         (returned
           (multiple-value-list
            (sl:collector-accumulate
             (progn (push :collector events) collector)
             (progn (push :element events) (values object :discarded))))))
    (parachute:is equal '(:collector :element) (reverse events))
    (parachute:is = 1 (length returned))
    (parachute:is eq collector (first returned))
    (let ((results (multiple-value-list (sl:collector-result collector))))
      (parachute:is = 1 (length results))
      (parachute:is = 1 (length (first results)))
      (parachute:is eq object (first (first results)))
      (parachute:is eq (first results) (sl:collector-result collector))))
  ;; Fresh empty mutable builtins and independent state, including direct GF use.
  (dolist (name '(vector string hash-table))
    (let* ((target (s-collect-target name))
           (left (sl:make-collector-for target))
           (right (sl:make-collector-for target))
           (a (sl:collector-result left))
           (b (sl:collector-result right)))
      (parachute:false (eq left right))
      (parachute:true (typep a target))
      (parachute:false (eq a b))
      (parachute:is eq a (sl:collector-result left))
      (parachute:is = 0 (if (hash-table-p a) (hash-table-count a) (length a)))
      (parachute:is = 0 (if (hash-table-p b) (hash-table-count b) (length b))))))

(parachute:define-test collector.finalization-failure-retry-and-result-caching
  (let* ((calls 0)
         (condition (make-condition 's-collect-sentinel))
         (result (list :result))
         (collector
           (make-instance 's-collect-state
                          :factory (lambda (items)
                                     (parachute:is equal '(:retained) items)
                                     (incf calls)
                                     (if (= calls 1)
                                         (error condition)
                                         result)))))
    (s-collect-fill collector '(:retained))
    (parachute:is eq condition
                  (handler-case (progn (sl:collector-result collector) nil)
                    (s-collect-sentinel (caught) caught)))
    (parachute:is = 1 calls)
    (parachute:is eq result (sl:collector-result collector))
    (parachute:is = 2 calls)
    (parachute:is eq result (sl:collector-result collector))
    (parachute:is = 2 calls)))
