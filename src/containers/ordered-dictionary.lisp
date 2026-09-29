;;;; Persistent ordered dictionaries: immutable AVL order and direct key index.
(in-package #:sophie-lisp.internal)

;;; Index payloads contain no tree links: unrelated keys cannot pin old paths.
(defstruct (ordered-association
             (:constructor ordered-association (ordinal entry))
             (:copier nil))
  (ordinal 0 :type integer :read-only t)
  (entry nil :read-only t))

(defstruct (ordered-node
             (:constructor make-ordered-node (ordinal entry left right height))
             (:copier nil))
  (ordinal 0 :type integer :read-only t)
  (entry nil :read-only t)
  (left nil :read-only t)
  (right nil :read-only t)
  (height 1 :type integer :read-only t))

(defun ordered-height (node)
  (if node (ordered-node-height node) 0))

(defun ordered-branch (ordinal entry left right)
  (make-ordered-node ordinal entry left right
                     (1+ (max (ordered-height left) (ordered-height right)))))

(defun ordered-rotate-left (node)
  (let ((right (ordered-node-right node)))
    (ordered-branch
     (ordered-node-ordinal right) (ordered-node-entry right)
     (ordered-branch (ordered-node-ordinal node) (ordered-node-entry node)
                     (ordered-node-left node) (ordered-node-left right))
     (ordered-node-right right))))

(defun ordered-rotate-right (node)
  (let ((left (ordered-node-left node)))
    (ordered-branch
     (ordered-node-ordinal left) (ordered-node-entry left)
     (ordered-node-left left)
     (ordered-branch (ordered-node-ordinal node) (ordered-node-entry node)
                     (ordered-node-right left) (ordered-node-right node)))))

(defun ordered-balance (ordinal entry left right)
  ;; Each child is AVL; cached heights make each repair constant node work.
  (cond
    ((> (- (ordered-height left) (ordered-height right)) 1)
     (ordered-rotate-right
      (ordered-branch
       ordinal entry
       (if (< (ordered-height (ordered-node-left left))
              (ordered-height (ordered-node-right left)))
           (ordered-rotate-left left) left)
       right)))
    ((> (- (ordered-height right) (ordered-height left)) 1)
     (ordered-rotate-left
      (ordered-branch
       ordinal entry left
       (if (< (ordered-height (ordered-node-right right))
              (ordered-height (ordered-node-left right)))
           (ordered-rotate-right right) right))))
    (t (ordered-branch ordinal entry left right))))

(defun ordered-avl-set (node ordinal entry)
  (if (null node)
      (ordered-branch ordinal entry nil nil)
      (let ((at (ordered-node-ordinal node))
            (left (ordered-node-left node))
            (right (ordered-node-right node)))
        (cond ((< ordinal at)
               (ordered-balance at (ordered-node-entry node)
                                (ordered-avl-set left ordinal entry) right))
              ((> ordinal at)
               (ordered-balance at (ordered-node-entry node)
                                left (ordered-avl-set right ordinal entry)))
              (t (ordered-branch ordinal entry left right))))))

(defun ordered-avl-minimum (node)
  (when node
    (loop while (ordered-node-left node)
          do (setf node (ordered-node-left node))
          finally (return node))))

(defun ordered-avl-delete (node ordinal)
  (when node
    (let ((at (ordered-node-ordinal node))
          (entry (ordered-node-entry node))
          (left (ordered-node-left node))
          (right (ordered-node-right node)))
      (cond ((< ordinal at)
             (ordered-balance at entry (ordered-avl-delete left ordinal) right))
            ((> ordinal at)
             (ordered-balance at entry left (ordered-avl-delete right ordinal)))
            ((null left) right)
            ((null right) left)
            (t (let ((successor (ordered-avl-minimum right)))
                 (ordered-balance
                  (ordered-node-ordinal successor) (ordered-node-entry successor)
                  left (ordered-avl-delete right (ordered-node-ordinal successor)))))))))

(defclass sl:ordered-dict ()
  ((lookup :initarg :lookup :reader ordered-dict-lookup)
   (root :initarg :root :reader ordered-dict-order-root)
   (next-ordinal :initarg :next-ordinal :reader ordered-dict-next-ordinal))
  (:documentation
   "Persistent finite dictionary with fixed EQUALS keys and stored entry order.
Construction is controlled by the public constructor and protocols; direct
MAKE-INSTANCE and subclassing have undefined consequences, as for DICT.
Ordering updates copy O(log n) nodes plus backing DICT operations. Hash/equality
callbacks and collisions add their own costs; ordinal integer bit cost can grow
with an indefinitely edited history. Contained objects are not frozen."))

(defun sl:ordered-dict-p (object)
  "Return true if OBJECT is an SL:ORDERED-DICT."
  (typep object 'sl:ordered-dict))

(defun ordered-from-buffer (class buffer)
  "Publish unique entries in BUFFER order without retaining mutable storage.
BUFFER must contain no EQUALS-duplicate keys: tree node count and lookup size
must agree, or SEQ-LENGTH undercounts traversal and EQUALS may signal TYPE-ERROR.
Exactly n tree nodes and n backing index insertions; no AVL insertions/rotations.
Tree building is linear, separately from hashing/equality and collision costs."
  (let ((lookup (sl:dict))
        (size (length buffer)))
    (loop for ordinal below size for entry = (aref buffer ordinal)
          do (setf lookup (sl:dict-set lookup (sl:entry-key entry)
                                       (ordered-association ordinal entry))))
    (labels ((build (start end)
               (when (< start end)
                 (let ((middle (floor (+ start end) 2)))
                   (ordered-branch middle (aref buffer middle)
                                   (build start middle)
                                   (build (1+ middle) end))))))
      (make-instance class :lookup lookup :root (build 0 size)
                     :next-ordinal size))))

(defun ordered-from-entries (class entries)
  "Consume entries into local first-position/latest-association staging."
  (let ((positions (sl:dict))
        (buffer (make-array 16 :adjustable t :fill-pointer 0)))
    (do-view-elements (entry entries)
      (unless (typep entry 'sl:map-entry)
        (raise-type-error entry 'sl:map-entry))
      (let ((key (sl:entry-key entry)))
        (multiple-value-bind (position present) (sl:dict-ref positions key)
          (if present
              (setf (aref buffer position) entry)
              (let ((position (length buffer)))
                (vector-push-extend entry buffer
                                    (max 1 (array-total-size buffer)))
                (setf positions (sl:dict-set positions key position)))))))
    (ordered-from-buffer class buffer)))

(defun sl:ordered-dict (&rest key-values)
  "Construct an ordered dictionary from alternating keys and values.
Keys match by EQUALS. For duplicate keys, the first position is retained and
the last association wins. Signals PROGRAM-ERROR for an odd argument count."
  ;; Validate complete arity before calling any key's value protocols.
  (when (oddp (length key-values)) (error 'program-error))
  (ordered-from-entries
   'sl:ordered-dict
   (loop for (key value) on key-values by #'cddr
         collect (sl:map-entry key value))))

(defmethod sl:dictp ((dictionary sl:ordered-dict)) t)

(defmethod sl:dict-ref ((dictionary sl:ordered-dict) key &optional default)
  (multiple-value-bind (association present)
      (sl:dict-ref (ordered-dict-lookup dictionary) key)
    (if present
        (values (sl:entry-value (ordered-association-entry association)) t)
        (values default nil))))

(defmethod (setf sl:dict-ref)
    (new-value (dictionary sl:ordered-dict) key &optional default)
  (declare (ignore new-value key default))
  (error "A persistent ORDERED-DICT is immutable; use DICT-SET instead."))

(defmethod sl:dict-test ((dictionary sl:ordered-dict)) #'sl:equals)

(defmethod sl:dict-size ((dictionary sl:ordered-dict))
  (sl:dict-size (ordered-dict-lookup dictionary)))

(defmethod sl:dict-set ((dictionary sl:ordered-dict) key value)
  (multiple-value-bind (old present) (sl:dict-ref (ordered-dict-lookup dictionary) key)
    (let* ((ordinal (if present (ordered-association-ordinal old)
                         (ordered-dict-next-ordinal dictionary)))
           (entry (sl:map-entry key value)))
      ;; Core DICT-SET already replaces the complete key representative, even
      ;; for EQ-identical values. All work is persistent until publication.
      (make-instance (class-of dictionary)
                     :lookup (sl:dict-set (ordered-dict-lookup dictionary) key
                                          (ordered-association ordinal entry))
                     :root (ordered-avl-set (ordered-dict-order-root dictionary)
                                            ordinal entry)
                     :next-ordinal (if present (ordered-dict-next-ordinal dictionary)
                                       (1+ ordinal))))))

(defmethod sl:dict-without ((dictionary sl:ordered-dict) key)
  (multiple-value-bind (old present) (sl:dict-ref (ordered-dict-lookup dictionary) key)
    (if present
        (make-instance (class-of dictionary)
                       :lookup (sl:dict-without (ordered-dict-lookup dictionary) key)
                       :root (ordered-avl-delete (ordered-dict-order-root dictionary)
                                                 (ordered-association-ordinal old))
                       :next-ordinal (ordered-dict-next-ordinal dictionary))
        dictionary)))

(defun ordered-pending (tree frames)
  ;; Frames are (entry . right-tree), not ancestors pinning consumed prefixes.
  ;; Neither frames nor trees are ever mutated.
  (loop while tree
        do (push (cons (ordered-node-entry tree) (ordered-node-right tree)) frames)
        (setf tree (ordered-node-left tree)))
  frames)

(defun ordered-advance (frames)
  (ordered-pending (cdar frames) (cdr frames)))

(defun ordered-entry-view (frames)
  "Linear in-order traversal with logarithmic pending state, no index lookups."
  (when frames
    (let ((entry (caar frames))
          (right (cdar frames))
          (pending (cdr frames)))
      (sl:lazy-seq
       (sl:lazy-cons entry (ordered-entry-view (ordered-pending right pending)))))))

(defmethod sl:seqablep ((dictionary sl:ordered-dict)) t)

(defmethod sl:seq-emptyp ((dictionary sl:ordered-dict))
  (null (ordered-dict-order-root dictionary)))

(defmethod sl:seq-first ((dictionary sl:ordered-dict))
  (let ((first (ordered-avl-minimum (ordered-dict-order-root dictionary))))
    (when first (ordered-node-entry first))))

(defmethod sl:seq-rest ((dictionary sl:ordered-dict))
  (ordered-entry-view
   (ordered-advance (ordered-pending (ordered-dict-order-root dictionary) nil))))

(defmethod sl:seq-length ((dictionary sl:ordered-dict))
  (sl:dict-size (ordered-dict-lookup dictionary)))

;;; SEQ-REF uses the standard positional traversal fallback; REF uses Dict first.
;;; No positional writer is supplied. Value protocols are owned separately.
(defmethod print-object ((dictionary sl:ordered-dict) stream)
  (print-unreadable-object (dictionary stream :type t :identity t)
    (format stream "~D entries" (sl:dict-size dictionary))))

(defmethod sl:equals ((left-dictionary sl:ordered-dict)
                      (right-dictionary sl:ordered-dict))
  ;; Do not compare the backing index, ordinals, or AVL shape. In particular,
  ;; neither key lookup nor a hash precheck may inspect an irrelevant value.
  ;; No identity shortcut or cycle table changes the default recursive policy.
  (and (eq (class-of left-dictionary) (class-of right-dictionary))
       (= (sl:dict-size left-dictionary) (sl:dict-size right-dictionary))
       (loop with left = (ordered-pending (ordered-dict-order-root left-dictionary) nil)
             with right = (ordered-pending (ordered-dict-order-root right-dictionary) nil)
             while left
             always (container-association-equal-p (caar left) (caar right))
             do (setf left (ordered-advance left)
                      right (ordered-advance right)))))

;;; ORDERED-DICT is a sibling of the other standardized containers. Their
;;; cross-representation calls in either direction already select the identity
;;; EQUALS fallback and equality-based COMPARE fallback. Do not install broad
;;; rejection methods that would interfere with unrelated user-type extensions.
(defmethod sl:compare ((left-object sl:ordered-dict)
                       (right-object sl:ordered-dict))
  (if (sl:equals left-object right-object) :equal :unequal))

(defmethod sl:hash-code ((object sl:ordered-dict))
  ;; Ordered prefixes are canonical, unlike prefixes of unordered trie walks.
  ;; Count plus the first +HASH-PREFIX+ associations supplies content hashing;
  ;; equal-size differences beyond that prefix may intentionally collide.
  ;; Each key/value edge spends the provider's remaining depth. The private
  ;; MAP-ENTRY storage wrapper and AVL edges are not logical content edges.
  (call-with-structural-hash
   object
   (lambda ()
     (let* ((count (sl:dict-size object))
            (depth (1- *hash-depth*))
            (frames (ordered-pending (ordered-dict-order-root object) nil))
            (hash (hash-combine (mix64 29) count)))
       (loop repeat (min count +hash-prefix+)
             for entry = (caar frames)
             do (setf hash
                      (hash-combine
                       hash (container-association-hash
                             (sl:entry-key entry) (sl:entry-value entry) depth))
                      frames (ordered-advance frames)))
       (hash-combine hash (if (> count +hash-prefix+) 30 31))))))

;;; Completed structural hashes are memoized only in the dynamically scoped
;;; invocation context, so mutable values are observed afresh by the next outer
;;; call. HASH-COMPONENT still truncates before public dispatch at zero and
;;; restores the shared depth on every exit. Finite core cycles therefore
;;; terminate without changing the hash of equivalent shared and copied
;;; unfoldings. No public hash-context protocol is introduced.

(defun lazy-key-within-hash-p (key)
  "Detect lazy nodes along bounded built-in structural HASH-CODE edges.
User-defined HASH-CODE methods may traverse or force objects this
representation-based scan cannot inspect."
  (let (seen)
    (labels ((visit (object depth)
               (cond
                 ((<= depth 0) nil)
                 ;; Atomic hash inputs have no structural edges to a lazy node.
                 ((or (numberp object) (characterp object) (symbolp object)) nil)
                 ;; NIL is a valid lazy sequence, but hashing NIL cannot force
                 ;; anything; the top-level NIL case retains its old exclusion.
                 ((typep object 'sl:lazy-seq) t)
                 ;; Only character and proven numeric array elements exclude
                 ;; compounds; other specialized element types are not enough.
                 ;; NIL element type passes SUBTYPEP as numeric; an array with
                 ;; no elements cannot hold a lazy node. If accessing one
                 ;; would signal NIL-ARRAY-ACCESSED-ERROR, SAFE-KEY-HASH catches
                 ;; it just as it caught the old scan's access error.
                 ((and (arrayp object)
                       (or (stringp object)
                           (multiple-value-bind (numeric-p certain-p)
                               (subtypep (array-element-type object) 'number)
                             (and certain-p numeric-p))))
                  nil)
                 ((not (or (consp object) (arrayp object) (hash-table-p object)
                           (typep object 'sl:map-entry)
                           (typep object 'sl:dict) (typep object 'sl:hash-set)
                           (typep object 'sl:ordered-dict)
                           (typep object 'sl:plist-dict-view)))
                  nil)
                 (t
                  (unless seen (setf seen (make-hash-table :test #'eq)))
                  ;; A prior visit with at least this depth already explored as far.
                  (when (>= (gethash object seen 0) depth)
                    (return-from visit nil))
                  (setf (gethash object seen) depth)
                  (let ((child-depth (1- depth)))
                    (typecase object
                      (cons
                       (or (visit (car object) child-depth)
                           (visit (cdr object) child-depth)))
                      (array
                       (loop for index below
                               (min (if (= (array-rank object) 1)
                                        (length object) (array-total-size object))
                                    +hash-prefix+)
                             thereis (visit (row-major-aref object index)
                                            child-depth)))
                      (sl:map-entry
                       (or (visit (sl:entry-key object) child-depth)
                           (visit (sl:entry-value object) child-depth)))
                      (hash-table
                       (block found
                         (maphash (lambda (item value)
                                    (when (or (visit item child-depth)
                                              (visit value child-depth))
                                      (return-from found t)))
                                  object)))
                      (sl:ordered-dict
                       (loop with frames = (ordered-pending
                                            (ordered-dict-order-root object) nil)
                             repeat (min (sl:dict-size object) +hash-prefix+)
                             for entry = (caar frames)
                             when (or (visit (sl:entry-key entry) child-depth)
                                      (visit (sl:entry-value entry) child-depth))
                               return t
                             do (setf frames (ordered-advance frames))))
                      (sl:plist-dict-view
                       (loop for entry across (plist-view-canonical object)
                             thereis (or (visit (sl:entry-key entry) child-depth)
                                         (visit (sl:entry-value entry) child-depth))))
                      ((or sl:dict sl:hash-set)
                       (loop with dictionary-p = (typep object 'sl:dict)
                             with cursor = (trie-cursor
                                            (if dictionary-p (dict-root object)
                                                (set-root object)))
                             do (multiple-value-bind (present-p item value next)
                                    (trie-next cursor)
                                  (unless present-p (return nil))
                                  (when (or (visit item child-depth)
                                            (and dictionary-p
                                                 (visit value child-depth)))
                                    (return t))
                                  (setf cursor next))))))))))
      (visit key +hash-depth+))))

(defclass ordered-collector (collector)
  ((result-class :initarg :result-class :reader ordered-collector-result-class)
   (entries :initform (make-array 16 :adjustable t :fill-pointer 0)
            :reader ordered-collector-entries))
  (:documentation
   "Buffer successful entries without key callbacks. Finalization deduplicates
into local first-position staging and builds an immutable AVL tree in linear
node work. Failure leaves every buffered success available for retry."))

(defun make-ordered-collector (class options)
  (validate-collector-options options nil)
  (make-instance 'ordered-collector :result-class class))

(defmethod sl:make-collector-for
    ((target (eql (find-class 'sl:ordered-dict))) &rest options &key)
  (make-ordered-collector target options))

(defmethod sl:make-collector-for ((target sl:ordered-dict) &rest options &key)
  ;; The source supplies its class, never its initial contents.
  (make-ordered-collector (class-of target) options))

(defmethod sl:collector-accumulate ((collector ordered-collector) element)
  ;; Reject before touching state. Key work belongs to retryable finalization,
  ;; not accumulation: even keys whose HASH-CODE exits are buffered successes.
  (unless (typep element 'sl:map-entry)
    (raise-type-error element 'sl:map-entry))
  (let ((entries (ordered-collector-entries collector)))
    (vector-push-extend element entries (max 1 (array-total-size entries))))
  collector)

(defmethod sl:collector-result ((collector ordered-collector))
  (cache-collector-result
   collector
   (lambda ()
     (ordered-from-entries (ordered-collector-result-class collector)
                           (ordered-collector-entries collector)))))

(defmethod sl:dict-collect ((source sl:ordered-dict) entries &key (test 'eql))
  ;; Fixed EQUALS matching ignores even incompatible TEST designators. Unlike
  ;; ordinary Collector options, this keyword is part of the batch protocol.
  (declare (ignore test))
  (ordered-from-entries (class-of source) entries))
