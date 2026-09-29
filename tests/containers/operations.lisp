;;;; Independent Chapter 9 9.1.12--14, DICT-MERGE and DICT-MERGE*.
;;;; BATCH-* fixtures are dependency-owned finite, ordered reference models.
(in-package #:sophie-lisp.tests)
;;;; BATCH-* and UPDATE-MODEL-* fixtures live in tests/containers/integration.lisp,
;;;; which loads before this operations unit.

(defvar *merge-visits* nil)
(defclass merge-ordered (batch-configurable) ())
(defmethod sl:seq-first ((source merge-ordered))
  (push (batch-tag source) *merge-visits*)
  (call-next-method))
(defmethod sl:seq-rest ((source merge-ordered))
  (labels ((tail (pairs)
             (sl:lazy-seq
              (when pairs
                (push (batch-tag source) *merge-visits*)
                (sl:lazy-cons (sl:map-entry (caar pairs) (cdar pairs))
                              (tail (cdr pairs)))))))
    (tail (cdr (batch-pairs source)))))

(parachute:define-test dict-merge.argument-validation
  (let ((source (make-instance 'batch-child :pairs '((:a . 1))))
        (*batch-forbid-traversal* t) (*batch-events* nil))
    (dolist (bad (list nil 3 '((:a . 1)) (list (sl:map-entry :a 1))
                       (sl:hash-set :a)))
      (parachute:fail (sl:dict-merge source bad) type-error)
      (parachute:fail (sl:dict-merge bad source) type-error))
    (parachute:fail (sl:dict-merge source source :collision :unknown) program-error)
    ;; The removed keyword is subject to ordinary CL keyword checking; ECL's
    ;; CLOS accepts unknown GF keywords, so the rejection is asserted only
    ;; where the host enforces it.
    (when (dict-unknown-keywords-rejected-p)
      (parachute:fail (sl:dict-merge source source :test 'eql) program-error))
    (parachute:false *batch-events*))
  ;; Same dynamic class, but non-EQ test designators: selection MUST fall back
  ;; before checking 1 versus 1.0, even though both source tests are EQL-like.
  (let ((left (make-instance 'batch-child :test 'eql :pairs '((1 . :one))))
        (right (make-instance 'batch-child :test #'eql :pairs '((1.0 . :float)))))
    (parachute:fail (sl:dict-merge left right :collision :error) program-error)
    (parachute:true (typep (sl:dict-merge left right) 'sl:dict)))
  (dolist (test '(eq eql equal equalp))
    (let* ((left (make-hash-table :test test)) (right (make-hash-table :test test))
           (result (sl:dict-merge left right)))
      (parachute:true (hash-table-p result))
      (parachute:is eq test (sl:dict-test result))
      (parachute:false (or (eq result left) (eq result right))))))

(parachute:define-test dict-merge.traversal-and-collision
  (let* ((left (make-instance 'merge-ordered :tag :left :pairs '((:a . 1) (:b . 2))))
         (right (make-instance 'merge-ordered :tag :right :pairs '((:c . 3) (:d . 4))))
         (*merge-visits* nil) (*batch-events* nil)
         (result (sl:dict-merge left right :collision :error)))
    (parachute:is equal '(:left :left :right :right) (reverse *merge-visits*))
    (parachute:is = 4 (sl:dict-size result))
    (parachute:is = 1 (length *batch-events*)))
  ;; A valid EQL source contains two numeric keys that collapse in the selected
  ;; EQUALS result. Test both operand positions, without choosing a survivor.
  (let ((source (make-instance 'batch-child :test 'eql
                               :pairs '((1 . :integer) (1.0 . :float)))))
    (parachute:fail (sl:dict-merge source (sl:dict) :collision :error) program-error)
    (parachute:fail (sl:dict-merge (sl:dict) source :collision :error) program-error)
    (parachute:is = 1 (sl:dict-size (sl:dict-merge source (sl:dict)))))
  (let* ((left (make-instance 'merge-ordered :tag :left :pairs '((:same . :left))))
         (right (make-instance 'merge-ordered :tag :right
                               :pairs '((:same . :right) (:untouched . :later))))
         (*merge-visits* nil) (*batch-events* nil) (returned nil))
    (parachute:fail
     (progn (sl:dict-merge left right :collision :error) (setf returned t)) program-error)
    (parachute:false returned)
    (parachute:false *batch-events*)
    (parachute:is equal '(:left :right) (reverse *merge-visits*))
    (parachute:is eq :left (sl:dict-ref left :same))
    (parachute:is eq :right (sl:dict-ref right :same))))

(parachute:define-test dict-merge.result-selection
  (let* ((first (copy-seq "same")) (last (copy-seq "same"))
         (value (list :last))
         (left (make-instance 'batch-child :test 'equal :tag :configured
                             :pairs (list (cons first :first))))
         (right (make-instance 'batch-child :test 'equal :tag :configured
                              :pairs (list (cons last value))))
         (*batch-events* nil) (result (sl:dict-merge left right)))
    (parachute:is eq (class-of left) (class-of result))
    (parachute:is eq 'equal (sl:dict-test result))
    (parachute:is eq :configured (batch-tag result))
    (parachute:is = 1 (length *batch-events*))
    (parachute:is eq 'equal (third (first *batch-events*)))
    (batch-check-one result last value)
    (parachute:is eq first (caar (batch-pairs left)))
    (parachute:is eq :first (sl:dict-ref left first))
    (parachute:is eq last (caar (batch-pairs right))))
  (dolist (class '(batch-readonly batch-aux-only))
    (let* ((*batch-events* nil)
           (left (make-instance class :pairs '((:a . 1))))
           (right (make-instance class :pairs '((:b . 2))))
           (result (sl:dict-merge left right)))
      (parachute:true (typep result 'sl:dict))
      (parachute:is = 2 (sl:dict-size result))
      (parachute:false *batch-events*)))
  (let ((result (sl:dict-merge (sl:plist-dict-view '(:a 1))
                              (sl:plist-dict-view '(:b 2)))))
    (parachute:true (typep result 'sl:dict)))
  ;; Mutable reconstruction must replace the resident key as well as its value.
  (let* ((k1 (copy-seq "key")) (k2 (copy-seq "key"))
         (left (make-hash-table :test 'equal)) (right (make-hash-table :test 'equal)))
    (setf (gethash k1 left) :old (gethash k2 right) :new)
    (let ((result (sl:dict-merge left right)))
      (batch-check-one result k2 :new)
      (parachute:is eq :old (gethash k1 left))
      (parachute:false (or (eq result left) (eq result right))))))

(parachute:define-test dict-merge.multiple-operands
  (parachute:fail (funcall #'sl:dict-merge*) program-error)
  (parachute:fail (funcall #'sl:dict-merge* (sl:dict)) program-error)
  (let ((a (make-instance 'batch-child :test 'equal :pairs '((:k . 1))))
        (b (make-instance 'batch-child :test 'equal :pairs '((:k . 2))))
        (c (make-instance 'batch-child :test 'equal :pairs '((:k . 3)))))
    (let* ((*batch-events* nil) (result (sl:dict-merge* a b c)))
      (parachute:is eq (class-of a) (class-of result))
      (parachute:is eq 'equal (sl:dict-test result))
      (parachute:is = 3 (sl:dict-ref result :k))
      (parachute:is = 2 (length *batch-events*)))
    (let ((*batch-forbid-traversal* t) (*batch-events* nil))
      (parachute:fail (sl:dict-merge* a b :collision :error) type-error)
      (parachute:fail (sl:dict-merge* a b c 12) type-error)
      (parachute:false *batch-events*))
    (let ((result (sl:dict-merge* a b (sl:dict :k 4) c)))
      (parachute:true (typep result 'sl:dict))
      (parachute:is eq #'sl:equals (sl:dict-test result))
      (parachute:is = 3 (sl:dict-ref result :k)))))

(parachute:define-test dict-merge-with.combines-values
  (dolist (left (list (sl:dict :a 1 :b 2)
                      (let ((table (make-hash-table :test 'eq)))
                        (setf (gethash :a table) 1
                              (gethash :b table) 2)
                        table)
                      (sl:ordered-dict :a 1 :b 2)))
    (let ((result (sl:dict-merge-with #'+ left (sl:dict :b 10 :c 3))))
      (parachute:is = 3 (sl:dict-size result))
      (parachute:true (typep result 'sl:dict))
      (parachute:is = 1 (sl:dict-ref result :a))
      (parachute:is = 12 (sl:dict-ref result :b))
      (parachute:is = 3 (sl:dict-ref result :c))))
  (let ((left (sl:ordered-dict :a 1 :b 2))
        (right (sl:ordered-dict :b 10 :c 3)))
    (parachute:true
     (sl:ordered-dict-p (sl:dict-merge-with #'+ left right)))))

(parachute:define-test dict-merge-with.collision-callback
  ;; EQL source keys 1 and 1.0 coalesce under the selected EQUALS result test.
  (let ((source (make-hash-table :test 'eql)))
    (setf (gethash 1 source) 4
          (gethash 1.0 source) 5)
    (let ((result (sl:dict-merge-with #'+ source (sl:dict))))
      (parachute:true (typep result 'sl:dict))
      (parachute:is = 2 (hash-table-count source))
      (parachute:is = 4 (gethash 1 source))
      (parachute:is = 1 (sl:dict-size result))
      (parachute:is = 9 (sl:dict-ref result 1))))
  (let* ((left (sl:ordered-dict :k 1))
         (right (sl:ordered-dict :k 2))
         (calls nil)
         (result (sl:dict-merge-with
                  (lambda (old new)
                    (push (list old new) calls)
                    (list old new))
                  left right)))
    (parachute:is equal '((1 2)) calls)
    (parachute:true (sl:ordered-dict-p result))
    (parachute:is = 1 (sl:dict-size result))
    (parachute:is = 1 (sl:dict-ref left :k))
    (parachute:is = 2 (sl:dict-ref right :k))
    (parachute:is equal '(:k) (mapcar #'car (sl:dict-alist result)))
    (parachute:is equal '(1 2) (sl:dict-ref result :k))))

(parachute:define-test dict-merge-with.order-and-nil-values
  (let* ((left (sl:ordered-dict :a 1 :b 2))
         (right (sl:ordered-dict :b 10 :c 3))
         (result (sl:dict-merge-with (lambda (old new) (- old new)) left right)))
    (parachute:true (sl:ordered-dict-p result))
    (parachute:is = 3 (sl:dict-size result))
    (parachute:is = 1 (sl:dict-ref result :a))
    (parachute:is = 3 (sl:dict-ref result :c))
    (parachute:is = 2 (sl:dict-ref left :b))
    (parachute:is = 10 (sl:dict-ref right :b))
    (parachute:is = -8 (sl:dict-ref result :b))
    (parachute:is equal '(:a :b :c)
                  (mapcar #'car (sl:dict-alist result))))
  (let* ((left (sl:dict :a nil))
         (right (sl:dict :a 7))
         (result (sl:dict-merge-with (lambda (old new) (list old new)) left right)))
    (parachute:true (typep result 'sl:dict))
    (parachute:is = 1 (sl:dict-size result))
    (parachute:is equal '(nil t) (multiple-value-list (sl:dict-ref left :a)))
    (parachute:is = 7 (sl:dict-ref right :a))
    (parachute:is equal '(nil 7) (sl:dict-ref result :a))))

(parachute:define-test dict-merge-with.callback-on-collisions
  (dolist (operands (list (list (sl:dict) (sl:dict))
                          (list (sl:dict) (sl:dict :a 1))
                          (list (sl:dict :a 1) (sl:dict))))
    (destructuring-bind (left right) operands
      (let* ((calls 0)
             (left-size (sl:dict-size left))
             (right-size (sl:dict-size right))
             (result (sl:dict-merge-with
                      (lambda (old new) (incf calls) (+ old new))
                      left right)))
        (parachute:is = (if (and (= (sl:dict-size left) 1)
                                (= (sl:dict-size right) 1))
                            1 0)
                      calls)
        (parachute:is = left-size (sl:dict-size left))
        (parachute:is = right-size (sl:dict-size right))
        (parachute:is = (+ (sl:dict-size left) (sl:dict-size right)
                           (- calls))
                      (sl:dict-size result))))))

(defclass merge-unhashable-key () ())

(defmethod sl:hash-code ((key merge-unhashable-key))
  (declare (ignore key))
  (error "Unhashable merge key"))

(defmethod sl:equals ((left merge-unhashable-key) (right merge-unhashable-key))
  (declare (ignore left right))
  nil)

(parachute:define-test dict-merge-with.accumulation-order-and-identity
  (let* ((first (copy-seq "key"))
         (second (copy-seq "key"))
         (third (copy-seq "key"))
         (left (make-instance 'batch-child :test #'sl:equals
                              :pairs (list (cons :before 0) (cons first 1)
                                           (cons second 2) (cons :after 3))))
         (right (make-instance 'batch-child :test #'sl:equals
                               :pairs (list (cons third 4) (cons :last 5))))
         (calls nil)
         (result (sl:dict-merge-with
                  (lambda (old incoming)
                    (push (list old incoming) calls)
                    (- old incoming))
                  left right))
         (pairs (batch-pairs result)))
    (parachute:is equal '((1 2) (-1 4)) (reverse calls))
    (parachute:is equal '(:before "key" :after :last) (mapcar #'car pairs))
    (parachute:is eq third (car (second pairs)))
    (parachute:is = -5 (cdr (second pairs)))))

(parachute:define-test dict-merge-with.indexed-accumulation-order-and-identity
  ;; Six fixed entries plus fillers give threshold (linear) and threshold+1 (indexed).
  (let ((threshold sophie-lisp.internal::+dict-merge-with-index-threshold+))
    (dolist (extra (list (- threshold 6) (- threshold 5)))
      (let* ((first (copy-seq "key"))
             (second (copy-seq "key"))
             (third (copy-seq "key"))
             (left (make-instance 'batch-child :test #'sl:equals
                                  :pairs (append (list (cons :before 0)
                                                       (cons first 1)
                                                       (cons second 2)
                                                       (cons :after 3))
                                                 (loop for index below extra
                                                       collect (cons index index)))))
             (right (make-instance 'batch-child :test #'sl:equals
                                   :pairs (list (cons third 4) (cons :last 5))))
             (calls nil)
             (result (sl:dict-merge-with
                      (lambda (old incoming)
                        (push (list old incoming) calls)
                        (- old incoming))
                      left right))
             (pairs (batch-pairs result)))
        (parachute:is equal '((1 2) (-1 4)) (reverse calls))
        (parachute:is = (+ extra 4) (length pairs))
        (parachute:is equal '(:before "key" :after) (mapcar #'car (subseq pairs 0 3)))
        (parachute:is eq :last (caar (last pairs)))
        (parachute:is eq third (car (second pairs)))
        (parachute:is = -5 (cdr (second pairs)))))))

(defclass merge-index-key ()
  ((label :initarg :label :reader merge-index-label)
   (matches :initarg :matches :reader merge-index-matches)
   (hashable-p :initarg :hashable-p :reader merge-index-hashable-p)))

(defmethod sl:equals ((left merge-index-key) (right merge-index-key))
  (not (null (intersection (merge-index-matches left)
                           (merge-index-matches right)))))

(defmethod sl:hash-code ((key merge-index-key))
  (if (merge-index-hashable-p key)
      17
      (error "Unhashable merge index key")))

(parachute:define-test dict-merge-with.indexed-earliest-bucket-and-overflow
  ;; A deliberately non-transitive user matcher permits two distinct residents
  ;; to match the incoming key. The first encounter must win across both lists.
  (dolist (overflow-first '(t nil))
    (let* ((overflow (make-instance 'merge-index-key :label :overflow
                                    :matches '(:overflow) :hashable-p nil))
           (bucket (make-instance 'merge-index-key :label :bucket
                                  :matches '(:bucket) :hashable-p t))
           (incoming (make-instance 'merge-index-key :label :incoming
                                    :matches '(:overflow :bucket) :hashable-p t))
           (first (if overflow-first overflow bucket))
           (second (if overflow-first bucket overflow))
           (fillers (loop for index below sophie-lisp.internal::+dict-merge-with-index-threshold+
                          collect (cons index index)))
           (left (make-instance 'batch-child :test #'sl:equals
                                :pairs (append (list (cons first 10) (cons second 20))
                                               fillers)))
           (right (make-instance 'batch-child :test #'sl:equals
                                 :pairs (list (cons incoming 30))))
           (calls nil)
           (result (sl:dict-merge-with
                    (lambda (old new) (push (list old new) calls) (+ old new))
                    left right)))
      (parachute:is equal '((10 30)) (reverse calls))
      (parachute:is = (1+ (length fillers)) (length (batch-pairs result)))
      (parachute:is eq second (caar (batch-pairs result)))
      (parachute:is = 20 (cdar (batch-pairs result)))
      (parachute:is = 10 (cdar (batch-pairs left)))
      (parachute:is = 20 (cdadr (batch-pairs left))))))

(parachute:define-test dict-merge-with.hash-failure-overflow
  (let* ((first (make-instance 'merge-unhashable-key))
         (second (make-instance 'merge-unhashable-key))
         (left (make-instance 'batch-child :test #'sl:equals
                              :pairs (list (cons first :a))))
         (right (make-instance 'batch-child :test #'sl:equals
                               :pairs (list (cons second :b))))
         (result (sl:dict-merge-with #'list left right)))
    (parachute:is = 2 (length (batch-pairs result)))
    (parachute:is eq first (caar (batch-pairs result)))
    (parachute:is eq second (caadr (batch-pairs result)))))

(parachute:define-test dict-merge-with.lazy-key-does-not-force
  (let* ((forces 0)
         (key (sl:lazy-seq (progn (incf forces) (sl:lazy-cons :key nil))))
         (left (make-instance 'batch-child :test #'sl:equals
                              :pairs (list (cons key :old))))
         (right (make-instance 'batch-child :test #'sl:equals :pairs nil))
         (before forces)
         (result (sl:dict-merge-with #'list left right)))
    (parachute:is = before forces)
    (parachute:is eq key (caar (batch-pairs result))))
  (let* ((forces 0)
         (key (sl:lazy-seq (progn (incf forces) (sl:lazy-cons :key nil))))
         (left (sl:dict key :old))
         (before forces)
         (result (sl:dict-merge-with #'list left (sl:dict))))
    (parachute:is = before forces)
    (parachute:is = 1 (sl:dict-size result))))

(defun d-path-read-values (dict keys &optional (default nil default-supplied-p))
  (if default-supplied-p
      (multiple-value-list (sl:dict-ref-in dict keys default))
      (multiple-value-list (sl:dict-ref-in dict keys))))

;; A read-only user dict with EQL keys and the complete required seq protocol.
;; Only lookup is instrumented; no standardized methods are replaced.
(defclass d-path-read-logging-dict ()
  ((table :initform (make-hash-table :test 'eql) :reader d-path-read-table)
   (events :initarg :events :reader d-path-read-events)))

(defmethod sl:dictp ((dict d-path-read-logging-dict)) t)

(defmethod sl:dict-ref ((dict d-path-read-logging-dict) key &optional default)
  (push (list :lookup key) (car (d-path-read-events dict)))
  (gethash key (d-path-read-table dict) default))

(defmethod sl:dict-test ((dict d-path-read-logging-dict)) 'eql)

(defmethod sl:dict-size ((dict d-path-read-logging-dict))
  (hash-table-count (d-path-read-table dict)))

(defmethod sl:seqablep ((dict d-path-read-logging-dict)) t)

(defmethod sl:seq-emptyp ((dict d-path-read-logging-dict))
  (zerop (sl:dict-size dict)))

(defmethod sl:seq-first ((dict d-path-read-logging-dict))
  (sl:seq-first (d-path-read-table dict)))

(defmethod sl:seq-rest ((dict d-path-read-logging-dict))
  (sl:seq-rest (d-path-read-table dict)))

(defmethod sl:seq-length ((dict d-path-read-logging-dict))
  (sl:dict-size dict))

(defun d-path-read-logged-path (events)
  (sl:lazy-seq
    (progn
      (push :first (car events))
      (sl:lazy-cons
       :absent
       (sl:lazy-seq
         (progn
           (push :second (car events))
           (sl:lazy-cons
            :later
            (sl:lazy-seq
              (progn
                (push :end (car events))
                nil)))))))))

(parachute:define-test dict-ref-in.path-validation-and-forcing
  ;; The complete path is forced before lookup.  In particular, the later
  ;; component is forced even though the first component is absent.
  (let* ((forced-components nil)
         (root (sl:dict :present (sl:dict :leaf :value)))
         (path
           (sl:lazy-seq
             (progn
               (push :first forced-components)
               (sl:lazy-cons
                :absent
                (sl:lazy-seq
                  (progn
                    (push :second forced-components)
                    (sl:lazy-cons
                     :later
                     (sl:lazy-seq
                       (progn
                         (push :end forced-components)
                         nil)))))))))
         (default (list :default))
         (values (d-path-read-values root path default)))
    (parachute:is equal '(:first :second :end) (reverse forced-components))
    (parachute:is = 2 (length values))
    (parachute:is eq default (first values))
    (parachute:false (second values)))
  (parachute:fail (sl:dict-ref-in (sl:dict) nil) program-error)
  (parachute:fail (sl:dict-ref-in (sl:dict) 42) type-error)
  ;; A dotted path is not a finite proper seqable path.
  (parachute:fail (sl:dict-ref-in (sl:dict) (cons :key :dotted)) type-error)
  (parachute:fail (sl:dict-ref-in 42 '(:key)) type-error)
  ;; Shared event order proves all forcing precedes the single absent lookup.
  (let* ((events (list nil))
         (root (make-instance 'd-path-read-logging-dict :events events))
         (default (list :fallback))
         (values (d-path-read-values root (d-path-read-logged-path events)
                                     default)))
    (parachute:is equal '(:first :second :end (:lookup :absent))
                  (reverse (car events)))
    (parachute:is = 1 (count-if #'consp (car events)))
    (parachute:is = 2 (length values))
    (parachute:is eq default (first values))
    (parachute:false (second values)))
  ;; Even root validation must wait for the entire path.
  (let ((events (list nil)))
    (parachute:fail (sl:dict-ref-in 42 (d-path-read-logged-path events))
                    type-error)
    (parachute:is equal '(:first :second :end) (reverse (car events))))
  (parachute:fail (sl:dict-ref-in 42 nil) program-error)
  ;; A malformed late segment precludes any lookup, not merely later lookups.
  (let* ((events (list nil))
         (root (make-instance 'd-path-read-logging-dict :events events)))
    (parachute:fail (sl:dict-ref-in root '(:absent . :dotted)) type-error)
    (parachute:is equal nil (car events))))

(parachute:define-test dict-ref-in.nested-lookup
  (let* ((leaf-value (list :leaf-value))
         (root (sl:dict
                :nested (sl:dict :leaf leaf-value)
                :nil-intermediate nil
                :atom-intermediate 17))
         (default (list :fallback)))
    ;; Missing anywhere in the path returns the supplied default and NIL
    ;; suppliedness, including a missing first segment.
    (let ((values (d-path-read-values root '(:missing :never-probe) default)))
      (parachute:is = 2 (length values))
      (parachute:is eq default (first values))
      (parachute:false (second values)))
    (let ((values (d-path-read-values root '(:missing))))
      (parachute:is = 2 (length values))
      (parachute:is eq nil (first values))
      (parachute:false (second values)))
    ;; A supplied NIL default is still a supplied default; the operation keeps
    ;; its two-value interface rather than treating NIL as presence.
    (let ((values (d-path-read-values root '(:missing :later) nil)))
      (parachute:is = 2 (length values))
      (parachute:is eq nil (first values))
      (parachute:false (second values)))
    (let ((values (d-path-read-values root '(:nested :leaf))))
      (parachute:is = 2 (length values))
      (parachute:is eq leaf-value (first values))
      (parachute:true (second values)))
    ;; A present NIL or other non-dict value is invalid only when it is an
    ;; intermediate; arbitrary objects remain valid at the leaf.
    (parachute:fail (sl:dict-ref-in root '(:nil-intermediate :leaf)) type-error)
    (parachute:fail (sl:dict-ref-in root '(:atom-intermediate :leaf)) type-error)
    (let ((values (d-path-read-values root '(:atom-intermediate))))
      (parachute:is eq 17 (first values))
      (parachute:true (second values)))))

(parachute:define-test dict-ref-in.leaf-and-errors
  (let* ((key (gensym "PATH-LEAF-"))
         (root (sl:dict key nil :other :value))
         (ref-values (multiple-value-list (sl:dict-ref root key)))
         (path-values (d-path-read-values root (vector key))))
    ;; A one-key path is DICT-REF, including present NIL and exact suppliedness.
    (parachute:is = 2 (length ref-values))
    (parachute:is = 2 (length path-values))
    (parachute:is eq nil (first ref-values))
    (parachute:is eq nil (first path-values))
    (parachute:true (second ref-values))
    (parachute:true (second path-values)))
  ;; A later path error is not hidden by an earlier missing key.
  (let* ((tag (gensym "PATH-LATER-ERROR-"))
         (path (sl:lazy-seq
                 (sl:lazy-cons
                  :missing
                  (sl:lazy-seq (throw tag :later-path-error))))))
    (parachute:is eq :later-path-error
                  (catch tag
                    (sl:dict-ref-in (sl:dict) path :fallback))))
  ;; A present non-NIL leaf is ordinary data and is not required to be a dict.
  (let ((values (d-path-read-values (sl:dict :leaf 99) '(:leaf))))
    (parachute:is eq 99 (first values))
    (parachute:true (second values)))
  ;; A lazy leaf is returned as data without forcing it.
  (let* ((forced nil)
         (leaf (sl:lazy-seq (progn (setf forced t) nil)))
         (values (d-path-read-values (sl:dict :leaf leaf) '(:leaf))))
    (parachute:is = 2 (length values))
    (parachute:is eq leaf (first values))
    (parachute:true (second values))
    (parachute:false forced)))

(defvar *path-write-events* nil)
(defclass path-writable (batch-configurable) ())
(defclass path-fallback (batch-readonly) ())
(define-condition path-write-sentinel (error) ())

(defun path-model-set (source key value)
  (push (list :set (batch-tag source) key) *path-write-events*)
  (make-instance (class-of source) :test (batch-test source) :tag (batch-tag source)
                 :pairs (append (remove key (batch-pairs source)
                                        :key #'car :test (batch-test source))
                                (list (cons key value)))))
(defmethod sl:dict-set ((source path-writable) key value)
  (path-model-set source key value))
(defmethod sl:dict-set ((source path-fallback) key value)
  (path-model-set source key value))
(defmethod sl:dict-ref :before ((source path-writable) key &optional default)
  (declare (ignore default))
  (push (list :ref (batch-tag source) key) *path-write-events*))

(defun path-write-keys (keys)
  (sl:lazy-seq
   (progn
     (push (if keys (list :path (car keys)) :path-end) *path-write-events*)
     (when keys (sl:lazy-cons (car keys) (path-write-keys (cdr keys)))))))

(defun path-symbol-key= (left right)
  (check-type left symbol)
  (check-type right symbol)
  (eq left right))

(defclass path-symbol-keys (path-writable) ()
  (:default-initargs :test #'path-symbol-key=))

(defmethod sl:dict-ref :before ((source path-symbol-keys) key &optional default)
  (declare (ignore source default))
  (unless (symbolp key) (error 'type-error :datum key :expected-type 'symbol)))

(parachute:define-test dict-set-in.path-validation
  (dolist (operation '(:set :update))
    (let ((source (make-instance 'path-writable :tag :root))
          (*path-write-events* nil) (calls 0))
      (flet ((invoke (keys)
               (if (eq operation :set) (sl:dict-set-in source keys :new)
                   (sl:dict-update-in source keys (lambda (old)
                                                   (declare (ignore old))
                                                   (incf calls) :new)))))
        (parachute:fail (invoke nil) program-error)
        (parachute:fail (invoke #()) program-error)
        (parachute:fail (invoke 7) type-error)
        (parachute:fail (invoke '(:a . :bad)) type-error)
        (parachute:fail
         (invoke (sl:lazy-cons :missing (sl:lazy-seq (error 'path-write-sentinel))))
         path-write-sentinel)
        (parachute:is = 0 calls)
        (parachute:false *path-write-events*))))
  (let* ((source (make-instance 'path-writable :tag :root))
         (*path-write-events* nil)
         (result (sl:dict-update-in source (path-write-keys '(:a :b))
                                    (lambda (old)
                                      (parachute:false old)
                                      (push :callback *path-write-events*) :value))))
    (parachute:is equal '((:path :a) (:path :b) :path-end)
      (subseq (reverse *path-write-events*) 0 3))
    (parachute:is eq :value (sl:dict-ref-in result '(:a :b)))
    (parachute:is = 0 (sl:dict-size source)))
  (dolist (bad (list nil 42 :atom))
    (let ((calls 0) (source (sl:dict :intermediate bad)))
      (parachute:fail
       (sl:dict-update-in source '(:intermediate :leaf)
                          (lambda (x) (declare (ignore x)) (incf calls))) type-error)
      (parachute:fail (sl:dict-set-in source '(:intermediate :leaf) :v) type-error)
      (parachute:is = 0 calls)))
  ;; Known missing capability on either an ancestor or the leaf parent prevents
  ;; callbacks. PLIST's specified refusal is known, not a speculative write.
  (dolist (source (list (make-instance 'batch-readonly :pairs (list (cons :a (sl:dict))))
                        (sl:dict :a (make-instance 'batch-readonly))
                        (sl:dict :a (sl:plist-dict-view nil))))
    (let ((calls 0))
      (parachute:fail
       (sl:dict-update-in source '(:a :b) (lambda (x) (declare (ignore x)) (incf calls)))
       program-error)
      (parachute:fail (sl:dict-set-in source '(:a :b) :new) program-error)
      (parachute:is = 0 calls)))
  (parachute:fail (sl:dict-update-in (sl:dict) '(:a) 7) type-error)
  (parachute:fail (sl:dict-set-in 7 '(:a) :value) type-error)
  (parachute:fail (sl:dict-update-in 7 '(:a) #'identity) type-error)
  (let ((source (make-instance 'path-writable)) (calls 0) (*path-write-events* nil))
    (flet ((callback (old) (declare (ignore old)) (incf calls)))
      (dolist (path (list nil #()))
        (parachute:fail (sl:dict-update-in source path #'callback :default :seed) program-error))
      (dolist (path (list 7 '(:a . :bad)))
        (parachute:fail (sl:dict-update-in source path #'callback :default :seed) type-error))
      (parachute:fail
       (sl:dict-update-in source
                         (sl:lazy-cons :absent (sl:lazy-seq (error 'path-write-sentinel)))
                         #'callback :default :seed) path-write-sentinel)
      (parachute:false *path-write-events*)
      (parachute:fail (sl:dict-update-in 7 '(:key) #'callback :default :seed) type-error)
      (dolist (bad (list nil 7 :atom))
        (parachute:fail (sl:dict-update-in (sl:dict :branch bad) '(:branch :key)
                                          #'callback :default :seed) type-error))
      (dolist (readonly (list (make-instance 'batch-readonly)
                             (sl:dict :branch (sl:plist-dict-view nil))))
        (parachute:fail (sl:dict-update-in readonly '(:branch :key)
                                          #'callback :default :seed) program-error))
      (parachute:fail (sl:dict-update-in (make-instance 'path-symbol-keys) '(7)
                                        #'callback :default :seed) type-error)
      (parachute:is = 0 calls)))

  (let* ((source (make-instance 'path-writable :tag :root))
         (*path-write-events* nil)
         (results (multiple-value-list
                   (sl:dict-update-in source (path-write-keys '(:branch :key))
                                      (lambda (old) (parachute:is eq :seed old)
                                        (push :callback *path-write-events*) :new)
                                      :default (progn (push :default *path-write-events*) :seed)))))
    (parachute:is = 1 (length results))
    (parachute:is equal '(:default (:path :branch) (:path :key) :path-end)
                  (subseq (reverse *path-write-events*) 0 4))
    (parachute:is = 1 (count :callback *path-write-events*))
    (parachute:is eq :new (sl:dict-ref-in (first results) '(:branch :key))))

  (dolist (bad (list 7 nil 'when 'if (gensym "UNDEFINED-CALLBACK-")))
    (parachute:fail (sl:dict-update-in (sl:dict) '(:branch :key) bad :default :seed) type-error)))

(parachute:define-test dict-set-in.reconstruction
  (let* ((test #'equal) (source (make-instance 'path-writable :test test :tag :config
                                             :pairs '((:old . :retained))))
         (*batch-events* nil)
         (result (sl:dict-set-in source '(:a :b :c) :leaf))
         (a (sl:dict-ref result :a)) (b (sl:dict-ref a :b)))
    (dolist (node (list result a b))
      (parachute:is eq (class-of source) (class-of node))
      (parachute:is eq test (sl:dict-test node))
      (parachute:is eq :config (batch-tag node)))
    (parachute:is = 2 (length *batch-events*))
    (parachute:true (every (lambda (event) (eq test (third event))) *batch-events*))
    (parachute:is = 1 (sl:dict-size a))
    (parachute:is = 1 (sl:dict-size b))
    (parachute:is eq :leaf (sl:dict-ref b :c))
    (parachute:is eq :retained (sl:dict-ref result :old))
    (parachute:is = 1 (sl:dict-size source)))
  (let* ((source (make-instance 'path-fallback :test 'eql))
         (result (sl:dict-set-in source '(:new :leaf) :value))
         (child (sl:dict-ref result :new)))
    (parachute:true (typep result 'path-fallback))
    (parachute:true (typep child 'sl:dict))
    (parachute:is eq #'sl:equals (sl:dict-test child))
    (parachute:is eq :value (sl:dict-ref child :leaf)))
  (dolist (test '(eq eql equal equalp))
    (let* ((source (make-hash-table :test test))
           (result (sl:dict-set-in source '(:a :b :c) :value))
           (a (sl:dict-ref result :a)) (b (sl:dict-ref a :b)))
      (dolist (node (list result a b))
        (parachute:true (hash-table-p node))
        (parachute:is eq test (sl:dict-test node)))
      (parachute:false (or (eq source result) (eq a b) (eq result a)))
      (parachute:is = 0 (hash-table-count source)))))

(parachute:define-test dict-update-in.persistent-updates
  (let* ((leaf (make-instance 'path-writable :tag :leaf :pairs '((:k . 1))))
         (root (make-instance 'path-writable :tag :root :pairs (list (cons :child leaf))))
         (*path-write-events* nil)
         (result (sl:dict-update-in root '(:child :k)
                                    (lambda (old) (push :callback *path-write-events*)
                                      (values (1+ old) :ignored)))))
    (parachute:is equal '(:callback (:set :leaf :k) (:set :root :child))
      (member :callback (reverse *path-write-events*)))
    (parachute:is = 2 (sl:dict-ref-in result '(:child :k)))
    (parachute:is eq leaf (sl:dict-ref root :child))
    (parachute:is = 1 (sl:dict-ref leaf :k)))
  ;; Different tests at existing ancestors must NOT be homogenized.
  (let* ((shared (list :unchanged)) (leaf (make-hash-table :test 'equal))
         (middle (sl:dict :child leaf :shared shared))
         (root (make-hash-table :test 'eq)))
    (setf (gethash "key" leaf) :old (gethash :middle root) middle
          (gethash :shared root) shared)
    (let* ((result (sl:dict-set-in root '(:middle :child "key") :new))
           (new-middle (sl:dict-ref result :middle)) (new-leaf (sl:dict-ref new-middle :child)))
      (parachute:false (eq root result))
      (parachute:false (eq leaf new-leaf))
      (parachute:true (typep new-middle 'sl:dict))
      (parachute:is eq 'eq (sl:dict-test result))
      (parachute:is eq 'equal (sl:dict-test new-leaf))
      (parachute:is eq :new (gethash "key" new-leaf))
      (parachute:is eq :old (gethash "key" leaf))
      (parachute:is eq middle (gethash :middle root))
      (parachute:is eq shared (gethash :shared result))
      (parachute:is eq shared (sl:dict-ref new-middle :shared))))
  (let* ((source (make-hash-table :test 'equal)) (effects 0) (tag (gensym "EXIT-")))
    (setf (gethash :a source) (sl:dict :b 1))
    (parachute:is eq :escaped
      (catch tag (sl:dict-update-in source '(:a :b)
                                    (lambda (x) (declare (ignore x))
                                      (incf effects) (throw tag :escaped))) :returned))
    (parachute:fail
     (sl:dict-update-in source '(:a :b) (lambda (x) (declare (ignore x))
                                        (incf effects) (error 'path-write-sentinel)))
     path-write-sentinel)
    (parachute:is = 2 effects)
    (parachute:is = 1 (sl:dict-ref-in source '(:a :b))))
  (dolist (source (list (sl:dict) (make-hash-table :test 'equal)
                        (make-instance 'path-writable :test #'equal :tag :custom)))
    (let ((effects 0) (tag (gensym "PATH-EXIT-"))
          (condition (make-condition 'path-write-sentinel)))
      (let ((result (sl:dict-update-in source '(:branch :key)
                                      (lambda (old) (parachute:is eq :seed old)
                                        (incf effects) (values))
                                      :default :seed)))
        (parachute:is = 1 effects)
        (parachute:is equal '(nil t) (multiple-value-list (sl:dict-ref-in result '(:branch :key)))))
      (parachute:is eq :escaped
        (catch tag
          (sl:dict-update-in source '(:branch :key)
                             (lambda (old) (parachute:is eq :seed old)
                               (incf effects) (throw tag :escaped))
                             :default :seed)
          :returned))
      (parachute:is eq condition
        (handler-case
            (sl:dict-update-in source '(:branch :key)
                               (lambda (old) (parachute:is eq :seed old)
                                 (incf effects) (error condition))
                               :default :seed)
          (path-write-sentinel (caught) caught)))
      (parachute:is = 3 effects)
      (parachute:is = 0 (sl:dict-size source)))))

(defclass path-writable-child (path-writable) ())

(parachute:define-test dict-update-in.defaults-and-inheritance
  ;; No UPDATE-IN specialization: inherited REF/SET/COLLECT primitives suffice.
  (dolist (empty (list (sl:dict) (make-instance 'path-writable-child :test #'equal :tag :child)
                      (make-instance 'path-fallback :test 'eql)
                      (make-hash-table :test 'eq) (make-hash-table :test 'eql)
                      (make-hash-table :test 'equal) (make-hash-table :test 'equalp)))
    (let ((object (list :default-object))
          (function (lambda () (error "DEFAULT is an object, not a thunk"))))
      (dolist (options (list nil (list :default nil) (list :default 0)
                            (list :default :marker) (list :default object)
                            (list :default function)))
        (dolist (path '((:key) (:branch :middle :key)))
          (dolist (state '(:absent :nil :value))
            (let* ((resident (list :resident))
                   (source (if (eq state :absent) empty
                               (sl:dict-set-in empty path (if (eq state :nil) nil resident))))
                   (expected (case state (:absent (second options)) (:nil nil) (t resident)))
                   (calls 0) (argument :unobserved) (replacement (list :replacement))
                   (results (multiple-value-list
                             (apply #'sl:dict-update-in source path
                                    (lambda (old) (incf calls) (setf argument old)
                                      (values replacement :ignored)) options)))
                   (result (first results)))
              (parachute:is = 1 calls)
              (parachute:is eq expected argument)
              (parachute:is = 1 (length results))
              (parachute:is eq replacement (sl:dict-ref-in result path))
              (parachute:true (nth-value 1 (sl:dict-ref-in result path)))
              (parachute:is eq (class-of source) (class-of result))
              (parachute:is eq (sl:dict-test source) (sl:dict-test result))
              (parachute:is eq (not (eq state :absent))
                            (not (null (nth-value 1 (sl:dict-ref-in source path)))))
              (parachute:is eq (if (eq state :value) resident nil) (sl:dict-ref-in source path))
              (when (rest path)
                (let* ((a (sl:dict-ref result :branch)) (b (sl:dict-ref a :middle)))
                  (dolist (node (list a b))
                    (if (typep source 'path-fallback)
                        (progn (parachute:true (typep node 'sl:dict))
                               (parachute:is eq #'sl:equals (sl:dict-test node)))
                        (progn (parachute:is eq (class-of source) (class-of node))
                               (parachute:is eq (sl:dict-test source) (sl:dict-test node)))))))
              (when (hash-table-p source) (parachute:false (eq source result)))))))
      (dolist (source (list empty (sl:dict-set-in empty '(:branch :key) nil)))
        (let ((events nil) (calls 0))
          (sl:dict-update-in source '(:branch :key)
                             (lambda (old) (incf calls) (push :callback events) old)
                             :default (progn (push :default events) object))
          (parachute:is = 1 calls)
          (parachute:is equal '(:callback :default) events))
        (when (dict-unknown-keywords-rejected-p)
          ;; The removed :SIGNAL keyword is subject to ordinary CL keyword
          ;; checking; ECL's CLOS accepts unknown GF keywords, so the
          ;; rejection is asserted only where the host enforces it.
          (dolist (obsolete '(nil t))
            (let ((calls 0))
              (parachute:fail
               (funcall #'sl:dict-update-in source '(:branch :key)
                        (lambda (old) (declare (ignore old)) (incf calls))
                        :signal obsolete) program-error)
              (parachute:is = 0 calls)))))))
  ;; Preserve unrelated SET-IN keyword rejection and single-key SET equivalence.
  (let ((source (sl:dict :present nil)))
    (parachute:true (nth-value 1 (sl:dict-ref source :present)))
    (parachute:false (sl:dict-ref source :present))
    (parachute:false (nth-value 1 (sl:dict-ref source :missing)))
    (parachute:is eq :value (sl:dict-ref (sl:dict-set-in source '(:new) :value) :new))
    (parachute:fail (funcall #'sl:dict-set-in source '(:new) 1 :signal t) program-error)
    (parachute:fail (funcall #'sl:dict-set-in source '(:new) 1 :default nil) program-error)
    (parachute:is = (sl:dict-size (sl:dict-set source :new 1))
                   (sl:dict-size (sl:dict-set-in source '(:new) 1)))
    (parachute:is equal (multiple-value-list (sl:dict-ref (sl:dict-set source :new 1) :new))
                       (multiple-value-list (sl:dict-ref (sl:dict-set-in source '(:new) 1) :new)))
    (parachute:is eq :new (sl:dict-ref (sl:dict-update-in source '(:present)
                                                        (lambda (x) (declare (ignore x)) :new))
                                     :present)))
  (let ((calls 0) (effects 0) (tag (gensym "DEFAULT-EXIT-")))
    (parachute:is eq :default-escaped
      (catch tag
        (sl:dict-update-in (sl:dict :key :present) '(:key)
                           (lambda (old) (declare (ignore old)) (incf calls))
                           :default (progn (incf effects) (throw tag :default-escaped)))
        :returned))
    (parachute:is = 1 effects)
    (parachute:is = 0 calls))

  (dolist (empty (list (sl:dict) (make-hash-table :test 'equal)
                        (make-instance 'path-writable-child :test #'equal)))
    (let* ((source (sl:dict-set empty :branch empty)) (argument :unobserved) (calls 0)
           (object (list :leaf-default))
           (result (sl:dict-update-in source '(:branch :leaf)
                                      (lambda (old) (setf argument old) (incf calls) old)
                                      :default object)))
      (parachute:is = 1 calls)
      (parachute:is eq object argument)
      (parachute:is eq object (sl:dict-ref-in result '(:branch :leaf)))
      (parachute:is eq empty (sl:dict-ref source :branch))
      (parachute:is = 0 (sl:dict-size empty))))
  (let ((source (sl:dict :present nil)) (calls 0))
    (let ((result (sl:dict-update-in source #(:present)
                                   (lambda (old) (incf calls) (parachute:is eq nil old) :new)
                                   :default :unused)))
      (parachute:is eq :new (sl:dict-ref result :present))
      (parachute:is = 1 calls)
      (parachute:is equal '(nil t) (multiple-value-list (sl:dict-ref source :present))))))

(define-condition transform-sentinel (error) ())

(parachute:define-test dict-transform.validation-and-callbacks
  (let ((source (make-instance 'batch-child :pairs '((:a . 1) (:b . 2))))
        (*batch-forbid-traversal* t) (calls 0))
    (flet ((callback (k v) (incf calls) (values k v)))
      (dolist (bad (list nil 3 '((:a . 1)) (list (sl:map-entry :a 1))))
        (parachute:fail (sl:dict-transform #'callback bad) type-error))
      (parachute:fail (sl:dict-transform #'callback source :collision :bogus) program-error)
      ;; The removed :TEST keyword is subject to ordinary CL keyword
      ;; checking; ECL's CLOS accepts unknown GF keywords, so the rejection
      ;; is asserted only where the host enforces it.
      (when (dict-unknown-keywords-rejected-p)
        (parachute:fail (sl:dict-transform #'callback source :test 'eql)
                        program-error)))
    (dolist (bad (list 17 nil 'if 'when (gensym "UNBOUND-")))
      (parachute:fail (sl:dict-transform bad source) type-error))
    (parachute:is = 0 calls))
  (let* ((pairs '((:a . 1) (:b . 2) (:c . 3)))
         (source (make-instance 'batch-child :pairs pairs)) (calls nil)
         (result (sl:dict-transform (lambda (k v) (push (cons k v) calls)
                                      (values k (1+ v))) source)))
    (parachute:is equal pairs (reverse calls))
    (parachute:is = 3 (sl:dict-size result))
    (parachute:is = 4 (sl:dict-ref result :c))
    (parachute:is equal pairs (batch-pairs source)))
  ;; Symbol callbacks retain invocation-time identity, not a captured function.
  (let ((name (gensym "TRANSFORM-CALLBACK-")) (calls nil)
        (source (make-instance 'batch-child :pairs '((:a . 1) (:b . 2)))))
    (unwind-protect
         (progn
           (setf (symbol-function name)
                 (lambda (k v)
                   (push :first calls)
                   (setf (symbol-function name)
                         (lambda (k v) (push :second calls) (values k v)))
                   (values k v)))
           (sl:dict-transform name source)
           (parachute:is equal '(:second :first) calls))
      (fmakunbound name))))

(parachute:define-test dict-transform.callback-arity
  (dolist (count '(0 1 3))
    (let ((calls 0) (*batch-events* nil)
          (source (make-instance 'batch-child :pairs '((:a . 1) (:b . 2)))))
      (parachute:fail
       (sl:dict-transform
        (lambda (key value)
          (parachute:is eq :a key)
          (parachute:is = 1 value)
          (incf calls)
          (values-list (subseq '(:key :value :extra) 0 count))) source)
       program-error)
      (parachute:is = 1 calls)
      (parachute:false *batch-events*)
      (parachute:is = 2 (sl:dict-size source))))
  (let ((result (sl:dict-transform (lambda (k v) (declare (ignore k v))
                                   (values nil nil)) (sl:dict :a :b))))
    (parachute:is = 1 (sl:dict-size result))
    (parachute:is equal '(nil t) (multiple-value-list (sl:dict-ref result nil)))))

(parachute:define-test dict-transform.collision-and-errors
  (let ((source (make-instance 'batch-child :test 'equal
                              :pairs '((:a . 1) (:b . 2) (:c . 3))))
        (effects nil) (*batch-events* nil) (returned nil))
    (parachute:fail
     (progn
       (sl:dict-transform (lambda (k v) (push k effects)
                            (values (copy-seq "collision") v))
                          source :collision :error)
       (setf returned t)) program-error)
    (parachute:false returned)
    (parachute:is equal '(:b :a) effects)
    (parachute:false *batch-events*)
    (parachute:is equal '((:a . 1) (:b . 2) (:c . 3)) (batch-pairs source)))
  (dolist (escape '(nil t))
    (let ((source (sl:dict :a 1 :b 2)) (calls 0) (tag (gensym "ESCAPE-")))
      (flet ((callback (k v)
               (declare (ignore k v)) (incf calls)
               (if escape (throw tag :escaped) (error 'transform-sentinel))))
        (if escape
            (parachute:is eq :escaped
              (catch tag (sl:dict-transform #'callback source) :returned))
            (parachute:fail (sl:dict-transform #'callback source) transform-sentinel)))
      (parachute:is = 1 calls)
      (parachute:is = 2 (sl:dict-size source))
      (parachute:is = 1 (sl:dict-ref source :a)))))

(parachute:define-test dict-transform.result-selection
  (let* ((source (make-instance 'batch-child :test 'equal :tag :configuration
                               :pairs '((:a . 1) (:b . 2) (:c . 3))))
         (keys nil) (seen nil) (*batch-events* nil)
         (result (sl:dict-transform
                  (lambda (k v) (push k seen) (push (copy-seq "same") keys)
                    (values (first keys) v)) source)))
    (parachute:is equal '(:c :b :a) seen)
    (parachute:is eq (class-of source) (class-of result))
    (parachute:is eq 'equal (sl:dict-test result))
    (parachute:is eq :configuration (batch-tag result))
    (parachute:is = 1 (length *batch-events*))
    (parachute:is eq 'equal (third (first *batch-events*)))
    (batch-check-one result (first keys) 3)
    (parachute:is = 3 (sl:dict-size source)))
  ;; EQ preserves distinct transformed strings; EQUAL collapses them. Do not
  ;; choose a survivor for unordered input: record the callback's actual order.
  (dolist (test '(eq eql equal equalp))
    (let ((source (make-hash-table :test test)) (last-key nil) (last-value nil))
      (setf (gethash :a source) 1 (gethash :b source) 2)
      (let ((result (sl:dict-transform
                     (lambda (k v) (declare (ignore k))
                       (setf last-key (copy-seq "same") last-value v)
                       (values last-key v)) source)))
        (parachute:true (hash-table-p result))
        (parachute:false (eq source result))
        (parachute:is eq test (sl:dict-test result))
        (parachute:is = (if (member test '(eq eql)) 2 1) (sl:dict-size result))
        (when (member test '(equal equalp)) (batch-check-one result last-key last-value))
        (parachute:is = 2 (sl:dict-size source)))))
  ;; No primary collector means EQUALS result, BEFORE transformed collisions.
  (dolist (source (list (make-instance 'batch-readonly :test 'eql :pairs '((:a . 1) (:b . 1.0)))
                        (make-instance 'batch-aux-only :pairs '((:a . 1) (:b . 1.0)))
                        (sl:plist-dict-view '(:a 1 :b 1.0))))
    (let ((*batch-events* nil) (calls 0))
      (parachute:fail
       (sl:dict-transform (lambda (k v) (incf calls) (values v k))
                          source :collision :error) program-error)
      (parachute:is = 2 calls)
      (parachute:false *batch-events*)
      (let ((result (sl:dict-transform (lambda (k v) (values v k)) source)))
        (parachute:true (typep result 'sl:dict))
        (parachute:is = 1 (sl:dict-size result))))))

(parachute:define-test dict-values-map.applies-values
  (let ((source (sl:dict :a 1 :b 2 :nil nil)) (calls 0))
    (let ((result (sl:dict-values-map (lambda (value) (incf calls) (and value (* 10 value)))
                                     source)))
      (parachute:is = 3 calls)
      (parachute:is = 3 (sl:dict-size result))
      (parachute:is = 10 (sl:dict-ref result :a))
      (parachute:is = 20 (sl:dict-ref result :b))
      (parachute:is equal '(nil t) (multiple-value-list (sl:dict-ref result :nil)))
      (parachute:true (typep result 'sl:dict)))))

(parachute:define-test dict-values-map.preserves-representation
  (let ((table (make-hash-table :test 'equal)))
    (setf (gethash :a table) 2 (gethash :b table) 3)
    (let ((result (sl:dict-values-map #'1+ table)))
      (parachute:true (hash-table-p result))
      (parachute:is eq 'equal (sl:dict-test result))
      (parachute:is = 2 (sl:dict-size result))
      (parachute:is = 2 (hash-table-count table))
      (parachute:is = 3 (sl:dict-ref result :a))
      (parachute:is = 4 (sl:dict-ref result :b))))
  (let* ((source (sl:ordered-dict :a 1 :b 2))
         (result (sl:dict-values-map #'1+ source)))
    (parachute:true (sl:ordered-dict-p result))
    (parachute:is equal '(:a 2 :b 3) (sl:dict-plist result))))

(parachute:define-test dict-keys-map.transforms-and-collides
  (let ((source (sl:ordered-dict :a 1 :b 2 :c 3)))
    (let ((result (sl:dict-keys-map (lambda (key) (if (member key '(:a :b)) :same key))
                                    source)))
      (parachute:true (sl:ordered-dict-p result))
      (parachute:is = 2 (sl:dict-size result))
      (parachute:is = 1 (sl:dict-ref source :a))
      (parachute:is equal '(:same 2 :c 3) (sl:dict-plist result))))
  (let* ((source (sl:dict nil 1 :b 2))
         (result (sl:dict-keys-map #'identity source)))
    (parachute:is = 2 (sl:dict-size result))
    (parachute:is equal '(1 t) (multiple-value-list (sl:dict-ref result nil))))
  ;; A plain SL:DICT traverses in host-SXHASH order (unspecified, Chapter 9),
  ;; so which colliding source entry is last depends on the host; an
  ;; SL:ORDERED-DICT's stored order makes last-wins deterministic.
  (let ((result (sl:dict-keys-map
                 (lambda (key) (declare (ignore key)) nil)
                 (sl:ordered-dict nil 1 :b 2))))
    (parachute:is = 1 (sl:dict-size result))
    (parachute:is equal '(2 t) (multiple-value-list (sl:dict-ref result nil))))
  (let ((source (sl:dict :a 1 :b 2)))
    (parachute:fail (sl:dict-keys-map (constantly :same) source :collision :error)
                    program-error)
    (parachute:fail (sl:dict-keys-map #'identity source :collision :unknown)
                    program-error)))

(parachute:define-test dict-map.empty-and-fallback
  (let ((empty (sl:ordered-dict)))
    (parachute:is = 0 (sl:dict-size (sl:dict-values-map #'identity empty)))
    (parachute:true (sl:ordered-dict-p (sl:dict-keys-map #'identity empty))))
  (let ((view (sl:plist-dict-view '(:a 1 :b nil))))
    (let ((result (sl:dict-values-map #'identity view)))
      (parachute:true (typep result 'sl:dict))
      (parachute:is = 2 (sl:dict-size result))
      (parachute:is = 1 (sl:dict-ref result :a))
      (parachute:is equal '(nil t) (multiple-value-list (sl:dict-ref result :b)))))
  (let* ((source (sl:plist-dict-view
                  (list (copy-seq "k") 1 (copy-seq "k") 2)))
         (result (sl:dict-values-map #'identity source)))
    (parachute:true (typep result 'sl:dict))
    (parachute:is = 1 (sl:dict-size result))
    (parachute:is = 2 (sl:dict-ref result "k"))
    (parachute:is = 2 (sl:dict-size source))))

(defun select-remove-pairs (dict)
  (sl:dict-alist dict))

(defun select-remove-association= (left right)
  (flet ((canonical (pairs)
           (sort (copy-list pairs) #'string<
                 :key (lambda (pair) (princ-to-string (car pair))))))
    (equal (canonical left) (canonical right))))

(parachute:define-test dict-select-keys.selection-and-removal
  (dolist (source (list (sl:dict :a 1 :b 2 :c 3)
                        (sl:ordered-dict :a 1 :b 2 :c 3)))
    (let* ((source-pairs (select-remove-pairs source))
           (selected (sl:dict-select-keys source '(:c :a :missing :a)))
           (removed (sl:dict-remove-keys source '(:b :missing :b)))
           (selected-pairs (select-remove-pairs selected))
           (removed-pairs (select-remove-pairs removed)))
      (parachute:true
       (select-remove-association=
        (remove-if-not (lambda (pair) (member (car pair) '(:a :c))) source-pairs)
        selected-pairs))
      (parachute:true
       (select-remove-association=
        (remove-if (lambda (pair) (eq (car pair) :b)) source-pairs)
        removed-pairs))
      (when (sl:ordered-dict-p source)
        (parachute:is equal '((:a . 1) (:c . 3)) selected-pairs)
        (parachute:is equal '((:a . 1) (:c . 3)) removed-pairs))
      (parachute:is = 3 (sl:dict-size source))
      (parachute:is = 2 (sl:dict-size selected))
      (parachute:is = 2 (sl:dict-size removed))
      (parachute:is eq (class-of source) (class-of selected))
      (parachute:is eq (class-of source) (class-of removed))))
  (let ((table (make-hash-table :test 'equal)))
    (setf (gethash "a" table) 1
          (gethash "b" table) 2
          (gethash "c" table) 3)
    (let ((selected (sl:dict-select-keys table (vector (copy-seq "c") "a")))
          (removed (sl:dict-remove-keys table (list (copy-seq "b")))))
      (parachute:true (hash-table-p selected))
      (parachute:true (hash-table-p removed))
      (parachute:is = 2 (hash-table-count selected))
      (parachute:is = 2 (hash-table-count removed))
      (parachute:is = 1 (gethash "a" selected))
      (parachute:is = 3 (gethash "c" selected))
      (parachute:false (nth-value 1 (gethash "b" selected)))
      (parachute:is = 1 (gethash "a" removed))
      (parachute:is = 3 (gethash "c" removed))
      (parachute:false (nth-value 1 (gethash "b" removed)))
      (parachute:is = 3 (hash-table-count table)))))

(parachute:define-test dict-select-keys.boundaries-and-equality
  (dolist (operation (list #'sl:dict-select-keys #'sl:dict-remove-keys))
    (let ((source (sl:dict :a 1 :b 2)))
      (parachute:true
       (select-remove-association=
        (if (eq operation #'sl:dict-select-keys) nil (select-remove-pairs source))
        (select-remove-pairs (funcall operation source nil))))
      (parachute:true
       (select-remove-association=
        (if (eq operation #'sl:dict-select-keys) (select-remove-pairs source) nil)
        (select-remove-pairs (funcall operation source '(:a :b)))))
      (parachute:is = 2 (sl:dict-size source))
      (parachute:is = 1 (sl:dict-ref source :a))
      (parachute:is = 2 (sl:dict-ref source :b))
      (parachute:true (typep source 'sl:dict))))
  ;; A plist view has no collector and therefore falls back to SL:DICT.
  (let ((source (sl:plist-dict-view '(:a 1 :b 2 :c 3))))
    (dolist (result (list (sl:dict-select-keys source '(:b))
                          (sl:dict-remove-keys source '(:a :c))))
      (parachute:true (typep result 'sl:dict))
      (parachute:is = 1 (sl:dict-size result))
      (parachute:false (typep result 'sl:plist-dict-view))))
  (let* ((key (copy-seq "key"))
         (distinct-key (copy-seq key))
         (source (sl:plist-dict-view (list key :value)))
         (selected (sl:dict-select-keys source (list distinct-key)))
         (removed (sl:dict-remove-keys source (list distinct-key))))
    (parachute:false (eq key distinct-key))
    (parachute:is = 0 (sl:dict-size selected))
    (parachute:is = 1 (sl:dict-size removed))
    (parachute:is eq :value (sl:dict-ref removed key))
    (parachute:true (nth-value 1 (sl:dict-ref removed key))))
  (parachute:fail (sl:dict-select-keys nil nil) type-error)
  (parachute:fail (sl:dict-remove-keys (sl:dict) 42) type-error))

(parachute:define-test dict-select-keys.indexed-order-and-unhashable-keys
  (let* ((source (sl:ordered-dict :first 1 :middle 2 :last 3))
         (selected (sl:dict-select-keys source '(:last :first :last)))
         (removed (sl:dict-remove-keys source '(:middle :missing :middle))))
    (parachute:is equal '((:first . 1) (:last . 3)) (sl:dict-alist selected))
    (parachute:is equal '((:first . 1) (:last . 3)) (sl:dict-alist removed)))
  ;; An unhashable request and an unhashable source entry both fall back
  ;; without exposing the hash failure or changing the linear result.
  (let* ((key (make-instance 'merge-unhashable-key))
         (source (make-instance 'batch-child :test #'sl:equals
                                :pairs (list (cons :a 1) (cons key 2))))
         (requested (list key :a)))
    (parachute:is equal '((:a . 1))
                  (batch-pairs (sl:dict-select-keys source requested)))
    (parachute:is eq key
                  (caar (batch-pairs (sl:dict-remove-keys source requested))))
    (parachute:is = 1
                  (length (batch-pairs (sl:dict-remove-keys source requested))))))

(parachute:define-test dict-select-keys.threshold-indexed-membership
  (let* ((count (1+ sophie-lisp.internal::+dict-requested-key-index-threshold+))
         (source (sl:ordered-dict :first 1 :middle 2 :last 3))
         (requested (append (list :last :missing :first :last)
                            (loop for index below count collect (+ 1000 index))))
         (selected (sl:dict-select-keys source requested))
         (removed (sl:dict-remove-keys source requested)))
    (parachute:true (> (length requested)
                       sophie-lisp.internal::+dict-requested-key-index-threshold+))
    (parachute:is equal '((:first . 1) (:last . 3)) (sl:dict-alist selected))
    (parachute:is equal '((:middle . 2)) (sl:dict-alist removed))
    (parachute:is = 3 (sl:dict-size source)))
  ;; Force the indexed :hash branch, including a failed hash for a requested
  ;; key and a source key. Neither failure may turn an absent key into a hit.
  (let* ((unhashable (make-instance 'merge-unhashable-key))
         (source (make-instance 'batch-child :test #'sl:equals
                                :pairs (list (cons :first 1) (cons unhashable 2)
                                             (cons :last 3))))
         (count (1+ sophie-lisp.internal::+dict-requested-key-index-threshold+))
         (requested (append (list :last :first unhashable)
                            (loop for index below count collect (+ 1000 index))))
         (selected (sl:dict-select-keys source requested))
         (removed (sl:dict-remove-keys source requested)))
    (parachute:is equal '((:first . 1) (:last . 3)) (batch-pairs selected))
    (parachute:is = 1 (length (batch-pairs removed)))
    (parachute:is eq unhashable (caar (batch-pairs removed)))))

(defclass select-overflow-key ()
  ((label :initarg :label :reader select-overflow-label)
   (matches :initarg :matches :reader select-overflow-matches)
   (hashable-p :initarg :hashable-p :reader select-overflow-hashable-p)
   (calls :initarg :calls :reader select-overflow-calls)))

(defmethod sl:hash-code ((key select-overflow-key))
  (if (select-overflow-hashable-p key)
      17
      (error "Unhashable select key")))

(defmethod sl:equals ((left select-overflow-key) (right select-overflow-key))
  (push (select-overflow-label left) (car (select-overflow-calls left)))
  (not (null (intersection (select-overflow-matches left)
                           (select-overflow-matches right)))))

(parachute:define-test dict-select-keys.successful-overflow-matches
  ;; Both directions must match on either side of the requested-key cutoff.
  (dolist (indexed '(nil t))
    (dolist (hashable-source '(nil t))
      (let* ((calls (list nil))
             (source-key (make-instance 'select-overflow-key :label :source
                                        :matches '(:hit) :hashable-p hashable-source
                                        :calls calls))
             (request-key (make-instance 'select-overflow-key :label :request
                                         :matches '(:hit) :hashable-p (not hashable-source)
                                         :calls calls))
             (source (make-instance 'batch-child :test #'sl:equals
                                    :pairs (list (cons source-key :hit) (cons :other :keep))))
             (requested (cons request-key
                              (loop for i below (if indexed
                                                    sophie-lisp.internal::+dict-requested-key-index-threshold+
                                                    (1- sophie-lisp.internal::+dict-requested-key-index-threshold+))
                                    collect (+ 1000 i))))
             (selected (sl:dict-select-keys source requested))
             (removed (sl:dict-remove-keys source requested)))
        (parachute:is = (if indexed
                            (1+ sophie-lisp.internal::+dict-requested-key-index-threshold+)
                            sophie-lisp.internal::+dict-requested-key-index-threshold+)
                      (length requested))
        (parachute:is equal '(:request :request) (reverse (car calls)))
        (parachute:is eq source-key (caar (batch-pairs selected)))
        (parachute:is equal '((:other . :keep)) (batch-pairs removed))
        (parachute:is = 1 (length (batch-pairs selected)))))))

(parachute:define-test dict-select-keys.earliest-overflow-and-bucket-match
  ;; Membership is the same either way, but the first requested match wins:
  ;; even if the bucket is probed first, an earlier overflow match wins.
  (dolist (overflow-first '(nil t))
    (let* ((calls (list nil))
           (request (lambda (label hashable-p matches)
                      (make-instance 'select-overflow-key :label label
                                     :hashable-p hashable-p :matches matches :calls calls)))
           (overflow (funcall request :overflow nil '(:overflow)))
           (bucket (funcall request :bucket t '(:bucket)))
           (source-key (funcall request :source t '(:overflow :bucket)))
           (first (if overflow-first overflow bucket))
           (second (if overflow-first bucket overflow))
           (requested (append (list first second)
                              (loop for i below sophie-lisp.internal::+dict-requested-key-index-threshold+
                                    collect (+ 1000 i))))
           (source (make-instance 'batch-child :test #'sl:equals
                                  :pairs (list (cons source-key :hit) (cons :other :keep))))
           (selected (sl:dict-select-keys source requested))
           (removed (sl:dict-remove-keys source requested)))
      (parachute:is equal (if overflow-first
                             '(:bucket :overflow :bucket :overflow)
                             '(:bucket :bucket))
                    (reverse (car calls)))
      (parachute:is eq source-key (caar (batch-pairs selected)))
      (parachute:is equal '((:other . :keep)) (batch-pairs removed)))))

(parachute:define-test dict-select-keys.lazy-request-key-does-not-force
  (let* ((forces 0)
         (key (sl:lazy-seq (progn (incf forces) (sl:lazy-cons :item nil))))
         (source (sl:ordered-dict :plain 1))
         (requested (list key))
         (before forces))
    (parachute:is = 0 before)
    (parachute:is = 0 (sl:dict-size (sl:dict-select-keys source requested)))
    (parachute:is = before forces)
    (parachute:is = 1 (sl:dict-size (sl:dict-remove-keys source requested)))
    (parachute:is = before forces)))

(defclass update-no-set-dict ()
  ((value :initarg :value :reader update-no-set-value)))

(defmethod sophie-lisp:dictp ((object update-no-set-dict))
  (declare (ignore object))
  t)

(defmethod sophie-lisp:dict-ref ((dict update-no-set-dict) key
                                &optional default)
  (if (eq key :only-key)
      (values (update-no-set-value dict) t)
      (values default nil)))

(defmethod sophie-lisp:dict-test ((dict update-no-set-dict))
  (declare (ignore dict))
  #'eq)

(defmethod sophie-lisp:dict-size ((dict update-no-set-dict))
  (declare (ignore dict))
  1)

(defmethod sophie-lisp:seqablep ((dict update-no-set-dict))
  (declare (ignore dict))
  t)

(defmethod sophie-lisp:seq-emptyp ((dict update-no-set-dict))
  (declare (ignore dict))
  nil)

(defmethod sophie-lisp:seq-first ((dict update-no-set-dict))
  (sophie-lisp:map-entry :only-key (update-no-set-value dict)))

(defmethod sophie-lisp:seq-rest ((dict update-no-set-dict))
  (declare (ignore dict))
  nil)

(defmethod sophie-lisp:seq-length ((dict update-no-set-dict))
  (declare (ignore dict))
  1)

(defun update-caught-condition (thunk)
  (handler-case
      (progn (funcall thunk) nil)
    (condition (condition) condition)))

(parachute:define-test dict-update.validation-and-dispatch
  (let* ((key (gensym "UPDATE-KEY-"))
         (old-value (list :old)) (new-value (list :new))
         (dict (sophie-lisp:dict key old-value))
         (calls 0) (argument nil)
         (values (multiple-value-list
                  (sophie-lisp:dict-update
                   dict key (lambda (value) (incf calls) (setf argument value)
                              (values new-value :ignored))))))
    (parachute:is = 1 calls)
    (parachute:is eq old-value argument)
    (parachute:is = 1 (length values))
    (let ((result (first values)))
      (parachute:true (sophie-lisp:dictp result))
      (parachute:false (eq dict result))
      (parachute:is eq new-value (sophie-lisp:dict-ref result key))
      (parachute:is eq old-value (sophie-lisp:dict-ref dict key))))
  (let ((dict (sl:dict :valid-key :valid-value)) (calls 0))
    (parachute:fail
     (sl:dict-update :not-a-dict :valid-key
                     (lambda (value) (declare (ignore value)) (incf calls))
                     :default :unused) type-error)
    (parachute:is = 0 calls)
    (dolist (key '(:valid-key :missing))
      (parachute:fail (sl:dict-update dict key 42 :default :unused) type-error))
    (parachute:is eq :valid-value (sl:dict-ref dict :valid-key))
    ;; The removed :UNKNOWN-OPTION keyword is subject to ordinary CL keyword
    ;; checking; ECL's CLOS accepts unknown GF keywords, so the rejection is
    ;; asserted only where the host enforces it.
    (when (dict-unknown-keywords-rejected-p)
      (parachute:fail
       (sl:dict-update dict :valid-key
                       (lambda (value) (declare (ignore value)) (incf calls))
                       :unknown-option t) program-error)
      (parachute:is = 0 calls)))
  (parachute:is
   eq 'when
   (type-error-datum
    (update-caught-condition
     (lambda () (sl:dict-update "not a dict" :k 'when)))))
  (let ((source (make-instance 'update-model-child)) (calls 0))
    (parachute:fail
     (sl:dict-update source 42 (lambda (old) (declare (ignore old)) (incf calls))
                     :default :unused) type-error)
    (parachute:is = 0 calls)
    (parachute:is = 0 (sl:dict-size source))))

(parachute:define-test dict-update.defaults-and-inheritance
  ;; Independent expected arguments, not results computed with DICT-UPDATE.
  ;; The subclass inherits only primitives; no specialized UPDATE method exists.
  (dolist (empty (list (sl:dict) (make-hash-table :test 'equal)
                      (make-instance 'update-model-child)))
    (let ((object (list :default-object))
          (function (lambda () (error "A default object is not a thunk"))))
      (dolist (options (list nil (list :default nil) (list :default 0)
                            (list :default :marker) (list :default object)
                            (list :default function)))
        (dolist (state '(:absent :nil :value))
          (let* ((resident (list :resident))
                 (source (if (eq state :absent) empty
                             (sl:dict-set empty :key (if (eq state :nil) nil resident))))
                 (expected (case state (:absent (second options)) (:nil nil) (t resident)))
                 (calls 0) (argument :unobserved) (replacement (list :replacement))
                 (results (multiple-value-list
                           (apply #'sl:dict-update source :key
                                  (lambda (old) (incf calls) (setf argument old)
                                    (values replacement :ignored)) options)))
                 (result (first results)))
            (parachute:is = 1 calls)
            (parachute:is eq expected argument)
            (parachute:is = 1 (length results))
            (parachute:is eq replacement (sl:dict-ref result :key))
            (parachute:true (nth-value 1 (sl:dict-ref result :key)))
            (parachute:is eq (class-of source) (class-of result))
            (parachute:is eq (sl:dict-test source) (sl:dict-test result))
            (parachute:is eq (not (eq state :absent))
                          (not (null (nth-value 1 (sl:dict-ref source :key)))))
            (parachute:is eq (if (eq state :value) resident nil) (sl:dict-ref source :key))
            (when (hash-table-p source) (parachute:false (eq source result))))))
      ;; Eager DEFAULT evaluation occurs once even for a present key.
      (dolist (source (list empty (sl:dict-set empty :key nil)))
        (let ((events nil))
          (sl:dict-update source :key
                          (lambda (old) (push :callback events) old)
                          :default (progn (push :default events) object))
          (parachute:is equal '(:callback :default) events)))
      ;; Removed keyword is rejected for both values and presence states,
      ;; subject to ordinary CL keyword checking; ECL's CLOS accepts unknown
      ;; GF keywords, so the rejection is asserted only where the host
      ;; enforces it.
      (when (dict-unknown-keywords-rejected-p)
        (dolist (source (list empty (sl:dict-set empty :key nil)))
          (dolist (obsolete '(nil t))
            (let ((calls 0))
              (parachute:fail
               (funcall #'sl:dict-update source :key
                        (lambda (old) (declare (ignore old)) (incf calls))
                        :signal obsolete) program-error)
              (parachute:is = 0 calls)))))))
  (let ((calls 0) (effects 0) (tag (gensym "DEFAULT-EXIT-")))
    (parachute:is eq :default-escaped
      (catch tag
        (sl:dict-update (sl:dict :key :present) :key
                        (lambda (old) (declare (ignore old)) (incf calls))
                        :default (progn (incf effects) (throw tag :default-escaped)))
        :returned))
    (parachute:is = 1 effects)
    (parachute:is = 0 calls)))

(parachute:define-test dict-update.persistence-and-errors
  (let* ((key (gensym "HASH-UPDATE-")) (old-value (list :old)) (new-value (list :new))
         (source (make-hash-table :test 'equal :rehash-size 2.0 :rehash-threshold 0.75))
         (calls 0) (argument nil))
    (setf (gethash key source) old-value)
    (let ((result (sl:dict-update source key
                                 (lambda (value) (incf calls) (setf argument value) new-value)
                                 :default :unused)))
      (parachute:true (hash-table-p result))
      (parachute:false (eq source result))
      (parachute:is eq 'equal (sl:dict-test result))
      (parachute:is = 1 calls)
      (parachute:is eq old-value argument)
      (parachute:is eq old-value (gethash key source))
      (parachute:is eq new-value (gethash key result))))
  (dolist (empty (list (sl:dict) (make-hash-table :test 'equal)
                      (make-instance 'update-model-child)))
    (let* ((source (sl:dict-set empty :key :resident))
           (effects 0) (tag (gensym "EXIT-"))
           (condition (make-condition 'simple-error :format-control "callback sentinel")))
      (dolist (key '(:key :missing))
        (let* ((calls 0)
               (results (multiple-value-list
                         (sl:dict-update source key
                                         (lambda (old) (declare (ignore old))
                                           (incf calls) (values))
                                         :default :seed))))
          (parachute:is = 1 calls)
          (parachute:is = 1 (length results))
          (parachute:is equal '(nil t) (multiple-value-list (sl:dict-ref (first results) key))))
        (parachute:is eq :escaped
          (catch tag
            (sl:dict-update source key
                            (lambda (old) (declare (ignore old))
                              (incf effects) (throw tag :escaped))
                            :default :seed)
            :returned))
        (parachute:is eq condition
          (update-caught-condition
           (lambda ()
             (sl:dict-update source key
                             (lambda (old) (declare (ignore old))
                               (incf effects) (error condition))
                             :default :seed)))))
      (parachute:is = 4 effects)
      (parachute:is eq :resident (sl:dict-ref source :key))
      (parachute:false (nth-value 1 (sl:dict-ref source :missing)))))
  (let ((dict (make-instance 'update-no-set-dict :value :resident)))
    (dolist (key '(:only-key :missing))
      (let ((calls 0))
        (parachute:fail
         (sl:dict-update dict key (lambda (value) (declare (ignore value)) (incf calls))
                         :default :seed) program-error)
        (parachute:is = 0 calls)
        (parachute:is eq :resident (sl:dict-ref dict :only-key)))))
  (let* ((called-p nil)
         (view (sl:plist-dict-view '(:key :value)))
         (condition
           (handler-case
               (progn
                 (sl:dict-update view :key
                                 (lambda (value) (declare (ignore value))
                                   (setf called-p t)))
                 nil)
             (program-error (condition) condition))))
    (parachute:true (typep condition 'program-error))
    (parachute:true (typep condition 'simple-condition))
    (parachute:is string= "The dictionary does not support DICT-SET."
                  (simple-condition-format-control condition))
    (parachute:false called-p)))
