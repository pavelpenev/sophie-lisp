;;;; Eager binary/folded merging and the shared transform entry builder.
(in-package #:sophie-lisp.internal)

(defstruct (entry-builder-state
             (:constructor make-entry-builder-state))
  prototype test collision
  (entries (make-array 0 :adjustable t :fill-pointer 0))
  (index-kind nil) (index nil)
  (finished-p nil)
  (result nil))

(defun entry-builder (prototype test collision)
  "Prepare reconstruction before traversal; never invoke the batch collector here."
  (unless (member collision '(:last-wins :error) :test #'eq)
    (raise-program-error "Unknown dictionary collision policy: ~S" collision))
  (usable-function test)
  (let ((builder (make-entry-builder-state
                  :prototype prototype :test test :collision collision)))
    ;; Last-wins needs no speculative matching: DICT-COLLECT performs it once
    ;; over the ordered buffer, retaining the last key AND value objects.
    (when (eq collision :error)
      (multiple-value-bind (kind standard) (index-kind-for-test test)
        (case kind
          (:table
           (setf (entry-builder-state-index-kind builder) :table
                 (entry-builder-state-index builder)
                 (make-hash-table :test standard)))
          (:hash (setf (entry-builder-state-index-kind builder) :trie))
          (:linear
           ;; Arbitrary user tests have no corresponding hash protocol.
           (setf (entry-builder-state-index-kind builder) :linear)))))
    builder))

(defun entry-builder-add (builder key value)
  "Check a strict collision before accepting an entry; do not force later input."
  (when (entry-builder-state-finished-p builder)
    (raise-program-error "Cannot add to a finished dictionary entry builder."))
  (when (eq (entry-builder-state-collision builder) :error)
    (flet ((collision ()
             (raise-program-error "Duplicate key in dictionary reconstruction.")))
      (ecase (entry-builder-state-index-kind builder)
        (:table
         (let ((table (entry-builder-state-index builder)))
           (when (nth-value 1 (gethash key table)) (collision))
           (setf (gethash key table) t)))
        (:trie
         (let ((hash (sl:hash-code key))
               (root (entry-builder-state-index builder)))
           (when (nth-value 1 (trie-ref root key hash)) (collision))
           (setf (entry-builder-state-index builder)
                 (trie-put root key t hash nil))))
        (:linear
         (when (member key (entry-builder-state-index builder)
                       :test (entry-builder-state-test builder))
           (collision))
         (push key (entry-builder-state-index builder))))))
  (vector-push-extend (sl:map-entry key value)
                      (entry-builder-state-entries builder))
  builder)

(defun entry-builder-finish (builder)
  "Make one batch result and cache successful finalization, without callback replay."
  ;; Keep this success-only finalization protocol aligned with CACHE-COLLECTOR-RESULT.
  (unless (entry-builder-state-finished-p builder)
    (setf (entry-builder-state-result builder)
          (sl:dict-collect (entry-builder-state-prototype builder)
                           (entry-builder-state-entries builder)
                           :test (entry-builder-state-test builder))
          (entry-builder-state-finished-p builder) t))
  (entry-builder-state-result builder))

(defmethod sl:dict-merge ((dictionary1 t) dictionary2 &key (collision :last-wins))
  (multiple-value-bind (prototype test) (select-dict-result (list dictionary1 dictionary2))
    (let ((builder (entry-builder prototype test collision)))
      (dolist (source (list dictionary1 dictionary2))
        (let ((view (open-view source)))
          (loop
           (multiple-value-bind (empty-p entry rest) (view-step view)
             (when empty-p (return))
             (unless (typep entry 'sl:map-entry)
               (raise-type-error entry 'sl:map-entry))
             (entry-builder-add builder (sl:entry-key entry)
                                (sl:entry-value entry))
             (setf view rest)))))
      (entry-builder-finish builder))))

(defmethod sl:dict-merge* ((dictionary1 t) dictionary2 &rest more-dicts)
  ;; Validate even late operands before the first fold invokes user traversal.
  (dolist (source (list* dictionary1 dictionary2 more-dicts))
    (unless (sl:dictp source)
      (raise-type-error source '(satisfies sl:dictp))))
  (let ((result (sl:dict-merge dictionary1 dictionary2 :collision :last-wins)))
    (dolist (source more-dicts result)
      (setf result (sl:dict-merge result source :collision :last-wins)))))

(defun dict-merge-with-add (entries key value test combine)
  "Add KEY/VALUE, combining with the accumulated value on a result-test match."
  (loop for index below (length entries)
        for entry = (aref entries index)
        when (funcall test key (sl:entry-key entry))
        do (setf (aref entries index)
                 (sl:map-entry key
                               (funcall combine
                                        (sl:entry-value entry)
                                        value)))
        (return entries)
        finally (vector-push-extend (sl:map-entry key value) entries))
  entries)

;;; Post-B4 worst-host crossover measurement (SBCL, CCL, ECL): indexed
;;; merge ties or wins at 64 total entries and wins at least 1.5x at 128.
(defconstant +dict-merge-with-index-threshold+ 64)

(defun dict-merge-with-linear (prototype test combine dictionary1 dictionary2)
  (let ((entries (make-array 0 :adjustable t :fill-pointer 0)))
    (dolist (source (list dictionary1 dictionary2))
      (let ((view (open-view source)))
        (loop
         (multiple-value-bind (empty-p entry rest) (view-step view)
           (when empty-p (return))
           (unless (typep entry 'sl:map-entry)
             (raise-type-error entry 'sl:map-entry))
           (dict-merge-with-add entries (sl:entry-key entry)
                                (sl:entry-value entry) test combine)
           (setf view rest)))))
    (sl:dict-collect prototype entries :test test)))

(defun dict-merge-with-indexed (prototype test combine dictionary1 dictionary2)
  (multiple-value-bind (kind standard) (index-kind-for-test test)
    (when (eq kind :linear)
      (return-from dict-merge-with-indexed
        (dict-merge-with-linear prototype test combine dictionary1 dictionary2)))
    (let* ((entries (make-array 0 :adjustable t :fill-pointer 0))
           (index (case kind
                    (:table (make-hash-table :test standard))
                    (:hash (make-hash-table :test 'eql))))
           (overflow nil)
           (overflow-tail nil))
      (labels ((matching-position (key positions)
                 (loop for position across positions
                       when (funcall test key (sl:entry-key (aref entries position)))
                         return position))
               (overflow-position (key)
                 (loop for position in overflow
                       when (funcall test key (sl:entry-key (aref entries position)))
                         return position))
               (add-hashed (key value)
                 ;; The earliest match wins, whether in overflow or the bucket.
                 (multiple-value-bind (hash hashable-p) (safe-key-hash key)
                   (let* ((bucket (and hashable-p (gethash hash index)))
                          (candidate (if hashable-p
                                         (and bucket (matching-position key bucket))
                                         ;; An unhashable incoming key may still
                                         ;; equal a previously hashable key.
                                         (loop for position below (length entries)
                                               when (funcall test key
                                                             (sl:entry-key
                                                              (aref entries position)))
                                                 return position)))
                          (position (if hashable-p
                                        (let ((overflow-match (overflow-position key)))
                                          (if (and overflow-match candidate)
                                              (min overflow-match candidate)
                                              (or overflow-match candidate)))
                                        candidate)))
                     (if position
                         (let ((old (aref entries position)))
                           (setf (aref entries position)
                                 (sl:map-entry key
                                               (funcall combine (sl:entry-value old)
                                                        value))))
                         (let ((new-position (length entries)))
                           (vector-push-extend (sl:map-entry key value) entries)
                           (if hashable-p
                               (let ((positions (or bucket
                                                    (setf (gethash hash index)
                                                          (make-array 0 :adjustable t
                                                                      :fill-pointer 0)))))
                                 (vector-push-extend new-position positions))
                               (let ((cell (list new-position)))
                                 (if overflow-tail
                                     (setf (cdr overflow-tail) cell)
                                     (setf overflow cell))
                                 (setf overflow-tail cell))))))))
               (add (key value)
                 (case kind
                   (:table
                    (multiple-value-bind (position found-p) (gethash key index)
                      (if found-p
                          (let ((old (aref entries position)))
                            (setf (aref entries position)
                                  (sl:map-entry key
                                                (funcall combine (sl:entry-value old)
                                                         value)))
                            ;; Refresh the resident key: the table must not retain OLD.
                            (remhash (sl:entry-key old) index)
                            (setf (gethash key index) position))
                          (let ((position (length entries)))
                            (vector-push-extend (sl:map-entry key value) entries)
                            (setf (gethash key index) position)))))
                   (:hash (add-hashed key value)))))
        (dolist (source (list dictionary1 dictionary2))
          (let ((view (open-view source)))
            (loop
             (multiple-value-bind (empty-p entry rest) (view-step view)
               (when empty-p (return))
               (unless (typep entry 'sl:map-entry)
                 (raise-type-error entry 'sl:map-entry))
               (add (sl:entry-key entry) (sl:entry-value entry))
               (setf view rest)))))
        (sl:dict-collect prototype entries :test test)))))

(defmethod sl:dict-merge-with ((combine t) dictionary1 dictionary2)
  (usable-function combine)
  (multiple-value-bind (prototype test) (select-dict-result (list dictionary1 dictionary2))
    (when (<= (+ (sl:dict-size dictionary1) (sl:dict-size dictionary2))
              +dict-merge-with-index-threshold+)
      (return-from sl:dict-merge-with
        (dict-merge-with-linear prototype test combine dictionary1 dictionary2)))
    (dict-merge-with-indexed prototype test combine dictionary1 dictionary2)))

(defun force-path (keys)
  "Eagerly validate and copy a finite, nonempty path into a simple vector."
  (let ((view (open-view keys))
        (path nil))
    (loop
      (multiple-value-bind (empty-p key rest) (view-step view)
        (if empty-p
            (return
              (if path
                  (coerce (nreverse path) 'simple-vector)
                  (raise-program-error "A dictionary path must be nonempty.")))
            (progn
              (push key path)
              (setf view rest)))))))

(defun read-path (dictionary path default)
  "Read a nonempty simple vector from FORCE-PATH; return exactly two values."
  (unless (sl:dictp dictionary)
    (raise-type-error dictionary '(satisfies sl:dictp)))
  (let ((current dictionary)
        (last-index (1- (length path))))
    (loop for key across path
          for index from 0
          do (multiple-value-bind (value present-p)
                 (sl:dict-ref current key)
               (unless present-p
                 (return-from read-path (values default nil)))
               (if (= index last-index)
                   (return-from read-path (values value t))
                   (progn
                     (unless (sl:dictp value)
                       (raise-type-error value '(satisfies sl:dictp)))
                     (setf current value)))))))

(defmethod sl:dict-ref-in ((dictionary t) keys &optional default)
  "Read KEYS through nested dictionaries, returning (value, T) when present and
(DEFAULT, NIL) when any segment is absent. KEYS must be a finite, nonempty seqable;
an empty path signals PROGRAM-ERROR, a non-seqable path or non-dict intermediate
signals TYPE-ERROR, and the path is fully validated before traversal."
  ;; Finish path forcing before even checking root dictness or doing lookup.
  (read-path dictionary (force-path keys) default))

(defun check-path-set-capability (dictionary key)
  "Reject detectable missing or standardized declining functional setters."
  (unless (sl:dictp dictionary)
    (raise-type-error dictionary '(satisfies sl:dictp)))
  ;; Inspect only: never call a setter with a speculative value. Arbitrary
  ;; specialized runtime refusals propagate during the actual rebuild.
  (let* ((arguments (list dictionary key nil))
         (primary (find-if (lambda (method)
                             (null (method-qualifiers method)))
                           (compute-applicable-methods #'sl:dict-set arguments)))
         (view-class (find-class 'sl:plist-dict-view nil)))
    (when (or (not (nondefault-primary-p #'sl:dict-set arguments 0))
              ;; Respect a subclass override, but recognize the standardized
              ;; read-only primary even when inherited by a subclass.
              (and view-class
                   (eq primary
                       (find-method #'sl:dict-set nil
                                    (list view-class (find-class 't)
                                          (find-class 't))
                                    nil))))
      (raise-program-error "The dictionary does not support DICT-SET."))))

(defun prepare-path (dictionary path)
  "Prepare a nonempty forced vector; return ancestors, leaf parent, leaf key.
ANCESTORS is a nearest-parent-first list of (parent . key) pairs. No input
container is changed, and no functional setter is invoked during preparation."
  (let ((current dictionary)
        (ancestors nil)
        (last-index (1- (length path))))
    (loop for key across path
          for index from 0
          do (check-path-set-capability current key)
             (when (= index last-index)
               (return (values ancestors current key)))
             (multiple-value-bind (child present-p) (sl:dict-ref current key)
               (push (cons current key) ancestors)
               (setf current (if present-p child (empty-like-dict current)))))))

(defun rebuild-path (ancestors leaf-parent leaf-key value)
  "Rebuild prepared parents from leaf to root, using ordinary DICT-SET only."
  (let ((result (sl:dict-set leaf-parent leaf-key value)))
    (dolist (ancestor ancestors result)
      (setf result (sl:dict-set (car ancestor) (cdr ancestor) result)))))

(defmethod sl:dict-set-in ((dictionary t) keys value)
  (multiple-value-bind (ancestors leaf-parent leaf-key)
      (prepare-path dictionary (force-path keys))
    ;; Suppress any extra values returned by a user primitive.
    (let ((result (rebuild-path ancestors leaf-parent leaf-key value)))
      result)))

(defmethod sl:dict-update-in ((dictionary t) keys function &key (default nil))
  (let* ((path (force-path keys))
         (function (usable-function function)))
    (multiple-value-bind (ancestors leaf-parent leaf-key)
        (prepare-path dictionary path)
      (multiple-value-bind (old-value present-p) (sl:dict-ref leaf-parent leaf-key)
        ;; Invoke exactly once, after preparation, using only the primary value
        ;; (including NIL for a zero-value return). Never intercept an escape.
        (let* ((value (funcall function (if present-p old-value default)))
               (result (rebuild-path ancestors leaf-parent leaf-key value)))
          result)))))

(defmethod sl:dict-transform ((function t) dictionary &key (collision :last-wins))
  (usable-function function)
  (multiple-value-bind (prototype test) (select-dict-result (list dictionary))
    ;; Select the result test and validate policy before opening the source.
    (let ((builder (entry-builder prototype test collision))
          (view (open-view dictionary)))
      (loop
        (multiple-value-bind (empty-p entry rest) (view-step view)
          (when empty-p (return))
          (unless (typep entry 'sl:map-entry)
            (raise-type-error entry 'sl:map-entry))
          ;; Retain a symbol designator, resolving it anew at each invocation.
          ;; MULTIPLE-VALUE-BIND alone would silently pad or discard values.
          (let ((results (multiple-value-list
                          (funcall function (sl:entry-key entry)
                                   (sl:entry-value entry)))))
            (unless (= 2 (length results))
              (raise-program-error "DICT-TRANSFORM callback must return exactly two values."))
            (entry-builder-add builder (first results) (second results)))
          ;; Strict collision checks finish before the next source position.
          (setf view rest)))
      (entry-builder-finish builder))))

(defmethod sl:dict-values-map ((function t) dictionary)
  (usable-function function)
  (multiple-value-bind (prototype test) (select-dict-result (list dictionary))
    (let ((builder (entry-builder prototype test :last-wins))
          (view (open-view dictionary)))
      (loop
       (multiple-value-bind (empty-p entry rest) (view-step view)
         (when empty-p (return))
         (unless (typep entry 'sl:map-entry)
           (raise-type-error entry 'sl:map-entry))
         (entry-builder-add builder
                            (sl:entry-key entry)
                            (funcall function (sl:entry-value entry)))
         (setf view rest)))
      (entry-builder-finish builder))))

(defmethod sl:dict-keys-map ((function t) dictionary &key (collision :last-wins))
  (usable-function function)
  (multiple-value-bind (prototype test) (select-dict-result (list dictionary))
    ;; Validate COLLISION and prepare collision tracking before opening the source.
    (let ((builder (entry-builder prototype test collision))
          (view (open-view dictionary)))
      (loop
       (multiple-value-bind (empty-p entry rest) (view-step view)
         (when empty-p (return))
         (unless (typep entry 'sl:map-entry)
           (raise-type-error entry 'sl:map-entry))
         (entry-builder-add builder
                            (funcall function (sl:entry-key entry))
                            (sl:entry-value entry))
         (setf view rest)))
      (entry-builder-finish builder))))

(defun dict-key-list (keys)
  "Consume KEYS once and return its elements in encounter order."
  (let ((view (open-view keys))
        (result nil))
    (loop
     (multiple-value-bind (empty-p key rest) (view-step view)
       (when empty-p (return (nreverse result)))
       (push key result)
       (setf view rest)))))

(defun dict-key-matches-p (key requested test)
  (some (lambda (candidate) (funcall test candidate key)) requested))

;;; SBCL 2.6.1 on cube: N-pair ranged DICT with N/2 requested fixnums,
;;; linear/indexed crossover falls between 50 and 100 requested keys
;;; (50: 68/84 us; 100: 202/172 us). Retain linear matching through 64.
;;; This is a performance heuristic; both paths preserve membership, though
;;; user-supplied test invocation counts may differ.
(defconstant +dict-requested-key-index-threshold+ 64)

(defun dict-select-remove-keys (dictionary keys select-p)
  (require-seqable keys)
  (unless (sl:dictp dictionary)
    (raise-type-error dictionary '(satisfies sl:dictp)))
  ;; Materialize the requested keys before opening the source dictionary.
  (multiple-value-bind (prototype result-test) (select-dict-result (list dictionary))
    (let* ((requested (dict-key-list keys))
           (source-test (sl:dict-test dictionary)))
      (multiple-value-bind (kind standard)
          (if (<= (length requested) +dict-requested-key-index-threshold+)
              (values :linear nil)
              (index-kind-for-test source-test))
        (let* ((index (case kind
                        (:table (make-hash-table :test standard))
                        (:hash (make-hash-table :test 'eql))))
               (overflow nil)
               (entries nil)
               (view nil))
          ;; EQUALS-matching hashable keys share a hash by the chapter 7
          ;; hash/equals obligation. Unhashable requested keys live in the
          ;; overflow list, checked at every hashable-key lookup in request order.
          (loop for candidate in requested
                for position from 0
                do (case kind
                     (:table (setf (gethash candidate index) t))
                     (:hash
                      (multiple-value-bind (hash hashable-p)
                          (safe-key-hash candidate)
                        (if hashable-p
                            (let ((bucket (or (gethash hash index)
                                              (setf (gethash hash index)
                                                    (make-array 0 :adjustable t
                                                                :fill-pointer 0)))))
                              (vector-push-extend (cons position candidate) bucket))
                            (push (cons position candidate) overflow))))))
          (setf overflow (nreverse overflow))
          (setf view (open-view dictionary))
          (loop
           (multiple-value-bind (empty-p entry rest) (view-step view)
             (when empty-p (return))
             (unless (typep entry 'sl:map-entry)
               (raise-type-error entry 'sl:map-entry))
             (let* ((key (sl:entry-key entry))
                    (matches
                      (case kind
                        (:linear (dict-key-matches-p key requested source-test))
                        (:table (nth-value 1 (gethash key index)))
                        (:hash
                         (multiple-value-bind (hash hashable-p)
                             (safe-key-hash key)
                           (if (not hashable-p)
                               (dict-key-matches-p key requested source-test)
                               (let* ((bucket (gethash hash index))
                                      (match (and bucket
                                                  (loop for item across bucket
                                                        when (funcall source-test (cdr item) key)
                                                          return item))))
                                 (or (loop for item in overflow
                                           while (or (null match)
                                                     (< (car item) (car match)))
                                           when (funcall source-test (cdr item) key)
                                             return item)
                                     match))))))))
               (when (if select-p matches (not matches))
                 (push entry entries)))
             (setf view rest)))
          (sl:dict-collect prototype (nreverse entries) :test result-test))))))

(defmethod sl:dict-select-keys ((dictionary t) keys)
  (dict-select-remove-keys dictionary keys t))

(defmethod sl:dict-remove-keys ((dictionary t) keys)
  (dict-select-remove-keys dictionary keys nil))

(defmethod sl:dict-update ((dictionary t) key function &key (default nil))
  "Apply FUNCTION to the value associated with KEY, or the DEFAULT when KEY is
absent, and functionally install its primary result via DICT-SET. A
non-designator FUNCTION signals TYPE-ERROR; a dictionary that does not support
DICT-SET signals PROGRAM-ERROR."
  (let ((function (usable-function function)))
    (check-path-set-capability dictionary key)
    (multiple-value-bind (old-value present-p)
        (sl:dict-ref dictionary key)
      (let ((new-value
              (funcall function
                       (if present-p old-value default))))
        ;; Bind the result so secondary values from a specialized DICT-SET
        ;; method do not become secondary values of DICT-UPDATE.
        (let ((result (sl:dict-set dictionary key new-value)))
          result)))))
