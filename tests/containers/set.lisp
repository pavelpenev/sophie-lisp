;;;; Set core, edit, query, and algebra tests.
(in-package #:sophie-lisp.tests)

(defclass core-set-subclass (sl:hash-set) ())
(defclass core-set-specialized (sl:hash-set) ())
(defmethod sl:hash-set-p ((object core-set-specialized)) :specialized)

(parachute:define-test hash-set.type-predicate-and-subclass-dispatch
  (let ((set (sl:hash-set nil :element)) (dict (sl:dict :element nil)))
    (parachute:true (typep set 'sl:hash-set))
    (parachute:true (sl:hash-set-p set))
    (parachute:false (sl:hash-set-p dict))
    (parachute:false (sl:dictp set))
    (parachute:false (sl:dictp (sl:hash-set)))
    (dolist (object (list nil 1 :symbol '(1 2) #() (make-hash-table)))
      (parachute:false (sl:hash-set-p object)))
    ;; ALLOCATE-INSTANCE tests normal subclass dispatch without imposing a
    ;; public MAKE-INSTANCE slot/initarg contract on persistent constructors.
    (parachute:true (sl:hash-set-p (allocate-instance (find-class 'core-set-subclass))))
    (parachute:is eq :specialized
      (sl:hash-set-p (allocate-instance (find-class 'core-set-specialized))))))
  ;; DICTP's T method and TYPE-ERROR calls on sets remain ADAPTER-004-owned;
  ;; requiring that provider here would introduce a reverse dependency.

(parachute:define-test hash-set.construction-persistence-and-callbacks
  (let* ((empty (sl:hash-set))
         (set (sl:hash-set nil nil 1 1.0 1d0 1/2 0.5 #\A #\a :test 'eql)))
    (parachute:true (typep empty 'sl:hash-set))
    (parachute:is = 0 (sl:set-size empty))
    (parachute:true (typep set 'sl:hash-set))
    ;; NIL, one, half, upper A, lower a, :TEST, EQL: seven classes.
    (parachute:is = 7 (sl:set-size set))
    (dolist (expected '(nil 1 1/2 #\A #\a :test eql))
      (parachute:true (sl:set-member expected set))))
  (let ((set (sl:hash-set)) (versions nil))
    (dotimes (key 32)
      (push set versions)
      (setf set (sl:set-add key set)))
    (loop for old in (reverse versions) for count from 0 do
      (parachute:is = count (sl:set-size old))
      (loop for key below count do
        (parachute:true (sl:set-member key old))))
    (let ((removed (sl:set-remove 0 set))
          (absent (sl:set-remove :absent set)))
      (parachute:is = 32 (sl:set-size set))
      (parachute:is = 31 (sl:set-size removed))
      (parachute:is = 32 (sl:set-size absent))
      (parachute:false (sl:set-member 0 removed))
      (parachute:true (sl:set-member 0 set))
      (dotimes (key 32)
        (parachute:true (sl:set-member key set))
        (parachute:true (sl:set-member key absent)))))
  (let* ((a (make-instance 'core-key :id 1))
         (b (make-instance 'core-key :id 2))
         (alias (make-instance 'core-key :id 1))
         (*core-hash-calls* 0) (*core-equal-calls* 0)
         (set (sl:hash-set a b alias)))
    (parachute:true (plusp *core-hash-calls*))
    (parachute:true (plusp *core-equal-calls*))
    (parachute:is = 2 (sl:set-size set))
    (parachute:true (sl:set-member a set))
    (dolist (stage '(:hash :equals))
      (let ((*core-key-exit* stage))
        (parachute:is eq stage
          (catch 'core-key-exit (sl:hash-set a alias) :returned))
        (parachute:is eq stage
          (catch 'core-key-exit (sl:set-add alias set) :returned))
        (parachute:is eq stage
          (catch 'core-key-exit (sl:set-remove alias set) :returned))))
    (parachute:is = 2 (sl:set-size set))
    (parachute:true (sl:set-member a set))))

(defun set-edit-call-one-value (function &rest arguments)
  (let ((values (multiple-value-list (apply function arguments))))
    (parachute:is = 1 (length values))
    (first values)))

(defun set-edit-model-equal-p (left right)
  ;; These fixtures group equal strings, 1 with 1.0, and all other values by EQ.
  (or (eq left right)
      (and (stringp left) (stringp right) (string= left right))
      (and (numberp left) (numberp right) (= left 1) (= right 1))))

(defun set-edit-model-unique (objects)
  (let ((model nil))
    (dolist (object objects (nreverse model))
      (unless (some (lambda (resident) (set-edit-model-equal-p object resident)) model)
        (push object model)))))

(defun set-edit-model-add (item model)
  (if (some (lambda (resident) (set-edit-model-equal-p item resident)) model)
      model
      (append model (list item))))

(defun set-edit-model-remove (item model)
  (remove-if (lambda (resident) (set-edit-model-equal-p item resident)) model))

(defun set-edit-drain (source)
  ;; The public seq protocol retains each traversal state between FIRST and
  ;; REST calls.  The finite bound prevents a broken result from hanging tests.
  (let ((view source)
        (elements nil))
    (loop for steps below 10000 do
      (if (sl:seq-emptyp view)
          (return (nreverse elements))
          (progn
            (push (sl:seq-first view) elements)
            (setf view (sl:seq-rest view))))
      finally (error "Finite set-edit result exceeded fixture bound"))))

(defun set-edit-assert-model (result model)
  (parachute:true (typep result 'sl:hash-set))
  (parachute:true (sl:hash-set-p result))
  (let ((observed (set-edit-drain result)))
    (parachute:is = (length model) (length observed))
    (dolist (expected model)
      (parachute:true
       (member expected observed :test #'eq)))
    (dolist (actual observed)
      (parachute:true
       (member actual model :test #'eq)))))


(defun set-edit-has-nil-p (result)
  (some (lambda (element) (and (null element) t))
        (set-edit-drain result)))

(parachute:define-test set-edit.generic-source-and-eagerness
  (let* ((first (copy-seq "same"))
         (alias (copy-seq "same"))
         (source (list first alias nil 1 1.0))
         (before (copy-list source))
         (source-model (set-edit-model-unique source))
         (added (set-edit-call-one-value #'sl:set-add :new source))
         (removed (set-edit-call-one-value #'sl:set-remove alias source)))
    ;; Fixture classes: {first, alias}, {NIL}, and {1, 1.0}.
    (parachute:is = 3 (length source-model))
    (set-edit-assert-model added (set-edit-model-add :new source-model))
    (set-edit-assert-model removed (set-edit-model-remove alias source-model))
    (parachute:true (set-edit-has-nil-p added))
    (parachute:is equal before source))
  ;; Both generic edits consume a finite lazy source before returning.
  (dolist (operation '(sl:set-add sl:set-remove))
    (let* ((tag (gensym "SET-EDIT-TAIL-"))
           (source (sl:lazy-cons :head
                                 (sl:lazy-seq (throw tag :tail-forced))))
           (outcome (catch tag (list :returned
                                     (multiple-value-list
                                      (funcall operation :item source))))))
      (parachute:is eq :tail-forced outcome))))

(parachute:define-test set-edit.persistent-source-preservation
  (let* ((resident (copy-seq "resident"))
         (alias (copy-seq "resident"))
         (old (sl:hash-set resident nil 1))
         (old-model (set-edit-model-unique (list resident nil 1)))
         (added (set-edit-call-one-value #'sl:set-add :new old))
         (duplicate (set-edit-call-one-value #'sl:set-add alias old))
         (removed (set-edit-call-one-value #'sl:set-remove alias added))
         (absent (set-edit-call-one-value #'sl:set-remove :absent old)))
    (set-edit-assert-model added (set-edit-model-add :new old-model))
    (set-edit-assert-model duplicate old-model)
    (set-edit-assert-model removed (set-edit-model-remove alias
                                                          (set-edit-model-add
                                                           :new old-model)))
    (set-edit-assert-model absent old-model)
    ;; Duplicate/absent edits may reuse the input, but must at least preserve
    ;; the same observations and cannot mutate the retained old version.
    (parachute:true (set-edit-has-nil-p old))
    (set-edit-assert-model old old-model)))

(parachute:define-test set-edit.non-seqable-rejection
  ;; A non-seqable is an argument error for the generic fallback, independent
  ;; of any result representation.
  (parachute:fail (sl:set-add :item 42) type-error)
  (parachute:fail (sl:set-remove :item 42) type-error))

(defun set-query-call-one-value (function &rest arguments)
  (let ((values (multiple-value-list (apply function arguments))))
    (parachute:is = 1 (length values))
    (first values)))

(defun set-query-model-unique (objects)
  (let ((model nil))
    (dolist (object objects (nreverse model))
      (unless (some (lambda (resident) (set-edit-model-equal-p object resident)) model)
        (push object model)))))

(defun set-query-drain (source)
  ;; The public seq protocol retains each traversal state between FIRST and
  ;; REST calls.  The finite bound prevents a broken result from hanging tests.
  (let ((view source)
        (elements nil))
    (loop for steps below 10000 do
      (if (sl:seq-emptyp view)
          (return (nreverse elements))
          (progn
            (push (sl:seq-first view) elements)
            (setf view (sl:seq-rest view))))
      finally (error "Finite set-query result exceeded fixture bound"))))

(defclass set-query-size-sentinel (sl:hash-set) ())

(defmethod sl:seq-first :before ((source set-query-size-sentinel))
  (declare (ignore source))
  (error "SET-SIZE unexpectedly traversed FIRST"))

(defmethod sl:seq-rest :before ((source set-query-size-sentinel))
  (declare (ignore source))
  (error "SET-SIZE unexpectedly traversed REST"))

;; A minimal conforming read-only dict fixture owned by this unit.  The
;; inherited SEQ-REF protocol method supplies the required indexed operation.
(defclass set-query-readonly ()
  ((pairs :initarg :pairs :reader set-query-pairs)
   (test :initarg :test :reader set-query-test)))

(defmethod sl:dictp ((source set-query-readonly)) t)
(defmethod sl:dict-test ((source set-query-readonly)) (set-query-test source))
(defmethod sl:dict-size ((source set-query-readonly))
  (length (set-query-pairs source)))
(defmethod sl:dict-ref ((source set-query-readonly) key &optional default)
  (let ((pair (assoc key (set-query-pairs source)
                   :test (set-query-test source))))
    (if pair (values (cdr pair) t) (values default nil))))
(defmethod sl:seqablep ((source set-query-readonly)) t)
(defmethod sl:seq-length ((source set-query-readonly))
  (length (set-query-pairs source)))
(defmethod sl:seq-emptyp ((source set-query-readonly))
  (null (set-query-pairs source)))
(defmethod sl:seq-first ((source set-query-readonly))
  (let ((pair (car (set-query-pairs source))))
    (when pair (sl:map-entry (car pair) (cdr pair)))))
(defmethod sl:seq-rest ((source set-query-readonly))
  (mapcar (lambda (pair) (sl:map-entry (car pair) (cdr pair)))
          (cdr (set-query-pairs source))))

(parachute:define-test set-query.membership-and-dict-membership
  (let* ((first (copy-seq "same"))
         (alias (copy-seq "same"))
         (set (sl:hash-set nil first alias 1 1.0))
         (source (list nil first alias 1 1.0)))
    ;; NIL is a positive element, not a missing-value sentinel.  Numeric and
    ;; string aliases exercise the specified EQUALS relation.
    (parachute:true (set-query-call-one-value #'sl:set-member nil set))
    (parachute:true (set-query-call-one-value #'sl:set-member alias set))
    (parachute:true (set-query-call-one-value #'sl:set-member 1.0 set))
    (parachute:false (set-query-call-one-value #'sl:set-member :absent set))
    (parachute:true (set-query-call-one-value #'sl:set-member alias source))
    (parachute:false (set-query-call-one-value #'sl:set-member :absent source))

    ;; DICT-MEMBER is a public two-value key-membership operation.  In
    ;; particular, a present NIL value must remain distinct from absence.
    (let ((values (multiple-value-list
                   (sl:dict-member (sl:dict :present nil) :present))))
      (parachute:is = 2 (length values))
      (parachute:true (first values))
      (parachute:is eq nil (second values)))
    (let ((values (multiple-value-list
                   (sl:dict-member (sl:dict :present nil) :absent))))
      (parachute:is = 2 (length values))
      (parachute:false (first values))
      (parachute:is eq nil (second values)))

    ;; A plist view uses first-match EQ lookup even when its raw plist repeats
    ;; the same indicator.
    (let* ((key (gensym "SET-QUERY-PLIST-KEY-"))
           (view (sl:plist-dict-view (list key :first key :hidden)))
           (values (multiple-value-list (sl:dict-member view key))))
      (parachute:is = 2 (length values))
      (parachute:true (first values))
      (parachute:is eq :first (second values))
      (parachute:is eq #'eq (sl:dict-test view)))

    ;; Native dictionaries retain their standard test designator as a symbol.
    (let* ((key (gensym "SET-QUERY-HASH-KEY-"))
           (table (make-hash-table :test 'eql)))
      (setf (gethash key table) nil)
      (let ((values (multiple-value-list (sl:dict-member table key))))
        (parachute:is = 2 (length values))
        (parachute:true (first values))
        (parachute:is eq nil (second values)))
      (parachute:is eq 'eql (sl:dict-test table)))

    ;; A conforming custom dict gets the derived default method through its
    ;; DICT-REF method; no DICT-MEMBER method is defined by this test.
    (let* ((key (gensym "SET-QUERY-CUSTOM-KEY-"))
           (custom (make-instance 'set-query-readonly
                                  :pairs (list (cons key nil))
                                  :test 'eq))
           (values (multiple-value-list (sl:dict-member custom key))))
      (parachute:is = 2 (length values))
      (parachute:true (first values))
      (parachute:is eq nil (second values)))

    ;; DICT-MEMBER tests keys, whereas SET-MEMBER on a dict tests its MAP-ENTRY
    ;; elements.  The key itself is absent from the latter set view.
    (let* ((dict (sl:dict :key nil))
           (entry (first (set-query-drain dict))))
      (let ((values (multiple-value-list (sl:dict-member dict :key))))
        (parachute:is = 2 (length values))
        (parachute:true (first values))
        (parachute:is eq nil (second values)))
      (parachute:false (set-query-call-one-value #'sl:set-member :key dict))
      (parachute:true (set-query-call-one-value #'sl:set-member entry dict))))
  (parachute:fail (sl:dict-member :not-a-dict :key) type-error)
  ;; A successful finite match must not force an unbounded suffix.
  (let* ((tag (gensym "SET-MEMBER-TAIL-"))
         (source (sl:lazy-cons :hit
                               (sl:lazy-seq (throw tag :tail-forced))))
         (outcome (catch tag
                    (list :returned
                          (multiple-value-list
                           (sl:set-member :hit source))))))
    (parachute:is eq :returned (first outcome))
    (parachute:is = 1 (length (second outcome)))
    (parachute:true (first (second outcome)))))

(parachute:define-test set-query.size-and-metadata
  (let* ((first (copy-seq "same"))
         (alias (copy-seq "same"))
         (source (list nil nil 1 1.0 first alias :other))
         (model (set-query-model-unique source))
         (count (set-query-call-one-value #'sl:set-size source)))
    ;; Fixture classes: {NIL}, {1, 1.0}, {first, alias}, and {:other}.
    (parachute:is = 4 (length model))
    (parachute:is = (length model) count)
    (parachute:is = 7 (length source))
    (parachute:true (< count (length source))))
  ;; The HASH-SET method reads maintained metadata, not its seq protocol.
  (let ((source (change-class (sl:hash-set nil :one :two)
                              'set-query-size-sentinel)))
    (parachute:is = 3 (set-query-call-one-value #'sl:set-size source))))

(parachute:define-test set-query.subset-eagerness-and-validation
  (let* ((first (copy-seq "same"))
         (alias (copy-seq "same"))
         (left (list nil 1 first alias))
         (right (list 0 nil 1.0 (copy-seq "same") :extra)))
    (parachute:true (set-query-call-one-value #'sl:set-subset-p left right))
    (parachute:false
     (set-query-call-one-value #'sl:set-subset-p right left)))
  (parachute:true (set-query-call-one-value #'sl:set-subset-p nil '(1 2)))
  (parachute:false (set-query-call-one-value #'sl:set-subset-p '(1) nil))
  ;; Subset validation is eager on both operands: neither an empty first
  ;; operand nor an already-decisive first element licenses skipping a tail.
  (let ((tag (gensym "SET-SUBSET-FIRST-"))
        (source nil))
    (setf source (sl:lazy-cons :present
                                (sl:lazy-seq (throw tag :first-tail-forced))))
    (parachute:is eq :first-tail-forced
                  (catch tag (sl:set-subset-p source '(:present)))))
  (let* ((tag (gensym "SET-SUBSET-SECOND-"))
         (source (sl:lazy-seq (throw tag :second-forced))))
    (parachute:is eq :second-forced
                  (catch tag (sl:set-subset-p nil source))))
  (parachute:fail (sl:set-member :x 42) type-error)
  (parachute:fail (sl:set-size 42) type-error)
  (parachute:fail (sl:set-subset-p 42 nil) type-error)
  (parachute:fail (sl:set-subset-p nil 42) type-error))

(defun d-set-algebra-drain (source)
  (loop with view = source for step below 10000
        until (sl:seq-emptyp view)
        collect (sl:seq-first view)
        do (setf view (sl:seq-rest view))
        finally (unless (sl:seq-emptyp view)
                  (parachute:true nil "D-SET-ALGEBRA-DRAIN exceeded its finite fixture bound"))))

(defun d-set-algebra-counted-source (counts element)
  (sl:lazy-seq
    (progn
      (incf (car counts))
      (sl:lazy-cons
       element
       (sl:lazy-seq
         (progn
           (incf (cdr counts))
           nil))))))

(defun d-set-algebra-assert-result (result)
  (parachute:true (typep result 'sl:hash-set))
  (parachute:true (sl:hash-set-p result)))

(parachute:define-test set-algebra.eager-consumption-and-arity
  ;; Each operation eagerly consumes every operand, including operands whose
  ;; contents are not needed to decide an intersection or subtraction.
  (dolist (operation (list #'sl:set-union
                           #'sl:set-intersection
                           #'sl:set-minus))
    (let* ((counts-1 (cons 0 0))
           (counts-2 (cons 0 0))
           (counts-3 (cons 0 0))
           (first (d-set-algebra-counted-source counts-1 :element))
           (second (d-set-algebra-counted-source counts-2 :element))
           (third (d-set-algebra-counted-source counts-3 :element))
           (result (funcall operation first second third)))
      (d-set-algebra-assert-result result)
      (parachute:is = 1 (car counts-1))
      (parachute:is = 1 (cdr counts-1))
      (parachute:is = 1 (car counts-2))
      (parachute:is = 1 (cdr counts-2))
      (parachute:is = 1 (car counts-3))
      (parachute:is = 1 (cdr counts-3))))
  ;; An empty first operand does not excuse skipping the finite later operand:
  ;; both operations still consume that operand all the way to its end.
  (dolist (operation (list #'sl:set-intersection #'sl:set-minus))
    (let* ((counts (cons 0 0))
           (later (d-set-algebra-counted-source counts :later))
           (result (funcall operation nil later)))
      (d-set-algebra-assert-result result)
      (parachute:is = 1 (car counts))
      (parachute:is = 1 (cdr counts))))
  (parachute:fail (sl:set-union '(1)) program-error)
  (parachute:fail (sl:set-intersection '(1)) program-error)
  (parachute:fail (sl:set-minus '(1)) program-error))

(parachute:define-test set-algebra.results-and-representatives
  (let* ((left-name (copy-seq "left-name"))
         (middle-name (copy-seq "left-name"))
         (right-name (copy-seq "left-name"))
         (left (list left-name 1 2 :keep))
         (middle (vector middle-name 1.0 2 3))
         (right (list right-name 2 4))
         (union (sl:set-union left middle right))
         (intersection (sl:set-intersection left middle right))
         (minus (sl:set-minus left middle right)))
    (parachute:false (eq left-name middle-name))
    (parachute:true (sl:equals left-name middle-name))
    (dolist (result (list union intersection minus))
      (d-set-algebra-assert-result result))
    ;; Union inserts all elements under EQUALS; 1 and 1.0 coalesce.
    (parachute:is = 6 (sl:set-size union))
    (dolist (item (list left-name 1 2 :keep 3 4))
      (parachute:true (sl:set-member item union)))
    ;; Intersection retains the members common to every operand.
    (parachute:is = 2 (sl:set-size intersection))
    (parachute:true (sl:set-member left-name intersection))
    (parachute:false (sl:set-member 1 intersection))
    (parachute:true (sl:set-member 2 intersection))
    (parachute:false
     (sl:set-member :keep intersection))
    ;; Minus removes the union of all later operands from the first.
    (parachute:is = 1 (sl:set-size minus))
    (parachute:true (sl:set-member :keep minus))
    (parachute:false (sl:set-member left-name minus))
    (parachute:false (sl:set-member 1 minus))
    ;; All three operations leave every input unchanged.
    (parachute:is = 4 (length left))
    (parachute:is = 4 (length middle))
    (parachute:is = 3 (length right))))

(parachute:define-test set-algebra.dictionary-entry-elements
  ;; A dict contributes MAP-ENTRY objects, not its keys.  An EQ table can hold
  ;; two EQ-distinct but EQUAL strings, so this also checks that its custom key
  ;; test is not reused as the set operation's equality test.
  (let* ((key-1 (copy-seq "same-key"))
         (key-2 (copy-seq "same-key"))
         (value-1 (list :first-value))
         (value-2 (list :second-value))
         (table (make-hash-table :test #'eq))
         (result nil))
    (setf (gethash key-1 table) value-1
          (gethash key-2 table) value-2)
    (setf result (sl:set-union table nil))
    (d-set-algebra-assert-result result)
    (parachute:is = 2 (sl:dict-size table))
    (parachute:is = 2 (sl:set-size result))
    (let ((entries (d-set-algebra-drain result)))
      (parachute:is = 2 (length entries))
      (dolist (entry entries)
        (parachute:true (typep entry 'sl:map-entry)))
      (parachute:true
       (some (lambda (entry)
               (and (sl:equals (sl:entry-key entry) key-1)
                    (sl:equals (sl:entry-value entry) value-1)))
             entries))
      (parachute:true
       (some (lambda (entry)
               (and (sl:equals (sl:entry-key entry) key-2)
                    (sl:equals (sl:entry-value entry) value-2)))
             entries)))
    ;; A separately allocated string and mathematical numeric aliases are
    ;; coalesced by EQUALS in every set-producing operation.
    (let* ((alias (copy-seq "same-key"))
           (numeric (sl:set-union '(1) '(1.0)))
           (inter (sl:set-intersection (list alias) (list key-1)))
           (difference (sl:set-minus (list alias :other) (list key-1))))
      (parachute:is = 1 (sl:set-size numeric))
      (parachute:is = 1 (sl:set-size inter))
      (parachute:is = 1 (sl:set-size difference))
      (parachute:true (sl:set-member alias inter))
      (parachute:true (sl:set-member :other difference)))
    ;; None of the result operations mutates the table or its resident objects.
    (parachute:is eq value-1 (gethash key-1 table))
    (parachute:is eq value-2 (gethash key-2 table))))

(parachute:define-test set-algebra.operand-validation
  ;; Every operand position is in the any-seqable domain.
  (parachute:fail (sl:set-union 42 nil) type-error)
  (parachute:fail (sl:set-union nil 42) type-error)
  (parachute:fail (sl:set-union nil nil 42) type-error)
  (parachute:fail (sl:set-intersection 42 nil) type-error)
  (parachute:fail (sl:set-intersection nil 42) type-error)
  (parachute:fail (sl:set-intersection nil nil 42) type-error)
  (parachute:fail (sl:set-minus 42 nil) type-error)
  (parachute:fail (sl:set-minus nil 42) type-error)
  (parachute:fail (sl:set-minus nil nil 42) type-error))
