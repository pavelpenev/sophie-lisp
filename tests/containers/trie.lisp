;;;; Independent D-HASH acceptance, Chapter 7 in full.
;;;; Frozen prototype bounds are tested separately from portable hash laws.
;;;; Portable hash laws impose no exact values or collision-free requirement;
;;;; host-specific golden pins below detect accidental implementation drift.
(in-package #:sophie-lisp.tests)

(defclass hashing-identity () ((value :initform 0 :accessor hashing-value)))
(defstruct hashing-record value)

(defclass hashing-counted ()
  ((value :initarg :value :reader hashing-counted-value)
   (count :initform 0 :accessor hashing-counted-count)))

(defmethod sl:hash-code ((object hashing-counted))
  ;; Public recursive dispatch reaches this user method once per actual
  ;; computation of the object's hash; it is the observation probe for the
  ;; memoization tests below.
  (incf (hashing-counted-count object))
  (sophie-lisp.internal::mix64 (sxhash (hashing-counted-value object))))

(defclass hashing-pair ()
  ((left :initarg :left :reader hashing-pair-left)
   (right :initarg :right :reader hashing-pair-right)))

(defmethod sl:hash-code ((object hashing-pair))
  ;; A user-defined compound method in the documented public recursion
  ;; style: one structural edge per slot, but no self-memoization, so both
  ;; components are hashed by nested public dispatch within one invocation.
  (let ((depth (1- sophie-lisp.internal::*hash-depth*)))
    (sophie-lisp.internal::hash-combine
     (sophie-lisp.internal::hash-combine
      (sophie-lisp.internal::mix64 32)
      (sophie-lisp.internal::hash-component
       (hashing-pair-left object) depth))
     (sophie-lisp.internal::hash-component
      (hashing-pair-right object) depth))))

(defun hashing-valid (object)
  (let ((hash (sl:hash-code object)))
    (parachute:true (typep hash '(integer 0)))
    hash))

(defun hashing-same (a b)
  ;; A and B are explicitly constructed equal, not filtered by EQUALS.
  (parachute:is = (hashing-valid a) (hashing-valid b)))

(defun hashing-lazy (elements)
  (reduce #'sl:lazy-cons elements :from-end t :initial-value nil))

(defun hashing-table (test entries)
  (let ((table (make-hash-table :test test)))
    (dolist (entry entries table)
      (setf (gethash (car entry) table) (cdr entry)))))

(defun hashing-infinity-fixtures ()
  "The four float infinities (single/double, positive/negative), or NIL.
ANSI defines no infinity constructor, so each host's constants sit behind
feature guards; a host without them excludes the infinity checks below."
  #+sbcl (list sb-ext:single-float-positive-infinity
               sb-ext:double-float-positive-infinity
               sb-ext:single-float-negative-infinity
               sb-ext:double-float-negative-infinity)
  #+ecl (list ext:single-float-positive-infinity
              ext:double-float-positive-infinity
              ext:single-float-negative-infinity
              ext:double-float-negative-infinity)
  #+ccl (let ((positive ccl::double-float-positive-infinity)
              (negative ccl::double-float-negative-infinity))
          (list (coerce positive 'single-float) positive
                (coerce negative 'single-float) negative))
  #-(or sbcl ecl ccl) nil)

(defun hashing-nan-float ()
  "A quiet NaN for this host, or NIL when the host offers no constructor.
NaN-producing arithmetic traps FLOATING-POINT-INVALID on every supported
host, so the bit pattern must come from a host constructor or constant."
  #+sbcl (sb-kernel:make-single-float #x7fc00000)
  #+ccl ccl::double-float-nan
  #+ecl (ext:nan)
  #-(or sbcl ccl ecl) nil)

(defun hashing-weak-dead-p (pointer)
  "Whether a weak pointer's referent has been collected.
TRIVIAL-GARBAGE's CCL and ECL backends return only the referent, NIL once
the weak entry is purged; SBCL adds an explicit validity flag. Fixtures are
always non-nil, so a NIL referent means dead on every host."
  (null (nth-value 0 (tg:weak-pointer-value pointer))))


;; FROZEN-DO-NOT-EDIT: This is the pre-optimization bignum formulation of the
;; SplitMix64 finalizer, kept independent of production MIX64 so the bit-identity
;; test pins compiler/declaration-induced divergence; syncing it makes the test vacuous.
(defun reference-mix64 (integer)
  "The recorded bignum formulation of the SplitMix64 finalizer."
  (let ((word (ldb (byte 64 0) integer)))
    (setf word
          (ldb (byte 64 0)
               (* (logxor word (ash word -30)) #xbf58476d1ce4e5b9)))
    (setf word
          (ldb (byte 64 0)
               (* (logxor word (ash word -27)) #x94d049bb133111eb)))
    (logxor word (ash word -31))))

(parachute:define-test hash-code.mix64-bit-identity
  ;; On supported hosts the seam replaces the wide MIX64 function cell.
  ;; Only unlisted wide-fixnum hosts retain the production wide definition;
  ;; call its function cell directly there, not an inlined same-file binding.
  (when (and (> (integer-length most-positive-fixnum) 61)
             (not (member (lisp-implementation-type)
                          sophie-lisp.internal::*narrow-hash-discipline-hosts*
                          :test #'string=)))
    (let ((two62 (ash 1 62))
          (two63 (ash 1 63))
          (two64 (ash 1 64)))
      (dolist (input
               (append (list 0 1
                             (1- two62) two62
                             (1- two63) two63
                             (1- two64) two64 (1+ two64)
                             (+ (ash 1 127) #x123456789abcdef)
                             -1 (- two64) (- (ash 1 130)) -123456789)
                       (loop for bit from 0 below 64 collect (ash 1 bit))))
        (parachute:is = (reference-mix64 input)
                      (funcall (fdefinition 'sophie-lisp.internal::mix64) input)))
      ;; Two fixed-seed LCG steps form each 64-bit input.
      (let ((state #x6d2b79f5))
        (loop repeat 10000
              do (setf state
                       (mod (+ (* state 1664525) 1013904223) #x100000000))
              do (let ((low state))
                   (setf state
                         (mod (+ (* state 1664525) 1013904223) #x100000000))
                   (let ((input (+ (ash state 32) low)))
                     (parachute:is = (reference-mix64 input)
                                   (funcall (fdefinition 'sophie-lisp.internal::mix64)
                                            input)))))))))

(defun wide-mix64-formulation (integer)
  "Independent wide arithmetic formulation for checking the frozen oracle."
  (let ((word (mod integer (ash 1 64))))
    (setf word (mod (* (logxor word (floor word (ash 1 30)))
                       #xbf58476d1ce4e5b9)
                    (ash 1 64)))
    (setf word (mod (* (logxor word (floor word (ash 1 27)))
                       #x94d049bb133111eb)
                    (ash 1 64)))
    (logxor word (floor word (ash 1 31)))))

(parachute:define-test hash-code.mix64-wide-formulation-reference
  ;; SBCL/CCL swap the production function cell to MIX64-LIMB; ECL selects
  ;; it by fixnum width. The production wide path is therefore dormant on
  ;; supported hosts. This independently formulated comparison runs everywhere;
  ;; MIX64-BIT-IDENTITY checks the actual production cell on unlisted wide hosts.
  (dolist (input (append (list 0 1 -1 -123456789
                               (1- (ash 1 62)) (ash 1 62)
                               (1- (ash 1 63)) (ash 1 63)
                               (1- (ash 1 64)) (ash 1 64) (1+ (ash 1 64))
                               (+ (ash 1 127) #x123456789abcdef)
                               (- (ash 1 130)))
                         (loop for bit below 64 collect (ash 1 bit))))
    (parachute:is = (reference-mix64 input)
                  (wide-mix64-formulation input))))

(defun mix64-wide-reference-inputs ()
  "Inputs shared by the wide mixer and retained delegator oracle tests."
  (append (list 0 1 -1 -123456789
                (1- (ash 1 62)) (ash 1 62)
                (1- (ash 1 63)) (ash 1 63)
                (1- (ash 1 64)) (ash 1 64) (1+ (ash 1 64))
                (+ (ash 1 127) #x123456789abcdef)
                (- (ash 1 130))
                (1- #x9e3779b97f4a7c15)
                #x9e3779b97f4a7c15
                (1+ #x9e3779b97f4a7c15))
          (loop for bit below 64 collect (ash 1 bit))))

(parachute:define-test hash-code.mix64-wide-matches-frozen-reference
  ;; Call the retained production wide body even when MIX64 is host-swapped.
  (dolist (input (mix64-wide-reference-inputs))
    (parachute:is = (reference-mix64 input)
                  (sophie-lisp.internal::mix64-wide input))))

(parachute:define-test hash-code.mix64-delegator-matches-frozen-reference
  ;; Exercise the captured production delegator even when its function cell is swapped.
  (let ((delegator sophie-lisp.internal::*mix64-load-definition*))
    (parachute:true (functionp delegator))
    (dolist (input (mix64-wide-reference-inputs))
      (parachute:is = (reference-mix64 input)
                    (funcall delegator input)))))

(parachute:define-test hash-code.mix64-delegator-swap-order
  ;; Narrow hosts replace the production cell after the delegator is captured.
  (let ((captured sophie-lisp.internal::*mix64-load-definition*)
        (production (fdefinition 'sophie-lisp.internal::mix64)))
    (if (or (<= (integer-length most-positive-fixnum) 61)
            (member (lisp-implementation-type)
                    sophie-lisp.internal::*narrow-hash-discipline-hosts*
                    :test #'string=))
        (parachute:false (eq captured production))
        (parachute:true (eq captured production)))))

(defun reference-mix64-limb (integer)
  "Independent exact-integer oracle for the narrow-fixnum 32-bit finalizer."
  (let* ((modulus (expt 2 32))
         (word (logxor (mod integer modulus)
                       (mod (floor integer modulus) modulus))))
    (setf word (mod (* (logxor word (floor word (expt 2 16)))
                       #x9e37) modulus))
    (setf word (mod (* (logxor word (floor word (expt 2 13)))
                       #x85eb) modulus))
    (mod (logxor word (floor word (expt 2 16))) modulus)))

(parachute:define-test hash-code.mix64-limb-reference
  (let ((inputs (append (list 0 1 -1 -123456789 most-positive-fixnum
                              most-negative-fixnum (1+ most-positive-fixnum)
                              (ash 1 64) (1- (ash 1 64))
                              (+ (ash 1 127) #x123456789abcdef)
                              (- (ash 1 130)))
                        (loop for bit below 64 collect (ash 1 bit)))))
    ;; Exercise both the independent oracle and the selected production seam.
    (labels ((check (input)
               (let ((expected (reference-mix64-limb input))
                     (actual (sophie-lisp.internal::mix64-limb input)))
                 (parachute:is = expected actual)
                 (parachute:true (typep actual '(unsigned-byte 64)))
                 (parachute:true (<= 0 actual))
                 (when (or (<= (integer-length most-positive-fixnum) 61)
                           (member (lisp-implementation-type)
                                   sophie-lisp.internal::*narrow-hash-discipline-hosts*
                                   :test #'string=))
                   (parachute:is = expected (sophie-lisp.internal::mix64 input))))))
      (dolist (input inputs) (check input))
      (let ((state #x6d2b79f5))
        (loop repeat 10000
              do (setf state (mod (+ (* state 1664525) 1013904223)
                                  #x100000000))
              do (let ((low state))
                   (setf state (mod (+ (* state 1664525) 1013904223)
                                     #x100000000))
                   (check (+ (ash state 32) low)))))))
  ;; A single flipped input bit should change many output bits in aggregate.
  ;; This is statistical sanity, not a collision-freedom claim.
  (let* ((base #x12345678abcdef09)
         (original (reference-mix64-limb base))
         (changed (loop for bit below 64
                        sum (logcount
                             (logxor original
                                     (reference-mix64-limb
                                      (logxor base (ash 1 bit))))))))
    (parachute:true (>= changed 640))))

(parachute:define-test hash-code.identity-hash-narrow-mixer-call-site
  ;; A direct MIX64 check cannot detect a host binding a same-file caller to
  ;; the original MIX64 delegator (behaviorally wide) despite the function-cell swap.
  (when (or (<= (integer-length most-positive-fixnum) 61)
            (member (lisp-implementation-type)
                    sophie-lisp.internal::*narrow-hash-discipline-hosts*
                    :test #'string=))
    (let ((distinct-from-wide 0))
      (dotimes (index 16)
        (declare (ignore index))
        (let* ((object (make-instance 'hashing-identity))
               (before sophie-lisp.internal::*identity-hash-counter*)
               (actual (sophie-lisp.internal::identity-hash object))
               (counter (1+ before)))
          (parachute:is = counter sophie-lisp.internal::*identity-hash-counter*)
          (parachute:is = (reference-mix64-limb counter) actual)
          (parachute:true (< actual (ash 1 32)))
          (unless (= (reference-mix64 counter) actual)
            (incf distinct-from-wide))))
      (parachute:true (plusp distinct-from-wide)))))

(parachute:define-test hash-code.equal-representations-share-hash
  (dolist (pair (list (list 1 1.0d0) (list -3/8 -0.375d0)
                     (list (list 1 2) (list 1.0d0 2.0d0))
                     (list (vector 1 2) (vector 1.0d0 2.0d0))))
    (parachute:true (sl:equals (first pair) (second pair)))
    (parachute:is = (sl:hash-code (first pair))
                  (sl:hash-code (second pair)))
    (dolist (object pair)
      (let ((hash (sl:hash-code object)))
        (parachute:true (<= 0 hash))
        (parachute:true (typep hash '(unsigned-byte 64)))))))

(parachute:define-test hash-code.default-combining-golden
  ;; ECL retains the pre-round-C default-combining values from 247c05d.
  (if (string= (lisp-implementation-type) "ECL")
      (loop for object in (list 0 1 -7 #\A '(1 2) #(1 2) "abc" (ash 1 100))
            for value in '(4233642116 3973057764 159291007 2456516382
                           4186662002 4150653285 2292094681 1545850076)
            do (parachute:is = value (sl:hash-code object)))
      (parachute:skip "ECL golden pin is not applicable on this host")))

(parachute:define-test hash-code.selected-32-bit-golden
  ;; Values from the SBCL narrow mixer and 32-bit combining path.
  ;; Also observed in a fresh CCL 1.13 process with the full round-C host-list seam.
  (if (member (lisp-implementation-type) '("SBCL" "Clozure Common Lisp")
              :test #'string=)
      (loop for object in (list 0 1 -7 #\A '(1 2) #(1 2) "abc" (ash 1 100))
            for value in '(1467084162 1062885574 2360094981 3090736573
                           2801082921 3446141175 2050361096 2191825817)
            do (parachute:is = value (sl:hash-code object)))
      (parachute:skip "SBCL/CCL golden pin is not applicable on this host")))
(parachute:define-test hash-code.selected-32-bit-combining-properties
  ;; Both selected hosts exercise the narrow mixer and 32-bit combining.
  ;; ECL retains its separate default-combining golden pins.
  (when (member (lisp-implementation-type)
                sophie-lisp.internal::*narrow-hash-discipline-hosts*
                :test #'string=)
    (let ((seen (make-hash-table :test #'eql)))
      (loop for index below 128
            for object = (vector index (ash 1 (+ 64 (mod index 37))))
            for hash = (sl:hash-code object)
            do (parachute:true (typep hash '(unsigned-byte 32)))
               (parachute:true (typep hash '(unsigned-byte 64)))
               (parachute:false (gethash hash seen))
               (setf (gethash hash seen) t))
      (parachute:is = 128 (hash-table-count seen)))
    (dolist (object (list (ash 1 200) -123456789123456789
                          '(1 (2 3) 4) "abc" (sl:dict :a 1 :b 2)
                          (hashing-table 'equal '(("a" . 1) ("b" . 2)))))
      (parachute:true (typep (sl:hash-code object) '(unsigned-byte 32))))
    ;; Full-width user values must contribute their upper 32 bits, without
    ;; forcing a general bignum product in the unordered square fold.
    (let* ((words '(#x8000000180000001 #x12345678abcdef01))
           (folded (mapcar (lambda (value)
                             (logxor (ldb (byte 32 0) value)
                                     (ldb (byte 32 32) value))) words))
           (sum (ldb (byte 32 0) (reduce #'+ folded)))
           (squares (ldb (byte 32 0)
                         (reduce #'+ (mapcar (lambda (word) (* word word))
                                             folded))))
           (expected (reference-mix64-limb
                      (logxor 24 (reference-mix64-limb 2)
                              (reference-mix64-limb sum)
                              (reference-mix64-limb squares))))
           (actual (sophie-lisp.internal::hash-unordered 24 2 words)))
      (parachute:is = expected actual)
      (parachute:true (typep actual '(unsigned-byte 32))))))

(parachute:define-test hash-code.equal-structural-values
  (parachute:true (typep #'sl:hash-code 'generic-function))
  (dolist (pair (list (list 3 3.0d0) (list #\a #\a)
                     (list (copy-seq "Ab") (vector #\A #\b))
                     (list #*101 #(1.0 0 1))
                     (list '(1 (2) . 3) '(1.0 (2.0) . 3.0))
                     (list (hashing-lazy '(1 (2))) (hashing-lazy '(1.0 (2.0))))
                     (list (cons 1 (sl:lazy-seq nil)) '(1.0))
                     (list (cons 1 (hashing-lazy '(2)))
                           (cons 1.0 (hashing-lazy '(2.0))))
                     (list (sl:map-entry '(1) #(2))
                           (sl:map-entry '(1.0) #(2.0)))
                     (list (make-array nil :initial-element '(1))
                           (make-array nil :initial-element '(1.0)))))
    (hashing-same (first pair) (second pair))))

(parachute:define-test hash-code.numeric-equality
  (dolist (format '(short-float single-float double-float long-float))
    (dolist (rational '(0 1 -1 3/8 -17/16 16777216 9007199254740992))
      (let ((float (coerce rational format)))
        (hashing-same (rational float) float)
        (hashing-same float (complex float (coerce 0 format)))))
    (hashing-same 0 (- (coerce 0 format))))
  (dolist (float (list least-positive-single-float least-positive-double-float
                       least-positive-normalized-single-float
                       least-positive-normalized-double-float
                       most-positive-single-float most-positive-double-float
                       0.1 0.1d0))
    (hashing-same (rational float) float))
  (hashing-same (expt 2 200) (scale-float 1.0d0 200))
  (hashing-same #c(3/8 -17/16) #c(0.375d0 -1.0625d0))
  (let ((infinities (hashing-infinity-fixtures)))
    (when infinities
      ;; Hosts without infinity constants exclude this block (see the fixture).
      (destructuring-bind
          (positive-single positive-double negative-single negative-double)
          infinities
        (dolist (infinity infinities)
          (hashing-valid infinity))
        (hashing-same positive-single positive-double)
        (hashing-same negative-single negative-double)
        (hashing-same (complex positive-single 1.0f0)
                      (complex positive-double 1.0d0))
        (hashing-same (complex 1.0f0 negative-single)
                      (complex 1.0d0 negative-double)))))
  ;; Seeded exact dyadic triples test the equality/hash law without asking
  ;; production EQUALS which pairs should count. PRNG is test-local, reproducible.
  (dolist (seed '(20260906 7 1729))
    (let ((state seed))
      (dotimes (i 64)
        (declare (ignore i))
        (setf state (mod (+ (* state 1664525) 1013904223) (expt 2 32)))
        (let* ((q (/ (- (mod state 65536) 32768) 16))
               (a (coerce q 'single-float)) (b (coerce q 'double-float)))
          (parachute:true (= q a b))
          (hashing-same q a)
          (hashing-same a b)
          (hashing-same q (complex b 0.0d0)))))))

(parachute:define-test hash-code.portable-infinity-predicate
  ;; The seam predicate must agree with the retired SB-EXT:FLOAT-INFINITY-P at
  ;; the HASH-REAL call site: infinities are T, finite extremes are NIL without
  ;; signaling, and NaN is NIL so it falls through to RATIONAL, which signals.
  ;; NaN bit patterns come from the per-host fixture constructor, because
  ;; NaN-producing arithmetic itself traps FLOATING-POINT-INVALID here.
  (let ((nan (hashing-nan-float)))
    (when nan
      (parachute:false (sophie-lisp.internal::float-infinity-p nan))
      ;; The retired SBCL oracle is cross-checked only on its own host.
      #+sbcl (parachute:is eq (sb-ext:float-infinity-p nan)
                          (sophie-lisp.internal::float-infinity-p nan)))
    (dolist (finite (list most-positive-double-float most-positive-single-float
                          most-negative-double-float most-negative-single-float
                          0.0 1.5f0 1.5d0))
      (parachute:false (sophie-lisp.internal::float-infinity-p finite)))
    (dolist (infinity (hashing-infinity-fixtures))
      (parachute:true (sophie-lisp.internal::float-infinity-p infinity)))
    ;; NaN is not an infinity, so HASH-REAL must reach RATIONAL and signal
    ;; instead of returning an infinity hash.
    (when nan
      (parachute:is eq :signaled
                    (handler-case
                        (sl:hash-code nan)
                      (error () :signaled))))))

(parachute:define-test hash-code.cycle-termination
  ;; Timeout is a safety guard, never an equality/cycle semantic oracle.
  ;; No portable timeout exists: non-SBCL hosts run the deterministic body
  ;; unguarded, following the tests/syntax/reader.lisp convention.
  (macrolet ((guarded (&body body)
               #+sbcl `(sb-ext:with-timeout 5 ,@body)
               #-sbcl `(progn ,@body)))
    (guarded
      (let ((one (list :x)) (two (list :x :x))
            (array (make-array 1)) (table (make-hash-table)))
        (setf (cdr one) one (cddr two) two
              (aref array 0) array (gethash :self table) table)
        (hashing-valid one)
        (hashing-valid two)
        (hashing-valid array)
        (hashing-valid table)))
    (guarded
      (let* ((array (make-array 1)) (entry (sl:map-entry :key array)))
        (setf (aref array 0) entry)
        (hashing-valid entry)))
    (guarded
      (let ((array (make-array 64)))
        (fill array array)
        (hashing-valid array)))))

(parachute:define-test hash-code.sequence-shapes
  (hashing-same nil (sl:lazy-seq nil))
  (let* ((empty (sl:lazy-seq nil)) (wrapper (sl:lazy-seq empty)))
    (hashing-same empty wrapper)
    (hashing-same (list nil) (list wrapper)))
  (hashing-same "Ab" (make-array 4 :element-type 'character
                                  :initial-contents "AbXY" :fill-pointer 2))
  (hashing-same #(1 2) (make-array 4 :initial-contents '(1.0 2.0 8 9)
                                   :fill-pointer 2))
  (hashing-same "Ab" (make-array 2 :displaced-to "XAbY" :displaced-index-offset 1
                                  :element-type 'character))
  (hashing-same (make-array '(2 2) :initial-contents '((1 2) (3 4)))
                (make-array '(2 2) :initial-contents '((1.0 2.0) (3.0 4.0))))
  (let* ((seq (hashing-lazy '(1 2 3))) (wrapper (sl:lazy-seq seq)))
    (hashing-same seq wrapper)))

(parachute:define-test hash-code.hash-tables
  (dolist (test '(eq eql equal equalp))
    (hashing-same
     (hashing-table test (list (cons (copy-seq "key") (list 1))))
     (hashing-table 'equal (list (cons (copy-seq "key") (list 1.0))))))
  (hashing-same
   (hashing-table 'eq (list (cons (list 1) :a) (cons (list 1) :b)))
   (hashing-table 'eq (list (cons (list 1.0) :b) (cons (list 1.0) :a))))
  (let ((entries (loop for i below 100 collect (cons i (vector i)))))
    (hashing-same (hashing-table 'eql entries)
                  (hashing-table 'equalp (reverse entries)))))

(defun hashing-weak-fixtures ()
  ;; Return only weak references; the hashing layer must not retain these keys.
  ;; TRIVIAL-GARBAGE replaces the retired SB-EXT weak-pointer seam.
  (mapcar (lambda (object)
            (sl:hash-code object)
            (tg:make-weak-pointer object))
          (list (make-instance 'hashing-identity) (make-hashing-record :value 0))))

(parachute:define-test hash-code.identity-stability-and-weak-references
  (let* ((object (make-instance 'hashing-identity))
         (record (make-hashing-record :value 0))
         (a (hashing-valid object)) (b (hashing-valid record)))
    (setf (hashing-value object) 9 (hashing-record-value record) 9)
    (dotimes (i 3)
      (tg:gc :full t)
      (parachute:is = a (sl:hash-code object))
      (parachute:is = b (sl:hash-code record))))
  (dolist (object (list :symbol (make-symbol "UNINTERNED") #'identity))
    (hashing-same object object))
  ;; BORDEAUX-THREADS replaces the retired SB-THREAD seam: the fixtures must
  ;; die with their worker's stack, not the suite's own stack.
  (let* ((worker (bt:make-thread #'hashing-weak-fixtures))
         (weak (bt:join-thread worker)))
    (dolist (pointer weak)
      (parachute:true
       (loop repeat 20
             when (progn
                    (tg:gc :full t)
                    (hashing-weak-dead-p pointer))
               return t)))))

(parachute:define-test hash-code.mutable-dictionary-and-table-values
  (let* ((value (vector 1))
         (dictionary (sl:dict :key value))
         (table (make-hash-table :test 'equal)))
    (setf (gethash :key table) value)
    (sl:hash-code dictionary)
    (sl:hash-code table)
    (setf (aref value 0) 2)
    (let ((fresh-dictionary (sl:dict :key #(2)))
          (fresh-table (make-hash-table :test 'equal)))
      (setf (gethash :key fresh-table) #(2))
      (parachute:true (sl:equals dictionary fresh-dictionary))
      (parachute:is = (sl:hash-code dictionary)
                    (sl:hash-code fresh-dictionary))
      (parachute:true (sl:equals table fresh-table))
      (parachute:is = (sl:hash-code table) (sl:hash-code fresh-table)))))

(parachute:define-test hash-code.cross-call-cycle-consistency
  ;; The memoization context is confined to one dynamic invocation, so two
  ;; separate SL:HASH-CODE calls on the same cyclic structure must agree:
  ;; nothing computed by the first invocation may leak into the second.
  (let ((cycle (list :x)))
    (setf (cdr cycle) cycle)
    (let ((first (hashing-valid cycle))
          (second (hashing-valid cycle)))
      (parachute:is = first second)
      (parachute:true (equal first second))))
  (let* ((array (make-array 1)) (entry (sl:map-entry :key array)))
    (setf (aref array 0) entry)
    (let ((first (hashing-valid entry))
          (second (hashing-valid entry)))
      (parachute:is = first second)
      (parachute:true (equal first second)))))

(parachute:define-test hash-code.within-call-shared-substructure-memoization
  ;; One invocation over a DAG: both parents reach the shared child at the
  ;; same remaining depth, so the second visit must observe the (object,
  ;; depth) memo rather than recompute. The counting probe is dispatched
  ;; once per actual computation of the shared child's hash. Two shapes are
  ;; covered: a built-in cons DAG, and a user-compound HASHING-PAIR DAG
  ;; whose method memoizes nothing itself, so both edges are nested public
  ;; dispatch — the shape under which a table-nil in-invocation
  ;; discriminator would silently drop the memo and recompute the child.
  (flet ((fresh-copy (probe) (list probe :shared)))
    (let* ((probe (make-instance 'hashing-counted :value :probe))
           (shared (fresh-copy probe))
           (cons-dag (cons (list shared) (list shared)))
           (cons-fresh (cons (list (fresh-copy probe))
                             (list (fresh-copy probe))))
           (pair-dag (make-instance 'hashing-pair
                                    :left shared :right shared))
           (pair-fresh (make-instance 'hashing-pair
                                      :left (fresh-copy probe)
                                      :right (fresh-copy probe))))
      ;; Built-in shape: the shared child was computed exactly once within
      ;; the single invocation, not once per reaching parent.
      (let ((cons-dag-hash (hashing-valid cons-dag)))
        (parachute:is = 1 (hashing-counted-count probe))
        ;; Transparency: sharing must not change the value, so the DAG
        ;; hashes like the equal shape built from fresh, unshared copies.
        (parachute:is = cons-dag-hash (hashing-valid cons-fresh))
        (parachute:is = 3 (hashing-counted-count probe)))
      ;; User-compound shape: same observation through nested dispatch that
      ;; does not memoize the parent first.
      (let ((pair-dag-hash (hashing-valid pair-dag)))
        (parachute:is = 4 (hashing-counted-count probe))
        (parachute:is = pair-dag-hash (hashing-valid pair-fresh))
        (parachute:is = 6 (hashing-counted-count probe))))))
