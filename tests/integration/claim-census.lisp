(in-package #:sophie-lisp.tests)

(parachute:define-test claim-census.seq-filter-count-zero-does-not-traverse
  (let* ((forces (list 0))
         (source (select-stream '(1 2) forces))
         (result (sl:seq-filter #'evenp source :count 0)))
    (parachute:true (sl:seq-emptyp result))
    (parachute:is = 0 (car forces))))

(parachute:define-test claim-census.count-zero-remove-and-substitute-skip-matchers
  (let ((source '(1 2 1)))
    (dolist (operation (list #'sl:seq-remove #'sl:seq-remove-if))
      (let ((key-calls 0) (match-calls 0))
        (let ((result
                (if (eq operation #'sl:seq-remove)
                    (sl:seq-remove 9 source :count 0
                                   :test (lambda (left right)
                                           (incf match-calls) (eql left right))
                                   :key (lambda (value) (incf key-calls) value))
                    (sl:seq-remove-if (lambda (value)
                                        (incf match-calls) (oddp value))
                                      source :count 0
                                      :key (lambda (value) (incf key-calls) value)))))
          (parachute:is equal source result)
          (parachute:false (eq source result))
          (parachute:is = 0 key-calls)
          (parachute:is = 0 match-calls))))
    (dolist (operation (list #'sl:seq-substitute #'sl:seq-substitute-if))
      (let ((key-calls 0) (match-calls 0))
        (let ((result
                (if (eq operation #'sl:seq-substitute)
                    (sl:seq-substitute 9 1 source :count 0
                                       :test (lambda (left right)
                                               (incf match-calls) (eql left right))
                                       :key (lambda (value) (incf key-calls) value))
                    (sl:seq-substitute-if 9 (lambda (value)
                                              (incf match-calls) (oddp value))
                                          source :count 0
                                          :key (lambda (value) (incf key-calls) value)))))
          (parachute:is equal source result)
          (parachute:false (eq source result))
          (parachute:is = 0 key-calls)
          (parachute:is = 0 match-calls))))))

(defvar *claim-census-normalizing* nil)

(defun claim-census-with-normalization-guard (thunk)
  (let* ((name 'sophie-lisp.internal::normalize-ordered-dict)
         (original (symbol-function name)))
    (unwind-protect
         (progn
           (setf (symbol-function name)
                 (lambda (sequence operation)
                   (let ((*claim-census-normalizing* t))
                     (funcall original sequence operation))))
           (funcall thunk))
      (setf (symbol-function name) original))))

(parachute:define-test claim-census.promoted-sort-callbacks-follow-normalization
  (let ((table (make-hash-table :test #'eq))
        (key-calls 0)
        (comparison-calls 0))
    (setf (gethash :a table) 3
          (gethash :b table) 1
          (gethash :c table) 2)
    (let* ((result
             (claim-census-with-normalization-guard
              (lambda ()
                (sl:seq-sort
                 table
                 :key (lambda (entry)
                        (parachute:false *claim-census-normalizing*)
                        (parachute:true (typep entry 'sl:map-entry))
                        (incf key-calls)
                        (sl:entry-value entry))
                 :test (lambda (right left)
                         (parachute:false *claim-census-normalizing*)
                         (incf comparison-calls)
                         (< right left))))))
           (entries (policy-list result)))
      (parachute:true (sl:ordered-dict-p result))
      (parachute:is equal '(1 2 3) (mapcar #'sl:entry-value entries))
      ;; Current stable merge sort intentionally may call :KEY repeatedly.
      (parachute:true (plusp key-calls))
      (parachute:true (plusp comparison-calls))))
  ;; Without :KEY, the sort comparator receives normalized map entries.
  (let ((table (make-hash-table :test #'eq)) (comparison-calls 0))
    (setf (gethash :a table) 3
          (gethash :b table) 1
          (gethash :c table) 2)
    (let* ((result
             (claim-census-with-normalization-guard
              (lambda ()
                (sl:seq-sort
                 table
                 :test (lambda (right left)
                         (parachute:false *claim-census-normalizing*)
                         (parachute:true (typep right 'sl:map-entry))
                         (parachute:true (typep left 'sl:map-entry))
                         (incf comparison-calls)
                         (< (sl:entry-value right) (sl:entry-value left)))))))
           (entries (policy-list result)))
      (parachute:is = 3 (sl:dict-size result))
      (parachute:is equal '(1 2 3) (mapcar #'sl:entry-value entries))
      (parachute:true (plusp comparison-calls)))))

(parachute:define-test claim-census.map-widening-does-not-replay-callbacks
  (let ((calls 0)
        (source (copy-seq "abc")))
    (let ((result
            (sl:seq-map (lambda (character)
                          (incf calls)
                          (if (char= character #\b) :widened character))
                        source)))
      (parachute:true (vectorp result))
      (parachute:false (stringp result))
      (parachute:is equalp #(#\a :widened #\c) result)
      (parachute:is = 3 calls)
      (parachute:is string= "abc" source))))

(parachute:define-test claim-census.partition-buffers-only-the-demanded-chunk
  (let* ((*census-random-access-work* 0)
         (reads nil)
         (source (part03-stream '(1 2 3 4 5 6) (lambda (index) (push index reads))))
         (partition (sl:seq-partition 2 source :step 2)))
    (parachute:is eq nil reads)
    (parachute:is = 0 *census-random-access-work*)
    (let ((first (sl:seq-first partition)))
      (parachute:is equal '(1 2) (part03-list first))
      (parachute:is equal '(0 1) (reverse reads))
      (parachute:is = 0 *census-random-access-work*))
    (let ((second (sl:seq-first (sl:seq-rest partition))))
      (parachute:is equal '(3 4) (part03-list second))
      (parachute:is equal '(0 1 2 3) (reverse reads))
      (parachute:is = 0 *census-random-access-work*))))

(defun claim-census-stream (items observer &optional (index 0))
  (sl:make-lazy-seq
   (lambda ()
     (funcall observer index)
     (if items
         (sl:lazy-cons (car items)
                       (claim-census-stream (cdr items) observer (1+ index)))
         nil))))

(parachute:define-test claim-census.frequencies-consumes-before-return
  (let* ((nodes nil)
         (source (claim-census-stream '(1 2 1) (lambda (index) (push index nodes))))
         (result (sl:dict-frequencies source)))
    (parachute:is equal '(0 1 2 3) (reverse nodes))
    (parachute:is = 2 (sl:dict-size result))
    (parachute:is = 2 (sl:dict-ref result 1))
    (parachute:is = 1 (sl:dict-ref result 2))))

(defvar *claim-census-dictionary-events* nil)

(defclass claim-census-tracked-batch (batch-child) ())

(defmethod sl:seq-emptyp :around ((source claim-census-tracked-batch))
  (push :dictionary-empty *claim-census-dictionary-events*)
  (call-next-method))

(defmethod sl:seq-first :around ((source claim-census-tracked-batch))
  (push :dictionary-first *claim-census-dictionary-events*)
  (call-next-method))

(defmethod sl:seq-rest :around ((source claim-census-tracked-batch))
  (push :dictionary-rest *claim-census-dictionary-events*)
  (call-next-method))

(defun claim-census-tracked-dictionary ()
  (make-instance 'claim-census-tracked-batch
                 :test 'equal
                 :pairs '((:a . 1) (:b . 2) (:c . 3))))

(defun claim-census-dictionary-traversal-events ()
  (append (loop repeat 3 append
                '(:dictionary-empty :dictionary-first :dictionary-rest))
          '(:dictionary-empty)))

(parachute:define-test claim-census.select-remove-keys-consume-keys-before-one-traversal
  (dolist (operation (list #'sl:dict-select-keys #'sl:dict-remove-keys))
    (let* ((*claim-census-dictionary-events* nil)
           (key-nodes nil)
           (keys (claim-census-stream '(:b)
                                      (lambda (index)
                                        (push (list :key-node index) key-nodes)
                                        (push (list :key-node index)
                                              *claim-census-dictionary-events*))))
           (dictionary (claim-census-tracked-dictionary))
           (result (funcall operation dictionary keys)))
      (parachute:is equal
                    (append '((:key-node 0) (:key-node 1))
                            (claim-census-dictionary-traversal-events))
                    (reverse *claim-census-dictionary-events*))
      (parachute:is equal '((:key-node 0) (:key-node 1)) (reverse key-nodes))
      (parachute:is = (if (eq operation #'sl:dict-select-keys) 1 2)
                    (sl:dict-size result)))))

(parachute:define-test claim-census.reduce-kv-visits-all-entries-with-constant-accumulator
  (let* ((*claim-census-dictionary-events* nil)
         (calls 0)
         (dictionary (claim-census-tracked-dictionary))
         (result (sl:dict-reduce-kv (lambda (accumulator key value)
                                      (declare (ignore key value))
                                      (incf calls)
                                      :constant)
                                    :constant dictionary)))
    (parachute:is eq :constant result)
    (parachute:is = 3 calls)
    (parachute:is equal (claim-census-dictionary-traversal-events)
                  (reverse *claim-census-dictionary-events*))))

(parachute:define-test claim-census.count-by-calls-key-once-per-element-eagerly
  (let* ((nodes nil)
         (calls 0)
         (source (claim-census-stream '(1 2 3 4)
                                      (lambda (index) (push index nodes))))
         (result (sl:dict-count-by (lambda (element) (incf calls) (mod element 2))
                                   source)))
    (parachute:is equal '(0 1 2 3 4) (reverse nodes))
    (parachute:is = 4 calls)
    (parachute:is = 2 (sl:dict-ref result 0))
    (parachute:is = 2 (sl:dict-ref result 1))))

(defmethod sl:seq-rest ((source claim-census-tracked-batch))
  (make-instance (class-of source)
                 :test (batch-test source)
                 :pairs (cdr (batch-pairs source))))
