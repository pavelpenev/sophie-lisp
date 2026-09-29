;;;; Shared validation and condition helpers.

(in-package #:sophie-lisp.internal)

(define-condition malformed-plist-error (program-error type-error)
  ((datum
     :initarg :datum
     :reader malformed-plist-error-datum)
   (expected-type
     :initarg :expected-type
     :reader malformed-plist-error-expected-type))
  (:report
    (lambda (condition stream)
      (format stream "Malformed plist ~S; expected ~S."
              (type-error-datum condition)
              (type-error-expected-type condition)))))

(defun raise-type-error (datum expected-type)
  "Signal the standard TYPE-ERROR for DATUM against EXPECTED-TYPE."
  (error 'type-error :datum datum :expected-type expected-type))

(define-condition simple-program-error (simple-condition program-error) ())

(defun raise-program-error (&optional format-control &rest format-arguments)
  "Signal PROGRAM-ERROR with a formatted report."
  (if (and format-control
           (not (and (stringp format-control) (zerop (length format-control)))))
      (error 'simple-program-error
             :format-control format-control
             :format-arguments format-arguments)
      (error 'simple-program-error
             :format-control "Invalid syntax or arguments."
             :format-arguments nil)))

(defun raise-simple-error (format-control &rest format-arguments)
  "Signal a standard SIMPLE-ERROR with FORMAT-CONTROL and FORMAT-ARGUMENTS."
  (error 'simple-error
         :format-control format-control
         :format-arguments format-arguments))

(defun signal-malformed-plist (datum expected-type)
  (error 'malformed-plist-error
         :datum datum
         :expected-type expected-type))

(defun usable-function-designator-p (object)
  (or (functionp object)
      (and (symbolp object)
           (not (macro-function object))
           (not (special-operator-p object))
           (fboundp object))))

(defun usable-function (designator)
  "Validate and retain a usable callback designator.

A function object is returned as-is.  An ordinary, currently fbound symbol is
also returned as-is so callers that defer invocation can resolve its definition
at the time of invocation."
  (cond
    ((functionp designator)
     designator)
    ((and (symbolp designator)
          (not (macro-function designator))
          (not (special-operator-p designator))
          (fboundp designator))
     designator)
    ((and (symbolp designator) (macro-function designator))
     (error 'simple-type-error
            :datum designator
            :expected-type '(satisfies usable-function-designator-p)
            :format-control "~S is a macro name, not an ordinary function."
            :format-arguments (list designator)))
    ((and (symbolp designator) (special-operator-p designator))
     (error 'simple-type-error
            :datum designator
            :expected-type '(satisfies usable-function-designator-p)
            :format-control "~S is a special-operator name, not an ordinary function."
            :format-arguments (list designator)))
    ((symbolp designator)
     (error 'simple-type-error
            :datum designator
            :expected-type '(satisfies usable-function-designator-p)
            :format-control "~S does not name a function."
            :format-arguments (list designator)))
    (t
     (raise-type-error designator '(or function symbol)))))

;;; Values never refer back to keys. DEFVAR preserves live identities on reload.
;; One portable weak-table path serves every host without implementation
;; conditionals. ECL's weak hash table does purge dead keys of the kinds this
;; table receives (verified on ECL 26.5.5): structure-object entries vanish
;; after one quiet full GC, and standard-object entries purge under allocation
;; churn, though not necessarily after a quiet full GC alone. ECL does retain
;; dead CONS-key entries even under allocation churn, but identity-hash is
;; called only from the standard-object and structure-object hash-code
;; methods, so no cons ever becomes a key here.
(defvar *identity-hashes* (tg:make-weak-hash-table :test #'eq :weakness :key))
(defvar *identity-hash-counter* 0)
;; BORDEAUX-THREADS replaces the SBCL sb-thread seam. BT:MAKE-LOCK takes the
;; name as an optional argument where SB-THREAD:MAKE-MUTEX took a :NAME
;; keyword; the lock itself is otherwise equivalent for this critical section.
(defvar *identity-hash-lock* (bt:make-lock "Sophie identity hashes"))

(defun mix64-wide (integer)
  "Return the original wide 64-bit SplitMix64 finalizer for INTEGER on every host."
  ;; SBCL compiles the unsigned word to raw SHR/XOR/MUL with one result box.
  ;; Keep SAFETY 1: at SAFETY 0 older compilers truncated round constants.
  (let ((word (ldb (byte 64 0) integer)))
    (declare (type (unsigned-byte 64) word))
    (setf word
          (ldb (byte 64 0)
               (* (logxor word (ash word -30)) #xbf58476d1ce4e5b9)))
    (setf word
          (ldb (byte 64 0)
               (* (logxor word (ash word -27)) #x94d049bb133111eb)))
    (logxor word (ash word -31))))

(defun mix64 (integer)
  "Return the 64-bit SplitMix64 finalizer for INTEGER when called directly.
On hosts with at most 61-bit fixnums, the load-time seam replaces MIX64's global
function definition with the fixnum-safe 32-bit MIX64-LIMB finalizer.
The host-list seam in src/containers/trie.lisp also replaces the MIX64 function
cell at load time on SBCL and CCL; see docs/portability.md.
The load-time MIX64 delegator definition is retained in *MIX64-LOAD-DEFINITION*."
  ;; Supported hosts swap this cell to the narrow mixer at load time (via the
  ;; fixnum-width seam here or the host-list seam in src/containers/trie.lisp);
  ;; the wide formulation lives in MIX64-WIDE, pinned by the frozen-reference oracle test.
  (mix64-wide integer))

(defvar *mix64-load-definition* nil
  "The pre-swap MIX64 function object, retained so the dormant delegator stays
pinned by tests on hosts whose load-time seam swaps the production cell.")

(eval-when (:load-toplevel :execute)
  (setf *mix64-load-definition* (fdefinition 'mix64)))

(defun mix64-limb (integer)
  "Return a non-negative 32-bit finalizer using arithmetic that stays in
fixnums on measured hosts with up to 61-bit fixnums. A port to narrower
fixnums may box intermediates without changing correctness."
  ;; The two 32-bit halves fold before mixing; each multiplication is below
  ;; 2^48, within fixnum range on the measured hosts; narrower ports may box.
  (let ((word (logxor (ldb (byte 32 0) integer)
                      (ldb (byte 32 32) integer))))
    (declare (type (unsigned-byte 32) word))
    (setf word (ldb (byte 32 0)
                    (* (logxor word (ash word -16)) #x9e37)))
    (setf word (ldb (byte 32 0)
                    (* (logxor word (ash word -13)) #x85eb)))
    (ldb (byte 32 0) (logxor word (ash word -16)))))

(eval-when (:load-toplevel :execute)
  ;; One load-time capability seam; on SBCL's 62-bit fixnums the MIX64 cell
  ;; retains the delegator until a seam swaps it; unboxed wide arithmetic lives
  ;; in MIX64-WIDE.
  ;; Same-file callers must declare MIX64 NOTINLINE to see the swapped function
  ;; cell rather than a compiler-bound wide definition; see IDENTITY-HASH.
  (when (<= (integer-length most-positive-fixnum) 61)
    (setf (fdefinition 'mix64) #'mix64-limb)))

(defun identity-hash (object)
  "Return OBJECT's stable unsigned-64 identity hash without retaining it."
  ;; ECL otherwise binds same-file calls to the original MIX64 delegator,
  ;; behaviorally wide but bypassing its load-time function-cell replacement.
  (declare (notinline mix64))
  ;; BT:WITH-LOCK-HELD takes the lock as its first argument, the same call
  ;; shape as the replaced SB-THREAD:WITH-MUTEX; no timeout or other keyword
  ;; differences apply to this uncontended critical section.
  (bt:with-lock-held (*identity-hash-lock*)
    (multiple-value-bind (hash presentp) (gethash object *identity-hashes*)
      (if presentp
          hash
          (setf (gethash object *identity-hashes*)
                (mix64 (incf *identity-hash-counter*)))))))

(declaim (ftype (function (t) t) lazy-key-within-hash-p))

(defun safe-key-hash (key)
  "Return KEY's hash and success flag, without forcing structural lazy nodes.
Any condition from HASH-CODE or the lazy-node scan returns (VALUES NIL NIL),
so the key is treated as unhashable."
  (unless (sl:lazy-seq-p key)
    (handler-case
        (if (lazy-key-within-hash-p key)
            (values nil nil)
            (values (sl:hash-code key) t))
      (condition () (values nil nil)))))

(defun standard-hash-test (designator)
  "Return the CL symbol for a standard hash-table test, or signal TYPE-ERROR.
A symbol designator must name one of the four standard test function objects."
  (let ((function
         (and (symbolp designator)
              (not (macro-function designator))
              (not (special-operator-p designator))
              (fboundp designator)
              (fdefinition designator))))
    (or (loop for name in '(eq eql equal equalp)
              when (eq (or function designator) (symbol-function name))
              return name)
        (raise-type-error
         designator
         '(or (member eq eql equal equalp)
           (satisfies standard-hash-test-function-p))))))

(defun standard-hash-test-function-p (object)
  "Whether OBJECT is one of the four standard hash-table test functions."
  (not (null (member object (list #'eq #'eql #'equal #'equalp) :test #'eq))))

(defun index-kind-for-test (test)
  "Return an index kind and standard CL test symbol, if applicable."
  (let ((standard (find-if (lambda (name)
                             (or (eq test name)
                                 (eq test (symbol-function name))))
                           '(eq eql equal equalp))))
    (values (cond (standard :table)
                  ((or (eq test 'sl:equals) (eq test #'sl:equals)) :hash)
                  (t :linear))
            standard)))

(defun nondefault-primary-p (generic-function arguments dispatch-index)
  "Classify participation using current methods applicable to actual ARGUMENTS.
DISPATCH-INDEX is zero-based among required arguments. This is inspection only:
callers invoke GENERIC-FUNCTION normally, with all methods and ordinary method combination."
  (let ((default-class (find-class 't)))
    (not
      (null
        (some (lambda (method)
                (and (null (method-qualifiers method))
                     (not (eq (nth dispatch-index
                                   (closer-mop:method-specializers method))
                              default-class))))
              (compute-applicable-methods generic-function arguments))))))

(defun copy-pristine-readtable ()
  "Copy the standard readtable, independently of the active reader state."
  (copy-readtable nil))

(defun register-named-readtable (name readtable)
  "Register READTABLE under NAME without activating or copying it."
  (named-readtables:register-readtable name readtable))

(defun require-external (package name)
  "Find an external symbol without interning or exporting anything."
  (multiple-value-bind (symbol status) (find-symbol name package)
    (unless (eq status :external)
      (error "~S is not external in package ~A." name (package-name package)))
    symbol))

(defun float-infinity-p (number)
  "Whether NUMBER is a floating-point infinity, in any float format."
  ;; Portable bounds check: an infinity in any format exceeds the widest finite
  ;; bound, and LONG-FLOAT is the widest format on every supported host (on
  ;; ECL a LONG-FLOAT distinct from, and wider than, DOUBLE-FLOAT). The
  ;; doubling trick is unusable here: every supported host traps
  ;; floating-point-overflow when doubling a large finite float, so it signals
  ;; instead of yielding a comparison bound. NaN needs the same care: SBCL and
  ;; CCL trap FLOATING-POINT-INVALID on comparisons involving NaN, while ECL
  ;; returns a false result without trapping, so the handler-case normalization
  ;; covers the trapping hosts and is harmless on the rest, classifying NaN as
  ;; not-an-infinity, matching the replaced SB-EXT:FLOAT-INFINITY-P, which
  ;; returns NIL for NaN.
  (and (floatp number)
       (handler-case (or (> number most-positive-long-float)
                         (< number most-negative-long-float))
         (floating-point-invalid-operation () nil))))

(defun float-nan-p (number)
  "Whether NUMBER is a floating-point NaN, in any float format."
  ;; A NaN is unordered: the self-comparison traps FLOATING-POINT-INVALID on
  ;; SBCL and CCL, while ECL returns a false result without trapping. The
  ;; handler-case normalization covers the trapping hosts and is harmless on
  ;; the rest, so a NaN is classified as unequal to itself on every host.
  ;; Finite and infinite floats always compare equal to themselves.
  (and (floatp number)
       (not (handler-case (= number number)
              (floating-point-invalid-operation () nil)))))
