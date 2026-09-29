;;;; Independent D-CONTAINERS primitive gate, not full container conformance.
;;;; Normative authority: Chapter 9.1.2, 9.1.4, 9.1.8-10 and the complete
;;;; DICT/DICTP/DICT-REF/DICT-TEST/DICT-SIZE/DICT-SET/DICT-WITHOUT entries.
;;;; No container is used as a key, compared, or hashed here. Late value,
;;;; traversal, collector, printing and full key-domain obligations remain for
;;;; their owners and Z-INTEGRATION. Default/non-dict/declined-method tests
;;;; belong to ADAPTER-004, not this gate (D-HASH-ADAPTER owns those methods).
(in-package #:sophie-lisp.tests)

(defun core-ref-check (dict key value present &optional (default nil))
  (let ((results (multiple-value-list (sl:dict-ref dict key default))))
    (parachute:is = 2 (length results))
    (parachute:is eq value (first results))
    (parachute:is eq (not (null present)) (not (null (second results))))))



(defclass core-key () ((id :initarg :id :reader core-key-id)))
(defvar *core-hash-calls* 0)
(defvar *core-equal-calls* 0)
(defvar *core-key-exit* nil)
(defmethod sl:hash-code ((key core-key))
  (incf *core-hash-calls*)
  (when (eq *core-key-exit* :hash) (throw 'core-key-exit :hash))
  ;; Valid adversarial hashing: all unequal keys collide.
  37)
(defmethod sl:equals ((a core-key) (b core-key))
  (incf *core-equal-calls*)
  (when (eq *core-key-exit* :equals) (throw 'core-key-exit :equals))
  (= (core-key-id a) (core-key-id b)))

(parachute:define-test dict.persistent-construction-and-versions
  (let* ((empty (sl:dict)) (dict empty) (versions (list empty)))
    (parachute:true (typep empty 'sl:dict))
    (parachute:true (sl:dictp empty))
    (parachute:is = 0 (sl:dict-size empty))
    (parachute:is eq #'sl:equals (sl:dict-test empty))
    (parachute:is equal '(nil nil) (multiple-value-list (sl:dict-ref empty :absent)))
    (loop for key below 32 do
      (setf dict (sl:dict-set dict key (+ key 100)))
      (push dict versions))
    ;; All 33 retained versions, including the empty version, stay usable.
    (loop for old in (reverse versions) for count from 0 do
      (parachute:is = count (sl:dict-size old))
      (parachute:is eq #'sl:equals (sl:dict-test old))
      (loop for key below count do (core-ref-check old key (+ key 100) t))
      (core-ref-check old count :missing nil :missing))
    (let* ((changed (sl:dict-set dict 0 :replacement))
           (removed (sl:dict-without changed 1))
           (absent (sl:dict-without removed :absent)))
      (parachute:is = 32 (sl:dict-size changed))
      (parachute:is = 31 (sl:dict-size removed))
      (parachute:is = 31 (sl:dict-size absent))
      (core-ref-check dict 0 100 t)
      (core-ref-check changed 0 :replacement t)
      (core-ref-check changed 1 101 t)
      (core-ref-check removed 1 :missing nil :missing)
      (loop for key from 2 below 32 do
        (core-ref-check removed key (+ key 100) t)
        (core-ref-check absent key (+ key 100) t))
      (parachute:is eq (sl:dict-test dict) (sl:dict-test removed))
      (parachute:true (sl:dictp removed))))
  (let* ((payload (list :shared)) (default (list :default))
         (dict (sl:dict nil nil :payload payload)))
    (core-ref-check dict nil nil t default)
    (core-ref-check dict :missing default nil default)
    (core-ref-check dict :payload payload t)
    (parachute:is = 2 (length (multiple-value-list (sl:dict-ref dict nil))))
    (parachute:fail (setf (sl:dict-ref dict nil) :changed) simple-error)
    (parachute:fail (funcall #'(setf sl:dict-ref) :changed dict nil default) simple-error)
    (core-ref-check dict nil nil t)
    (parachute:is = 2 (sl:dict-size dict))))

(parachute:define-test dict.equal-key-replacement
  (let* ((first (copy-seq "resident")) (last (copy-seq "resident"))
         (old-value (list :old)) (new-value (list :new))
         (dict (sl:dict first old-value))
         (changed (sl:dict-set dict last new-value))
         (set (sl:hash-set first))
         (duplicate (sl:set-add last set)))
    (parachute:false (eq first last))
    (parachute:true (sl:equals first last))
    (parachute:is = 1 (sl:dict-size changed))
    (core-ref-check dict last old-value t)
    (core-ref-check changed first new-value t)
    (parachute:is eq last (sl:entry-key (sl:seq-first changed)))
    (parachute:true (sl:set-member first set))
    (parachute:true (sl:set-member first duplicate))
    (parachute:true (sl:set-member last duplicate))
    (parachute:is = 1 (sl:set-size duplicate)))
  ;; Collision buckets have exactly the same replacement/persistence law.
  (let* ((a (make-instance 'core-key :id 1))
         (b (make-instance 'core-key :id 2))
         (a2 (make-instance 'core-key :id 1))
         (dict (sl:dict a :old b :unaffected))
         (changed (sl:dict-set dict a2 :new)))
    (core-ref-check dict a2 :old t)
    (core-ref-check changed a :new t)
    (parachute:is eq a2 (sl:entry-key (sl:seq-first changed)))
    (core-ref-check changed b :unaffected t)
    (parachute:is = 2 (sl:dict-size changed)))
  ;; Removing a middle leaf exercises the vector-compaction collision path.
  (let* ((keys (loop for id below 5
                     collect (make-instance 'core-key :id id)))
         (values (loop for id below 5 collect (list :value id)))
         (dict (loop with result = (sl:dict)
                     for key in keys for value in values
                     do (setf result (sl:dict-set result key value))
                     finally (return result)))
         (middle-key (third keys))
         (without (sl:dict-without dict middle-key)))
    (parachute:is = 5 (sl:dict-size dict))
    (parachute:is = 4 (sl:dict-size without))
    (multiple-value-bind (value present-p) (sl:dict-ref without middle-key)
      (declare (ignore value))
      (parachute:false present-p))
    (dolist (key keys)
      (unless (eq key middle-key)
        (core-ref-check without key (nth (core-key-id key) values) t))))
  ;; Equal full hashes must fail before trie-join can recurse indefinitely.
  (parachute:fail
   (sophie-lisp.internal::trie-join
    (sophie-lisp.internal::make-trie-leaf 37 :left :left)
    (sophie-lisp.internal::make-trie-leaf 37 :right :right)
    0)
   simple-error))

(parachute:define-test dict.trie-join.shift-60-boundary
  ;; These internal hashes agree in chunks 0 through 11 and differ at 60.
  (let* ((left-hash #x1000000000000000)
         (right-hash #x2000000000000000)
         (left (sophie-lisp.internal::make-trie-leaf left-hash :left :left))
         (right (sophie-lisp.internal::make-trie-leaf right-hash :right :right))
         (joined (sophie-lisp.internal::trie-join left right 0)))
    (loop for shift from 0 below 60 by 5 do
      (parachute:is =
                    (sophie-lisp.internal::trie-bit left-hash shift)
                    (sophie-lisp.internal::trie-bit right-hash shift)))
    (parachute:is = 2 (sophie-lisp.internal::trie-bit left-hash 60))
    (parachute:is = 4 (sophie-lisp.internal::trie-bit right-hash 60))
    (parachute:is equal '(:left t :left)
                  (multiple-value-list
                   (sophie-lisp.internal::trie-ref joined :left left-hash)))
    (parachute:is equal '(:right t :right)
                  (multiple-value-list
                   (sophie-lisp.internal::trie-ref joined :right right-hash)))))

(parachute:define-test dict.constructor-validation-and-metadata
  (let* ((first (copy-seq "key")) (last (copy-seq "key"))
         (value (list :last)) (dict (sl:dict first :old last value)))
    (parachute:is = 1 (sl:dict-size dict))
    (core-ref-check dict first value t))
  (let ((dict (sl:dict 1 :integer 1.0 :float 1d0 :double
                       1/2 :ratio 0.5 :half #\A :upper #\a :lower
                       :test 'eql)))
    ;; Four equality classes plus the ordinary :TEST key = five, not six.
    (parachute:is = 5 (sl:dict-size dict))
    (core-ref-check dict 1 :double t)
    (core-ref-check dict 1/2 :half t)
    (core-ref-check dict #\A :upper t)
    (core-ref-check dict #\a :lower t)
    (core-ref-check dict :test 'eql t)
    (parachute:is eq #'sl:equals (sl:dict-test dict)))
  (parachute:fail (sl:dict :unpaired) program-error)
  (parachute:fail (sl:dict :a 1 :unpaired) program-error)
  (let* ((key (make-instance 'core-key :id 1))
         (other (make-instance 'core-key :id 2))
         (alias (make-instance 'core-key :id 1))
         (*core-hash-calls* 0) (*core-equal-calls* 0))
    ;; Arity is detectably wrong before any key callback is permitted.
    (parachute:fail (sl:dict key :value other) program-error)
    (parachute:is = 0 *core-hash-calls*)
    (parachute:is = 0 *core-equal-calls*)
    (let ((dict (sl:dict key :old other :other alias :last)))
      (parachute:true (plusp *core-hash-calls*))
      (parachute:true (plusp *core-equal-calls*))
      (parachute:is = 2 (sl:dict-size dict))
      (core-ref-check dict key :last t)
      (core-ref-check dict other :other t)
      ;; Size/test are metadata reads, not an equality/hash traversal.
      (let ((*core-key-exit* :hash))
        (parachute:is = 2 (sl:dict-size dict))
        (parachute:is eq #'sl:equals (sl:dict-test dict)))
      (dolist (stage '(:hash :equals))
        (let ((*core-key-exit* stage))
          (parachute:is eq stage
            (catch 'core-key-exit (sl:dict-set dict alias :lost) :returned))
          (parachute:is eq stage
            (catch 'core-key-exit (sl:dict-without dict alias) :returned))
          (parachute:is eq stage
            (catch 'core-key-exit (sl:dict-ref dict alias) :returned))))
      (core-ref-check dict key :last t)
      (core-ref-check dict other :other t))))

(parachute:define-test dict.constructor-direct-trie-path
  ;; SL:DICT threads the trie directly and wraps once; these assertions pin
  ;; the constructor path itself, where DICT-SET-based retention tests cannot.
  (let* ((first (copy-seq "resident")) (last (copy-seq "resident"))
         (old-value (list :old)) (new-value (list :new))
         (dict (sl:dict first old-value last new-value)))
    (parachute:false (eq first last))
    (parachute:true (sl:equals first last))
    (parachute:is = 1 (sl:dict-size dict))
    ;; The LAST of two EQ-distinct equal keys is the resident key object.
    (parachute:is eq last (sl:entry-key (sl:seq-first dict)))
    (parachute:false (eq first (sl:entry-key (sl:seq-first dict))))
    (core-ref-check dict first new-value t)
    (core-ref-check dict last new-value t))
  ;; Constructor output is EQUALS- and SL:HASH-CODE-identical to the
  ;; incremental DICT-SET chain over the same pairs.
  (let* ((pairs (loop for key below 64
                      append (list key (list :value key))))
         (constructed (apply #'sl:dict pairs))
         (chained (loop with dict = (sl:dict)
                        for (key value) on pairs by #'cddr
                        do (setf dict (sl:dict-set dict key value))
                        finally (return dict))))
    (parachute:is = 64 (sl:dict-size constructed))
    (parachute:true (sl:equals constructed chained))
    (parachute:is = (sl:hash-code constructed) (sl:hash-code chained)))
  ;; Odd arity signals before any key hash or equality callback runs.
  (let* ((key (make-instance 'core-key :id 1))
         (*core-hash-calls* 0) (*core-equal-calls* 0))
    (parachute:fail (sl:dict key :value key) program-error)
    (parachute:is = 0 *core-hash-calls*)
    (parachute:is = 0 *core-equal-calls*)))

(defun adapter-table-association (table predicate)
  (let (found-key found-value)
    (maphash (lambda (key value)
               (when (funcall predicate key value)
                 (setf found-key key
                       found-value value)))
             table)
    (values found-key found-value)))

(defclass adapter-declining-dict () ())
(defclass adapter-broken-dict () ())

(defmethod sophie-lisp:dictp ((object adapter-declining-dict))
  (declare (ignore object))
  t)

(defmethod sophie-lisp:dictp ((object adapter-broken-dict))
  (declare (ignore object))
  t)

(parachute:define-test dict-adapter.standard-table-query
  (dolist (test '(eq eql equal equalp))
    (let* ((key (if (member test '(equal equalp))
                    (copy-seq "adapter-key")
                    (gensym "ADAPTER-KEY-")))
           (value (list :value test))
           (table (make-hash-table :test test)))
      (setf (gethash key table) value)
      (parachute:true (sophie-lisp:dictp table))
      (parachute:is eq test (hash-table-test table))
      (parachute:is eq test (sophie-lisp:dict-test table))
      (parachute:is = 1 (sophie-lisp:dict-size table))
      (let ((values (multiple-value-list
                     (sophie-lisp:dict-ref table key :unused))))
        (parachute:is = 2 (length values))
        (parachute:is eq value (first values))
        (parachute:true (second values)))
      (let ((values (multiple-value-list
                     (sophie-lisp:dict-ref table :adapter-absent :default))))
        (parachute:is = 2 (length values))
        (parachute:is eq :default (first values))
        (parachute:false (second values))))))

(parachute:define-test dict-adapter.persistent-edits
  (let* ((resident-key (copy-seq "resident"))
         (resident-value (list :resident))
         (new-key (list :new-key))
         (new-value (list :new-value))
         (source (make-hash-table :test 'equal
                                  :rehash-size 2.0
                                  :rehash-threshold 0.75)))
    (setf (gethash resident-key source) resident-value)
    (let ((copy (sophie-lisp:dict-set source new-key new-value)))
      (parachute:true (hash-table-p copy))
      (parachute:false (eq source copy))
      (parachute:is eq 'equal (sophie-lisp:dict-test copy))
      (parachute:is = 1 (hash-table-count source))
      (parachute:is = 2 (hash-table-count copy))
      (multiple-value-bind (key value)
          (adapter-table-association copy
                                     (lambda (candidate candidate-value)
                                       (and (equal candidate resident-key)
                                            (eq candidate-value resident-value))))
        (parachute:is eq resident-key key)
        (parachute:is eq resident-value value))
      (multiple-value-bind (key value)
          (adapter-table-association copy
                                     (lambda (candidate candidate-value)
                                       (and (eq candidate new-key)
                                            (eq candidate-value new-value))))
        (parachute:is eq new-key key)
        (parachute:is eq new-value value)))
    (let* ((replacement-key (copy-seq "resident"))
           (replacement-value (list :replacement))
           (updated (sophie-lisp:dict-set source replacement-key
                                          replacement-value)))
      (parachute:false (eq resident-key replacement-key))
      (parachute:false (eq source updated))
      (parachute:is = 1 (hash-table-count source))
      (multiple-value-bind (key value)
          (adapter-table-association source
                                     (lambda (candidate candidate-value)
                                       (and (equal candidate resident-key)
                                            (eq candidate-value resident-value))))
        (parachute:is eq resident-key key)
        (parachute:is eq resident-value value))
      (multiple-value-bind (key value)
          (adapter-table-association updated
                                     (lambda (candidate candidate-value)
                                       (and (equal candidate replacement-key)
                                            (eq candidate-value replacement-value))))
        (parachute:is eq replacement-key key)
        (parachute:is eq replacement-value value)))
    (let ((without-present
            (sophie-lisp:dict-without source (copy-seq "resident")))
          (without-absent (sophie-lisp:dict-without source :absent)))
      (parachute:false (eq source without-present))
      (parachute:false (eq source without-absent))
      (parachute:is = 0 (hash-table-count without-present))
      (parachute:is = 1 (hash-table-count without-absent))
      (parachute:is eq 'equal (sophie-lisp:dict-test without-present))
      (parachute:is eq 'equal (sophie-lisp:dict-test without-absent))
      (parachute:is = 1 (hash-table-count source)))))

(parachute:define-test dict-adapter.setter-and-copy-semantics
  (let* ((table (make-hash-table :test 'eql))
         (key (gensym "MUTABLE-KEY-"))
         (default (list :ignored-default))
         (value (list :stored)))
    (let ((returns (multiple-value-list
                    (setf (sophie-lisp:dict-ref table key default) value))))
      (parachute:is = 1 (length returns))
      (parachute:is eq value (first returns)))
    (multiple-value-bind (stored present)
        (gethash key table)
      (parachute:is eq value stored)
      (parachute:true present))
    (let ((nil-value (list :nil-value)))
      (setf (sophie-lisp:dict-ref table :another default) nil-value)
      (parachute:is eq nil-value (gethash :another table)))))

(parachute:define-test dict-adapter.invalid-provider-handling
  (dolist (operation
           (list (lambda () (sophie-lisp:dict-ref :not-a-dict :key))
                 (lambda () (sophie-lisp:dict-test :not-a-dict))
                 (lambda () (sophie-lisp:dict-size :not-a-dict))
                 (lambda () (sophie-lisp:dict-set :not-a-dict :key :value))
                 (lambda () (sophie-lisp:dict-without :not-a-dict :key))
                 (lambda ()
                   (funcall #'(setf sophie-lisp:dict-ref)
                            :value :not-a-dict :key :default))))
    (parachute:fail (funcall operation) type-error))
  ;; Invalid DICT-COLLECT tests are retained in BATCH-006, its API owner.
  (let ((broken (make-instance 'adapter-broken-dict))
        (declining (make-instance 'adapter-declining-dict)))
    (parachute:true (sophie-lisp:dictp broken))
    (parachute:true (sophie-lisp:dictp declining))
    (parachute:fail (sophie-lisp:dict-ref broken :key) type-error)
    (parachute:fail (sophie-lisp:dict-test broken) type-error)
    (parachute:fail (sophie-lisp:dict-size broken) type-error)
    (parachute:fail (sophie-lisp:dict-set declining :key :value)
                    program-error)
    (parachute:fail
     (funcall #'(setf sophie-lisp:dict-ref) :value declining :key :default)
     program-error)
    (parachute:fail (sophie-lisp:dict-without declining :key)
                    program-error))
  (parachute:fail
   (funcall #'(setf sophie-lisp:dict-ref) :value (sophie-lisp:dict) :key)
   simple-error))

(defun plist-caught-condition (constructor plist)
  (handler-case
      (progn (funcall constructor plist) nil)
    (condition (condition) condition)))

(defun plist-dual-condition-p (condition)
  (and condition
       (typep condition 'program-error)
       (typep condition 'type-error)))

(defun plist-circular-input ()
  ;; Do not read a circular datum from source: this is a finite object whose
  ;; second cons closes the cdr back to its first cons.
  (let ((plist (list :cycle 1)))
    (setf (cdr (cdr plist)) plist)
    plist))

(defun plist-ref-values (view key default)
  (multiple-value-list (sophie-lisp:dict-ref view key default)))

(defclass plist-hash-sentinel () ())
(defvar *plist-key-hash-calls* 0)
(defmethod sophie-lisp:hash-code ((key plist-hash-sentinel))
  (declare (ignore key))
  (incf *plist-key-hash-calls*)
  17)

(parachute:define-test plist-dict.input-validation
  (dolist (constructor
           (list #'sophie-lisp:plist-dict
                 #'sophie-lisp:plist-dict-view))
    (let ((key (make-instance 'plist-hash-sentinel)))
      (dolist (bad (list (list key :value :odd)
                        (cons key (cons :value :tail))))
        (let ((*plist-key-hash-calls* 0))
          (parachute:true (typep (plist-caught-condition constructor bad)
                                 'program-error))
          (parachute:is = 0 *plist-key-hash-calls*))))
    (let ((result (funcall constructor (list :a 1 :b 2))))
      (parachute:true (sophie-lisp:dictp result))
      (parachute:is = 2 (sophie-lisp:dict-size result)))
    (let ((condition (plist-caught-condition constructor (list :odd))))
      (parachute:true (typep condition 'program-error))
      (parachute:false (typep condition 'type-error)))
    (let* ((improper (cons :a (cons 1 :tail)))
           (condition (plist-caught-condition constructor improper)))
      (parachute:true (plist-dual-condition-p condition))
      (parachute:is eq improper (type-error-datum condition))
      (parachute:true (type-error-expected-type condition)))
    (let* ((atom 42)
           (condition (plist-caught-condition constructor atom)))
      (parachute:true (plist-dual-condition-p condition))
      (parachute:is eq atom (type-error-datum condition))
      (parachute:true (type-error-expected-type condition)))
    (let* ((circular (plist-circular-input))
           (condition (plist-caught-condition constructor circular)))
      (parachute:true (plist-dual-condition-p condition))
      (parachute:is eq circular (type-error-datum condition))
      (parachute:true (type-error-expected-type condition)))))

(parachute:define-test plist-dict.input-detachment
  (let* ((plist (list :first 1 :second 2))
         (dict (sophie-lisp:plist-dict plist)))
    (setf (car plist) :changed
          (car (cddr plist)) :also-changed)
    (core-ref-check dict :first 1 t)
    (core-ref-check dict :second 2 t)
    (core-ref-check dict :changed :missing nil :missing)))

(parachute:define-test plist-dict.equality-and-eq-lookup
  (let* ((first-key (copy-seq "same-key"))
         (last-key (copy-seq "same-key"))
         (dict (sophie-lisp:plist-dict
                (list first-key :first last-key :last)))
         (query (copy-seq "same-key")))
    (parachute:false (eq first-key last-key))
    (parachute:is = 1 (sophie-lisp:dict-size dict))
    (parachute:is eq #'sophie-lisp:equals (sophie-lisp:dict-test dict))
    (let ((values (plist-ref-values dict query :missing)))
      (parachute:is = 2 (length values))
      (parachute:is eq :last (first values))
      (parachute:true (second values))))
  (let* ((first-key (gensym "PLIST-FIRST-"))
         (second-key (gensym "PLIST-SECOND-"))
         (raw (list first-key :first second-key :second first-key :hidden))
         (view (sophie-lisp:plist-dict-view raw)))
    (parachute:true (sophie-lisp:dictp view))
    (parachute:is = 2 (sophie-lisp:dict-size view))
    (parachute:is eq #'eq (sophie-lisp:dict-test view))
    (let ((first-values (plist-ref-values view first-key :missing))
          (second-values (plist-ref-values view second-key :missing))
          (absent-values (plist-ref-values view (gensym) :missing)))
      (parachute:is = 2 (length first-values))
      (parachute:is = 2 (length second-values))
      (parachute:is eq :first (first first-values))
      (parachute:true (second first-values))
      (parachute:is eq :second (first second-values))
      (parachute:true (second second-values))
      (parachute:is = 2 (length absent-values))
      (parachute:is eq :missing (first absent-values))
      (parachute:false (second absent-values)))))

(parachute:define-test plist-dict.eq-distinct-representatives
  (let* ((first-key (copy-seq "equal-but-distinct"))
         (second-key (copy-seq "equal-but-distinct"))
         (raw (list first-key :first
                    second-key :second
                    first-key :later-first
                    second-key :later-second))
         (view (sophie-lisp:plist-dict-view raw)))
    ;; EQ-distinct keys that are EQUALS remain two canonical associations.
    (parachute:false (eq first-key second-key))
    (parachute:true (sophie-lisp:equals first-key second-key))
    (parachute:is = 2 (sophie-lisp:dict-size view))
    (let ((first-values (plist-ref-values view first-key :missing))
          (second-values (plist-ref-values view second-key :missing)))
      (parachute:is = 2 (length first-values))
      (parachute:is = 2 (length second-values))
      (parachute:is eq :first (first first-values))
      (parachute:true (second first-values))
      (parachute:is eq :second (first second-values))
      (parachute:true (second second-values)))
    ;; EQ lookup does not merge an equal but fresh indicator, and later raw
    ;; duplicates do not increase canonical multiplicity.
    (let ((fresh-values
            (plist-ref-values view (copy-seq "equal-but-distinct") :missing)))
      (parachute:is = 2 (length fresh-values))
      (parachute:is eq :missing (first fresh-values))
      (parachute:false (second fresh-values)))))

(parachute:define-test plist-dict.read-only-refusals
  (let* ((key (gensym "READ-ONLY-KEY-"))
         (raw (list key :original :other 2))
         (before (copy-list raw))
         (view (sophie-lisp:plist-dict-view raw)))
    (parachute:true (sophie-lisp:dictp view))
    (parachute:fail (sophie-lisp:dict-set view :new :value) program-error)
    (parachute:fail (sophie-lisp:dict-without view key) program-error)
    (parachute:fail
     (funcall #'(setf sophie-lisp:dict-ref) :changed view key :ignored)
     program-error)
    ;; Default batch refusal is tested by PLIST-BATCH-001, not this local gate.
    (parachute:is equal (list :original t)
                  (plist-ref-values view key :missing))
    ;; Every refusal is observed before the backing list can be changed.
    (parachute:is equal before raw)
    (parachute:is eq key (first raw))
    (parachute:is eq :original (second raw))
    (parachute:is = 2 (sophie-lisp:dict-size view))))

;; PLIST-005 is defined only in containers/conversions.lisp: malformed ALISTS
;; must not receive the private dual plist condition. Backing mutation is
;; undefined and deliberately not exercised by any of these tests.
