;;;; Bounded structural hashing, with ordinary generic component dispatch.

(in-package #:sophie-lisp.internal)

(defconstant +hash-depth+ 16)
(defconstant +hash-prefix+ 64)
(defconstant +hash-truncated+ #x243f6a8885a308d3)
(defconstant +hash-empty+ #x13198a2e03707344)
(defconstant +hash-positive-infinity+ #x6a09e667f3bcc909)
(defconstant +hash-negative-infinity+ #xbb67ae8584caa73b)

(defvar *hash-depth* +hash-depth+)
(defvar *hash-context* nil)
;; Sole in-invocation discriminator for SL:HASH-CODE. The outer call binds
;; this marker to T alongside a fresh NIL *HASH-CONTEXT*; the memoization
;; table itself is then created lazily by CALL-WITH-STRUCTURAL-HASH, so flat
;; data (numbers, strings, ...) never pays for a table it cannot use. The
;; marker must be a separate variable: if the table's own nil-ness remained
;; the discriminator, every nested HASH-COMPONENT -> SL:HASH-CODE transition
;; would look like a fresh outer call and rebind a fresh table, silently
;; losing all shared-substructure memoization within one invocation while
;; every value-correctness test still passed.
(defvar *hash-invocation-active* nil)

(defun hash-combine (accumulator child)
  (mix64 (logxor accumulator (mix64 (+ child #x9e3779b97f4a7c15)))))

(defun hash-component (object depth)
  "Hash a component at DEPTH, without inspecting anything at depth zero.
The dynamic bound is restored on all exits. Recursive dispatch remains public,
including user subclass methods; their integer results are normalized privately."
  (if (<= depth 0)
      +hash-truncated+
      (let ((*hash-depth* depth))
        (ldb (byte 64 0) (sl:hash-code object)))))

(defun call-with-structural-hash (object function)
  "Return OBJECT's completed structural hash at the current remaining depth."
  ;; Lazy table creation: the SETF installs the table into the dynamic binding
  ;; established by the SL:HASH-CODE :around method, so memos never escape one
  ;; invocation. Creating the table eagerly in that method instead would tax
  ;; every flat hash with a table it never touches; keying the discriminator
  ;; on this table instead of the marker would break nested memoization.
  (unless *hash-context*
    (setf *hash-context* (make-hash-table :test #'eq)))
  (let ((entry (assoc *hash-depth* (gethash object *hash-context*))))
    (if entry
        (cdr entry)
        (let ((hash (funcall function)))
          (push (cons *hash-depth* hash) (gethash object *hash-context*))
          hash))))

(defun hash-unordered (tag count hashes)
  "Combine all HASHES commutatively, retaining repeated contributions.
The fold retains sums and sums of squares modulo 2^64 and is not
collision-resistant: for an even number of contributions, adding 2^63
to every HASH can leave both retained sums unchanged. Such collisions
between unequal containers are legal and affect performance only; trie
membership is always confirmed with SL:EQUALS, as covered by Chapter 9's
adversarial-hashing note."
  (let ((sum 0) (squares 0))
    (map nil (lambda (hash)
               (setf sum (ldb (byte 64 0) (+ sum hash))
                     squares (ldb (byte 64 0) (+ squares (* hash hash)))))
         hashes)
    (mix64 (logxor tag (mix64 count) (mix64 sum) (mix64 squares)))))

(defun hash-integer (integer)
  ;; Include all limbs, not just the low machine word of a bignum. The sign
  ;; and limb count separate different finite encodings; collisions are legal.
  ;; Keep the positive seed load-time and the negative seed runtime for load-order shaping.
  (let ((magnitude (abs integer))
        (hash (if (minusp integer)
                  (mix64 11)
                  (load-time-value (mix64 12) t)))
        (count 0))
    (loop
     (setf hash (hash-combine hash (ldb (byte 64 0) magnitude)))
     (incf count)
     (setf magnitude (ash magnitude -64))
     (when (zerop magnitude)
       (return (hash-combine hash count))))))

;; This is a separate host-tuning decision from the fixnum-width MIX64 seam.
;; Adding a measured host to this list opts it into the full narrow discipline.
(eval-when (:compile-toplevel :load-toplevel :execute)
  (defparameter *narrow-hash-discipline-hosts*
    '("Clozure Common Lisp" "SBCL")))

;; Selected hosts resolve same-file calls through the swapped function cells.
(eval-when (:compile-toplevel)
  (when (member (lisp-implementation-type) *narrow-hash-discipline-hosts*
                :test #'string=)
    (proclaim '(notinline mix64 hash-combine hash-unordered hash-integer))))

(defun hash-fold32 (value)
  ;; Child methods can supply full 64-bit values; fold both halves first.
  (logxor (ldb (byte 32 0) value) (ldb (byte 32 32) value)))

(defun hash-combine-32 (accumulator child)
  ;; The largest addition is below 2^33; MIX64 uses the selected limb mixer.
  (mix64 (logxor (hash-fold32 accumulator)
                 (mix64 (ldb (byte 32 0)
                             (+ (hash-fold32 child) #x7f4a7c15))))))

(defun hash-square32 (value)
  ;; (lo + 2^16 hi)^2 modulo 2^32; hi^2 vanishes. The largest
  ;; multiplication is 2*lo*hi < 2^33, never a general 32x32 product.
  (let ((lo (ldb (byte 16 0) value))
        (hi (ldb (byte 16 16) value)))
    (ldb (byte 32 0)
         (+ (* lo lo)
            (ash (ldb (byte 16 0) (* 2 lo hi)) 16)))))

(defun hash-unordered-32 (tag count hashes)
  "Combine all HASHES commutatively with 32-bit sums and squares.
This fold is not collision-resistant: for an even number of contributions,
adding 2^31 to every folded HASH can leave both sums unchanged modulo 2^32.
Unequal-container collisions affect performance only; trie membership is
confirmed with SL:EQUALS (Chapter 9, adversarial hashing)."
  (let ((sum 0) (squares 0))
    (map nil (lambda (hash)
               (let ((word (hash-fold32 hash)))
                 (setf sum (ldb (byte 32 0) (+ sum word))
                       squares (ldb (byte 32 0)
                                    (+ squares (hash-square32 word))))))
         hashes)
    (mix64 (logxor (hash-fold32 tag)
                   (mix64 (hash-fold32 count))
                   (mix64 sum)
                   (mix64 squares)))))

(defun hash-integer-32 (integer)
  ;; Process all 32-bit limbs, not merely the low machine word.
  ;; The seed calls must run after the host-list seam swaps MIX64 below: a
  ;; LOAD-TIME-VALUE here would capture the pre-swap wide mixer on SBCL.
  (let ((magnitude (abs integer))
        (hash (if (minusp integer) (mix64 11) (mix64 12)))
        (count 0))
    (loop
     (setf hash (hash-combine hash (ldb (byte 32 0) magnitude)))
     (incf count)
     (setf magnitude (ash magnitude -32))
     (when (zerop magnitude)
       (return (hash-combine hash count))))))

(eval-when (:load-toplevel :execute)
  ;; CCL already selects MIX64-LIMB through the fixnum-width seam; SBCL also
  ;; needs the narrow mixer because wide MIX64 products box there. ECL's
  ;; C-level bignums are cheap: measured narrow-combining variants regress,
  ;; so it keeps its width-selected limb mixer and default combining.
  (when (member (lisp-implementation-type) *narrow-hash-discipline-hosts*
                :test #'string=)
    (setf (fdefinition 'mix64) #'mix64-limb
          (fdefinition 'hash-combine) #'hash-combine-32
          (fdefinition 'hash-unordered) #'hash-unordered-32
          (fdefinition 'hash-integer) #'hash-integer-32)))

(defun hash-real (number)
  ;; Unlike the seeds in HASH-INTEGER-32, the LOAD-TIME-VALUE seeds below
  ;; are correct because this definition follows the host-list swap above.
  ;; RATIONAL is exact, unlike RATIONALIZE or conversion to a common float
  ;; format. It also canonicalizes signed zero and all integral floats.
  ;; NaN is classified here because the hosts disagree underneath: SBCL's
  ;; RATIONAL signals for a NaN, while CCL's accepts it and returns its bit
  ;; pattern, so the TYPE-ERROR is raised on every host before RATIONAL runs.
  (cond ((float-nan-p number)
         (raise-type-error number 'rational))
        ((float-infinity-p number)
         (if (minusp number)
             +hash-negative-infinity+
             +hash-positive-infinity+))
        (t
         (let* ((canonical (rational number))
                (denominator (denominator canonical)))
           (hash-combine
            (hash-combine (load-time-value (mix64 13) t)
                          (hash-integer (numerator canonical)))
            (if (= denominator 1)
                (load-time-value (hash-integer 1) t)
                (hash-integer denominator)))))))

(defmethod sl:hash-code :around ((object t))
  (declare (ignore object))
  (if *hash-invocation-active*
      (call-next-method)
      ;; One fresh invocation: the marker records in-invocation state and the
      ;; table starts NIL for CALL-WITH-STRUCTURAL-HASH to create lazily. An
      ;; eager table here would allocate on every flat hash; testing the table
      ;; instead of the marker would rebind it at every nested component.
      (let ((*hash-invocation-active* t)
            (*hash-context* nil))
        (call-next-method))))

(defmethod sl:hash-code ((object t))
  ;; SXHASH guarantees EQL consistency. Compound and instance types have
  ;; more specific methods below, so mutable structural SXHASH is not used.
  (mix64 (sxhash object)))

(defmethod sl:hash-code ((object standard-object))
  (identity-hash object))

(defmethod sl:hash-code ((object structure-object))
  (identity-hash object))

(defmethod sl:hash-code ((object number))
  (cond ((realp object)
         (hash-real object))
        ((zerop (imagpart object))
         (hash-real (realpart object)))
        (t
         (hash-combine
          (hash-combine (mix64 14) (hash-real (realpart object)))
          (hash-real (imagpart object))))))

(defmethod sl:hash-code ((object character))
  (hash-combine (mix64 15) (char-code object)))

(defmethod sl:hash-code ((object null))
  +hash-empty+)

(defmethod sl:hash-code ((object cons))
  ;; Actual car/cdr structure, not a flattened list: lazy and dotted tails
  ;; reach their own methods. Decreasing both edges bounds even car cycles.
  (call-with-structural-hash
   object
   (lambda ()
     (let ((depth (1- *hash-depth*)))
       (hash-combine
        (hash-combine (mix64 16) (hash-component (car object) depth))
        (hash-component (cdr object) depth))))))

(defmethod sl:hash-code ((object array))
  ;; STRING inherits this method: element type, capacity and displacement
  ;; cannot distinguish equality-equivalent rank-one character arrays.
  (call-with-structural-hash
   object
   (lambda ()
     (let* ((rank (array-rank object))
            (size (if (= rank 1) (length object) (array-total-size object)))
            (depth (1- *hash-depth*))
            (hash (hash-combine (mix64 17) rank)))
       (if (= rank 1)
           (setf hash (hash-combine hash size))
           (dolist (dimension (array-dimensions object))
             (setf hash (hash-combine hash dimension))))
       (setf hash (hash-combine hash 18))
       (dotimes (index (min size +hash-prefix+))
         (setf hash (hash-combine
                     hash (hash-component (row-major-aref object index) depth))))
       (hash-combine hash (if (> size +hash-prefix+) 19 20))))))

(defmethod sl:hash-code ((object sl:lazy-seq))
  ;; Resolve wrappers, never consult cached/known length. Recursive rest
  ;; dispatch spends a structural edge just like any other component; thus
  ;; at most 16 spine elements are observed, within the 64-element ceiling.
  ;; A finite cycle ends at depth zero, but diverging thunks are not caught.
  (call-with-structural-hash
   object
   (lambda ()
     (multiple-value-bind (empty-p element rest) (lazy-step object)
       (if empty-p
           +hash-empty+
           (let ((depth (1- *hash-depth*)))
             (hash-combine
              (hash-combine (mix64 21) (hash-component element depth))
              (hash-component rest depth))))))))

(defmethod sl:hash-code ((object sl:map-entry))
  (call-with-structural-hash
   object
   (lambda ()
     (let ((depth (1- *hash-depth*)))
       (hash-combine
        (hash-combine (mix64 22)
                      (hash-component (sl:entry-key object) depth))
        (hash-component (sl:entry-value object) depth))))))

(defmethod sl:hash-code ((object hash-table))
  ;; Do not use the native test, choose a traversal prefix, or collapse keys.
  ;; Every entry contributes one ordered key/value hash to a multiset fold.
  (call-with-structural-hash
   object
   (lambda ()
     (let ((depth (1- *hash-depth*))
           (hashes nil))
       (maphash (lambda (key value)
                  (push (hash-combine
                         (hash-combine (mix64 23) (hash-component key depth))
                         (hash-component value depth))
                        hashes))
                object)
       (hash-unordered 24 (hash-table-count object) hashes)))))

(defstruct (trie-leaf (:constructor make-trie-leaf (hash key value)))
  (hash 0 :type (unsigned-byte 64) :read-only t)
  (key nil :read-only t)
  (value nil :read-only t))

(defstruct (trie-branch (:constructor make-trie-branch (bitmap children)))
  (bitmap 0 :type (unsigned-byte 32) :read-only t)
  (children #() :type simple-vector :read-only t))

(defstruct (trie-collision (:constructor make-trie-collision (hash leaves)))
  (hash 0 :type (unsigned-byte 64) :read-only t)
  (leaves #() :type simple-vector :read-only t))

(defun trie-normalize-hash (hash)
  (ldb (byte 64 0) hash))

(defun trie-bit (hash shift)
  ;; At shift 60 the normalized word supplies only four remaining bits.
  (ash 1 (ldb (byte 5 shift) hash)))

(defun trie-rank (bitmap bit)
  (logcount (logand bitmap (1- bit))))

(defun trie-vector-insert (vector index item)
  (let ((result (make-array (1+ (length vector)))))
    (replace result vector :end1 index :end2 index)
    (setf (svref result index) item)
    (replace result vector :start1 (1+ index) :start2 index)
    result))

(defun trie-vector-replace (vector index item)
  (let ((result (copy-seq vector)))
    (setf (svref result index) item)
    result))

(defun trie-vector-remove (vector index)
  (let ((result (make-array (1- (length vector)))))
    (replace result vector :end1 index :end2 index)
    (replace result vector :start1 index :start2 (1+ index))
    result))

(defun trie-terminal-hash (node)
  (etypecase node
    (trie-leaf (trie-leaf-hash node))
    (trie-collision (trie-collision-hash node))))

(defun trie-join (left right shift)
  "Join terminals with distinct full hashes, preserving every prefix level."
  ;; Distinct normalized 64-bit hashes differ in one of 13 chunks (shifts
  ;; 0..60), even though narrow-discipline hosts' built-in mixer emits
  ;; only 32 bits, because user HASH-CODE methods can still supply all 64 bits.
  ;; Equal-bit recursion
  ;; terminates by shift 60; equal hashes never terminate because LDB past
  ;; bit 63 reads zero from shift 65 onward.
  (let ((left-bit (trie-bit (trie-terminal-hash left) shift))
        (right-bit (trie-bit (trie-terminal-hash right) shift)))
    (if (= left-bit right-bit)
        (if (>= shift 60)
            (error "TRIE-JOIN requires terminals with distinct full hashes.")
            (make-trie-branch left-bit
                              (vector (trie-join left right (+ shift 5)))))
        (make-trie-branch (logior left-bit right-bit)
                          (if (< left-bit right-bit)
                              (vector left right)
                              (vector right left))))))

(defun trie-leaf-matches-p (leaf key hash)
  (and (= hash (trie-leaf-hash leaf))
       (sl:equals key (trie-leaf-key leaf))))

(defun trie-collision-position (node key)
  (position key (trie-collision-leaves node)
            :key #'trie-leaf-key :test #'sl:equals))

(defun trie-ref (root key hash)
  (let ((hash (trie-normalize-hash hash)) (node root) (shift 0))
    (loop
     (etypecase node
       (null (return (values nil nil nil)))
       (trie-leaf
        (return (if (trie-leaf-matches-p node key hash)
                    (values (trie-leaf-value node) t (trie-leaf-key node))
                    (values nil nil nil))))
       (trie-collision
        (let ((index (and (= hash (trie-collision-hash node))
                          (trie-collision-position node key))))
          (return (if index
                      (let ((leaf (svref (trie-collision-leaves node) index)))
                        (values (trie-leaf-value leaf) t (trie-leaf-key leaf)))
                      (values nil nil nil)))))
       (trie-branch
        (let ((bit (trie-bit hash shift))
              (bitmap (trie-branch-bitmap node)))
          (unless (logtest bit bitmap) (return (values nil nil nil)))
          (setf node (svref (trie-branch-children node) (trie-rank bitmap bit)))
          (incf shift 5)))))))

(defun trie-put-leaf (node key value hash replace-key-p shift)
  (cond
    ((trie-leaf-matches-p node key hash)
     (if replace-key-p
         (values (make-trie-leaf hash key value) 0 t)
         (values node 0 nil)))
    ((= hash (trie-leaf-hash node))
     (values (make-trie-collision
              hash (vector node (make-trie-leaf hash key value)))
             1 t))
    (t
     (values (trie-join node (make-trie-leaf hash key value) shift) 1 t))))

(defun trie-put-collision (node key value hash replace-key-p shift)
  (unless (= hash (trie-collision-hash node))
    (return-from trie-put-collision
      (values (trie-join node (make-trie-leaf hash key value) shift) 1 t)))
  (let ((index (trie-collision-position node key))
        (leaves (trie-collision-leaves node)))
    (cond
      ((null index)
       (values (make-trie-collision
                hash (trie-vector-insert leaves (length leaves)
                                         (make-trie-leaf hash key value)))
               1 t))
      (replace-key-p
       (values (make-trie-collision
                hash (trie-vector-replace leaves index
                                          (make-trie-leaf hash key value)))
               0 t))
      (t (values node 0 nil)))))

(defun trie-put-branch (node key value hash replace-key-p shift)
  (let* ((bit (trie-bit hash shift))
         (bitmap (trie-branch-bitmap node))
         (children (trie-branch-children node))
         (index (trie-rank bitmap bit)))
    (if (logtest bit bitmap)
        (multiple-value-bind (child delta changed-p)
            (trie-put-at (svref children index) key value hash
                         replace-key-p (+ shift 5))
          (if changed-p
              (values (make-trie-branch
                       bitmap (trie-vector-replace children index child))
                      delta t)
              (values node 0 nil)))
        (values (make-trie-branch
                 (logior bitmap bit)
                 (trie-vector-insert children index (make-trie-leaf hash key value)))
                1 t))))

(defun trie-put-at (node key value hash replace-key-p shift)
  (etypecase node
    (null (values (make-trie-leaf hash key value) 1 t))
    (trie-leaf (trie-put-leaf node key value hash replace-key-p shift))
    (trie-collision (trie-put-collision node key value hash replace-key-p shift))
    (trie-branch (trie-put-branch node key value hash replace-key-p shift))))

(defun trie-put (root key value hash replace-key-p)
  (trie-put-at root key value (trie-normalize-hash hash) replace-key-p 0))

(defun trie-collapse-branch (bitmap children)
  ;; A terminal carries its full hash and may move up. A branch cannot: its
  ;; bitmap is relative to its depth, including any retained singleton prefix.
  (cond
    ((zerop (length children)) nil)
    ((and (= 1 (length children))
          (not (trie-branch-p (svref children 0))))
     (svref children 0))
    (t (make-trie-branch bitmap children))))

(defun trie-remove-collision (node key hash)
  (let ((index (and (= hash (trie-collision-hash node))
                    (trie-collision-position node key))))
    (if (null index)
        (values node nil)
        (let ((leaves (trie-collision-leaves node)))
          (values (if (= 2 (length leaves))
                      (svref leaves (- 1 index))
                      (make-trie-collision hash (trie-vector-remove leaves index)))
                  t)))))

(defun trie-remove-branch (node key hash shift)
  (let* ((bit (trie-bit hash shift))
         (bitmap (trie-branch-bitmap node))
         (children (trie-branch-children node))
         (index (trie-rank bitmap bit)))
    (unless (logtest bit bitmap)
      (return-from trie-remove-branch (values node nil)))
    (multiple-value-bind (child removed-p)
        (trie-remove-at (svref children index) key hash (+ shift 5))
      (if (not removed-p)
          (values node nil)
          (values (if child
                      (trie-collapse-branch
                       bitmap (trie-vector-replace children index child))
                      (trie-collapse-branch
                       (logxor bitmap bit) (trie-vector-remove children index)))
                  t)))))

(defun trie-remove-at (node key hash shift)
  (etypecase node
    (null (values nil nil))
    (trie-leaf
     (if (trie-leaf-matches-p node key hash)
         (values nil t)
         (values node nil)))
    (trie-collision (trie-remove-collision node key hash))
    (trie-branch (trie-remove-branch node key hash shift))))

(defun trie-remove (root key hash)
  (trie-remove-at root key (trie-normalize-hash hash) 0))

(defun trie-cursor (root)
  "An immutable stack of (node . next-child-index) frames; NIL is exhausted."
  (when root (list (cons root 0))))

(defun trie-next (cursor)
  ;; POP/PUSH change only this local stack binding. Frames and old list spines
  ;; are never modified, so any retained cursor may be stepped again.
  (let ((stack cursor))
    (loop while stack do
      (let* ((frame (pop stack)) (node (car frame)) (index (cdr frame)))
        (etypecase node
          (trie-leaf
           (return-from trie-next
             (values t (trie-leaf-key node) (trie-leaf-value node) stack)))
          (trie-collision
           (let* ((leaves (trie-collision-leaves node))
                  (leaf (svref leaves index)))
             (when (< (1+ index) (length leaves))
               (push (cons node (1+ index)) stack))
             (return-from trie-next
               (values t (trie-leaf-key leaf) (trie-leaf-value leaf) stack))))
          (trie-branch
           (let ((children (trie-branch-children node)))
             (when (< (1+ index) (length children))
               (push (cons node (1+ index)) stack))
             (push (cons (svref children index) 0) stack))))))
    (values nil nil nil nil)))
