(in-package #:sophie-lisp.tests)

;;;; Independent finite oracles and demand probes for the SELECT dependency chain.
;;;; S-POLICY supplies only observation and conforming extension fixtures.
(defun select-stream (items counter &optional sentinel)
  (sl:make-lazy-seq
   (lambda ()
     (incf (car counter))
     (if items
         (sl:lazy-cons (car items) (select-stream (cdr items) counter sentinel))
         (if sentinel (funcall sentinel) nil)))))

(defun select-prefix (source n)
  ;; Do not ask whether the tail after the Nth result is empty.
  (loop repeat n collect (sl:seq-first source)
        do (setf source (sl:seq-rest source))))

(defun select-vector-check (operation expected &optional (items '(1 0 1 0)))
  ;; 4 specialized sources, active length 3, plus a fresh empty result.
  (dolist (type '(bit (unsigned-byte 8) fixnum t))
    (let* ((s (make-array 4 :element-type type :initial-contents items :fill-pointer 3))
           (r (funcall operation s))
           (empty (make-array 0 :element-type type))
           (e (funcall operation empty)))
      (parachute:is equal expected (coerce r 'list))
      (parachute:is equal (array-element-type s) (array-element-type r))
      (parachute:false (eq s r))
      (parachute:is equal items (loop for i below 4 collect (aref s i)))
      (parachute:is = 0 (length e))
      (parachute:is equal (array-element-type empty) (array-element-type e))
      (parachute:false (eq empty e)))))

(defun select-subsets (operation cardinality)
  ;; Unknown unordered view: assert association identity and cardinality, never
  ;; compare positional selection with a second independently opened view.
  (dolist (kind '(eq eql equal equalp :dict))
    (let* ((keys (list (copy-seq "a") (copy-seq "b") (copy-seq "c")))
           (values (list (list 1) (list 2) (list 3)))
           (s (if (eq kind :dict)
                  (sl:dict (first keys) (first values) (second keys) (second values)
                           (third keys) (third values))
                  (let ((h (make-hash-table :test kind)))
                    (loop for k in keys for v in values do (setf (gethash k h) v)) h)))
           (r (funcall operation s)))
      (parachute:true (if (eq kind :dict) (typep r 'sl:dict) (hash-table-p r)))
      (parachute:is eq (sl:dict-test s) (sl:dict-test r))
      (parachute:is = cardinality (sl:dict-size r))
      (parachute:is = 3 (sl:dict-size s))
      (unless (eq kind :dict) (parachute:false (eq s r)))
      (let ((entries (policy-list r)))
        (parachute:is = cardinality (length entries))
        (dolist (entry entries)
          (let ((position (position (sl:entry-key entry) keys :test #'eq)))
            (parachute:true position)
            (parachute:is eq (nth position values) (sl:entry-value entry)))))))
  (let* ((s (sl:hash-set 1 2 3)) (r (funcall operation s)))
    (parachute:true (sl:hash-set-p r))
    (parachute:is = cardinality (length (policy-list r)))
    (parachute:true (subsetp (policy-list r) '(1 2 3)))
    (parachute:is = 3 (length (policy-list s)))))

(defun select-extension (operation expected)
  (let* ((reads (cons 0 0))
         (s (make-instance 'policy-source :items '(1 2 3) :reads reads))
         (r (funcall operation s)))
    (parachute:true (sl:lazy-seq-p r))
    (parachute:is = 0 (car reads))
    (parachute:is equal expected (policy-list r))
    (parachute:is = 0 (cdr reads)))
  (let* ((*policy-events* nil)
         (s (make-instance 'policy-child :items '(1 2 3) :config :retained))
         (r (funcall operation s)))
    (parachute:true (typep r 'policy-child))
    (parachute:is eq :retained (policy-config r))
    (parachute:is equal expected (policy-source-items r))
    (parachute:is = 1 (count :primary *policy-events*)))
  (dolist (phase '(:create :accumulate :result))
    (let ((*policy-refusal-phase* phase)
          (*policy-refusal* (make-condition 'policy-refusal)))
      (parachute:is eq *policy-refusal*
                    (handler-case
                        (funcall operation (make-instance 'policy-refusing :items '(1 2 3)))
                      (policy-refusal (e) e))))))

(defun select-invalid-options (operation)
  (let* ((forces (list 0)) (s (select-stream '(1) forces)))
    (dolist (options '((:start -1) (:start 1/2) (:end -1) (:end 1/2)
                       (:start 2 :end 1) (:count -1) (:count 1/2)))
      (parachute:fail (apply operation s options) 'type-error))
    (parachute:fail (funcall operation s :key 42) 'type-error)
    (parachute:fail (funcall operation s :test-not #'eql) 'program-error)
    (parachute:is = 0 (car forces)))
  (parachute:fail (funcall operation '(1 2) :start 3) 'type-error)
  ;; Removal may emit the untouched prefix before discovering invalid START.
  (let ((r (funcall operation (sl:lazy-cons 1 nil) :start 2)))
    (parachute:fail (policy-list r) 'type-error)))

(defun select-model (operation oracle)
  (dolist (back '(nil t))
    (dolist (count '(nil 0 1 2))
      (dolist (start '(0 1 3))
        (dolist (end '(3 5 9))
          (let* ((s (list 1 2 1 3 1))
                 (r (funcall operation s :from-end back :count count :start start :end end)))
            (parachute:is equal (funcall oracle s back count start (min 5 end)) r)
            (parachute:is equal '(1 2 1 3 1) s)
            (when r (parachute:false (eq s r)))))))))

(parachute:define-test seq-filter.model-and-representations
  (select-model (lambda (s &rest o) (apply #'sl:seq-filter #'oddp s o))
                (lambda (s back count start end)
                  (let ((matches (remove-if-not #'oddp (subseq s start end))))
                    (if count (if back (last matches (min count (length matches)))
                                  (subseq matches 0 (min count (length matches)))) matches))))
  (select-vector-check (lambda (s) (sl:seq-filter #'oddp s :key nil)) '(1 1))
  (parachute:fail (sl:seq-filter #'oddp nil :test #'eql) 'program-error)
  (parachute:fail (sl:seq-filter #'oddp nil :test-not #'eql) 'program-error))

(parachute:define-test seq-remove.model-and-representations
  (select-model (lambda (s &rest o) (apply #'sl:seq-remove 1 s o))
                (lambda (s back count start end)
                  (remove 1 s :from-end back :count count :start start :end end)))
  (select-vector-check (lambda (s) (sl:seq-remove 1 s :key nil)) '(0))
  (parachute:is equal '(2) (sl:seq-remove 1 '(1 1.0 2)))
  (parachute:is equal '(1.0 2) (sl:seq-remove 1 '(1 1.0 2) :test #'eql)))

(parachute:define-test seq-remove-if.model-and-representations
  (select-model (lambda (s &rest o) (apply #'sl:seq-remove-if #'oddp s o))
                (lambda (s back count start end)
                  (remove-if #'oddp s :from-end back :count count :start start :end end)))
  (select-vector-check (lambda (s) (sl:seq-remove-if #'oddp s :key nil)) '(0))
  (parachute:fail (sl:seq-remove-if #'oddp nil :test #'eql) 'program-error))

(parachute:define-test seq-filter.forcing-and-retry
  (let* ((forces (list 0)) (calls nil)
         (s (select-stream '(2 3) forces (lambda () (error "Past retained count"))))
         (r (sl:seq-filter (lambda (x) (push x calls) (oddp x)) s :count 1)))
    (parachute:is = 0 (car forces))
    (parachute:is equal nil calls)
    (parachute:is equal '(3) (policy-list r))
    (parachute:is = 2 (car forces))
    (parachute:is equal '(3 2) calls)
    (parachute:is equal '(3) (policy-list r))
    (parachute:is = 2 (car forces)))
  (let* ((forces (list 0)) (s (select-stream '(1) forces)))
    (parachute:true (sl:seq-emptyp (sl:seq-filter #'oddp s :count 0)))
    (parachute:is = 0 (car forces)))
  (let* ((n (list 0)) (keys nil)
         (r (sl:seq-filter #'oddp (select-stream '(1 2 3 4) n) :end 4
                          :count 1 :from-end t :key (lambda (x) (push x keys) x))))
    (parachute:is = 0 (car n))
    (parachute:is equal '(3) (policy-list r))
    (parachute:is = 4 (car n))
    (parachute:is = 4 (length keys))
    (parachute:is equal '(1 2 3 4) (sort keys #'<)))
  (select-match-retry
   (lambda (s k p back) (sl:seq-filter p s :key k :from-end back :count 2 :end 3))
   '(1) nil))

(defun select-remove-timing (operation)
  (let* ((n (list 0)) (keys nil)
         (r (funcall operation (select-stream '(1 2 1 3) n)
                     :count 1 :from-end t :end 4
                     :key (lambda (x) (push x keys) x))))
    (parachute:is = 0 (car n))
    (parachute:is equal nil keys)
    (parachute:is = 1 (sl:seq-first r))
    (parachute:is = 4 (car n))
    (parachute:is = 4 (length keys))
    (parachute:is equal '(1 2 3) (policy-list r))
    (parachute:is equal '(1 2 3) (policy-list r))
    (parachute:is = 4 (length keys)))
  (let* ((s (list 1 2 1))
         (r (funcall operation s :count 0 :key (lambda (x) (declare (ignore x))
                                                       (error "Matching disabled")))))
    (parachute:is equal s r)
    (parachute:false (eq s r)))
  (let ((r (funcall operation (sl:lazy-cons 1 nil) :start 2)))
    (parachute:is = 1 (sl:seq-first r))
    (parachute:fail (sl:seq-first (sl:seq-rest r)) 'type-error))
  ;; Default front traversal must not buffer the untouched suffix.
  (let* ((forces (list 0))
         (s (select-stream '(1 2) forces (lambda () (error "Untouched tail"))))
         (r (funcall operation s)))
    (parachute:is = 0 (car forces))
    (parachute:is = 2 (sl:seq-first r))
    (parachute:is = 2 (car forces)))
  ;; Unlike a trivially empty filter, removal still returns the prefix.
  (parachute:fail (funcall operation '(1) :start 2 :end 2) 'type-error)
  (let ((r (funcall operation (sl:lazy-cons 1 nil) :start 2 :end 2)))
    (parachute:is = 1 (sl:seq-first r))
    (parachute:fail (policy-list r) 'type-error)))

(parachute:define-test seq-remove.forcing-and-retry
  (select-remove-timing (lambda (s &rest o) (apply #'sl:seq-remove 1 s o)))
  (select-match-retry (lambda (s k p back) (sl:seq-remove 1 s :test (lambda (a b) (funcall p b) (= a b)) :key k :from-end back :count 2 :end 3)) '(0 2) t))
(parachute:define-test seq-remove-if.forcing-and-retry
  (select-remove-timing (lambda (s &rest o)
                         (apply #'sl:seq-remove-if (lambda (x) (= x 1)) s o)))
  (select-match-retry (lambda (s k p back) (sl:seq-remove-if p s :key k :from-end back :count 2 :end 3)) '(0 2) t))

(parachute:define-test seq-filter.extensions-and-validation
  (select-subsets (lambda (s) (sl:seq-filter (constantly t) s :count 2)) 2)
  (select-extension (lambda (s) (sl:seq-filter #'oddp s)) '(1 3))
  (select-invalid-options (lambda (s &rest o) (apply #'sl:seq-filter #'oddp s o)))
  (let ((calls 0))
    (let ((r (sl:seq-filter (lambda (e) (incf calls) (oddp (sl:entry-value e)))
                            (sl:dict :a 1 :b 2 :c 3))))
      (parachute:is = 3 calls)
      (parachute:is = 2 (sl:dict-size r))))
  (select-rotating-check (lambda (s) (sl:seq-filter (constantly t) s :start 1 :end 4))
                         (lambda (v) (subseq v 1 4))))

(parachute:define-test seq-remove.extensions-and-validation
  (select-subsets (lambda (s) (sl:seq-remove :absent s :count 0)) 3)
  (select-extension (lambda (s) (sl:seq-remove 2 s)) '(1 3))
  (select-invalid-options (lambda (s &rest o) (apply #'sl:seq-remove 2 s o))))

(parachute:define-test seq-remove-if.extensions-and-validation
  (select-subsets (lambda (s) (sl:seq-remove-if (constantly t) s :count 1)) 2)
  (select-extension (lambda (s) (sl:seq-remove-if #'evenp s)) '(1 3))
  (select-invalid-options (lambda (s &rest o) (apply #'sl:seq-remove-if #'evenp s o))))

(defclass select-rotating-source ()
  ((items :initarg :items :reader select-rotating-items)
   (opens :initform 0 :accessor select-rotating-opens)
   (view :accessor select-rotating-view)))

(defmethod sl:seqablep ((s select-rotating-source)) t)

(defmethod sl:seq-emptyp ((s select-rotating-source)) nil)

(defmethod sl:seq-first ((s select-rotating-source))
  (car (select-rotating-items s)))

(defmethod sl:seq-rest ((s select-rotating-source))
  ;; Every root REST opens a new legal order. The head is fixed; the suffix
  ;; rotates. Each returned cursor is persistent and coherent. Expected values
  ;; come from this recorded opening, never from another source traversal.
  (let* ((tail (cdr (select-rotating-items s)))
         (n (mod (select-rotating-opens s) (length tail)))
         (order (append (nthcdr n tail) (subseq tail 0 n))))
    (incf (select-rotating-opens s))
    (setf (select-rotating-view s) (cons (car (select-rotating-items s)) order))
    (make-instance 'policy-source :items order)))

(defmethod sl:seq-length ((s select-rotating-source))
  (error "Selection must traverse, not ask for length"))

(defmethod sl:seq-ref ((s select-rotating-source) index &optional default)
  (declare (ignore index default))
  (error "Selection must traverse, not index a different view"))

(defun select-rotating-check (operation oracle &optional (items '(0 1 2 3 4)))
  (let ((s (make-instance 'select-rotating-source :items items)) (previous nil))
    (dotimes (i 3)
      (let* ((r (funcall operation s)) (actual (policy-list r))
             (view (select-rotating-view s)))
        (parachute:is = (1+ i) (select-rotating-opens s))
        (parachute:is equal (funcall oracle view) actual)
        (when previous (parachute:false (equal previous view)))
        (setf previous view)
        (parachute:is equal actual (policy-list r))
        (parachute:is = (1+ i) (select-rotating-opens s))))))

(defun select-match-retry (operation expected streaming)
  ;; A successful key is not repeated when the following matcher escapes.
  ;; Position 0 has already progressed when position 1 throws.
  (dolist (back '(nil t))
    (let* ((tag (gensym)) (escaped nil) (keys nil) (matches nil) (n (list 0))
           (r (funcall operation
                       (select-stream '(0 1 2) n)
                       (lambda (x) (push x keys) x)
                       (lambda (x)
                         (push x matches)
                         (when (and (= x 1) (not escaped))
                           (setf escaped t) (throw tag :match-escape))
                         (= x 1))
                       back)))
      (parachute:is = 0 (car n))
      (when (and streaming (not back))
        (parachute:is = 0 (sl:seq-first r)))
      (parachute:is eq :match-escape (catch tag (policy-list r) :miss))
      (parachute:is equal expected (policy-list r))
      (parachute:is equal '(0 1 2) (sort (copy-list keys) #'<))
      (parachute:is = 2 (count 1 matches))
      (let ((saved (copy-list matches)))
        (parachute:is equal expected (policy-list r))
        (parachute:is equal saved matches)))))

(defun select-size-errors (operation &optional positive)
  (let* ((n (list 0)) (s (select-stream '(1 2) n)))
    (dolist (bad '(-1 1/2 nil :bad))
      (parachute:fail (funcall operation bad s) 'type-error))
    (when positive (parachute:fail (funcall operation 0 s) 'program-error))
    (parachute:is = 0 (car n))))

(defun select-no-keywords (operation)
  (dolist (key '(:test :test-not :key :start :end :from-end :count))
    (parachute:fail (funcall operation nil key nil) 'program-error)))

(defun select-while-timing (operation expected prefix-size)
  (let* ((n (list 0)) (calls nil)
         (s (select-stream '(1 3 4 5) n (lambda () (error "Unneeded tail"))))
         (r (funcall operation (lambda (x) (push x calls) (oddp x)) s)))
    (parachute:is = 0 (car n))
    (parachute:is equal nil calls)
    (parachute:is equal expected (select-prefix r prefix-size))
    (parachute:is = (+ 2 prefix-size) (car n))
    (parachute:is equal '(4 3 1) calls)
    (parachute:is equal expected (select-prefix r prefix-size))
    (parachute:is equal '(4 3 1) calls)))

(parachute:define-test seq-take.representations-and-validation
  (select-vector-check (lambda (s) (sl:seq-take 2 s)) '(1 0))
  (dotimes (n 8)
    (parachute:is equal (subseq '(0 1 2 3) 0 (min n 4))
                  (sl:seq-take n '(0 1 2 3))))
  (select-no-keywords (lambda (s &rest o) (apply #'sl:seq-take 2 s o))))

(parachute:define-test seq-drop.representations-and-validation
  (select-vector-check (lambda (s) (sl:seq-drop 2 s)) '(1))
  (dotimes (n 8)
    (parachute:is equal (nthcdr (min n 4) '(0 1 2 3))
                  (sl:seq-drop n '(0 1 2 3))))
  (select-no-keywords (lambda (s &rest o) (apply #'sl:seq-drop 2 s o))))

(parachute:define-test seq-take-while.representations-and-validation
  (select-vector-check (lambda (s) (sl:seq-take-while #'oddp s)) '(1))
  (parachute:is equal '(1 3) (sl:seq-take-while #'oddp '(1 3 4 5)))
  (parachute:is string= "aa" (sl:seq-take-while (lambda (x) (char= x #\a)) "aaba"))
  (select-no-keywords (lambda (s &rest o) (apply #'sl:seq-take-while #'oddp s o))))

(parachute:define-test seq-drop-while.representations-and-validation
  (select-vector-check (lambda (s) (sl:seq-drop-while #'oddp s)) '(0 1))
  (parachute:is equal '(4 5) (sl:seq-drop-while #'oddp '(1 3 4 5)))
  (parachute:is string= "ba" (sl:seq-drop-while (lambda (x) (char= x #\a)) "aaba"))
  (select-no-keywords (lambda (s &rest o) (apply #'sl:seq-drop-while #'oddp s o))))

(parachute:define-test seq-take.forcing-and-cyclic-input
  (let* ((n (list 0))
         (s (select-stream '(nil 2) n (lambda () (error "Third node forbidden"))))
         (r (sl:seq-take 2 s)))
    (parachute:is = 0 (car n))
    (parachute:is equal '(nil 2) (policy-list r))
    (parachute:is = 2 (car n))
    (parachute:is equal '(nil 2) (policy-list r))
    (parachute:is = 2 (car n)))
  (let* ((n (list 0)) (s (select-stream nil n (lambda () (error "Zero take read")))))
    (parachute:true (sl:seq-emptyp (sl:seq-take 0 s)))
    (parachute:is = 0 (car n)))
  (parachute:is equal '(7 7 7) (sl:seq-take 3 (let ((s (list 7))) (setf (cdr s) s)))))

(parachute:define-test seq-drop.forcing
  (let* ((n (list 0))
         (s (select-stream '(0 1 nil) n (lambda () (error "Beyond exposed suffix"))))
         (r (sl:seq-drop 2 s)))
    (parachute:is = 0 (car n))
    (parachute:false (sl:seq-emptyp r))
    (parachute:is eq nil (sl:seq-first r))
    (parachute:is = 3 (car n))
    (parachute:is eq nil (sl:seq-first r))
    (parachute:is = 3 (car n))))

(parachute:define-test seq-take-while.forcing
  (let* ((n (list 0)) (calls nil)
         (r (sl:seq-take-while (lambda (x) (push x calls) (oddp x))
                              (select-stream '(1 3 4) n
                                             (lambda () (error "After false boundary"))))))
    (parachute:is = 0 (car n))
    (parachute:is equal nil calls)
    (parachute:is equal '(1 3) (policy-list r))
    (parachute:is = 3 (car n))
    (parachute:is equal '(4 3 1) calls)
    (parachute:is equal '(1 3) (policy-list r))
    (parachute:is equal '(4 3 1) calls)))

(parachute:define-test seq-drop-while.forcing
  (select-while-timing #'sl:seq-drop-while '(4 5) 2))

(parachute:define-test seq-take.extensions-and-size-validation
  (select-subsets (lambda (s) (sl:seq-take 2 s)) 2)
  (select-extension (lambda (s) (sl:seq-take 2 s)) '(1 2))
  (select-size-errors #'sl:seq-take)
  (select-rotating-check (lambda (s) (sl:seq-take 3 s)) (lambda (v) (subseq v 0 3))))

(parachute:define-test seq-drop.extensions-and-size-validation
  (select-subsets (lambda (s) (sl:seq-drop 2 s)) 1)
  (select-extension (lambda (s) (sl:seq-drop 2 s)) '(3))
  (select-size-errors #'sl:seq-drop)
  (select-rotating-check (lambda (s) (sl:seq-drop 2 s)) (lambda (v) (nthcdr 2 v))))

(defun select-while-errors (operation)
  (let* ((n (list 0)) (s (select-stream '(1) n)))
    (parachute:fail (funcall operation 42 s) 'type-error)
    (parachute:is = 0 (car n)))
  (let* ((calls 0) (condition (make-condition 'simple-error))
         (r (funcall operation (lambda (x)
                                 (declare (ignore x))
                                 (when (= 1 (incf calls)) (error condition)) nil)
                     (sl:lazy-cons 1 nil))))
    (parachute:is = 0 calls)
    (parachute:is eq condition (handler-case (sl:seq-first r) (error (e) e)))
    (sl:seq-first r)
    (parachute:is = 2 calls)
    (sl:seq-first r)
    (parachute:is = 2 calls)))

(parachute:define-test seq-take-while.extensions-and-errors
  (select-subsets (lambda (s) (sl:seq-take-while (constantly t) s)) 3)
  (select-extension (lambda (s) (sl:seq-take-while #'oddp s)) '(1))
  (select-while-errors #'sl:seq-take-while))

(parachute:define-test seq-drop-while.extensions-and-errors
  (select-subsets (lambda (s) (sl:seq-drop-while (constantly nil) s)) 3)
  (select-extension (lambda (s) (sl:seq-drop-while #'oddp s)) '(2 3))
  (select-while-errors #'sl:seq-drop-while))



(parachute:define-test seq-subseq.representations-and-bounds
  ;; Start zero permits the same oracle on the typed empty source.
  (select-vector-check (lambda (s) (sl:seq-subseq s 0 2)) '(1 0))
  (parachute:is equal '(1 2) (sl:seq-subseq '(0 1 2 3) 1 3))
  (parachute:is equal '(2 3) (sl:seq-subseq '(0 1 2 3) 2 99))
  (parachute:is equal '(2 3) (sl:seq-subseq '(0 1 2 3) 2 nil))
  (parachute:is eq nil (sl:seq-subseq '(0 1 2 3) 4)))

(parachute:define-test seq-take-nth.representations-and-validation
  (select-vector-check (lambda (s) (sl:seq-take-nth 2 s)) '(1 1))
  (loop for n from 1 to 5 do
    (parachute:is equal (loop for x in '(0 1 2 3 4) for i from 0
                              when (zerop (mod i n)) collect x)
                  (sl:seq-take-nth n '(0 1 2 3 4))))
  (select-no-keywords (lambda (s &rest o) (apply #'sl:seq-take-nth 2 s o))))

(parachute:define-test seq-remove-duplicates.representations-and-validation
  (select-vector-check (lambda (s) (sl:seq-remove-duplicates s :key nil)) '(1 0))
  (parachute:is equal '(1 2 3) (sl:seq-remove-duplicates '(1 2 1 3)))
  (parachute:is equal '(2 1 3) (sl:seq-remove-duplicates '(1 2 1 3) :from-end t))
  (parachute:is equal '(1 2) (sl:seq-remove-duplicates '(1 1.0 2)))
  (parachute:is equal '(1 1.0 2) (sl:seq-remove-duplicates '(1 1.0 2) :test #'eql))
  (let* ((a (cons 1 :first)) (b (cons 1 :last))
         (r (sl:seq-remove-duplicates (list a b) :key #'car)))
    (parachute:is eq a (first r)))
  (parachute:fail (sl:seq-remove-duplicates nil :test-not #'eql) 'program-error)
  (parachute:fail (sl:seq-remove-duplicates nil :count 1) 'program-error))

(parachute:define-test seq-subseq.forcing
  (let* ((n (list 0))
         (s (select-stream '(0 1 2) n (lambda () (error "Beyond explicit end"))))
         (r (sl:seq-subseq s 1 3)))
    (parachute:is = 0 (car n))
    (parachute:is equal '(1 2) (policy-list r))
    (parachute:is = 3 (car n))
    (parachute:is equal '(1 2) (policy-list r))
    (parachute:is = 3 (car n)))
  (let* ((n (list 0))
         (r (sl:seq-subseq (select-stream '(0 1 2 3) n) 2)))
    (parachute:is = 0 (car n))
    (parachute:is = 2 (sl:seq-first r))
    (parachute:is = 3 (car n))))

(parachute:define-test seq-take-nth.forcing
  (let* ((n (list 0))
         (s (select-stream '(0 1 2 3 4) n (lambda () (error "Position five forbidden"))))
         (r (sl:seq-take-nth 2 s)))
    (parachute:is = 0 (car n))
    (parachute:is equal '(0 2 4) (select-prefix r 3))
    (parachute:is = 5 (car n))
    (parachute:is equal '(0 2 4) (select-prefix r 3))
    (parachute:is = 5 (car n))))

(parachute:define-test seq-remove-duplicates.forcing-and-retry
  (dolist (back '(nil t))
    (let* ((n (list 0)) (keys nil)
           (r (sl:seq-remove-duplicates (select-stream '(1 2 1 3) n) :from-end back
                                        :key (lambda (x) (push x keys) x))))
      (parachute:is = 0 (car n))
      (parachute:is equal nil keys)
      (parachute:is = (if back 2 1) (sl:seq-first r))
      (parachute:is = 5 (car n))
      (parachute:is equal '(1 1 2 3) (sort (copy-list keys) #'<))
      (parachute:is equal (if back '(2 1 3) '(1 2 3)) (policy-list r))
      (parachute:is = 4 (length keys))))
  ;; A finite sentinel proves both modes seek the end; never hang on infinity.
  (dolist (back '(nil t))
    (let* ((tag (gensym)) (n (list 0))
           (r (sl:seq-remove-duplicates
               (select-stream '(1 2 3) n (lambda () (throw tag :end-required)))
               :from-end back)))
      (parachute:is eq :end-required (catch tag (sl:seq-first r) :too-early))))
  (dolist (back '(nil t))
    (let* ((n (list 0)) (keys nil)
           (s (select-stream '(99 1 2 1) n (lambda () (error "At explicit END"))))
           (r (sl:seq-remove-duplicates s :start 1 :end 4 :from-end back
                                         :key (lambda (x) (push x keys) x))))
      (parachute:is = 0 (car n))
      (parachute:is equal (if back '(2 1) '(1 2)) (policy-list r))
      (parachute:is = 4 (car n))
      (parachute:is equal '(1 1 2) (sort keys #'<))))
  (select-duplicates-retry)
  (select-buffered-source-retry))

(parachute:define-test seq-subseq.extensions-and-validation
  (select-subsets (lambda (s) (sl:seq-subseq s 1 3)) 2)
  (select-extension (lambda (s) (sl:seq-subseq s 1 3)) '(2 3))
  (let* ((n (list 0)) (s (select-stream '(1) n)))
    (dolist (bounds '((-1) (1/2) (2 1) (0 -1) (0 1/2)))
      (parachute:fail (apply #'sl:seq-subseq s bounds) 'type-error))
    (parachute:is = 0 (car n))
    (let ((r (sl:seq-subseq s 2)))
      (parachute:is = 0 (car n))
      (parachute:fail (sl:seq-first r) 'type-error)))
  (parachute:fail (sl:seq-subseq '(1) 2) 'type-error)
  (parachute:fail (sl:seq-subseq nil 0 nil :key nil) 'program-error)
  (select-rotating-check (lambda (s) (sl:seq-subseq s 1 4)) (lambda (v) (subseq v 1 4)))
  ;; Trivially empty permission allows either no traversal or bounds discovery.
  (parachute:true
   (handler-case (null (sl:seq-subseq '(1) 2 2)) (type-error () t)))
  (parachute:true
   (handler-case (null (policy-list (sl:seq-subseq (sl:lazy-cons 1 nil) 2 2)))
     (type-error () t))))

(parachute:define-test seq-take-nth.extensions-and-size-validation
  (select-subsets (lambda (s) (sl:seq-take-nth 2 s)) 2)
  (select-extension (lambda (s) (sl:seq-take-nth 2 s)) '(1 3))
  (select-size-errors #'sl:seq-take-nth t)
  (select-rotating-check (lambda (s) (sl:seq-take-nth 2 s))
                         (lambda (v) (loop for x in v for i from 0
                                          when (evenp i) collect x))))

(parachute:define-test seq-remove-duplicates.extensions-and-validation
  (select-subsets #'sl:seq-remove-duplicates 3)
  (select-extension #'sl:seq-remove-duplicates '(1 2 3))
  (let ((calls 0))
    (let ((r (sl:seq-remove-duplicates (sl:dict :a 1 :b 1 :c 2)
                                      :key (lambda (e) (incf calls) (sl:entry-value e)))))
      (parachute:is = 3 calls)
      (parachute:is = 2 (sl:dict-size r))
      (parachute:is equal '(1 2) (sort (mapcar #'sl:entry-value (policy-list r)) #'<))
      (parachute:is = 3 calls)))
  ;; Read-only built-in adapter is deliberately outside the exact roster.
  (let ((r (sl:seq-remove-duplicates (sl:plist-dict-view '(:a 1 :b 2)))))
    (parachute:true (sl:lazy-seq-p r))
    (parachute:is = 2 (length (policy-list r))))
  (dolist (back '(nil t))
    (select-rotating-check
     (lambda (s) (sl:seq-remove-duplicates s :key #'car :from-end back))
     ;; CL's FROM-END convention for duplicate removal is opposite Sophie's.
     (lambda (v) (remove-duplicates v :key #'car :from-end (not back)))
     (list (cons 0 :head) (cons 1 :a) (cons 2 :b) (cons 1 :c) (cons 2 :d)))))

(defclass select-distinct-key ()
  ((id :initarg :id :reader select-distinct-id)
   (calls :initarg :calls :reader select-distinct-calls)))

(defmethod sl:hash-code ((key select-distinct-key))
  (declare (ignore key))
  0)

(defmethod sl:equals ((left select-distinct-key) (right select-distinct-key))
  (push (list (select-distinct-id left) (select-distinct-id right))
        (car (select-distinct-calls left)))
  (= (select-distinct-id left) (select-distinct-id right)))

(parachute:define-test seq-remove-duplicates.index-characterization
  (let* ((corpus (loop for i below 100
                       collect (cons (mod i 10) i)))
         (firsts (loop for i below 10 collect (cons i i)))
         (lasts (loop for i below 10 collect (cons i (+ 90 i)))))
    (parachute:is equal firsts
                  (sl:seq-remove-duplicates corpus :key #'car))
    (parachute:is equal lasts
                  (sl:seq-remove-duplicates corpus :key #'car :from-end t))
    (dolist (test '(eq eql equal equalp))
      (parachute:is equal firsts
                    (sl:seq-remove-duplicates corpus :key #'car :test test))
      (parachute:is equal lasts
                    (sl:seq-remove-duplicates corpus :key #'car
                                              :test (symbol-function test)
                                              :from-end t))))
  (dolist (back '(nil t))
    (let* ((forces (list 0))
           (a (select-stream '(1) forces))
           (b (select-stream '(1) forces))
           (source (sl:lazy-cons (cons :a a)
                                 (sl:lazy-cons (cons :b b) nil)))
           (result (sl:seq-remove-duplicates source :key #'cdr
                                             :from-end back)))
      (parachute:is = 0 (car forces))
      ;; The original linear comparison forces each keyed lazy sequence
      ;; through the terminator; hashing must add no forcing.
      (parachute:is = 1 (length (policy-list result)))
      (parachute:is = 4 (car forces))))
  (dolist (back '(nil t))
    (let* ((calls (list nil))
           (keys (loop for id in '(1 2 1 3)
                       collect (make-instance 'select-distinct-key
                                              :id id :calls calls)))
           (result (sl:seq-remove-duplicates keys :from-end back)))
      (parachute:is equal (if back '(2 1 3) '(1 2 3))
                    (mapcar #'select-distinct-id result))
      (parachute:is equal (if back '((3 1) (1 2) (3 2) (2 1) (1 1))
                            '((1 2) (2 1) (1 1) (2 3) (1 3)))
                    (reverse (car calls)))))
  (dolist (back '(nil t))
    (let ((calls nil))
      (sl:seq-remove-duplicates '(1 2 1 3) :from-end back
                                :test (lambda (prior later)
                                        (push (list prior later) calls)
                                        (= prior later)))
      (parachute:is equal (if back '((3 1) (1 2) (3 2) (2 1) (1 1))
                            '((1 2) (2 1) (1 1) (2 3) (1 3)))
                    (reverse calls)))))

(defclass select-merged-key ()
  ((label :initarg :label :reader select-merged-label)
   (hashable-p :initarg :hashable-p :reader select-merged-hashable-p)
   (calls :initarg :calls :reader select-merged-calls)))

(defmethod sl:hash-code ((key select-merged-key))
  (if (select-merged-hashable-p key)
      17
      (error "Unhashable selection key")))

(defmethod sl:equals ((prior select-merged-key) (candidate select-merged-key))
  (let ((left (select-merged-label prior))
        (right (select-merged-label candidate)))
    (when (and (member left '(:a :b :c))
               (member right '(:left-probe :right-probe)))
      (push left (car (select-merged-calls prior))))
    (or (and (eq left :duplicate) (eq right :duplicate))
        (and (eq right :right-probe) (eq left :a))
        (and (eq right :left-probe) (eq left :c)))))

(parachute:define-test seq-remove-duplicates.merged-bucket-overflow-order
  ;; The probe is last in traversal order, so A/B/C are all retained when
  ;; its bucket and overflow are merged. A wrong order changes the call trace.
  (dolist (back '(nil t))
    (let* ((calls (list nil))
           (key (lambda (label hashable-p)
                  (make-instance 'select-merged-key :label label
                                 :hashable-p hashable-p :calls calls)))
           (a (cons :a (funcall key :a t)))
           (b (cons :b (funcall key :b nil)))
           (c (cons :c (funcall key :c t)))
           (early (cons :early (funcall key :duplicate t)))
           (late (cons :late (funcall key :duplicate t)))
           (probe (cons :probe (funcall key (if back :left-probe :right-probe) t)))
           (fillers (loop for i below sophie-lisp.internal::+selection-distinct-index-threshold+
                          collect (cons i (+ 1000 i))))
           (source (if back
                       (append (list probe early) fillers (list a b c late))
                       (append (list early a b c) fillers (list late probe))))
           (result (sl:seq-remove-duplicates source :key #'cdr :from-end back))
           (entries (loop for item in source collect (cons item (cdr item)))))
      (parachute:true (> (length source)
                         sophie-lisp.internal::+selection-distinct-index-threshold+))
      (parachute:is equal (if back '(:a :b :c) '(:c :b :a))
                    (reverse (car calls)))
      (parachute:is = (- (length source) 2) (length result))
      (parachute:false (member probe result :test #'eq))
      (parachute:true (member (if back late early) result :test #'eq))
      (parachute:false (member (if back early late) result :test #'eq))
      (parachute:is equal (policy-list
                           (sophie-lisp.internal::selection-distinct-linear-result
                            (reverse entries) #'sl:equals back))
                    result))))

(parachute:define-test seq-remove-duplicates.nan-path-equivalence
  (let ((nan (hashing-nan-float)))
    (when nan
      (dolist (size '(4 513))
        (dolist (back '(nil t))
          (let ((corpus (loop for i below size collect i)))
            (flet ((outcome (test)
                     (handler-case
                         (list :result
                               (sl:seq-remove-duplicates
                                corpus :from-end back :test test
                                :key (lambda (x) (declare (ignore x)) nan)))
                       (error (condition)
                         (list :condition (class-of condition))))))
              (parachute:is equal (outcome #'sl:equals)
                            (outcome (lambda (a b) (sl:equals a b)))))))))))

(defun select-duplicates-retry ()
  (dolist (back '(nil t))
    (dolist (phase '(:key :comparison))
      (let* ((condition (make-condition 'simple-error)) (failed nil)
             (keys nil) (pairs nil) (n (list 0))
             (r (sl:seq-remove-duplicates
                 (select-stream '(1 2 1 3) n) :from-end back
                 :key (lambda (x)
                        (when (and (eq phase :key) (= x 2) (not failed))
                          (setf failed t) (error condition))
                        (push x keys) x)
                 :test (lambda (a b)
                         (push (list a b) pairs)
                         (when (and (eq phase :comparison) (not failed))
                           (setf failed t) (error condition))
                         (= a b)))))
        (parachute:is = 0 (car n))
        (parachute:is eq condition (handler-case (sl:seq-first r) (error (e) e)))
        (parachute:true (>= (car n) 2))
        (parachute:is equal (if back '(2 1 3) '(1 2 3)) (policy-list r))
        (parachute:is equal '(1 1 2 3) (sort (copy-list keys) #'<))
        (let ((saved (copy-tree pairs)))
          (parachute:is equal (if back '(2 1 3) '(1 2 3)) (policy-list r))
          (parachute:is equal saved pairs))))))

(defun select-buffered-source-retry ()
  (dolist (back '(nil t))
    (let* ((attempts 0) (keys nil) (condition (make-condition 'simple-error))
           (tail (sl:make-lazy-seq
                  (lambda ()
                    (when (= 1 (incf attempts)) (error condition))
                    (sl:lazy-cons 1 (sl:lazy-cons 3 nil)))))
           (s (sl:lazy-cons 1 (sl:lazy-cons 2 tail)))
           (r (sl:seq-remove-duplicates s :from-end back
                                         :key (lambda (x) (push x keys) x))))
      (parachute:is eq condition (handler-case (sl:seq-first r) (error (e) e)))
      (parachute:is = 1 attempts)
      (parachute:is equal (if back '(2 1 3) '(1 2 3)) (policy-list r))
      (parachute:is equal '(1 1 2 3) (sort (copy-list keys) #'<))
      (parachute:is = 2 attempts)
      (parachute:is equal (if back '(2 1 3) '(1 2 3)) (policy-list r))
      (parachute:is = 2 attempts))))

(parachute:define-test seq-dedupe.representations-and-validation
  (select-vector-check #'sl:seq-dedupe '(1 0 1))
  (parachute:is equal '(1 2 1) (sl:seq-dedupe '(1 1 2 2 1)))
  (parachute:is equal '(1 2) (sl:seq-dedupe '(1 1.0 2)))
  (parachute:fail (sl:seq-dedupe nil :key nil) 'program-error)
  (parachute:fail (sl:seq-dedupe nil :test-not #'eql) 'program-error))

(parachute:define-test seq-trim-left.representations-and-validation
  (select-vector-check (lambda (s) (sl:seq-trim-left s :predicate #'oddp)) '(0 1))
  (let* ((s (copy-seq "  x "))
         (r (sl:seq-trim-left s :predicate (lambda (c) (char= c #\Space)))))
    (parachute:is string= "x " r)
    (parachute:false (eq s r)))
  (dolist (key '(:test :test-not :key))
    (parachute:fail (funcall #'sl:seq-trim-left "" key nil) 'program-error))
)

(parachute:define-test seq-reductions.representations-and-validation
  (let* ((s (make-array 4 :element-type '(unsigned-byte 8)
                        :initial-contents '(1 2 3 99) :fill-pointer 3))
         (r (sl:seq-reductions #'+ s :initial-value 0)))
    (parachute:is equalp #(0 1 3 6) r)
    (parachute:is eq t (array-element-type r))
    (parachute:false (eq s r))
    (parachute:is = 99 (aref s 3)))
  (parachute:is equal '(10 9 7 4) (sl:seq-reductions #'- '(1 2 3) :initial-value 10))
  (dolist (key '(:test :test-not :key :count :start :end :from-end))
    (parachute:fail (funcall #'sl:seq-reductions #'+ nil key nil) 'program-error)))

(parachute:define-test seq-dedupe.forcing-and-retry
  ;; EQUAL is a lawful equivalence, but distinct EQ objects expose which
  ;; predecessor was passed even when the predecessor itself was omitted.
  (let* ((a (list 1)) (b (list 1)) (c (list 2)) (pairs nil) (n (list 0))
         (r (sl:seq-dedupe (select-stream (list a b c) n
                                          (lambda () (error "Beyond demanded run")))
                           :test (lambda (x y) (push (cons x y) pairs) (equal x y)))))
    (parachute:is = 0 (car n))
    (parachute:is eq a (sl:seq-first r))
    (parachute:is = 1 (car n))
    (parachute:is eq c (sl:seq-first (sl:seq-rest r)))
    (parachute:is = 3 (car n))
    (parachute:is eq b (caar pairs))
    (parachute:is eq c (cdar pairs))
    (parachute:is = 2 (length pairs)))
  (let* ((tag (gensym)) (escaped nil) (pairs nil) (n (list 0))
         (a (list 1)) (b (list 1)) (c (list 1)) (d (list 2))
         (r (sl:seq-dedupe (select-stream (list a b c d) n)
                           :test (lambda (x y)
                                   (push (list x y) pairs)
                                   (when (and (eq y d) (not escaped))
                                     (setf escaped t) (throw tag :comparison))
                                   (equal x y)))))
    (parachute:is eq a (sl:seq-first r))
    (let ((tail (sl:seq-rest r)))
      (parachute:is eq :comparison (catch tag (sl:seq-first tail) :miss))
      (parachute:is = 4 (car n))
      (parachute:is eq d (sl:seq-first tail))
      (parachute:is eq c (caar pairs))
      (parachute:is eq d (cadar pairs))
      (parachute:is = 4 (length pairs))
      (parachute:is eq d (sl:seq-first tail))
      (parachute:is = 4 (length pairs)))))

(parachute:define-test seq-trim-left.forcing
  (select-while-timing (lambda (p s) (sl:seq-trim-left s :predicate p)) '(4 5) 2))

(parachute:define-test seq-reductions.forcing-and-retry
  (parachute:is equal '(1 3 6) (sl:seq-reductions #'+ '(1 2 3)))
  (let* ((n (list 0)) (calls 0)
         (s (select-stream '(1 2) n (lambda () (error "Beyond finite demand"))))
         (r (sl:seq-reductions (lambda (a b) (incf calls) (+ (or a 0) b))
                               s :initial-value nil)))
    (parachute:is = 0 calls)
    (parachute:is = 0 (car n))
    (parachute:is eq nil (sl:seq-first r))
    (parachute:is = 0 (car n))
    (parachute:is equal '(nil 1 3) (select-prefix r 3))
    (parachute:is = 2 calls)
    (parachute:is = 2 (car n))
    (parachute:is equal '(nil 1 3) (select-prefix r 3))
    (parachute:is = 2 calls))
  (let* ((attempts 0) (condition (make-condition 'simple-error))
         (r (sl:seq-reductions (lambda (a b)
                                 (when (= 1 (incf attempts)) (error condition))
                                 (+ a b)) (sl:lazy-cons 1 nil) :initial-value 0))
         (tail (sl:seq-rest r)))
    (parachute:is eq condition (handler-case (sl:seq-first tail) (error (e) e)))
    (parachute:is = 1 (sl:seq-first tail))
    (parachute:is = 1 (sl:seq-first tail))
    (parachute:is = 2 attempts)))

(parachute:define-test seq-dedupe.extensions-and-validation
  (select-subsets #'sl:seq-dedupe 3)
  (select-extension #'sl:seq-dedupe '(1 2 3))
  (let ((r (sl:seq-dedupe (sl:plist-dict-view '(:a 1 :b 2)))))
    (parachute:true (sl:lazy-seq-p r))
    (parachute:is = 2 (length (policy-list r))))
  (parachute:fail (sl:seq-dedupe nil :test 42) 'error)
  (let ((symbol (gensym "LATE-EQUALITY")))
    (unwind-protect
         (progn
           (setf (symbol-function symbol) #'eql)
           (let ((r (sl:seq-dedupe (sl:lazy-cons 1 (sl:lazy-cons 1.0 nil))
                                   :test symbol)))
             (setf (symbol-function symbol) #'=)
             (parachute:is equal '(1) (policy-list r))
             (setf (symbol-function symbol) #'eql)
             (parachute:is equal '(1) (policy-list r))))
      (fmakunbound symbol)))
  (parachute:fail (sl:seq-dedupe 42) 'type-error))

(parachute:define-test seq-trim-left.extensions-and-validation
  (select-subsets (lambda (s) (sl:seq-trim-left s :predicate (constantly nil))) 3)
  (select-extension (lambda (s) (sl:seq-trim-left s :predicate #'oddp)) '(2 3))
  (parachute:fail (sl:seq-trim-left '(1)) 'program-error)
  (parachute:fail (sl:seq-trim-left "" :predicate nil) 'program-error)
  (select-while-errors (lambda (p s) (sl:seq-trim-left s :predicate p)))
  (parachute:fail (sl:seq-trim-left nil) 'program-error)
  (let* ((operations (list #'sl:seq-trim-left #'sl:seq-trim #'sl:seq-trim-right))
         (expected "A non-string trim requires :PREDICATE.")
         (reports
           (mapcar (lambda (operation)
                     (let ((condition
                             (handler-case (funcall operation '(1))
                               (program-error (condition) condition))))
                       (parachute:true (typep condition 'program-error))
                       (parachute:true (typep condition 'simple-condition))
                       (simple-condition-format-control condition)))
                   operations)))
    (parachute:is equal (list expected expected expected) reports)))

(parachute:define-test seq-reductions.empty-input-and-extensions
  (parachute:is eq nil (sl:seq-reductions #'+ nil))
  (parachute:is equal '(nil) (sl:seq-reductions #'+ nil :initial-value nil))
  (parachute:is equalp #() (sl:seq-reductions #'+ #()))
  (parachute:is equalp #(0) (sl:seq-reductions #'+ #() :initial-value 0))
  (dolist (s (list (sl:dict :a 1 :b 2)
                   (let ((h (make-hash-table)))
                     (setf (gethash :a h) 1 (gethash :b h) 2) h)))
    (let* ((calls 0)
           (r (sl:seq-reductions
               (lambda (a b) (declare (ignore b)) (incf calls)
                 (sl:map-entry :state (1+ (sl:entry-value a))))
               s :initial-value (sl:map-entry :state 0))))
      (parachute:true (sl:ordered-dict-p r))
      (parachute:is = 2 calls)
      (parachute:true (every (lambda (entry) (typep entry 'sl:map-entry))
                             (policy-list r)))
      (parachute:is = 1 (length (policy-list r)))
      (parachute:is equal '((:state 2))
                    (mapcar (lambda (entry) (list (sl:entry-key entry) (sl:entry-value entry)))
                            (policy-list r)))
      (parachute:is = 2 calls)))
  (dolist (s (list (sl:dict :a 1 :b 2)
                   (let ((h (make-hash-table)))
                     (setf (gethash :a h) 1 (gethash :b h) 2) h)))
    (parachute:fail (sl:seq-reductions (lambda (a b) (declare (ignore a b)) :bad)
                                      s :initial-value (sl:map-entry :state 0))
                    type-error))
  (dolist (source (list (sl:dict :a 1) (let ((h (make-hash-table)))
                          (setf (gethash :a h) 1) h)))
    (parachute:fail (sl:seq-reductions #'+ source :initial-value nil) type-error))
  (dolist (source (list (sl:dict) (make-hash-table)))
    (parachute:fail (sl:seq-reductions #'+ source :initial-value nil) type-error))
  (let* ((calls 0)
         (r (sl:seq-reductions (lambda (a b) (declare (ignore b)) (incf calls) (1+ a))
                               (sl:hash-set 1 2) :initial-value 0)))
    (parachute:true (sl:lazy-seq-p r))
    (parachute:is = 0 calls)
    (parachute:is equal '(0 1 2) (policy-list r))
    (parachute:is = 2 calls))
)

(defun select-subseq-vector-fixtures ()
  "Build new storage on each call so fast and generic paths cannot share it."
  (list
   (cons :empty (make-array 0 :element-type '(unsigned-byte 8)))
   (cons :plain (vector 10 20 30 40))
   (cons :specialized (make-array 4 :element-type '(unsigned-byte 8)
                                  :initial-contents '(10 20 30 40)))
   (cons :displaced
         (make-array 4 :displaced-to (vector 99 10 20 30 40 99)
                     :displaced-index-offset 1))
   (cons :fill-pointer
         (make-array 5 :fill-pointer 3 :initial-contents '(10 20 30 40 50)))
   (cons :string (coerce (list #\A (code-char #x3bb) #\B #\C) 'string))
   (cons :base-string (make-array 4 :element-type 'base-char
                                  :initial-contents '(#\A #\B #\C #\D)))
   (cons :string-fill-pointer
         (make-array 5 :element-type 'character :fill-pointer 3
                     :initial-contents '(#\A #\B #\C #\D #\E)))))

(defun select-subseq-vector-observe (source start end generic-p)
  (let ((sophie-lisp.internal::*force-generic-traversal* generic-p))
    (handler-case
        (let ((result (sl:seq-subseq source start end)))
          (list :value (coerce result 'list) (array-element-type result)
                (stringp result) (not (eq result source))
                (not (and (array-displacement result)
                          (eq (array-displacement result) source)))))
      (type-error (condition)
        (list :type-error (type-error-datum condition)
              (type-error-expected-type condition))))))

(parachute:define-test seq-subseq.direct-vector-oracle-corpus
  (dolist (bounds '((0 nil) (0 0) (0 2) (1 3) (2 2) (0 99)
                    (3 nil) (4 4) (5 5) (5 99) (99 nil)
                    (-1 nil) (1/2 nil) (0 -1) (0 1/2)
                    (3 2) (99 2)))
    (loop for fast in (select-subseq-vector-fixtures)
          for generic in (select-subseq-vector-fixtures)
          do (parachute:is equal
               (list (car generic)
                     (select-subseq-vector-observe
                      (cdr generic) (first bounds) (second bounds) t))
               (list (car fast)
                     (select-subseq-vector-observe
                      (cdr fast) (first bounds) (second bounds) nil)))))
  (loop for fast in (select-subseq-vector-fixtures)
        for generic in (select-subseq-vector-fixtures)
        for fast-result = (sl:seq-subseq (cdr fast) 0 1)
        for generic-result = (let ((sophie-lisp.internal::*force-generic-traversal* t))
                               (sl:seq-subseq (cdr generic) 0 1))
        unless (zerop (length fast-result))
          do (let ((old (aref (cdr fast) 0))
                   (replacement (if (stringp fast-result) #\Z 77)))
               (setf (aref fast-result 0) replacement
                     (aref generic-result 0) replacement)
               (parachute:is eql old (aref (cdr fast) 0))
               (parachute:is eql old (aref (cdr generic) 0))
               (setf (aref (cdr fast) 0) old)
               (parachute:is eql replacement (aref fast-result 0)))))

(defun select-nested-lazy-keys (count forces &key collision escape-p signal-p)
  (loop for index below count
        collect (cons (if (and collision (< index 2)) 0 (1+ index))
                      (sl:make-lazy-seq
                       (lambda ()
                         (incf (car forces))
                         (cond (escape-p (throw 'select-lazy-escape :escaped))
                               (signal-p (error "lazy tail forced")))
                         nil)))))

(parachute:define-test seq-remove-duplicates.nested-lazy-hash-safety
  (let ((below (1- sophie-lisp.internal::+selection-distinct-index-threshold+))
        (above (1+ sophie-lisp.internal::+selection-distinct-index-threshold+))
        (larger (+ 232 sophie-lisp.internal::+selection-distinct-index-threshold+)))
    (dolist (count (list below above larger))
      (let* ((forces (list 0))
             (source (select-nested-lazy-keys count forces))
             (result (sl:seq-remove-duplicates source)))
        (parachute:is = count (length result))
        (parachute:is = 0 (car forces))))
    (dolist (count (list below above))
      (let* ((forces (list 0))
             (source (select-nested-lazy-keys count forces :collision t))
             (result (sl:seq-remove-duplicates source)))
        (parachute:is = (1- count) (length result))
        (parachute:is = 2 (car forces))))
    (let ((forces (list 0)))
      (parachute:is eq :completed
                    (catch 'select-lazy-escape
                      (sl:seq-remove-duplicates
                       (select-nested-lazy-keys above forces :escape-p t))
                      :completed))
      (parachute:is = 0 (car forces)))
    (let ((forces (list 0)))
      (parachute:is = above
                    (length (sl:seq-remove-duplicates
                             (select-nested-lazy-keys above forces :signal-p t))))
      (parachute:is = 0 (car forces))))
  (let ((forces (list 0)))
    (multiple-value-bind (hash ok-p)
        (sophie-lisp.internal::safe-key-hash
         (cdr (first (select-nested-lazy-keys 1 forces))))
      (parachute:false hash)
      (parachute:false ok-p)
      (parachute:is = 0 (car forces))))
  (let ((cycle (cons 0 nil)))
    (setf (cdr cycle) cycle)
    (parachute:true (nth-value 1 (sophie-lisp.internal::safe-key-hash cycle))))
  (parachute:true (nth-value 1 (sophie-lisp.internal::safe-key-hash '(1 2 3)))))

(parachute:define-test seq-remove-duplicates.lazy-key-scan-atomic-fast-outs
  (let* ((forces (list 0))
         (lazy (sl:make-lazy-seq (lambda () (incf (car forces)) nil))))
    (dolist (atom (list 0 most-positive-fixnum (ash 1 200) 3/7 1.5d0 (coerce 1 'short-float) #c(1 2)
                        #\a 'scan-atom nil))
      (parachute:false (sophie-lisp.internal::lazy-key-within-hash-p atom))
      (parachute:false
       (sophie-lisp.internal::lazy-key-within-hash-p (vector atom)))
      (parachute:true
       (sophie-lisp.internal::lazy-key-within-hash-p (cons atom lazy)))
      (parachute:is = 0 (car forces)))))

(parachute:define-test seq-remove-duplicates.lazy-key-scan-array-fast-outs
  (let* ((forces (list 0))
         (lazy (sl:make-lazy-seq (lambda () (incf (car forces)) nil))))
    (dolist (array (list "abc" (vector 1.0 2.0) (vector #c(1 2))
                         (make-array 3 :element-type 'character
                                              :initial-contents '(#\a #\b #\c))
                         (make-array 3 :element-type '(unsigned-byte 8)
                                       :initial-contents '(1 2 3))
                         (make-array 3 :element-type 'bit
                                       :initial-contents '(1 0 1))
                         (make-array '(2 2) :element-type '(unsigned-byte 8)
                                             :initial-element 4)
                         (make-array 3 :fill-pointer 2
                                     :displaced-to (vector 9 10 11 12)
                                     :displaced-index-offset 1)))
      (parachute:false (sophie-lisp.internal::lazy-key-within-hash-p array))
      (parachute:true
       (sophie-lisp.internal::lazy-key-within-hash-p (vector array lazy)))
      (parachute:is = 0 (car forces)))))

(parachute:define-test seq-remove-duplicates.lazy-key-scan-compound-fallback
  (let* ((forces (list 0))
         (lazy (sl:make-lazy-seq (lambda () (incf (car forces)) nil)))
         (table (make-hash-table))
         (cycle (cons :head nil))
         (late (make-array 65 :initial-element 0)))
    (setf (gethash :value table) lazy
          (cdr cycle) cycle
          (aref late 64) lazy)
    (dolist (key (list (vector lazy) (vector (cons :nested lazy))
                       (cons :outer (vector table)) table
                       (vector (cons cycle (vector lazy)))))
      (parachute:true (sophie-lisp.internal::lazy-key-within-hash-p key))
      (multiple-value-bind (hash ok-p) (sophie-lisp.internal::safe-key-hash key)
        (parachute:false hash)
        (parachute:false ok-p))
      (parachute:is = 0 (car forces)))
    (parachute:false (sophie-lisp.internal::lazy-key-within-hash-p cycle))
    (parachute:false (sophie-lisp.internal::lazy-key-within-hash-p late))
    (parachute:is = 0 (car forces))))

(defvar *select-collector-calls* 0)

(parachute:define-test seq-subseq.collector-protocol-pristineness
  (parachute:true (sophie-lisp.internal::pristine-vector-collector-protocol-p #(1)))
  (parachute:is equalp #(2 3) (sl:seq-subseq #(1 2 3 4) 1 3))
  (let ((method nil))
    (unwind-protect
         (progn
           (setf method
                 (eval '(defmethod sl:make-collector-for :around
                            ((target vector) &rest options &key)
                          (declare (ignore options))
                          (incf sophie-lisp.tests::*select-collector-calls*)
                          (call-next-method))))
           (let ((*select-collector-calls* 0))
             (parachute:false
              (sophie-lisp.internal::pristine-vector-collector-protocol-p #(1)))
             (parachute:is equalp #(2 3) (sl:seq-subseq #(1 2 3 4) 1 3))
             (parachute:is = 1 *select-collector-calls*)
             (parachute:is string= "bc" (sl:seq-subseq "abcd" 1 3))
             (parachute:is = 2 *select-collector-calls*)))
      (when method (remove-method #'sl:make-collector-for method))))
  (parachute:true (sophie-lisp.internal::pristine-vector-collector-protocol-p #(1)))
  (let ((method nil))
    (unwind-protect
         (progn
           (setf method
                 (eval '(defmethod sl:collector-result :after
                            ((collector sophie-lisp.internal::vector-collector))
                          (incf sophie-lisp.tests::*select-collector-calls*))))
           (let ((*select-collector-calls* 0))
             (parachute:false
              (sophie-lisp.internal::pristine-vector-collector-protocol-p #(1)))
             (parachute:is equalp #(2 3) (sl:seq-subseq #(1 2 3 4) 1 3))
             (parachute:is = 1 *select-collector-calls*)))
      (when method (remove-method #'sl:collector-result method))))
  (parachute:true (sophie-lisp.internal::pristine-vector-collector-protocol-p #(1))))

;;;; Amendment coverage: the seq-subseq direct-construction fast path must meet
;;;; the same observable Collector obligations as the generic path, and must
;;;; yield to every applicable user Collector method while ignoring others.

(parachute:define-test seq-subseq.collector-accumulate-method-forces-generic
  ;; The pristineness guard also watches COLLECTOR-ACCUMULATE; a user method
  ;; there must disable direct construction and run once per accumulated element.
  (let ((method nil))
    (unwind-protect
         (progn
           (setf method
                 (eval '(defmethod sl:collector-accumulate :around
                            ((collector sophie-lisp.internal::vector-collector)
                             element)
                          (incf sophie-lisp.tests::*select-collector-calls*)
                          (call-next-method))))
           (let ((*select-collector-calls* 0))
             (parachute:false
              (sophie-lisp.internal::pristine-vector-collector-protocol-p #(1)))
             (parachute:is equalp #(2 3) (sl:seq-subseq #(1 2 3 4) 1 3))
             (parachute:is = 2 *select-collector-calls*)
             (parachute:is string= "bc" (sl:seq-subseq "abcd" 1 3))
             (parachute:is = 4 *select-collector-calls*)
             (let* ((source (make-array 4 :element-type '(unsigned-byte 8)
                                       :initial-contents '(1 2 3 4)))
                    (result (sl:seq-subseq source 1 3)))
               (parachute:is equalp #(2 3) result)
               (parachute:is equal (array-element-type source)
                             (array-element-type result))
               (parachute:false (eq source result))
               (parachute:is = 6 *select-collector-calls*))))
      (when method (remove-method #'sl:collector-accumulate method))))
  (parachute:true (sophie-lisp.internal::pristine-vector-collector-protocol-p #(1))))

(parachute:define-test seq-subseq.user-method-element-type-preservation
  ;; Under a user Collector method the generic path must still return what the
  ;; applicable Collector produces: specialized element types stay specialized.
  (let ((method nil))
    (unwind-protect
         (progn
           (setf method
                 (eval '(defmethod sl:make-collector-for :around
                            ((target vector) &rest options &key)
                          (declare (ignore options))
                          (incf sophie-lisp.tests::*select-collector-calls*)
                          (call-next-method))))
           (dolist (source (list (make-array 4 :element-type 'bit
                                             :initial-contents '(1 0 1 0))
                                 (make-array 4 :element-type '(unsigned-byte 8)
                                             :initial-contents '(10 20 30 40))
                                 (make-array 4 :element-type 'base-char
                                             :initial-contents '(#\A #\B #\C #\D))
                                 (make-array 4 :element-type 'character
                                             :initial-contents '(#\a #\b #\c #\d))))
             (let* ((*select-collector-calls* 0)
                    (result (sl:seq-subseq source 1 3)))
               (parachute:is = 1 *select-collector-calls*)
               (parachute:is equal (array-element-type source)
                             (array-element-type result))
               (parachute:false (eq source result))
               (parachute:is equalp (subseq source 1 3) result))))
      (when method (remove-method #'sl:make-collector-for method))))
  (parachute:true (sophie-lisp.internal::pristine-vector-collector-protocol-p #(1))))

(parachute:define-test seq-subseq.user-collector-refusal-parity
  ;; A user Collector refusal must surface identically whether or not direct
  ;; construction would otherwise be eligible; the fast path may not bypass it.
  (flet ((observe (source)
           (handler-case
               (list :value (sl:seq-subseq source 1 3))
             (simple-error (condition)
               (list :simple-error
                     (simple-condition-format-control condition))))))
    (let ((method nil))
      (unwind-protect
           (progn
             (setf method
                   (eval '(defmethod sl:collector-result :around
                              ((collector sophie-lisp.internal::vector-collector))
                            (error "select-user-collector-refusal"))))
             (parachute:false
              (sophie-lisp.internal::pristine-vector-collector-protocol-p #(1)))
             (dolist (source (list #(1 2 3 4) "abcd"))
               (let ((sophie-lisp.internal::*force-generic-traversal* nil))
                 (parachute:is equal '(:simple-error "select-user-collector-refusal")
                              (observe source)))
               (let ((sophie-lisp.internal::*force-generic-traversal* t))
                 (parachute:is equal '(:simple-error "select-user-collector-refusal")
                              (observe source)))))
        (when method (remove-method #'sl:collector-result method))))
    (parachute:true (sophie-lisp.internal::pristine-vector-collector-protocol-p #(1)))
    (parachute:is equalp #(2 3) (sl:seq-subseq #(1 2 3 4) 1 3))
    (parachute:is string= "bc" (sl:seq-subseq "abcd" 1 3))))

(parachute:define-test seq-subseq.user-collector-result-shape-takes-effect
  ;; The operation must return exactly what the applicable Collector produces,
  ;; including a user COLLECTOR-RESULT that reshapes the accumulated result.
  (let ((method nil))
    (unwind-protect
         (progn
           (setf method
                 (eval '(defmethod sl:collector-result :around
                            ((collector sophie-lisp.internal::vector-collector))
                          (let ((result (call-next-method)))
                            (if (stringp result)
                                result
                                (concatenate 'vector result #(99)))))))
           (parachute:false
            (sophie-lisp.internal::pristine-vector-collector-protocol-p #(1)))
           (parachute:is equalp #(2 3 99) (sl:seq-subseq #(1 2 3 4) 1 3))
           (parachute:is string= "bc" (sl:seq-subseq "abcd" 1 3)))
      (when method (remove-method #'sl:collector-result method))))
  (parachute:true (sophie-lisp.internal::pristine-vector-collector-protocol-p #(1))))

(parachute:define-test seq-subseq.inapplicable-collector-methods-keep-fast-path
  ;; Only applicable Collector methods disqualify direct construction; methods
  ;; on other targets neither disable the fast path nor take effect on vectors.
  (let ((make-method nil) (accumulate-method nil))
    (unwind-protect
         (progn
           (setf make-method
                 (eval '(defmethod sl:make-collector-for :before
                            ((target list) &rest options &key)
                          (declare (ignore options))
                          (incf sophie-lisp.tests::*select-collector-calls*)))
                 accumulate-method
                 (eval '(defmethod sl:collector-accumulate :before
                            ((collector sophie-lisp.internal::list-collector)
                             element)
                          (declare (ignore element))
                          (incf sophie-lisp.tests::*select-collector-calls*))))
           (let ((*select-collector-calls* 0))
             (parachute:true
              (sophie-lisp.internal::pristine-vector-collector-protocol-p #(1)))
             (parachute:is equalp #(2 3) (sl:seq-subseq #(1 2 3 4) 1 3))
             (parachute:is string= "bc" (sl:seq-subseq "abcd" 1 3))
             (parachute:is = 0 *select-collector-calls*)))
      (when accumulate-method
        (remove-method #'sl:collector-accumulate accumulate-method))
      (when make-method
        (remove-method #'sl:make-collector-for make-method)))))

(parachute:define-test seq-subseq.removed-builtin-collector-methods
  (let ((registry sophie-lisp.internal::*vector-collector-protocol-methods*))
    (parachute:is = 8 (length registry))
    (parachute:true (sophie-lisp.internal::pristine-vector-collector-protocol-p #(1)))
    (dolist (entry registry)
      (let ((generic (car entry)) (saved (cdr entry)))
        (unwind-protect
             (progn
               (remove-method generic saved)
               (parachute:false
                (sophie-lisp.internal::pristine-vector-collector-protocol-p #(1)))
               (let ((specializer (first (closer-mop:method-specializers saved))))
                 (cond
                   ((and (eq generic #'sl:make-collector-for)
                         (eq specializer (find-class 'vector)))
                    (let* ((source #(1 2 3 4))
                           (direct (handler-case
                                       (sl:make-collector-for source
                                                              :element-type
                                                              (array-element-type source))
                                     (type-error (condition) condition)))
                           (actual (handler-case (sl:seq-subseq source 1 3)
                                     (type-error (condition) condition))))
                      (parachute:true (typep direct 'type-error))
                      (parachute:true (typep actual 'type-error))
                      (parachute:is equal (type-error-expected-type direct)
                                    (type-error-expected-type actual))))
                   ((and (member generic (list #'sl:collector-accumulate
                                               #'sl:collector-result) :test #'eq)
                         (eq specializer
                             (find-class 'sophie-lisp.internal::vector-collector)))
                    (dolist (source (list #(1 2 3 4) "abcd"))
                      (let* ((collector (sl:make-collector-for
                                         source :element-type (array-element-type source)))
                             (direct (handler-case
                                         (if (eq generic #'sl:collector-accumulate)
                                             (sl:collector-accumulate collector
                                                                      (aref source 1))
                                             (sl:collector-result collector))
                                       (type-error (condition) condition)))
                             (actual (handler-case (sl:seq-subseq source 1 3)
                                       (type-error (condition) condition))))
                        (parachute:true (typep direct 'type-error))
                        (parachute:true (typep actual 'type-error))
                        (parachute:is equal (type-error-expected-type direct)
                                      (type-error-expected-type actual)))))
                   (t
                    ;; Removing a built-in primary or :before method disables the fast path;
                    ;; remaining primaries still handle vector and string generically.
                    (parachute:is equalp #(2 3)
                                  (sl:seq-subseq #(1 2 3 4) 1 3))
                    (parachute:is string= "bc" (sl:seq-subseq "abcd" 1 3))))))
          (add-method generic saved))
        (parachute:true
         (sophie-lisp.internal::pristine-vector-collector-protocol-p #(1)))))))

(parachute:define-test seq-subseq.collector-recapture-does-not-bless-user-method
  (let ((method nil))
    (unwind-protect
         (progn
           (setf method
                 (eval '(defmethod sl:make-collector-for :around
                            ((target vector) &rest options &key)
                          (declare (ignore options))
                          (incf sophie-lisp.tests::*select-collector-calls*)
                          (call-next-method))))
           (sophie-lisp.internal::capture-vector-collector-protocol)
           (let ((*select-collector-calls* 0))
             (parachute:false
              (sophie-lisp.internal::pristine-vector-collector-protocol-p #(1)))
             (parachute:is equalp #(2 3) (sl:seq-subseq #(1 2 3 4) 1 3))
             (parachute:is = 1 *select-collector-calls*)))
      (when method (remove-method #'sl:make-collector-for method))))
  (parachute:true (sophie-lisp.internal::pristine-vector-collector-protocol-p #(1))))

(parachute:define-test seq-subseq.collector-file-reload-lifecycle
  ;; LOAD must redefine the built-in methods before recapturing their identities.
  (let ((method nil)
        (source (merge-pathnames #p"src/core/collectors.lisp"
                                 (asdf:system-source-directory "sophie-lisp"))))
    (unwind-protect
         (progn
           (setf method
                 (eval '(defmethod sl:make-collector-for :around
                            ((target vector) &rest options &key)
                          (declare (ignore options))
                          (incf sophie-lisp.tests::*select-collector-calls*)
                          (call-next-method))))
           (load source)
           (parachute:is = 8
                         (length sophie-lisp.internal::*vector-collector-protocol-methods*))
           (let ((*select-collector-calls* 0))
             (parachute:false
              (sophie-lisp.internal::pristine-vector-collector-protocol-p #(1)))
             (parachute:is equalp #(2 3) (sl:seq-subseq #(1 2 3 4) 1 3))
             (parachute:is = 1 *select-collector-calls*))
           (remove-method #'sl:make-collector-for method)
           (setf method nil)
           (parachute:true
            (sophie-lisp.internal::pristine-vector-collector-protocol-p #(1))))
      (when method
        (remove-method #'sl:make-collector-for method))
      (sophie-lisp.internal::capture-vector-collector-protocol))))

(parachute:define-test seq-subseq.redefined-builtin-collector-method
  ;; Re-evaluating a built-in definition and recapturing mirrors a reload.
  (let ((original '(defmethod sl:collector-result ((collector t))
                      (sophie-lisp.internal::raise-type-error
                       collector 'sophie-lisp.internal::collector))))
    (unwind-protect
         (progn
           (eval original)
           (parachute:false
            (sophie-lisp.internal::pristine-vector-collector-protocol-p #(1)))
           (parachute:is equalp #(2 3) (sl:seq-subseq #(1 2 3 4) 1 3)))
      (eval original)
      (sophie-lisp.internal::capture-vector-collector-protocol))
    (parachute:true
     (sophie-lisp.internal::pristine-vector-collector-protocol-p #(1)))))
