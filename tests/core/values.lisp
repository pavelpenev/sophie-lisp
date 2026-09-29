(in-package #:sophie-lisp.tests)

;;; Chapter 7 acceptance fixtures. No production-private interfaces are used.
(defclass equality-identity () ())
(defstruct equality-record value)
(defclass equality-value () ((value :initarg :value :reader equality-value)))
(defclass equality-child (equality-value) ())
(defclass equality-peer () ((value :initarg :value :reader equality-value)))
(defmethod sophie-lisp:equals ((a equality-value) (b equality-value))
  (= (equality-value a) (equality-value b)))
(defmethod sophie-lisp:equals ((a equality-value) (b equality-peer))
  (= (equality-value a) (equality-value b)))
(defmethod sophie-lisp:equals ((a equality-peer) (b equality-value))
  (= (equality-value a) (equality-value b)))
(defmethod sophie-lisp:equals ((a equality-peer) (b equality-peer))
  (= (equality-value a) (equality-value b)))
;;; Constant hashes are legal, and keep these fixtures independent of D-HASH.
(defmethod sophie-lisp:hash-code ((a equality-value)) (declare (ignore a)) 17)
(defmethod sophie-lisp:hash-code ((a equality-peer)) (declare (ignore a)) 17)
(defstruct (equality-record-child (:include equality-record)))
(defmethod sophie-lisp:equals ((a equality-record-child) (b equality-record-child))
  (= (equality-record-value a) (equality-record-value b)))
(defmethod sophie-lisp:hash-code ((a equality-record-child)) (declare (ignore a)) 19)

(defun equality-pair (expected a b)
  (parachute:is eq expected (not (null (sophie-lisp:equals a b))))
  (parachute:is eq expected (not (null (sophie-lisp:equals b a)))))

(defun equality-lazy (&rest elements)
  (reduce #'sophie-lisp:lazy-cons elements :from-end t :initial-value nil))

(defun equality-table (test entries)
  (let ((table (make-hash-table :test test)))
    (dolist (entry entries table)
      (setf (gethash (car entry) table) (cdr entry)))))

(parachute:define-test equals.identity-fallback
  (parachute:true (typep #'sophie-lisp:equals 'generic-function))
  (let ((object (make-instance 'equality-identity))
        (record (make-equality-record :value 1)))
    (equality-pair t object object)
    (equality-pair nil object (make-instance 'equality-identity))
    (equality-pair t record record)
    (equality-pair nil record (make-equality-record :value 1)))
  (parachute:true (sophie-lisp:equals :same :same)))

(parachute:define-test equals.cross-class-extension
  (let ((a (make-instance 'equality-value :value 3))
        (b (make-instance 'equality-child :value 3))
        (c (make-instance 'equality-peer :value 3)))
    (equality-pair t a b)
    (equality-pair t b c)
    (equality-pair t a c)
    (equality-pair t a a)
    (equality-pair nil a (make-instance 'equality-peer :value 4))
    (parachute:is = (sophie-lisp:hash-code a) (sophie-lisp:hash-code b))
    (parachute:is = (sophie-lisp:hash-code b) (sophie-lisp:hash-code c))
    (equality-pair t (vector a) (vector c))))

(parachute:define-test equals.structure-subclass-extension
  (let ((a (make-equality-record-child :value 2))
        (b (make-equality-record-child :value 2)))
    (equality-pair t a b)
    (equality-pair t (list a) (list b))
    (equality-pair nil (make-equality-record :value 2)
                   (make-equality-record :value 2))))

(parachute:define-test equals.numeric-and-atomic-values
  ;; Exact values, not rounded decimal approximations, are the equality oracle.
  (dolist (pair '((1 1.0d0) (1/2 0.5) (0 -0.0d0)
                  (#c(1 2) #c(1.0d0 2.0d0))))
    (equality-pair t (first pair) (second pair)))
  (dolist (format '(short-float single-float double-float long-float))
    (let ((value (coerce 3/8 format)))
      (equality-pair t (rational value) value)))
  (dolist (value (list least-positive-single-float least-positive-double-float
                       most-positive-single-float most-positive-double-float))
    (equality-pair t (rational value) value))
  (equality-pair nil 16777217 16777216.0)
  (equality-pair nil 1/10 0.1)
  (equality-pair nil #\a #\A)
  (equality-pair t #\a #\a)
  (equality-pair t (copy-seq "Ab") (copy-seq "Ab"))
  (equality-pair nil "Ab" "ab")
  (equality-pair nil (make-symbol "SAME") (make-symbol "SAME")))

(parachute:define-test equals.cons-and-dotted-tails
  (equality-pair t (cons (list 1) 2) (cons (list 1.0) 2.0))
  (equality-pair nil '(1 . 2) '(1 . 3))
  (equality-pair nil '(1 . 2) '(1 2))
  (equality-pair t (cons 1 (equality-lazy 2 3))
                 (cons 1.0 (equality-lazy 2.0 3.0)))
  (equality-pair t (cons 1 (sophie-lisp:lazy-seq nil)) '(1))
  ;; Cons and lazy representations are not coerced to one another.
  (equality-pair nil '(1 2) (equality-lazy 1 2)))

(parachute:define-test equals.array-contents-and-dimensions
  (equality-pair t "Ab" (vector #\A #\b))
  (equality-pair nil "Ab" (vector #\A #\B))
  (equality-pair t #*101 #(1.0 0 1))
  (equality-pair t (make-array 4 :initial-contents '(1 2 99 98) :fill-pointer 2)
                 #(1.0 2.0))
  (equality-pair nil #(1 2) #(1 2 3))
  (equality-pair t (make-array nil :initial-element '(1 . 2))
                 (make-array nil :initial-element '(1.0 . 2.0)))
  (equality-pair nil (make-array nil :initial-element 1) #(1))
  (equality-pair t (make-array '(1 2 2) :initial-contents '(((1 2) (3 4))))
                 (make-array '(1 2 2) :initial-contents '(((1.0 2) (3 4)))))
  (equality-pair nil (make-array '(2 2) :initial-element 0)
                   (make-array '(1 4) :initial-element 0))
  (equality-pair nil (make-array '(2 2) :initial-contents '((1 2) (3 4)))
                   (make-array '(2 2) :initial-contents '((1 2) (4 3))))
  (equality-pair nil (make-array '(0 2)) (make-array '(0 3))))

(parachute:define-test equals.hash-table-entry-multisets
  (dolist (test '(eq eql equal equalp))
    (equality-pair t
      (equality-table test (list (cons (copy-seq "key") (list 1))))
      (equality-table 'equal (list (cons (copy-seq "key") (list 1.0))))))
  (let* ((a (equality-table 'eq (list (cons (list 1) :a) (cons (list 1) :b))))
         (b (equality-table 'eq (list (cons (list 1.0) :b) (cons (list 1.0) :a))))
         (bad (equality-table 'eq (list (cons (list 1) :a) (cons (list 1) :a)))))
    (equality-pair t a b)
    (equality-pair nil a bad)
    (equality-pair nil a (equality-table 'equal '(((1) . :a)))))
  (equality-pair nil (equality-table 'equal '((:a . 1) (:b . 2)))
                   (equality-table 'equal '((:a . 2) (:b . 1))))
  (equality-pair nil (equality-table 'equalp '(("a" . 1)))
                   (equality-table 'equal '(("A" . 1)))))

(parachute:define-test equals.lazy-sequences-and-empty-representations
  (equality-pair t nil (sophie-lisp:lazy-seq nil))
  (equality-pair t (sophie-lisp:lazy-seq nil) (sophie-lisp:lazy-seq nil))
  (equality-pair nil nil (equality-lazy nil))
  (equality-pair nil (sophie-lisp:lazy-seq nil) (equality-lazy 1))
  (equality-pair t (equality-lazy 1 (list 2)) (equality-lazy 1.0 (list 2.0)))
  (equality-pair nil (equality-lazy 1) (equality-lazy 1 2))
  (equality-pair nil nil #())
  (equality-pair nil (sophie-lisp:lazy-seq nil) "")
  (equality-pair nil (equality-lazy 1 2) #(1 2)))

(parachute:define-test equals.map-entry-components
  (equality-pair t (sophie-lisp:map-entry '(1) #(2))
                 (sophie-lisp:map-entry '(1.0) #(2.0)))
  (equality-pair nil (sophie-lisp:map-entry 1 2) (sophie-lisp:map-entry 2 2))
  (equality-pair nil (sophie-lisp:map-entry 1 2) (sophie-lisp:map-entry 1 3))
  (let ((object (make-instance 'equality-identity)))
    (equality-pair t (sophie-lisp:map-entry object nil)
                   (sophie-lisp:map-entry object nil))
    (equality-pair nil (sophie-lisp:map-entry object nil)
                   (sophie-lisp:map-entry (make-instance 'equality-identity) nil))))

(parachute:define-test equals.trie-backed-nested-containers
  (let ((left (sophie-lisp:dict :outer
                                (sophie-lisp:dict :inner (sophie-lisp:hash-set 1 2))))
        (right (sophie-lisp:dict :outer
                                 (sophie-lisp:dict :inner (sophie-lisp:hash-set 2d0 1d0)))))
    (equality-pair t left right)
    (equality-pair nil left
                   (sophie-lisp:dict :outer
                                     (sophie-lisp:dict :inner (sophie-lisp:hash-set 1 3))))))

(parachute:define-test equals.extension-hash-consistency
  ;; Undefined method redefinition with resident persistent keys has no runtime
  ;; oracle. All fixture methods above precede construction; none are redefined.
  (let ((a (make-instance 'equality-value :value 7))
        (b (make-instance 'equality-peer :value 7)))
    (equality-pair t a b)
    (parachute:is = (sophie-lisp:hash-code a) (sophie-lisp:hash-code b))
    (parachute:false (eq a b))))

(parachute:define-test equals.cons-head-short-circuit
  (let ((a (list 1)) (b (list 2)))
    (setf (cdr a) a (cdr b) b)
    (equality-pair nil a b))
  (let ((tail (sophie-lisp:lazy-seq (error "Untouched tail"))))
    (equality-pair nil (cons 1 tail) (cons 2 tail))
    (equality-pair nil nil (sophie-lisp:lazy-cons 1 tail))))

(parachute:define-test equals.lazy-short-circuit-and-retry
  (let ((forces 0))
    (let ((tail (sophie-lisp:lazy-seq (progn (incf forces) (error "Untouched")))))
      (equality-pair nil (sophie-lisp:lazy-cons 1 tail)
                     (sophie-lisp:lazy-cons 2 tail))
      (parachute:is = 0 forces)))
  (let ((cycle nil))
    (setf cycle (sophie-lisp:lazy-seq (sophie-lisp:lazy-cons 9 cycle)))
    (equality-pair nil (sophie-lisp:lazy-cons 1 cycle)
                   (sophie-lisp:lazy-cons 2 cycle)))
  (let* ((condition (make-condition 'simple-error :format-control "force"))
         (node (sophie-lisp:lazy-seq (error condition))))
    (parachute:is eq condition
      (handler-case (sophie-lisp:equals node nil) (error (caught) caught))))
  (let ((attempts 0))
    (let ((node (sophie-lisp:lazy-seq
                 (if (= 1 (incf attempts)) (throw 'equality-exit :escaped) nil))))
      (parachute:is eq :escaped (catch 'equality-exit (sophie-lisp:equals node nil)))
      (parachute:true (sophie-lisp:equals node nil))
      (parachute:is = 2 attempts))))

;;; Standalone fixtures: comparison tests do not depend on equality test helpers.
(defclass comparison-identity () ())
(defstruct comparison-record value)
(defclass comparison-value () ((value :initarg :value :reader comparison-value)))
(defclass comparison-child (comparison-value) ())
(defvar *comparison-calls* 0)
(defvar *comparison-condition* nil)
(defmethod sophie-lisp:equals ((a comparison-value) (b comparison-value))
  (= (comparison-value a) (comparison-value b)))
(defmethod sophie-lisp:hash-code ((a comparison-value)) (declare (ignore a)) 23)
(defmethod sophie-lisp:compare ((a comparison-value) (b comparison-value))
  (incf *comparison-calls*)
  (when *comparison-condition* (error *comparison-condition*))
  (cond ((< (comparison-value a) (comparison-value b)) :less)
        ((> (comparison-value a) (comparison-value b)) :greater)
        (t :equal)))

(defun comparison-pair (expected a b)
  (parachute:is eq expected (sophie-lisp:compare a b))
  (parachute:is eq (ecase expected
                    (:less :greater) (:greater :less)
                    (:equal :equal) (:unequal :unequal))
                (sophie-lisp:compare b a)))

(defun comparison-lazy (&rest elements)
  (reduce #'sophie-lisp:lazy-cons elements :from-end t :initial-value nil))

(defun comparison-table (test entries)
  (let ((table (make-hash-table :test test)))
    (dolist (entry entries table)
      (setf (gethash (car entry) table) (cdr entry)))))

(parachute:define-test compare.extension-ordering-laws
  (let ((a (make-instance 'comparison-value :value 1))
        (b (make-instance 'comparison-child :value 2))
        (c (make-instance 'comparison-child :value 3)))
    (comparison-pair :less a b)
    (comparison-pair :less b c)
    (comparison-pair :less a c)
    (comparison-pair :equal b (make-instance 'comparison-value :value 2))
    (comparison-pair :less (vector a) (vector c)))
  ;; Ordering equivalence is deliberately coarser than EQUALS for symbols.
  (let ((a (make-symbol "A")) (b (make-symbol "A")) (c (make-symbol "B")))
    (parachute:false (sophie-lisp:equals a b))
    (comparison-pair :equal a b)
    (comparison-pair :less b c)
    (comparison-pair :less a c))
  (dolist (pair (list (list 1 1.0d0) (list "ab" (vector #\a #\b))
                     (list '(1 . 2) '(1.0 . 2.0))
                     (list nil (sophie-lisp:lazy-seq nil))
                     (list (sophie-lisp:map-entry 1 2)
                           (sophie-lisp:map-entry 1.0 2.0))))
    (parachute:true (sophie-lisp:equals (first pair) (second pair)))
    (comparison-pair :equal (first pair) (second pair)))
  ;; 32 prior assertions + 3*15^2 pair laws + 3*15^3 triple laws.
  ;; The implications always assert, so the count cannot shrink when a buggy
  ;; comparator returns fewer ordered pairs. No implementation-derived oracle.
  (let* ((empty (sophie-lisp:lazy-seq nil))
         (a (make-symbol "A")) (z (make-symbol "Z"))
         (values (list nil empty a z (make-symbol "")
                       (make-symbol "NIL") (make-symbol "NIL")
                       "" #() #(0) '(1) (comparison-lazy 1)
                       (cons 1 empty) (cons 1 a) (cons 1 z))))
    (dolist (a values)
      (dolist (b values)
        (let ((ab (sophie-lisp:compare a b)))
          (parachute:true (member ab '(:less :equal :greater :unequal)))
          (parachute:is eq
            (ecase ab (:less :greater) (:greater :less)
                      (:equal :equal) (:unequal :unequal))
            (sophie-lisp:compare b a))
          (parachute:true (or (not (sophie-lisp:equals a b)) (eq ab :equal)))
          (dolist (c values)
            (let ((bc (sophie-lisp:compare b c))
                  (ac (sophie-lisp:compare a c)))
              (parachute:true
                (or (not (and (eq ab :less) (eq bc :less))) (eq ac :less)))
              (parachute:true
                (or (not (and (eq ab :greater) (eq bc :greater))) (eq ac :greater)))
              ;; Equal representatives must also preserve incomparability.
              (parachute:true (or (not (eq ab :equal)) (eq ac bc)))))))))
  ;; The unchanged NIL law matrix above has no numeric exception. These
  ;; exact conclusions test the narrow exception, never an opposite result.
  (let ((a #c(1.0d0 0.0d0)) (b 1) (c 2))
    (comparison-pair :equal a b)
    (comparison-pair :less b c)
    (comparison-pair :unequal a c))
  ;; Recursive lexicographic propagation through all four representations.
  (dolist (wrap (list #'vector #'list #'comparison-lazy
                     (lambda (x) (sophie-lisp:map-entry 0 x))))
    (let ((a (funcall wrap (vector #c(1.0d0 0.0d0) 0)))
          (b (funcall wrap (vector 1 1)))
          (c (funcall wrap (vector 2 0))))
      (comparison-pair :less a b)
      (comparison-pair :less b c)
      (comparison-pair :unequal a c))
    ;; Complex presence alone permits no exception: an earlier real
    ;; component decides, and strict transitivity still holds in both orders.
    (let ((a (funcall wrap (vector 0 #c(9 1))))
          (b (funcall wrap (vector 1 #c(8 2))))
          (c (funcall wrap (vector 2 #c(7 3)))))
      (comparison-pair :less a b)
      (comparison-pair :less b c)
      (comparison-pair :less a c))))

(parachute:define-test compare.numeric-and-atomic-ordering
  (comparison-pair :less -1 1/2)
  (comparison-pair :equal 1/2 0.5d0)
  (comparison-pair :equal 0 -0.0)
  (comparison-pair :greater 16777217 16777216.0)
  (comparison-pair :equal #c(1 2) #c(1.0d0 2.0d0))
  (comparison-pair :unequal #c(1 2) #c(1 3))
  (comparison-pair :unequal 1 #c(1 2))
  (comparison-pair :equal 1 #c(1.0 0.0))
  (comparison-pair :less #\a #\b)
  (comparison-pair (if (char< #\A #\a) :less :greater) #\A #\a)
  (comparison-pair :less (make-symbol "A") (make-symbol "Z"))
  ;; Approved §7.1.3 ruling supersedes NIL > A: NIL is not name-ordered.
  (dolist (name '("A" "Z" "" "NIL"))
    (comparison-pair :unequal nil (make-symbol name)))
  (comparison-pair :equal nil nil)
  (let ((a (make-symbol "NIL")) (b (make-symbol "NIL")))
    (parachute:false (sophie-lisp:equals a b))
    (comparison-pair :equal a b)
    (comparison-pair :less (make-symbol "A") a)
    (comparison-pair :less b (make-symbol "Z")))
  (let ((object (make-instance 'comparison-identity))
        (record (make-comparison-record :value 1)))
    (comparison-pair :equal object object)
    (comparison-pair :unequal object (make-instance 'comparison-identity))
    (comparison-pair :equal record record)
    (comparison-pair :unequal record (make-comparison-record :value 1)))
  (comparison-pair :unequal 1 "1")
  (dolist (value (list least-positive-single-float least-positive-double-float
                       most-positive-single-float most-positive-double-float))
    (comparison-pair :equal (rational value) value)
    (comparison-pair :less (- (rational value) 1) value))
  ;; 16^2 pairs * 3 assertions = 768 additional assertions. CL:= is
  ;; the independent equality oracle; CL:< is called only for two reals.
  ;; Explicit float complex literals retain their zero imaginary components.
  (let ((numbers (list 0 0.0s0 -0.0s0 0.0d0 -0.0d0 1 1/2
                       0.5s0 0.5d0 16777217 16777216.0s0
                       #c(1.0s0 0.0s0) #c(1.0d0 -0.0d0)
                       #c(0.0d0 -0.0d0) #c(1 2) #c(1.0d0 2.0d0))))
    (dolist (a numbers)
      (dolist (b numbers)
        (let* ((equalp (cl:= a b))
               (expected (cond (equalp :equal)
                               ((and (realp a) (realp b))
                                (if (cl:< a b) :less :greater))
                               (t :unequal))))
          (parachute:is eq (not (null equalp))
                          (not (null (sophie-lisp:equals a b))))
          (comparison-pair expected a b))))))

(parachute:define-test compare.cons-and-dotted-tail-ordering
  (comparison-pair :less '(1 9) '(2 0))
  (comparison-pair :equal '(1 . 2) '(1.0 . 2.0))
  (comparison-pair :less '(1) '(1 2))
  (comparison-pair :greater '(1 . 2) '(1))
  (comparison-pair :less '(1 . 2) '(1 . 3))
  (comparison-pair :unequal '(1 . 2) '(1 2))
  (comparison-pair :unequal '(1 "tail") '("1" 0))
  (comparison-pair :less (cons 1 (comparison-lazy 2))
                        (cons 1 (comparison-lazy 3)))
  (comparison-pair :equal (cons 1 (sophie-lisp:lazy-seq nil)) '(1))
  ;; 18 prior + 2 depths * (2*7*2 + 2*2*2 + 6*2) = 114.
  ;; Empty arrays/strings are nonempty dotted tails in this context.
  (let ((empties (list nil (sophie-lisp:lazy-seq nil)))
        (a (make-symbol "A")) (z (make-symbol "Z")))
    (dolist (wrap (list (lambda (tail) (cons 1 tail))
                       (lambda (tail) (cons 0 (cons 1 tail)))))
      (dolist (empty empties)
        (dolist (tail (list 2 '(2) a z "" #() (comparison-lazy 2)))
          (comparison-pair :less (funcall wrap empty) (funcall wrap tail)))
        (dolist (other empties)
          (comparison-pair :equal (funcall wrap empty) (funcall wrap other))))
      (dolist (pair (list (list :unequal '(2) 2)
                         (list :unequal '(2) a)
                         (list :unequal (comparison-lazy 2) '(2))
                         (list :unequal (comparison-lazy 2) 2)
                         (list :unequal (comparison-lazy 2) a)
                         (list :less a z)))
        (comparison-pair (first pair) (funcall wrap (second pair))
                         (funcall wrap (third pair))))))
  ;; Strict transitivity's conclusion is numerically forced incomparable.
  (let ((a (list #c(1.0d0 0.0d0) 0))
        (b (list 1 1)) (c (list 2 0)))
    (comparison-pair :less a b)
    (comparison-pair :less b c)
    (comparison-pair :unequal a c))
  ;; Dotted numeric tails use the same rule after equal cars.
  (comparison-pair :equal (cons 0 #c(1.0d0 0.0d0)) (cons 0 1))
  (comparison-pair :less (cons 0 1) (cons 0 2))
  (comparison-pair :unequal (cons 0 #c(1.0d0 0.0d0)) (cons 0 2)))

(parachute:define-test equals.deep-cons-chain-stack-boundedness
  ;; Deep chains must not need stack proportional to their length: hosts
  ;; without tail-call optimization must still traverse them to completion.
  (flet ((deep-chain (final)
           ;; Build iteratively: a recursive builder would exhaust stack itself.
           (let* ((head (list 0)) (tail head))
             (loop repeat 49999
                   do (let ((next (list 0)))
                        (setf (cdr tail) next)
                        (setf tail next)))
             (setf (cdr tail) final)
             head)))
    (equality-pair t (deep-chain nil) (deep-chain nil))
    (equality-pair nil (deep-chain 1) (deep-chain 2))
    (equality-pair nil (deep-chain 1) (deep-chain nil))
    (equality-pair nil (deep-chain 1) (deep-chain "1"))))

(parachute:define-test compare.deep-cons-chain-stack-boundedness
  ;; Deep chains must not need stack proportional to their length: hosts
  ;; without tail-call optimization must still traverse them to completion.
  (flet ((deep-chain (final)
           ;; Build iteratively: a recursive builder would exhaust stack itself.
           (let* ((head (list 0)) (tail head))
             (loop repeat 49999
                   do (let ((next (list 0)))
                        (setf (cdr tail) next)
                        (setf tail next)))
             (setf (cdr tail) final)
             head)))
    (comparison-pair :equal (deep-chain nil) (deep-chain nil))
    (comparison-pair :less (deep-chain 1) (deep-chain 2))
    (comparison-pair :greater (deep-chain 3) (deep-chain 2))
    (comparison-pair :unequal (deep-chain 1) (deep-chain "1"))))

(parachute:define-test compare.array-ordering-and-incomparability
  (comparison-pair :less #(1 2) #(1 3))
  (comparison-pair :less #(1) #(1 0))
  (comparison-pair :less #() #(0))
  (comparison-pair :equal "ab" (vector #\a #\b))
  (comparison-pair :less "ab" "abc")
  (comparison-pair :less "ab" "ac")
  (comparison-pair :unequal #(1 "x" 0) #(1 2 9))
  (comparison-pair :equal (make-array 4 :initial-contents '(1 2 8 9) :fill-pointer 2)
                         #(1.0 2.0))
  (comparison-pair :equal (make-array nil :initial-element 1)
                         (make-array nil :initial-element 1.0))
  (comparison-pair :unequal (make-array nil :initial-element 1)
                           (make-array nil :initial-element 2))
  (comparison-pair :unequal (make-array '(1 2) :initial-contents '((1 2)))
                           (make-array '(1 2) :initial-contents '((1 3))))
  (comparison-pair :unequal (make-array '(2 1) :initial-element 0)
                           (make-array '(1 2) :initial-element 0))
  (let ((a (vector #c(1.0d0 0.0d0) 0))
        (b (vector 1 1)) (c (vector 2 0)))
    (comparison-pair :less a b)
    (comparison-pair :less b c)
    (comparison-pair :unequal a c)))

(parachute:define-test compare.hash-tables-and-lazy-sequences
  (let ((a (comparison-table 'eq (list (cons (list 1) :a) (cons (list 1) :b))))
        (b (comparison-table 'equalp (list (cons (list 1.0) :a))))
        (c (comparison-table 'eq (list (cons (list 1.0) :b) (cons (list 1.0) :a))))
        (d (comparison-table 'eq (list (cons (list 1) :a) (cons (list 1) :a)))))
    (comparison-pair :equal a c)
    (comparison-pair :unequal a b)
    (comparison-pair :unequal a d)
    (dolist (other (list b c d))
      (parachute:is eq (not (null (sophie-lisp:equals a other)))
                       (eq :equal (sophie-lisp:compare a other)))))
  (comparison-pair :less (comparison-lazy 1 2) (comparison-lazy 1 3))
  (comparison-pair :less (comparison-lazy 1) (comparison-lazy 1 0))
  (comparison-pair :equal (comparison-lazy 1 2) (comparison-lazy 1.0 2.0))
  (comparison-pair :unequal (comparison-lazy 1 "x") (comparison-lazy 1 2))
  (let ((a (comparison-lazy #c(1.0d0 0.0d0) 0))
        (b (comparison-lazy 1 1)) (c (comparison-lazy 2 0)))
    (comparison-pair :less a b)
    (comparison-pair :less b c)
    (comparison-pair :unequal a c)))

(parachute:define-test compare.map-entries-and-empty-representations
  (comparison-pair :less (sophie-lisp:map-entry 1 99) (sophie-lisp:map-entry 2 0))
  (comparison-pair :less (sophie-lisp:map-entry 1 2) (sophie-lisp:map-entry 1 3))
  (comparison-pair :equal (sophie-lisp:map-entry 1 2) (sophie-lisp:map-entry 1.0 2.0))
  (comparison-pair :unequal (sophie-lisp:map-entry 1 2) (sophie-lisp:map-entry "1" 2))
  (comparison-pair :equal nil (sophie-lisp:lazy-seq nil))
  (comparison-pair :less nil (comparison-lazy nil))
  (comparison-pair :less (sophie-lisp:lazy-seq nil) (comparison-lazy 1))
  (comparison-pair :unequal (sophie-lisp:lazy-seq nil) #())
  (comparison-pair :unequal (comparison-lazy 1) #(1))
  (comparison-pair :unequal (comparison-lazy 1) '(1))
  ;; 20 prior + 2 empty representatives * 6 incomparable values * 2 + 4.
  (dolist (empty (list nil (sophie-lisp:lazy-seq nil)))
    (dolist (name '("A" "Z" "" "NIL"))
      (comparison-pair :unequal empty (make-symbol name)))
    (dolist (array (list "" #()))
      (comparison-pair :unequal empty array)))
  (comparison-pair :less nil (comparison-lazy 1))
  (comparison-pair :less (sophie-lisp:lazy-seq nil) (comparison-lazy nil))
  (let ((a (sophie-lisp:map-entry #c(1.0d0 0.0d0) 0))
        (b (sophie-lisp:map-entry 1 1)) (c (sophie-lisp:map-entry 2 0)))
    (comparison-pair :less a b)
    (comparison-pair :less b c)
    (comparison-pair :unequal a c)))

(parachute:define-test compare.ordering-predicates-and-incomparable-errors
  (loop for predicate in (list #'sophie-lisp:lt #'sophie-lisp:lte
                              #'sophie-lisp:gt #'sophie-lisp:gte)
        for truths in '((t nil nil) (t t nil) (nil nil t) (nil t t))
        do (loop for right in '(2 1 0) for expected in truths
                 do (let ((*comparison-calls* 0))
                      (parachute:is eq expected
                        (not (null (funcall predicate
                          (make-instance 'comparison-child :value 1)
                          (make-instance 'comparison-value :value right)))))
                      (parachute:is = 1 *comparison-calls*)))
           (parachute:fail (funcall predicate 1 "incomparable") simple-error)
           (let* ((*comparison-calls* 0)
                  (*comparison-condition*
                    (make-condition 'simple-error :format-control "extension")))
             (parachute:is eq *comparison-condition*
               (handler-case
                   (funcall predicate (make-instance 'comparison-value :value 1)
                                      (make-instance 'comparison-child :value 2))
                 (error (caught) caught)))
             (parachute:is = 1 *comparison-calls*))
           (parachute:false (typep predicate 'generic-function)))
  (dolist (name '("A" "Z" "" "NIL"))
    (let ((symbol (make-symbol name)))
      (parachute:fail (sophie-lisp:lt nil symbol) simple-error)
      (parachute:fail (sophie-lisp:lt symbol nil) simple-error)))
  ;; 4 predicates * (3 equal + 3 incomparable + 1 ordered) * 2 directions.
  (loop for predicate in (list #'sophie-lisp:lt #'sophie-lisp:lte
                              #'sophie-lisp:gt #'sophie-lisp:gte)
        for equal-result in '(nil t nil t)
        for less-result in '(t t nil nil)
        for greater-result in '(nil nil t t)
        do (dolist (pair (list (list 1 #c(1.0d0 -0.0d0))
                              (list -0.0s0 #c(0.0d0 -0.0d0))
                              (list #c(1 2) #c(1.0d0 2.0d0))))
             (dolist (args (list pair (reverse pair)))
               (parachute:is eq equal-result
                 (not (null (apply predicate args))))))
           (dolist (pair (list (list #c(1.0d0 0.0d0) 2)
                              (list 1 #c(1 2))
                              (list (vector #c(1.0d0 0.0d0) 0)
                                    (vector 2 0))))
             (dolist (args (list pair (reverse pair)))
               (parachute:fail (apply predicate args) simple-error)))
           (parachute:is eq less-result
             (not (null (funcall predicate 1/2 1))))
           (parachute:is eq greater-result
             (not (null (funcall predicate 1 1/2))))))

(parachute:define-test compare.short-circuit-forcing-and-retry
  (let ((a (list 1)) (b (list 2)))
    (setf (cdr a) a (cdr b) b)
    (comparison-pair :less a b))
  (let ((forces 0))
    (let ((tail (sophie-lisp:lazy-seq (progn (incf forces) (error "Untouched")))))
      (comparison-pair :less (cons 1 tail) (cons 2 tail))
      (comparison-pair :unequal (cons 1 tail) (cons "1" tail))
      (comparison-pair :unequal (sophie-lisp:lazy-cons 1 tail)
                               (sophie-lisp:lazy-cons "1" tail))
      (comparison-pair :less nil (sophie-lisp:lazy-cons 1 tail))
      (comparison-pair :less (sophie-lisp:lazy-seq nil)
                            (sophie-lisp:lazy-cons 1 tail))
      (comparison-pair :less (sophie-lisp:map-entry 1 tail)
                            (sophie-lisp:map-entry 2 tail))
      (parachute:is = 0 forces)))
  (let ((attempts 0))
    (let ((node (sophie-lisp:lazy-seq
                 (if (= 1 (incf attempts)) (throw 'comparison-exit :escaped) nil))))
      (parachute:is eq :escaped (catch 'comparison-exit (sophie-lisp:compare nil node)))
      (parachute:is eq :equal (sophie-lisp:compare nil node))
      (parachute:is = 2 attempts)))
  ;; Resolving tail emptiness is left-to-right and does not force the rest.
  (let ((order nil) (rest-forces 0))
    (let ((left (sophie-lisp:lazy-seq (progn (push :left order) nil)))
          (right (sophie-lisp:lazy-seq
                   (progn (push :right order)
                     (sophie-lisp:lazy-cons 2
                       (sophie-lisp:lazy-seq
                         (progn (incf rest-forces) (error "Untouched rest"))))))))
      (comparison-pair :less (cons 1 left) (cons 1 right))
      (parachute:is equal '(:left :right) (reverse order))
      (parachute:is = 0 rest-forces)))
  ;; Escaping while resolving a cons tail must not memoize the failed force.
  ;; Exercise both argument positions, retry, and successful memoization.
  (dolist (reversep '(nil t))
    (let ((attempts 0))
      (let* ((node (sophie-lisp:lazy-seq
                     (if (= 1 (incf attempts))
                         (throw 'comparison-exit :escaped) nil)))
             (left (cons 0 (cons 1 node)))
             (right '(0 1)))
        (flet ((compare-tails ()
                 (if reversep (sophie-lisp:compare right left)
                     (sophie-lisp:compare left right))))
          (parachute:is eq :escaped (catch 'comparison-exit (compare-tails)))
          (parachute:is eq :equal (compare-tails))
          (parachute:is eq :equal (compare-tails))
          (parachute:is = 2 attempts)))))
  ;; Neither ordered nor incomparable numeric heads may inspect the tail.
  ;; Distinct deferred nodes detect traversal even with identity shortcuts.
  (dolist (build (list #'cons #'vector #'sophie-lisp:lazy-cons
                      #'sophie-lisp:map-entry))
    (let ((forces 0))
      (flet ((tail ()
               (sophie-lisp:lazy-seq
                 (progn (incf forces) (error "Untouched numeric tail")))))
        (comparison-pair :less (funcall build 1 (tail))
                               (funcall build 2 (tail)))
        (comparison-pair :unequal (funcall build #c(1.0d0 0.0d0) (tail))
                                 (funcall build 2 (tail)))
        (comparison-pair :unequal (funcall build #c(1 2) (tail))
                                 (funcall build 1 (tail)))
        (parachute:is = 0 forces)))))
