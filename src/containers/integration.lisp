;;;; Late container traversal through the ordinary public seq protocol.
(in-package #:sophie-lisp.internal)

(defun container-trie-view (cursor entries-p)
  "Retain a persistent cursor, allocating entries only as nodes are forced."
  (when cursor
    (make-lazy-node
     (lambda ()
       (multiple-value-bind (present-p key value next) (trie-next cursor)
         (when present-p
           (sl:lazy-cons (if entries-p (sl:map-entry key value) key)
                         (container-trie-view next entries-p))))))))

;;; OPEN-VIEW uses the public FIRST/REST protocol for these classes. Both
;;; primitives begin at the same deterministic persistent cursor, so its default
;;; protocol wrapper is coherent without a private dispatch hook or snapshot.
;;; Subsequent positions retain the cursor rather than restarting at the root.
;;; Keeping that public boundary also honors subclass methods normally.
(defmethod sl:seqablep ((source sl:dict)) t)
(defmethod sl:seqablep ((source sl:hash-set)) t)
(defmethod sl:seqablep ((source sl:plist-dict-view)) t)

(defmethod sl:seq-length ((source sl:dict))
  (sl:dict-size source))

(defmethod sl:seq-length ((source sl:hash-set))
  (set-count source))

(defmethod sl:seq-length ((source sl:plist-dict-view))
  (sl:dict-size source))

(defmethod sl:seq-emptyp ((source sl:dict))
  (zerop (sl:seq-length source)))

(defmethod sl:seq-emptyp ((source sl:hash-set))
  (zerop (sl:seq-length source)))

(defmethod sl:seq-emptyp ((source sl:plist-dict-view))
  (zerop (sl:seq-length source)))

(defmethod sl:seq-first ((source sl:dict))
  (multiple-value-bind (present-p key value)
      (trie-next (trie-cursor (dict-root source)))
    (when present-p (sl:map-entry key value))))

(defmethod sl:seq-rest ((source sl:dict))
  (multiple-value-bind (present-p key value next)
      (trie-next (trie-cursor (dict-root source)))
    (declare (ignore present-p key value))
    (container-trie-view next t)))

(defmethod sl:seq-first ((source sl:hash-set))
  (nth-value 1 (trie-next (trie-cursor (set-root source)))))

(defmethod sl:seq-rest ((source sl:hash-set))
  (multiple-value-bind (present-p key value next)
      (trie-next (trie-cursor (set-root source)))
    (declare (ignore present-p key value))
    (container-trie-view next nil)))

;;; The provider already validated and canonicalized first-EQ associations.
;;; Reuse that metadata: neither copy the backing plist nor deduplicate again.
(defmethod sl:seq-first ((source sl:plist-dict-view))
  (let ((entries (plist-view-canonical source)))
    (unless (zerop (length entries)) (aref entries 0))))

(defmethod sl:seq-rest ((source sl:plist-dict-view))
  (let ((entries (plist-view-canonical source)))
    (vector-view entries 1 (length entries))))

;;; The inherited T reader validates the index before opening one coherent
;;; view, preserving default suppliedness and both return values. The inherited
;;; no-writer method signals SIMPLE-ERROR regardless of index or default, without
;;; traversal or mutation; more-specific user subclass writers remain possible.

(defmethod sl:dict-collect ((source t) entries &key (test 'eql))
  (declare (ignore entries test))
  (raise-type-error source '(satisfies dict-collector-p)))

(defmethod sl:dict-collect ((source sl:dict) entries &key (test 'eql))
  (declare (ignore source test))
  (let ((result (sl:dict)))
    (do-view-elements (entry entries :result result)
      (unless (typep entry 'sl:map-entry)
        (raise-type-error entry 'sl:map-entry))
      (setf result (sl:dict-set result (sl:entry-key entry)
                                 (sl:entry-value entry))))))

(defmethod sl:dict-collect ((source hash-table) entries &key (test 'eql))
  (declare (ignore source))
  ;; Validate the requested test before opening or forcing the entry source.
  (let ((result (make-hash-table :test (standard-hash-test test))))
    (do-view-elements (entry entries :result result)
      (unless (typep entry 'sl:map-entry)
        (raise-type-error entry 'sl:map-entry))
      (table-last-put result (sl:entry-key entry) (sl:entry-value entry)))))

(defun dict-collector-p (source)
  "Classify participation without invoking any collector or traversing SOURCE."
  (and (sl:dictp source)
       (nondefault-primary-p #'sl:dict-collect (list source nil) 0)))

(defun empty-like-dict (parent)
  "Reconstruct an empty parent type when eligible, otherwise an empty DICT."
  (if (dict-collector-p parent)
      (sl:dict-collect parent nil :test (sl:dict-test parent))
      (sl:dict)))

(defun select-dict-result (sources)
  "Return a prototype and its test, without traversing any source contents.
Non-identical dynamic classes or EQ-distinct test designators select DICT."
  (dolist (source sources)
    (unless (sl:dictp source)
      (raise-type-error source '(satisfies sl:dictp))))
  (when sources
    (let* ((prototype (car sources))
           (class (class-of prototype))
           (test (sl:dict-test prototype)))
      (when (and (dict-collector-p prototype)
                 (every (lambda (source)
                          (and (eq class (class-of source))
                               (eq test (sl:dict-test source))
                               (dict-collector-p source)))
                        (cdr sources)))
        (return-from select-dict-result (values prototype test)))))
  (values (sl:dict) #'sl:equals))

(defclass dict-collector (collector)
  ((entries :initform (make-array 16 :adjustable t :fill-pointer 0)
            :reader dict-collector-entries)))

(defclass set-collector (collector)
  ((set :initform (sl:hash-set) :accessor set-collector-set)))

(defmethod sl:make-collector-for ((target (eql (find-class 'sl:dict)))
                                  &rest options &key)
  (validate-collector-options options nil)
  (make-instance 'dict-collector))

(defmethod sl:make-collector-for ((target sl:dict) &rest options &key)
  (validate-collector-options options nil)
  (make-instance 'dict-collector))

(defmethod sl:make-collector-for ((target (eql (find-class 'sl:hash-set)))
                                  &rest options &key)
  (validate-collector-options options nil)
  (make-instance 'set-collector))

(defmethod sl:make-collector-for ((target sl:hash-set) &rest options &key)
  (validate-collector-options options nil)
  (make-instance 'set-collector))

(defmethod sl:collector-accumulate ((collector dict-collector) element)
  ;; Reject before touching the buffer: prior successes survive any refusal.
  (unless (typep element 'sl:map-entry)
    (raise-type-error element 'sl:map-entry))
  (let ((entries (dict-collector-entries collector)))
    (vector-push-extend element entries (max 1 (array-total-size entries))))
  collector)

(defmethod sl:collector-result ((collector dict-collector))
  (cache-collector-result
   collector
   (lambda ()
     ;; The active vector length includes all successes, including duplicates.
     ;; Batch reconstruction alone applies last-key-and-value-wins. Neither a
     ;; failed batch nor a nonlocal exit consumes the buffer or caches a result.
     (sl:dict-collect (sl:dict) (dict-collector-entries collector)
                      :test #'sl:equals))))

(defmethod sl:collector-accumulate ((collector set-collector) element)
  ;; Persistent insertion commits only after success. Duplicates are successful
  ;; no-ops, and the storage marker stays entirely inside the set implementation.
  (setf (set-collector-set collector)
        (set-insert (set-collector-set collector) element))
  collector)

(defmethod sl:collector-result ((collector set-collector))
  (cache-collector-result collector
                          (lambda () (set-collector-set collector))))

(defun container-trie-items (root count associations-p)
  "Capture resident elements or associations without key lookup or hashing."
  (let ((items (make-array count))
        (cursor (trie-cursor root)))
    (dotimes (index count items)
      (multiple-value-bind (present-p key value next) (trie-next cursor)
        (declare (ignore present-p))
        (setf (aref items index)
              (if associations-p
                  (sl:map-entry key value)
                  key)
              cursor next)))))

(defun container-bijection-p (left right test)
  "Match complete values one-to-one, retaining canonical multiplicity."
  ;; TEST is an equivalence relation: either EQUALS or its product on key
  ;; and value. Thus all candidates for an item belong to the same equivalence
  ;; class; consuming any COMPLETE match cannot steal a different class's
  ;; candidate. Greedy key-only matching would be wrong, but full-pair matching
  ;; needs neither permutation search nor augmenting paths. At most n^2 TEST
  ;; calls, O(n) scratch, and no recursion in the matching algorithm itself.
  (let ((count (length left)))
    (and (= count (length right))
         (let ((used (make-array count :element-type 'bit :initial-element 0)))
           (loop for item across left
                 always (loop for index below count
                              when (and (zerop (aref used index))
                                        (funcall test item (aref right index)))
                              do (setf (aref used index) 1)
                              (return t)
                              finally (return nil)))))))

(defun container-association-equal-p (left right)
  (and (sl:equals (sl:entry-key left) (sl:entry-key right))
       (sl:equals (sl:entry-value left) (sl:entry-value right))))

;;; Post-B4 worst-host crossover measurement: SBCL/CCL cross at 512-1024
;;; entries, ECL at 128-256; probing wins 1.54-2.59x at 1024.
;;; Retain the bijection path through 768 for margin on SBCL.
;;; This is only a performance heuristic: both paths preserve equality;
;;; their EQUALS call counts may differ, as permitted by the protocol.
(defconstant +equality-probe-threshold+ 768)

(defmethod sl:equals ((left-object sl:dict) (right-object sl:dict))
  (and (= (dict-count left-object) (dict-count right-object))
       (if (<= (dict-count left-object) +equality-probe-threshold+)
           (container-bijection-p
            (container-trie-items (dict-root left-object) (dict-count left-object) t)
            (container-trie-items (dict-root right-object) (dict-count right-object) t)
            #'container-association-equal-p)
           ;; Equal counts and unique resident keys make each successful probe
           ;; injective: distinct left keys cannot claim the same right key.
           ;; TRIE-PUT hashed every resident key at insertion; probing may
           ;; rehash it without newly signaling or forcing a lazy key.
           (let ((cursor (trie-cursor (dict-root left-object)))
                 (right-root (dict-root right-object)))
             (loop
               (multiple-value-bind (present-p key value next) (trie-next cursor)
                 (unless present-p (return t))
                 (multiple-value-bind (right-value found-p)
                     (trie-ref right-root key (sl:hash-code key))
                   (unless (and found-p (sl:equals value right-value))
                     (return nil)))
                 (setf cursor next)))))))

(defmethod sl:equals ((left-object sl:hash-set) (right-object sl:hash-set))
  (and (= (set-count left-object) (set-count right-object))
       (if (<= (set-count left-object) +equality-probe-threshold+)
           (container-bijection-p
            (container-trie-items (set-root left-object) (set-count left-object) nil)
            (container-trie-items (set-root right-object) (set-count right-object) nil)
            #'sl:equals)
           ;; With unique elements and equal counts, successful right-side probes
           ;; establish a bijection; TRIE-REF performs the EQUALS comparison.
           ;; The resident-key rehash invariant is explained in the DICT method.
           (let ((cursor (trie-cursor (set-root left-object)))
                 (right-root (set-root right-object)))
             (loop
               (multiple-value-bind (present-p element value next) (trie-next cursor)
                 (declare (ignore value))
                 (unless present-p (return t))
                 (unless (nth-value 1 (trie-ref right-root element (sl:hash-code element)))
                   (return nil))
                 (setf cursor next)))))))

(defmethod sl:equals ((left-object sl:plist-dict-view) (right-object sl:plist-dict-view))
  (and (= (plist-view-count left-object) (plist-view-count right-object))
       (container-bijection-p (plist-view-canonical left-object)
                              (plist-view-canonical right-object)
                              #'container-association-equal-p)))

;;; No cross-representation methods: the existing identity fallback rejects
;;; distinct representations. Public dispatch preserves subclass extensions.
(defmethod sl:compare ((left-object sl:dict) (right-object sl:dict))
  (if (sl:equals left-object right-object) :equal :unequal))

(defmethod sl:compare ((left-object sl:hash-set) (right-object sl:hash-set))
  (if (sl:equals left-object right-object) :equal :unequal))

(defmethod sl:compare ((left-object sl:plist-dict-view) (right-object sl:plist-dict-view))
  (if (sl:equals left-object right-object) :equal :unequal))

(defun container-association-hash (key value depth)
  ;; An association is an ordered pair, but its temporary MAP-ENTRY wrapper
  ;; is not an extra structural edge of the container being hashed.
  (hash-combine
   (hash-combine (mix64 25) (hash-component key depth))
   (hash-component value depth)))

(defun container-trie-hash (root count tag associations-p)
  ;; Use the provider's dynamically retained remaining depth, never reset it
  ;; at a late container boundary. HASH-COMPONENT truncates BEFORE dispatch
  ;; at zero; otherwise it calls the public HASH-CODE, including inherited
  ;; primaries, EQL specializers and auxiliary methods. All exits unwind it.
  (let ((depth (1- *hash-depth*))
        (cursor (trie-cursor root))
        (hashes nil))
    (loop
     (multiple-value-bind (present-p key value next) (trie-next cursor)
       (unless present-p (return))
       (push (if associations-p
                 (container-association-hash key value depth)
                 (hash-component key depth))
             hashes)
       (setf cursor next)))
    ;; Every unordered item participates: no traversal-prefix sampling.
    (hash-unordered tag count hashes)))

(defmethod sl:hash-code ((object sl:dict))
  (call-with-structural-hash
   object
   (lambda ()
     (container-trie-hash (dict-root object) (dict-count object) 26 t))))

(defmethod sl:hash-code ((object sl:hash-set))
  (call-with-structural-hash
   object
   (lambda ()
     (container-trie-hash (set-root object) (set-count object) 27 nil))))

(defmethod sl:hash-code ((object sl:plist-dict-view))
  (call-with-structural-hash
   object
   (lambda ()
     (let ((depth (1- *hash-depth*)))
       (hash-unordered
        28 (plist-view-count object)
        (loop for entry across (plist-view-canonical object)
              collect (container-association-hash
                       (sl:entry-key entry)
                       (sl:entry-value entry)
                       depth)))))))

(defmethod sl:ref ((object t) key &optional (default nil supplied-p))
  (cond ((sl:dictp object)
         (if supplied-p
             (sl:dict-ref object key default)
             (sl:dict-ref object key)))
        ((sl:seqablep object)
         (if supplied-p
             (sl:seq-ref object key default)
             (sl:seq-ref object key)))
        (t (raise-type-error object '(or (satisfies sl:dictp)
                                      (satisfies sl:seqablep))))))

;;; Keep the standardized direct methods explicit. Protocol calls preserve
;;; suppliedness, all returned values, and conditions without reinterpreting keys.
(defmethod sl:ref ((object list) key &optional (default nil supplied-p))
  (if supplied-p
      (sl:seq-ref object key default)
      (sl:seq-ref object key)))

(defmethod sl:ref ((object vector) key &optional (default nil supplied-p))
  (if supplied-p
      (sl:seq-ref object key default)
      (sl:seq-ref object key)))

(defmethod sl:ref ((object string) key &optional (default nil supplied-p))
  (if supplied-p
      (sl:seq-ref object key default)
      (sl:seq-ref object key)))

(defmethod sl:ref ((object hash-table) key &optional (default nil supplied-p))
  (if supplied-p
      (sl:dict-ref object key default)
      (sl:dict-ref object key)))

(defmethod sl:ref ((object sl:lazy-seq) key &optional (default nil supplied-p))
  (if supplied-p
      (sl:seq-ref object key default)
      (sl:seq-ref object key)))


;;; Ordinary SETF function calls supply standard place evaluation order; no
;;; expander is needed. A default has already been evaluated when ignored here.
(defmethod (setf sl:ref) (new-value (object t) key &optional default)
  (declare (ignore default))
  (cond ((sl:dictp object) (setf (sl:dict-ref object key) new-value))
        ((sl:seqablep object) (setf (sl:seq-ref object key) new-value))
        (t (raise-type-error object '(or (satisfies sl:dictp)
                                      (satisfies sl:seqablep)))))
  (values new-value))

(defmethod (setf sl:ref) (new-value (object list) key &optional default)
  (declare (ignore default))
  (setf (sl:seq-ref object key) new-value)
  (values new-value))

(defmethod (setf sl:ref) (new-value (object vector) key &optional default)
  (declare (ignore default))
  (setf (sl:seq-ref object key) new-value)
  (values new-value))

(defmethod (setf sl:ref) (new-value (object string) key &optional default)
  (declare (ignore default))
  (setf (sl:seq-ref object key) new-value)
  (values new-value))

(defmethod (setf sl:ref) (new-value (object hash-table) key &optional default)
  (declare (ignore default))
  (setf (sl:dict-ref object key) new-value)
  (values new-value))

(defmethod (setf sl:ref) (new-value (object sl:lazy-seq) key &optional default)
  (declare (ignore default))
  (setf (sl:seq-ref object key) new-value)
  (values new-value))
