(in-package #:sophie-lisp.tests)

;;;; Independent Chapter 6 scalar LAST tests; no Chapter 6 fixture dependencies.
(defun l01-q0-lazy (items observe)
  (sl:make-lazy-seq
   (lambda ()
     (funcall observe (if items (car items) :end))
     (if items (sl:lazy-cons (car items) (l01-q0-lazy (cdr items) observe)) nil))))

(defclass l01-q0-source () ((items :initarg :items :reader l01-q0-items)))
(defmethod sl:seqablep ((s l01-q0-source)) t)
(defmethod sl:seq-emptyp ((s l01-q0-source)) (null (l01-q0-items s)))
(defmethod sl:seq-first ((s l01-q0-source)) (car (l01-q0-items s)))
(defmethod sl:seq-rest ((s l01-q0-source))
  (make-instance 'l01-q0-source :items (cdr (l01-q0-items s))))
(defmethod sl:make-collector-for ((s l01-q0-source) &key)
  (error "Scalar LAST must not create a Collector."))

(parachute:define-test seq-last.finite-source-last-element
  (parachute:is eq t (typep (fdefinition 'sl:seq-last) 'generic-function))
  (loop for n from 1 to 40
        for items = (loop for i below n collect (mod (+ (* i 17) n) 31))
        do (parachute:is eql (car (last items)) (sl:seq-last items))
           (parachute:is eql (car (last items)) (sl:seq-last (coerce items 'vector))))
  (parachute:is eql #\c (sl:seq-last "abc"))
  (parachute:is eql 2 (sl:seq-last (make-array 4 :initial-contents '(1 2 99 99) :fill-pointer 2)))
  (parachute:is eq nil (sl:seq-last '(1 nil)))
  (dolist (key '(:test :test-not :key :start))
    (parachute:is eq t (handler-case (progn (funcall 'sl:seq-last '(1) key nil) nil)
                         (program-error () t)))))

(parachute:define-test seq-last.lazy-memoization-and-end-discovery
  (let* ((events nil) (source (l01-q0-lazy '(1 2 3) (lambda (x) (push x events)))))
    (parachute:is eql 3 (sl:seq-last source))
    (parachute:is equal '(1 2 3 :end) (reverse events))
    (parachute:is eql 3 (sl:seq-last source))
    (parachute:is equal '(1 2 3 :end) (reverse events)))
  ;; A finite sentinel witnesses required end discovery without a hanging test.
  (let* ((marker (make-condition 'simple-error :format-control "end sentinel"))
         (events nil)
         (source (l01-q0-lazy '(1 2 3) (lambda (x) (push x events)
                                        (when (eq x :end) (error marker))))))
    (parachute:is eq marker (handler-case (sl:seq-last source) (error (c) c)))
    (parachute:is equal '(1 2 3 :end) (reverse events))))

(parachute:define-test seq-last.empty-and-invalid-sources
  (dolist (source (list nil #() "" (sl:make-lazy-seq (lambda () nil))
                        (make-instance 'l01-q0-source :items nil)))
    (parachute:is eq t (handler-case (progn (sl:seq-last source) nil) (simple-error () t))))
  (parachute:is eql 9 (sl:seq-last (make-instance 'l01-q0-source :items '(3 nil 9))))
  (parachute:is eq t (handler-case (progn (sl:seq-last 42) nil) (type-error () t)))
  (parachute:is eq t (handler-case (progn (sl:seq-last '(1 . 42)) nil) (type-error () t))))

;;;; Independent finite models and fixtures. QUERY2/3 depend on QUERY1 and may
;;;; use these fixtures; QUERY0/4/REDUCE do not depend on this file.
(defun l01-q1-lazy (items observe)
  (sl:make-lazy-seq
   (lambda ()
     (funcall observe (if items (car items) :end))
     (if items (sl:lazy-cons (car items) (l01-q1-lazy (cdr items) observe)) nil))))
(defun l01-q1-list (source)
  (loop with view = source
        for step below 10000
        until (sl:seq-emptyp view)
        collect (sl:seq-first view)
        do (setf view (sl:seq-rest view))
        finally (unless (sl:seq-emptyp view)
                  (parachute:true nil "L01-Q1-LIST exceeded its finite fixture bound"))))
(defclass l01-q1-source () ((items :initarg :items :reader l01-q1-items)))
(defmethod sl:seqablep ((s l01-q1-source)) t)
(defmethod sl:seq-emptyp ((s l01-q1-source)) (null (l01-q1-items s)))
(defmethod sl:seq-first ((s l01-q1-source)) (car (l01-q1-items s)))
(defmethod sl:seq-rest ((s l01-q1-source))
  (make-instance 'l01-q1-source :items (cdr (l01-q1-items s))))
(defmethod sl:make-collector-for ((s l01-q1-source) &key)
  (error "Scalar query must not reconstruct."))
(defun l01-q1-error (thunk type)
  ;; ECL's TYPEP returns a truthy class-precedence list, not T, when the
  ;; signaled condition's class is a strict subclass of TYPE; normalize to a
  ;; strict boolean so the EQ-T assertions hold on every host.
  (handler-case (progn (funcall thunk) nil)
    (error (c) (if (typep c type) t nil))))

(defun l01-q1-model (items target start end backwards positionp)
  (let ((answer nil) (found nil))
    (loop for x in items for i from 0
          when (and (<= start i) (< i end) (= target (abs x)))
            do (when (or backwards (not found))
                 (setf found t answer (if positionp i x))))
    answer))
(defun l01-q1-normal (operation predicatep positionp)
  (parachute:is eq t (typep (fdefinition operation) 'generic-function))
  ;; Reproducible arithmetic corpus; no production or CL query as oracle.
  (loop for seed from 1 to 30
        for items = (loop for i below 9 collect (- (mod (+ seed (* i 7)) 11) 5))
        for start = (mod seed 5)
        for end = (+ start 4)
        for target = (mod seed 6)
        do (dolist (backwards '(nil t))
             (dolist (source (list (copy-list items) (coerce items 'vector)))
               (parachute:is eql (l01-q1-model items target start end backwards positionp)
                 (funcall operation (if predicatep (lambda (x) (= x target)) target)
                          source :key #'abs :start start :end end :from-end backwards)))))
  (let ((argument (if predicatep (lambda (x) (= x 2)) 2)))
    (parachute:is eql (if positionp 1 2)
      (funcall operation argument #(1 2 3) :key nil :end 99))
    (parachute:is eq nil (funcall operation argument #(1 2 3) :start 3))
    (parachute:is eq nil (funcall operation argument #(1 2 3) :start 1 :end 1))
    (parachute:is eq nil
      (funcall operation argument (make-array 4 :initial-contents '(1 3 2 2) :fill-pointer 2)))
    (dolist (keyword (if predicatep '(:test :test-not :count) '(:test-not :count)))
      (parachute:is eq t (l01-q1-error (lambda () (funcall operation argument #(1 2) keyword nil))
                                     'program-error))))
  (unless predicatep
    (let* ((element (list 1 2)) (source (vector element)))
      (parachute:is eql (if positionp 0 element) (funcall operation (list 1 2) source)))))

(defun l01-q1-front (operation predicatep positionp)
  (let* ((events nil) (keys nil) (calls nil)
         (source (l01-q1-lazy '(9 -2 7) (lambda (x) (push x events)
                                            (when (eql x 7) (error "read past match")))))
         (argument (if predicatep (lambda (x) (push x calls) (values (= x 2) :ignored)) 2))
         (options (unless predicatep
                    (list :test (lambda (item x) (push (list item x) calls)
                                  (values (= item x) :ignored))))))
    (parachute:is eql (if positionp 1 -2)
      (apply operation argument source :start 1 :key (lambda (x) (push x keys) (values (abs x) :ignored)) options))
    (parachute:is equal '(9 -2) (reverse events))
    (parachute:is equal '(-2) (reverse keys))
    (parachute:is equal (if predicatep '(2) '((2 2))) (reverse calls)))
  (parachute:is eql (if positionp 0 2)
    (funcall operation (if predicatep (lambda (x) (= x 2)) 2) '(2 . 99))))

(defun l01-q1-errors-and-back (operation predicatep positionp)
  (let ((argument (if predicatep (lambda (x) (= x 2)) 2)))
    (let ((events nil) (keys nil))
      (parachute:is eql (if positionp 3 -2)
        (funcall operation argument
                 (l01-q1-lazy '(9 -2 7 -2 8) (lambda (x) (push x events)
                                               (when (eql x 8) (error "past END"))))
                 :start 1 :end 4 :from-end t
                 :key (lambda (x) (push x keys) (abs x))))
      (parachute:is equal '(9 -2 7 -2) (reverse events))
      (parachute:is equal '(-2) (reverse keys)))
    (parachute:is eql (if positionp 2 2)
      (funcall operation argument (make-instance 'l01-q1-source :items '(8 9 2)) :start 1 :key nil))
    (dolist (options '((:start -1) (:start 1/2) (:end 1/2) (:start 2 :end 1)
                       (:key 23)))
      (let ((forces 0))
        (parachute:is eq t
          (l01-q1-error (lambda () (apply operation argument
                                    (l01-q1-lazy '(1 2) (lambda (x) (declare (ignore x)) (incf forces)))
                                    options)) 'type-error))
        (parachute:is = 0 forces)))
    (parachute:is eq t (l01-q1-error (lambda () (funcall operation argument #(1) :start 2)) 'type-error))
    (parachute:is eq t (l01-q1-error (lambda () (funcall operation argument
                                               (l01-q1-lazy '(1) (lambda (x) (declare (ignore x))))
                                               :start 2)) 'type-error))
    (parachute:is eq t (l01-q1-error (lambda () (funcall operation argument 23)) 'type-error))
    (let ((marker (make-condition 'simple-error :format-control "key sentinel")))
      (parachute:is eq marker
        (handler-case (funcall operation argument '(1 2) :key (lambda (x) (declare (ignore x)) (error marker)))
          (error (c) c))))
    (let ((forces 0))
      (parachute:is eq t
        (l01-q1-error (lambda ()
                       (if predicatep
                           (funcall operation 23 (l01-q1-lazy '(1) (lambda (x) (declare (ignore x)) (incf forces))))
                           (funcall operation argument (l01-q1-lazy '(1) (lambda (x) (declare (ignore x)) (incf forces))) :test 23)))
                     'type-error))
      (parachute:is = 0 forces))))

(defun l01-q1-unordered-view (operation predicatep positionp)
  ;; No order is assumed, and no separate primitive calls form an oracle.
  ;; The callbacks expose this operation's own retained view.
  (let ((table (make-hash-table)) (seen nil) (answer nil))
    (setf (gethash :a table) 11 (gethash :b table) 21 (gethash :c table) 31)
    (setf answer
          (funcall operation
                   (if predicatep (lambda (x) (= x 2)) 2) table
                   :key (lambda (entry)
                          (push (list (sl:entry-key entry) (sl:entry-value entry)) seen)
                          (sl:entry-value entry))))
    (parachute:is eq nil answer)
    (parachute:is equal '(11 21 31) (sort (mapcar #'second seen) #'<))
    (parachute:is equal '(:a :b :c) (sort (mapcar #'first seen) #'string<)))
  (let ((table (make-hash-table)) (seen nil))
    (setf (gethash :a table) 11 (gethash :b table) 21 (gethash :c table) 31)
    (let ((answer (funcall operation
                          (if predicatep (lambda (x) (= x 21)) 21) table
                          :key (lambda (entry) (push entry seen) (sl:entry-value entry)))))
      (if positionp
          (parachute:is = (1- (length seen)) answer)
          (parachute:is eq (car seen) answer))
      (parachute:is eql 21 (sl:entry-value (car seen))))))

(parachute:define-test seq-find.bounded-keyed-search
  (l01-q1-normal 'sl:seq-find nil nil))

(parachute:define-test seq-find.stops-at-first-match
  (l01-q1-front 'sl:seq-find nil nil))

(parachute:define-test seq-find.reverse-search-errors-and-hash-table-view
  (l01-q1-errors-and-back 'sl:seq-find nil nil)
  (l01-q1-unordered-view 'sl:seq-find nil nil))

(parachute:define-test seq-find-if.bounded-keyed-search
  (l01-q1-normal 'sl:seq-find-if t nil))

(parachute:define-test seq-find-if.stops-at-first-match
  (l01-q1-front 'sl:seq-find-if t nil))

(parachute:define-test seq-find-if.reverse-search-errors-and-hash-table-view
  (l01-q1-errors-and-back 'sl:seq-find-if t nil)
  (l01-q1-unordered-view 'sl:seq-find-if t nil))

(parachute:define-test seq-position.bounded-keyed-search
  (l01-q1-normal 'sl:seq-position nil t))

(parachute:define-test seq-position.stops-at-first-match
  (l01-q1-front 'sl:seq-position nil t))

(parachute:define-test seq-position.reverse-search-errors-and-hash-table-view
  (l01-q1-errors-and-back 'sl:seq-position nil t)
  (l01-q1-unordered-view 'sl:seq-position nil t))

(parachute:define-test seq-position-if.bounded-keyed-search
  (l01-q1-normal 'sl:seq-position-if t t))

(parachute:define-test seq-position-if.stops-at-first-match
  (l01-q1-front 'sl:seq-position-if t t))

(parachute:define-test seq-position-if.reverse-search-errors-and-hash-table-view
  (l01-q1-errors-and-back 'sl:seq-position-if t t)
  (l01-q1-unordered-view 'sl:seq-position-if t t))

(parachute:define-test seq-queries.find-and-position-reject-unknown-keywords
  (parachute:fail
   (sl:seq-find 1 '(1) :allow-other-keys t :unsupported nil)
   program-error)
  (parachute:fail
   (sl:seq-find-if #'identity '(1) :allow-other-keys t :unsupported nil)
   program-error)
  (parachute:fail
   (sl:seq-position 1 '(1) :allow-other-keys t :unsupported nil)
   program-error)
  (parachute:fail
   (sl:seq-position-if #'identity '(1) :allow-other-keys t :unsupported nil)
   program-error))

(parachute:define-test seq-queries.zero-end-regions-do-not-force-position-zero
  (let ((marker (make-condition 'simple-error :format-control "find sentinel")))
    (parachute:is eq nil
      (sl:seq-find 1
        (l01-q1-lazy '(1) (lambda (item) (declare (ignore item)) (error marker)))
        :end 0)))
  (let ((marker (make-condition 'simple-error :format-control "position sentinel")))
    (parachute:is eq nil
      (sl:seq-position 1
        (l01-q1-lazy '(1) (lambda (item) (declare (ignore item)) (error marker)))
        :end 0)))
  (let ((marker (make-condition 'simple-error :format-control "count sentinel")))
    (parachute:is = 0
      (sl:seq-count 1
        (l01-q1-lazy '(1) (lambda (item) (declare (ignore item)) (error marker)))
        :end 0)))
  (let ((marker (make-condition 'simple-error :format-control "search sentinel")))
    (parachute:is eql 0
      (sl:seq-search
       (l01-q1-lazy '(1) (lambda (item) (declare (ignore item)) (error marker)))
       nil :end1 0)))
  (let ((marker (make-condition 'simple-error :format-control "mismatch sentinel")))
    (parachute:is eq nil
      (sl:seq-mismatch
       (l01-q1-lazy '(1) (lambda (item) (declare (ignore item)) (error marker)))
       nil :end1 0))))

;;;; QUERY1 provides only the protocol fixtures, never expected answers.

(parachute:define-test seq-member.matching-suffix-across-representations
  (parachute:is eq t (typep (fdefinition 'sl:seq-member) 'generic-function))
  (loop for n from 1 to 20
        for items = (loop for i below n collect i)
        for index = (floor n 2)
        do (dolist (source (list items (coerce items 'vector)))
             (let ((tail (sl:seq-member index source :test #'eql :key #'identity)))
               (parachute:is equal (nthcdr index items) (l01-q1-list tail)))))
  (let ((tail (sl:seq-member #\b "abc" :key nil)))
    (parachute:is eq t (typep tail 'sl:lazy-seq))
    (parachute:is equal '(#\b #\c) (l01-q1-list tail)))
  (let ((tail (sl:seq-member '(2) #((1) (2) (3)))))
    (parachute:is equal '((2) (3)) (l01-q1-list tail)))
  (dolist (keyword '(:test-not :start :end :from-end :count))
    (parachute:is eq t (l01-q1-error (lambda () (funcall 'sl:seq-member 2 #(1 2) keyword nil)) 'program-error))))

(parachute:define-test seq-member.no-match-and-exhaustion
  (dolist (source (list nil #() '(1 3) #(1 3)))
    (parachute:is eq nil (sl:seq-member 2 source)))
  (let ((events nil) (keys nil))
    (parachute:is eq nil
      (sl:seq-member 2 (l01-q1-lazy '(1 3) (lambda (x) (push x events)))
                     :key (lambda (x) (push x keys) x)))
    (parachute:is equal '(1 3 :end) (reverse events))
    (parachute:is equal '(1 3) (reverse keys))))

(parachute:define-test seq-member.lazy-tail-and-callback-boundaries
  (let* ((events nil) (keys nil) (tests nil)
         (marker (make-condition 'simple-error :format-control "tail sentinel"))
         (source (l01-q1-lazy '(1 -2 3 4)
                   (lambda (x) (push x events) (when (eql x 4) (error marker)))))
         (tail (sl:seq-member 2 source
                 :key (lambda (x) (push x keys) (when (eql x 4) (error "key after match")) (abs x))
                 :test (lambda (a b) (push (list a b) tests) (= a b)))))
    (parachute:is equal '(1 -2) (reverse events))
    (parachute:is eq t (typep tail 'sl:lazy-seq))
    (parachute:is eql -2 (sl:seq-first tail))
    (parachute:is equal '(1 -2) (reverse events))
    (parachute:is eql 3 (sl:seq-first (sl:seq-rest tail)))
    (parachute:is equal '(1 -2 3) (reverse events))
    (parachute:is equal '(1 -2) (reverse keys))
    (parachute:is equal '((2 1) (2 2)) (reverse tests))
    (parachute:is eq marker
      (handler-case (sl:seq-first (sl:seq-rest (sl:seq-rest tail))) (error (c) c)))
    (parachute:is equal '(1 -2) (reverse keys)))
  (parachute:is equal '(2 3)
    (l01-q1-list (sl:seq-member 2 (make-instance 'l01-q1-source :items '(1 2 3)))))
  (dolist (option '(:test :key))
    (let ((forces 0))
      (parachute:is eq t
        (l01-q1-error (lambda () (funcall 'sl:seq-member 2
                                  (l01-q1-lazy '(1) (lambda (x) (declare (ignore x)) (incf forces)))
                                  option 42)) 'type-error))
      (parachute:is = 0 forces)))
  (parachute:is eq t (l01-q1-error (lambda () (sl:seq-member 2 42)) 'type-error))
  (let ((marker (make-condition 'simple-error :format-control "query key")))
    (parachute:is eq marker
      (handler-case (sl:seq-member 2 '(1 2) :key (lambda (x) (declare (ignore x)) (error marker)))
        (error (c) c)))))

(defun l01-q2-count-normal (operation predicatep)
  (parachute:is eq t (typep (fdefinition operation) 'generic-function))
  (loop for seed from 1 to 30
        for items = (loop for i below 8 collect (- (mod (+ (* seed 3) (* i 5)) 9) 4))
        for target = (mod seed 5)
        for start = (mod seed 4)
        for expected = (loop for x in items for i from 0 count (and (<= start i) (< i 7) (= (abs x) target)))
        do (dolist (backwards '(nil t))
             (parachute:is = expected
               (funcall operation (if predicatep (lambda (x) (= x target)) target)
                        (coerce items 'vector) :key #'abs :start start :end 7 :from-end backwards))))
  (let ((argument (if predicatep #'oddp 1)))
    (parachute:is = 0 (funcall operation argument nil))
    (parachute:is = 2 (funcall operation argument #(1 2 1) :key nil :end 99))
    (parachute:is = 0 (funcall operation argument #(1 2 1) :start 3))
    (parachute:is = 1 (funcall operation argument
                       (make-array 4 :initial-contents '(1 2 1 1) :fill-pointer 2)))
    (dolist (keyword (if predicatep '(:test :test-not :count) '(:test-not :count)))
      (parachute:is eq t (l01-q1-error (lambda () (funcall operation argument '(1) keyword nil)) 'program-error)))))
(defun l01-q2-count-timing (operation predicatep)
  (dolist (backwards '(nil t))
    (let ((forces nil) (keys nil) (calls nil))
      (parachute:is = 2
        (apply operation
               (if predicatep (lambda (x) (push x calls) (values (= x 2) :ignored)) 2)
               (l01-q1-lazy '(9 -2 3 2 8) (lambda (x) (push x forces) (when (eql x 8) (error "past END"))))
               :start 1 :end 4 :from-end backwards
               :key (lambda (x) (push x keys) (values (abs x) :ignored))
               (unless predicatep (list :test (lambda (a b) (push (list a b) calls) (values (= a b) :ignored))))))
      (parachute:is equal '(9 -2 3 2) (reverse forces))
      (parachute:is equal (if backwards '(2 3 -2) '(-2 3 2)) (reverse keys))
      (parachute:is equal (if predicatep '(2 3 2) '((2 2) (2 3) (2 2))) (reverse calls))))
  (let ((forces nil))
    (parachute:is = 2 (funcall operation (if predicatep #'oddp 1)
                              (l01-q1-lazy '(1 2 1) (lambda (x) (push x forces)))))
    (parachute:is equal '(1 2 1 :end) (reverse forces))))
(defun l01-q2-count-errors (operation predicatep)
  (let ((argument (if predicatep #'oddp 1)))
    (parachute:is = 2 (funcall operation argument (make-instance 'l01-q1-source :items '(1 2 1))))
    (dolist (options '((:start -1) (:end -1) (:start 1/2) (:end 1/2) (:start 2 :end 1) (:key 42)))
      (let ((forces 0))
        (parachute:is eq t
          (l01-q1-error (lambda () (apply operation argument
                                    (l01-q1-lazy '(1) (lambda (x) (declare (ignore x)) (incf forces))) options)) 'type-error))
        (parachute:is = 0 forces)))
    (parachute:is eq t (l01-q1-error (lambda () (funcall operation argument '(1) :start 2)) 'type-error))
    (parachute:is eq t (l01-q1-error (lambda () (funcall operation argument 42)) 'type-error))
    (let ((marker (make-condition 'simple-error :format-control "count traversal")))
      (parachute:is eq marker
        (handler-case (funcall operation argument
                       (l01-q1-lazy '(1 2 3) (lambda (x) (when (eq x :end) (error marker)))))
          (error (c) c)))
      (parachute:is eq marker
        (handler-case (funcall operation argument '(1) :key (lambda (x) (declare (ignore x)) (error marker)))
          (error (c) c))))
    (parachute:is eq t
      (l01-q1-error (lambda () (if predicatep (funcall operation 42 '(1))
                                 (funcall operation argument '(1) :test 42))) 'type-error))))

(parachute:define-test seq-count.bounded-keyed-count
  (l01-q2-count-normal 'sl:seq-count nil))

(parachute:define-test seq-count.forcing-and-callback-order
  (l01-q2-count-timing 'sl:seq-count nil))

(parachute:define-test seq-count.validation-and-error-propagation
  (l01-q2-count-errors 'sl:seq-count nil))

(parachute:define-test seq-count-if.bounded-keyed-count
  (l01-q2-count-normal 'sl:seq-count-if t))

(parachute:define-test seq-count-if.forcing-and-callback-order
  (l01-q2-count-timing 'sl:seq-count-if t))

(parachute:define-test seq-count-if.validation-and-error-propagation
  (l01-q2-count-errors 'sl:seq-count-if t))

(parachute:define-test seq-queries.member-and-count-reject-unknown-keywords
  (parachute:fail
   (sl:seq-member 1 '(1) :allow-other-keys t :unsupported nil)
   program-error)
  (parachute:fail
   (sl:seq-count 1 '(1) :allow-other-keys t :unsupported nil)
   program-error)
  (parachute:fail
   (sl:seq-count-if #'identity '(1) :allow-other-keys t :unsupported nil)
   program-error))

(defclass l01-q3-observed-source (l01-q1-source)
  ((observe :initarg :observe :reader l01-q3-observe)))
(defmethod sl:seqablep ((source l01-q3-observed-source))
  (funcall (l01-q3-observe source) :activate) t)

(defun l01-q3-empty-search-regressions ()
  ;; 6.1.2: only the prefix before START2 is needed for an empty pattern.
  (dolist (start '(0 2))
    (let ((events nil))
      (parachute:is eql start
        (handler-case
            (sl:seq-search nil
              (l01-q1-lazy '(10 11 12)
                (lambda (x) (push x events)
                  (when (eql x (if (zerop start) 10 12)) (error "subject boundary"))))
              :start2 start)
          (error (c) c)))
      (parachute:is equal (if (zerop start) nil '(10 11)) (reverse events))))
  (let ((events nil))
    (parachute:is eq t
      (l01-q1-error
       (lambda () (sl:seq-search nil
                    (l01-q1-lazy '(10 11) (lambda (x) (push x events))) :start2 3))
       'type-error))
    (parachute:is equal '(10 11 :end) (reverse events))))

(defun l01-q3-prefix-regressions ()
  ;; Literal CLHS alignment answers in SOURCE1 coordinates, never SOURCE2.
  (dolist (row '(((9 1 1) (8 8 1 1 1) 1 2 3 1)
                 ((9 1 1 1) (8 8 1 1) 1 2 3 2)
                 ((9) (8 8 1) 1 2 1 1)
                 ((9 1) (8 8) 1 2 1 2)
                 ((9) (8 8) 1 2 nil nil)))
    (destructuring-bind (a b start1 start2 forward backward) row
      (dolist (from-end '(nil t))
        (parachute:is eql (if from-end backward forward)
          (sl:seq-mismatch (copy-list a) (coerce b 'vector)
                           :start1 start1 :start2 start2 :from-end from-end)))))
  (dolist (from-end '(nil t))
    (parachute:is eql 1
      (sl:seq-mismatch '(9 7) '(8 8 1) :start1 1 :end1 1
                       :start2 2 :from-end from-end))
    (parachute:is eql (if from-end 2 1)
      (sl:seq-mismatch '(9 1) '(8 8 7) :start1 1
                       :start2 2 :end2 2 :from-end from-end))))

(defun l01-q3-activation-regressions ()
  ;; 6.1.3/6.1.5: syntax first, then first force before source2 activation.
  (dolist (from-end '(nil t))
    (dolist (instrumented '(nil t))
      (let* ((events nil)
             (marker (make-condition 'simple-error :format-control "first source"))
             (right (if instrumented
                        (make-instance 'l01-q3-observed-source :items '(1)
                          :observe (lambda (x) (push x events))) 42)))
        (parachute:is eq marker
          (handler-case
              (sl:seq-mismatch
               (l01-q1-lazy '(1) (lambda (x) (push x events) (error marker)))
               right :from-end from-end)
            (error (c) c)))
        (parachute:is equal '(1) (reverse events))))
    (dolist (options '((:start1 -1) (:start2 -1) (:end1 1/2)
                       (:end2 1/2) (:start1 2 :end1 1) (:start2 2 :end2 1)))
      (let ((events nil))
        (parachute:is eq t
          (l01-q1-error
           (lambda ()
             (apply #'sl:seq-mismatch
                    (l01-q1-lazy '(1) (lambda (x) (push x events)))
                    (make-instance 'l01-q3-observed-source :items '(1)
                      :observe (lambda (x) (push x events)))
                    :from-end from-end options)) 'type-error))
        (parachute:is equal nil events)))))

(defun l01-q3-reverse-regressions ()
  ;; 6.1.4: each key observes a complete pair, whether keys are immediate
  ;; or deferred. Record forces, keys, and tests in one chronological log.
  (let ((events nil) (premature nil))
    (parachute:is eql 1
      (sl:seq-mismatch
       (l01-q1-lazy '(11 12) (lambda (x) (push (list :a x) events)))
       (l01-q1-lazy '(21 22) (lambda (x) (push (list :b x) events)))
       :from-end t
       :key (lambda (x)
              (let ((i (mod x 10)))
                (unless (and (member (list :a (+ 10 i)) events :test #'equal)
                             (member (list :b (+ 20 i)) events :test #'equal))
                  (setf premature t)))
              (push (list :key x) events) x)
       :test (lambda (a b) (push (list :test a b) events)
               (= (if (= a 22) 12 a) (if (= b 22) 12 b)))))
    (parachute:is eq nil premature)
    (parachute:is equal '((:a 11) (:b 21) (:a 12) (:b 22) (:a :end) (:b :end))
      (remove-if-not (lambda (event) (member (car event) '(:a :b))) (reverse events)))
    (parachute:is equal '((:test 12 22) (:test 11 21))
      (remove-if-not (lambda (event) (eq (car event) :test)) (reverse events)))
    (parachute:is equal '(11 12 21 22)
      (sort (mapcar #'second (remove-if-not (lambda (event) (eq (car event) :key)) events)) #'<)))
  ;; No key/test for an incomplete tuple. Check the chronological first pair,
  ;; not total forcing: right alignment may require the longer region's end
  ;; (6.1.2 and SEQ-MISMATCH), unlike the forward one-node exhaustion check.
  (dolist (empty-left '(nil t))
    (let ((events nil) (marker (make-condition 'simple-error :format-control "incomplete key")))
      (parachute:is eql (if empty-left 0 1)
        (handler-case
            (sl:seq-mismatch
             (l01-q1-lazy (unless empty-left '(1)) (lambda (x) (push (list :a x) events)))
             (l01-q1-lazy (when empty-left '(2)) (lambda (x) (push (list :b x) events)))
             :from-end t :key (lambda (x) (declare (ignore x)) (error marker))
             :test (lambda (a b) (declare (ignore a b)) (error marker)))
          (error (c) c)))
      (let ((chronological (reverse events)))
        (parachute:is equal (if empty-left '((:a :end) (:b 2)) '((:a 1) (:b :end)))
          (subseq chronological 0 (min 2 (length chronological)))))))
  (let ((events nil) (marker (make-condition 'simple-error :format-control "complete key")))
    (parachute:is eq marker
      (handler-case
          (sl:seq-mismatch
           (l01-q1-lazy '(1) (lambda (x) (push (list :a x) events)))
           (l01-q1-lazy '(2) (lambda (x) (push (list :b x) events)))
           :from-end t :key (lambda (x) (push (list :key x) events) (error marker)))
        (error (c) c)))
    (let ((chronological (reverse events)))
      (parachute:is equal '((:a 1) (:b 2)) (subseq chronological 0 (min 2 (length chronological)))))))




(defun l01-q3-corpus ()
  (loop for n from 0 to 3 append
    (loop for bits below (ash 1 n) collect
      (loop for i below n collect (ldb (byte 1 i) bits)))))
(defun l01-q3-search-model (pattern source backwards)
  (let ((answer nil))
    (loop for i from 0 to (- (length source) (length pattern))
          when (loop for x in pattern for y in (nthcdr i source) always (= x y))
            do (setf answer i) (unless backwards (return)))
    answer))
(defun l01-q3-mismatch-model (a b backwards)
  (if backwards
      (let ((i (1- (length a))) (j (1- (length b))))
        (loop while (and (>= i 0) (>= j 0) (= (nth i a) (nth j b))) do (decf i) (decf j))
        (unless (and (= i -1) (= j -1)) (1+ i)))
      (let ((i 0))
        (loop while (and (< i (length a)) (< i (length b)) (= (nth i a) (nth i b))) do (incf i))
        (unless (= i (length a) (length b)) i))))
(defun l01-q3-binary-normal (operation model)
  (parachute:is eq t (typep (fdefinition operation) 'generic-function))
  (dolist (a (l01-q3-corpus))
    (dolist (b (l01-q3-corpus))
      (dolist (backwards '(nil t))
        (parachute:is eql (funcall model a b backwards)
          (funcall operation (coerce a 'vector) (copy-list b) :test #'eql :key nil :from-end backwards)))))
  (parachute:is eq t (l01-q1-error (lambda () (funcall operation '(1) '(1) :test-not nil)) 'program-error)))
(defun l01-q3-binary-errors (operation)
  (dolist (options '((:start1 -1) (:start2 -1) (:end1 1/2) (:end2 1/2)
                     (:start1 2 :end1 1) (:start2 2 :end2 1) (:key 42) (:test 42)))
    (let ((forces 0))
      (parachute:is eq t
        (l01-q1-error (lambda () (apply operation
                                  (l01-q1-lazy '(1) (lambda (x) (declare (ignore x)) (incf forces)))
                                  (l01-q1-lazy '(1) (lambda (x) (declare (ignore x)) (incf forces))) options)) 'type-error))
      (parachute:is = 0 forces)))
  (dolist (options '((:start1 2) (:start2 2)))
    (parachute:is eq t (l01-q1-error (lambda () (apply operation '(1) '(1) options)) 'type-error)))
  (parachute:is eq t (l01-q1-error (lambda () (funcall operation '(1) 42)) 'type-error))
  (let ((marker (make-condition 'simple-error :format-control "binary test sentinel")))
    (parachute:is eq marker
      (handler-case (funcall operation '(1) '(1) :test (lambda (a b) (declare (ignore a b)) (error marker)))
        (error (c) c)))))

(parachute:define-test seq-search.bounded-forward-and-reverse-matches
  (l01-q3-binary-normal 'sl:seq-search #'l01-q3-search-model)
  (parachute:is eql 2 (sl:seq-search #(9 2 3 8) #(0 0 2 3 0) :start1 1 :end1 3 :start2 1 :end2 99))
  (parachute:is eql 3 (sl:seq-search "ab" "zabab" :from-end t))
  (parachute:is eql 1 (sl:seq-search #((1)) #((0) (1)) ))
  (parachute:is eq nil (sl:seq-search #(2) (make-array 3 :initial-contents '(0 1 2) :fill-pointer 2))))

(parachute:define-test seq-search.pattern-first-forcing-and-short-circuit
  (let ((events nil) (keys nil))
    (parachute:is eql 1
      (sl:seq-search
       (l01-q1-lazy '(2 3) (lambda (x) (push (list :p x) events)))
       (l01-q1-lazy '(1 2 3 4) (lambda (x) (push (list :s x) events) (when (eql x 4) (error "past match"))))
       :key (lambda (x) (push x keys) x)))
    (parachute:is equal '((:p 2) (:p 3) (:p :end) (:s 1) (:s 2) (:s 3)) (reverse events))
    ;; Keys may interleave with pairwise tests, but never repeat per element.
    (parachute:is equal '(1 2 2 3 3) (sort (copy-list keys) #'<)))
  (let ((subject-forces 0) (marker (make-condition 'simple-error :format-control "pattern sentinel")))
    (parachute:is eq marker
      (handler-case
          (sl:seq-search (l01-q1-lazy '(1 2) (lambda (x) (when (eq x :end) (error marker))))
                         (l01-q1-lazy '(1 2) (lambda (x) (declare (ignore x)) (incf subject-forces))))
        (error (c) c)))
    (parachute:is = 0 subject-forces))
  (l01-q3-empty-search-regressions)
)

(parachute:define-test seq-search.validation-and-reverse-end-discovery
  (l01-q3-binary-errors 'sl:seq-search)
  (let ((events nil))
    (parachute:is eql 3
      (sl:seq-search '(2 3) (l01-q1-lazy '(1 2 3 2 3) (lambda (x) (push x events))) :from-end t))
    (parachute:is equal '(1 2 3 2 3 :end) (reverse events)))
  (parachute:is eql 1 (sl:seq-search (make-instance 'l01-q1-source :items '(2 3))
                                    (make-instance 'l01-q1-source :items '(1 2 3)))))

(parachute:define-test seq-mismatch.region-alignment-and-source-coordinates
  (l01-q3-binary-normal 'sl:seq-mismatch #'l01-q3-mismatch-model)
  (parachute:is eql 3 (sl:seq-mismatch #(9 1 2 8) #(0 0 1 2 7) :start1 1 :start2 2))
  (parachute:is eq nil (sl:seq-mismatch #((1) (2)) '((1) (2))))
  (parachute:is eq nil (sl:seq-mismatch #(1 2) #(1 2) :end1 99 :end2 99))
  (parachute:is eql 1 (sl:seq-mismatch #(1 2 3) #(9 2 3) :from-end t))
  (l01-q3-prefix-regressions)
)

(parachute:define-test seq-mismatch.pairwise-forcing-and-short-circuit
  (dolist (right '((1) (1 2)))
    (let ((events nil) (calls nil))
      (parachute:is eql (if (cdr right) 1 nil)
        (sl:seq-mismatch
         (l01-q1-lazy '(1) (lambda (x) (push (list :a x) events)))
         (l01-q1-lazy right (lambda (x) (push (list :b x) events)))
         :test (lambda (a b) (push (list a b) calls) (= a b))))
      (parachute:is equal (list '(:a 1) '(:b 1) '(:a :end) (list :b (if (cdr right) 2 :end)))
        (reverse events))
      (parachute:is equal '((1 1)) (reverse calls))))
  (let ((events nil))
    (parachute:is eql 0
      (sl:seq-mismatch
       (l01-q1-lazy '(1 8) (lambda (x) (push (list :a x) events) (when (eql x 8) (error "tail"))))
       (l01-q1-lazy '(2 9) (lambda (x) (push (list :b x) events) (when (eql x 9) (error "tail"))))))
    (parachute:is equal '((:a 1) (:b 2)) (reverse events)))
  (parachute:is eql 1 (sl:seq-mismatch '(1 2) '(1)))
  (parachute:is eq nil (sl:seq-mismatch nil nil))
  (l01-q3-activation-regressions)
)

(parachute:define-test seq-mismatch.reverse-callback-order-and-errors
  (l01-q3-binary-errors 'sl:seq-mismatch)
  (let ((calls nil))
    (parachute:is eql 1
      (sl:seq-mismatch (l01-q1-lazy '(1 2 3) (lambda (x) (declare (ignore x))))
                       (l01-q1-lazy '(9 2 3) (lambda (x) (declare (ignore x))))
                       :from-end t :test (lambda (a b) (push (list a b) calls) (= a b))))
    (parachute:is equal '((3 3) (2 2) (1 9)) (reverse calls)))
  (parachute:is eq nil (sl:seq-mismatch (make-instance 'l01-q1-source :items '(1 2))
                                      (make-instance 'l01-q1-source :items '(1 2))))
  (l01-q3-reverse-regressions)
)

(defun l01-q3-truth-normal (operation somep)
  (parachute:is eq t (typep (fdefinition operation) 'generic-function))
  (parachute:is eql (if somep 4 nil)
    (funcall operation (lambda (a b) (and (> b a) b)) '(1 3) #(0 4)))
  (parachute:is eq (if somep nil t) (funcall operation #'identity nil))
  (parachute:is eq (if somep :yes t) (funcall operation (lambda (x) (declare (ignore x)) :yes) '(1 2)))
  (parachute:is eq nil (funcall operation (lambda (x) (declare (ignore x)) nil) '(1 2)))
  (parachute:is eq (if somep :yes t)
    (funcall operation (lambda (a b c d) (and (= a b c d) :yes)) '(1 2) #(1 2) '(1 2) #(1 2)))
  (dolist (keyword '(:key :test :test-not))
    (parachute:is eq t (l01-q1-error (lambda () (funcall operation #'identity '(1) keyword #'identity)) 'type-error))))
(defun l01-q3-truth-timing (operation somep)
  (let ((events nil) (calls 0))
    (parachute:is eq (if somep :answer nil)
      (funcall operation (lambda (a b) (declare (ignore a b)) (incf calls) (values (if somep :answer nil) :ignored))
               (l01-q1-lazy '(1 8) (lambda (x) (push (list :a x) events) (when (eql x 8) (error "tail"))))
               (l01-q1-lazy '(2 9) (lambda (x) (push (list :b x) events) (when (eql x 9) (error "tail"))))))
    (parachute:is equal '((:a 1) (:b 2)) (reverse events))
    (parachute:is = 1 calls))
  (loop for empty-index below 4 do
    (let ((events nil) (calls 0))
      (parachute:is eq (if somep nil t)
        (apply operation (lambda (&rest xs) (declare (ignore xs)) (incf calls) (not somep))
               (loop for i below 4 collect
                 (let ((index i))
                   (l01-q1-lazy (unless (= i empty-index) '(1))
                     (lambda (x) (declare (ignore x)) (push index events)
                       (when (> index empty-index) (error "read after exhausted source"))))))))
      (parachute:is equal (loop for i to empty-index collect i) (reverse events))
      (parachute:is = 0 calls))))
(defun l01-q3-truth-errors (operation somep)
  (parachute:is eq (if somep :yes t)
    (funcall operation (lambda (a b) (and (= a b) :yes))
             (make-instance 'l01-q1-source :items '(1 2)) '(1)))
  (let ((marker (make-condition 'simple-error :format-control "predicate sentinel")))
    (parachute:is eq marker
      (handler-case (funcall operation (lambda (x) (declare (ignore x)) (error marker)) '(1)) (error (c) c))))
  (let ((forces 0))
    (parachute:is eq t (l01-q1-error (lambda () (funcall operation 42
                                               (l01-q1-lazy '(1) (lambda (x) (declare (ignore x)) (incf forces))))) 'type-error))
    (parachute:is = 0 forces))
  (parachute:is eq t (l01-q1-error (lambda () (funcall operation #'identity 42)) 'type-error)))

(parachute:define-test seq-every.multi-source-truth-values
  (l01-q3-truth-normal 'sl:seq-every nil))

(parachute:define-test seq-every.short-circuit-and-exhaustion-order
  (l01-q3-truth-timing 'sl:seq-every nil))

(parachute:define-test seq-every.validation-and-error-propagation
  (l01-q3-truth-errors 'sl:seq-every nil))

(parachute:define-test seq-some.multi-source-truth-values
  (l01-q3-truth-normal 'sl:seq-some t))

(parachute:define-test seq-some.short-circuit-and-exhaustion-order
  (l01-q3-truth-timing 'sl:seq-some t))

(parachute:define-test seq-some.validation-and-error-propagation
  (l01-q3-truth-errors 'sl:seq-some t))

(parachute:define-test seq-queries.binary-keyword-validation-and-empty-reverse-mismatch
  (parachute:fail
   (sl:seq-search '(1) '(1) :allow-other-keys t :unsupported nil)
   program-error)
  (parachute:fail
   (sl:seq-mismatch '(1) '(1) :allow-other-keys t :unsupported nil)
   program-error)
  (let ((marker (make-condition 'simple-error :format-control "right tail")))
    (parachute:is eql 0
      (sl:seq-mismatch
       nil
       (l01-q1-lazy '(1) (lambda (item)
                            (when (eq item :end) (error marker))))
       :from-end t))))

;;;; This unit deliberately does not depend on QUERY1 or QUERY3 fixtures.
(defun l01-q4-lazy (items observe)
  (sl:make-lazy-seq (lambda () (funcall observe (if items (car items) :end))
                     (if items (sl:lazy-cons (car items) (l01-q4-lazy (cdr items) observe)) nil))))
(defun l01-q4-error (thunk type)
  ;; ECL's TYPEP returns a truthy class-precedence list, not T, when the
  ;; signaled condition's class is a strict subclass of TYPE; normalize to a
  ;; strict boolean so the EQ-T assertions hold on every host.
  (handler-case (progn (funcall thunk) nil)
    (error (c) (if (typep c type) t nil))))
(defclass l01-q4-source () ((items :initarg :items :reader l01-q4-items)))
(defmethod sl:seqablep ((s l01-q4-source)) t)
(defmethod sl:seq-emptyp ((s l01-q4-source)) (null (l01-q4-items s)))
(defmethod sl:seq-first ((s l01-q4-source)) (car (l01-q4-items s)))
(defmethod sl:seq-rest ((s l01-q4-source)) (make-instance 'l01-q4-source :items (cdr (l01-q4-items s))))
(defmethod sl:make-collector-for ((s l01-q4-source) &key) (error "Scalar query Collector"))

(defun l01-q4-truth-normal (operation notanyp)
  (parachute:is eq t (typep (fdefinition operation) 'generic-function))
  (parachute:is eq (not notanyp) (funcall operation #'= '(1 2) '(1 3)))
  (parachute:is eq notanyp (funcall operation #'identity nil))
  (parachute:is eq nil (funcall operation (lambda (x) (declare (ignore x)) :yes) '(1 2)))
  (parachute:is eq t (funcall operation (lambda (x) (declare (ignore x)) nil) '(1 2)))
  (parachute:is eq nil (funcall operation #'= '(1 2) #(1 2) '(1 2) #(1 2)))
  (dolist (keyword '(:key :test :test-not))
    (parachute:is eq t (l01-q4-error (lambda () (funcall operation #'identity '(1) keyword #'identity)) 'type-error))))
(defun l01-q4-truth-timing (operation notanyp)
  (let ((events nil) (calls 0))
    (parachute:is eq (not notanyp)
      (funcall operation (lambda (a b) (declare (ignore a b)) (incf calls) (values notanyp :ignored))
               (l01-q4-lazy '(1 8) (lambda (x) (push (list :a x) events) (when (eql x 8) (error "tail"))))
               (l01-q4-lazy '(2 9) (lambda (x) (push (list :b x) events) (when (eql x 9) (error "tail"))))))
    (parachute:is equal '((:a 1) (:b 2)) (reverse events))
    (parachute:is = 1 calls))
  (loop for empty-index below 4 do
    (let ((events nil) (calls 0))
      (parachute:is eq notanyp
        (apply operation (lambda (&rest xs) (declare (ignore xs)) (incf calls) (not notanyp))
               (loop for i below 4 collect
                 (let ((index i))
                   (l01-q4-lazy (unless (= i empty-index) '(1))
                     (lambda (x) (declare (ignore x)) (push index events)
                       (when (> index empty-index) (error "read after exhaustion"))))))))
      (parachute:is equal (loop for i to empty-index collect i) (reverse events))
      (parachute:is = 0 calls))))
(defun l01-q4-truth-errors (operation)
  (parachute:is eq nil (funcall operation #'= (make-instance 'l01-q4-source :items '(1 2)) '(1)))
  (let ((marker (make-condition 'simple-error :format-control "predicate sentinel")))
    (parachute:is eq marker
      (handler-case (funcall operation (lambda (x) (declare (ignore x)) (error marker)) '(1)) (error (c) c))))
  (let ((forces 0))
    (parachute:is eq t (l01-q4-error (lambda () (funcall operation 42
                                               (l01-q4-lazy '(1) (lambda (x) (declare (ignore x)) (incf forces))))) 'type-error))
    (parachute:is = 0 forces))
  (parachute:is eq t (l01-q4-error (lambda () (funcall operation #'identity 42)) 'type-error)))

(defun l01-q4-extreme-normal (operation maxp)
  (parachute:is eq t (typep (fdefinition operation) 'generic-function))
  (loop for seed from 1 to 40
        for items = (loop for i below 7 collect (- (mod (+ seed (* i 11)) 19) 9))
        for expected = (let ((best (car items)))
                         (dolist (x (cdr items) best) (when (if maxp (> x best) (< x best)) (setf best x))))
        do (parachute:is eql expected (funcall operation items :key nil))
           (parachute:is eql expected (funcall operation (coerce items 'vector) :default :unused)))
  (parachute:is eql (if maxp 3 1) (funcall operation #(3 1 2) :key #'identity))
  (parachute:is eql (if maxp 2 1)
    (funcall operation (make-array 4 :initial-contents '(1 2 -99 99) :fill-pointer 2)))
  (dolist (keyword '(:test :test-not :start :end :from-end))
    (parachute:is eq t (l01-q4-error (lambda () (funcall operation '(1) keyword nil)) 'program-error))))
(defun l01-q4-extreme-timing (operation maxp)
  (let* ((a (copy-seq "aa")) (b (copy-seq "b")) (events nil) (keys nil))
    (parachute:is eq (if maxp a b)
      (funcall operation (l01-q4-lazy (list a b) (lambda (x) (push x events)))
               :key (lambda (x) (push x keys) (values (length x) :ignored))))
    (parachute:is equal (list a b :end) (reverse events))
    (parachute:is equal (list a b) (reverse keys)))
  (let* ((a (list 3 :a)) (b (list 3 :b)) (answer (funcall operation (list a b) :key #'car)))
    (parachute:is eq t (or (eq answer a) (eq answer b))))
  (let ((marker (make-condition 'simple-error :format-control "end required")))
    (parachute:is eq marker
      (handler-case (funcall operation (l01-q4-lazy '(1 2 3) (lambda (x) (when (eq x :end) (error marker)))))
        (error (c) c)))))
(defun l01-q4-extreme-errors (operation maxp)
  (dolist (source (list nil #() (sl:make-lazy-seq (lambda () nil))))
    (parachute:is eq :empty (funcall operation source :default :empty))
    (parachute:is eq nil (funcall operation source :default nil))
    (parachute:is eq t (l01-q4-error (lambda () (funcall operation source)) 'simple-error)))
  (parachute:is eq t (l01-q4-error (lambda () (funcall operation '(1 #c(2 3)))) 'simple-error))
  (parachute:is eq t (l01-q4-error (lambda () (funcall operation '(1 "a"))) 'simple-error))
  (parachute:is eq t (l01-q4-error (lambda () (funcall operation '(1 "a") :default :fallback))
                                  'simple-error))
  (parachute:is eql (if maxp 3 1)
    (funcall operation (make-instance 'l01-q4-source :items '(3 1 2))))
  (parachute:is eq t (l01-q4-error (lambda () (funcall operation 42)) 'type-error))
  (let ((forces 0))
    (parachute:is eq t
      (l01-q4-error (lambda () (funcall operation
                                (l01-q4-lazy '(1) (lambda (x) (declare (ignore x)) (incf forces)))
                                :key 42)) 'type-error))
    (parachute:is = 0 forces))
  (let ((marker (make-condition 'simple-error :format-control "key sentinel")))
    (parachute:is eq marker
      (handler-case
          (funcall operation '(1) :key (lambda (x) (declare (ignore x)) (error marker)))
        (error (c) c)))))

(parachute:define-test seq-notevery.multi-source-truth-values
  (l01-q4-truth-normal 'sl:seq-notevery nil))

(parachute:define-test seq-notevery.short-circuit-and-exhaustion-order
  (l01-q4-truth-timing 'sl:seq-notevery nil))

(parachute:define-test seq-notevery.validation-and-error-propagation
  (l01-q4-truth-errors 'sl:seq-notevery))

(parachute:define-test seq-notany.multi-source-truth-values
  (l01-q4-truth-normal 'sl:seq-notany t))

(parachute:define-test seq-notany.short-circuit-and-exhaustion-order
  (l01-q4-truth-timing 'sl:seq-notany t))

(parachute:define-test seq-notany.validation-and-error-propagation
  (l01-q4-truth-errors 'sl:seq-notany))

(parachute:define-test seq-min.finite-source-extrema
  (l01-q4-extreme-normal 'sl:seq-min nil))

(parachute:define-test seq-min.keyed-identity-and-end-discovery
  (l01-q4-extreme-timing 'sl:seq-min nil))

(parachute:define-test seq-min.empty-defaults-and-errors
  (l01-q4-extreme-errors 'sl:seq-min nil))

(parachute:define-test seq-max.finite-source-extrema
  (l01-q4-extreme-normal 'sl:seq-max t))

(parachute:define-test seq-max.keyed-identity-and-end-discovery
  (l01-q4-extreme-timing 'sl:seq-max t))

(parachute:define-test seq-max.empty-defaults-and-errors
  (l01-q4-extreme-errors 'sl:seq-max t))
