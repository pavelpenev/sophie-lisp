;;;; Chapter 6 result policy. Traversal and reconstruction are separate:
;;;; reconstruction consumes only finite, already-produced elements, never SOURCE.

(in-package #:sophie-lisp.internal)

(defun check-region-bounds (start end end-supplied-p)
  "Validate region index syntax, not source reachability.
Some callers pass END itself as END-SUPPLIED-P to preserve their original
non-NIL-END convention."
  ;; Validate index syntax only, not source reachability, even for empty regions.
  (check-seq-index start)
  (when (and end-supplied-p end)
    (check-seq-index end)
    (when (< end start) (raise-type-error end `(integer ,start *)))))

(defun pristine-vector-collector-protocol-p (source)
  "Whether direct vector construction can omit all applicable Collector methods.
Inspect current method objects, including qualified methods, on every call so
additions, removals and redefinitions immediately invalidate the fast path."
  (let* ((trusted *vector-collector-protocol-methods*)
         (collector-class (find-class 'vector-collector))
         (collector-classes (progn
                              (closer-mop:finalize-inheritance collector-class)
                              (closer-mop:class-precedence-list collector-class))))
    (and (every (lambda (entry)
                  (member (cdr entry)
                          (closer-mop:generic-function-methods (car entry))
                          :test #'eq))
                trusted)
         (every (lambda (method)
                  (find-if (lambda (entry)
                             (and (eq #'sl:make-collector-for (car entry))
                                  (eq method (cdr entry))))
                           trusted))
                (compute-applicable-methods #'sl:make-collector-for (list source)))
         (every (lambda (generic)
                  (every (lambda (method)
                           (or (find-if (lambda (entry)
                                          (and (eq generic (car entry))
                                               (eq method (cdr entry))))
                                        trusted)
                               (not (member (first (closer-mop:method-specializers method))
                                            collector-classes :test #'eq))))
                         (closer-mop:generic-function-methods generic)))
                (list #'sl:collector-accumulate #'sl:collector-result)))))

(defun policy-roster-p (roster operation)
  (member operation
          (ecase roster
            (:vector
             '(sl:seq-filter sl:seq-remove sl:seq-remove-if sl:seq-take
               sl:seq-drop sl:seq-take-while sl:seq-drop-while sl:seq-subseq
               sl:seq-take-nth sl:seq-take-last sl:seq-drop-last
               sl:seq-remove-duplicates sl:seq-dedupe sl:seq-trim-left
               sl:seq-trim-right sl:seq-trim sl:seq-reverse sl:seq-sort
               sl:seq-stable-sort))
            (:dict
             '(sl:seq-filter sl:seq-remove sl:seq-remove-if sl:seq-take
               sl:seq-drop sl:seq-take-while sl:seq-drop-while sl:seq-subseq
               sl:seq-take-nth sl:seq-take-last sl:seq-remove-duplicates
               sl:seq-dedupe sl:seq-trim-left sl:seq-trim-right sl:seq-trim))
            (:dict-ordered
             '(sl:seq-sort sl:seq-stable-sort sl:seq-reverse sl:seq-map
               sl:seq-map-indexed sl:seq-keep sl:seq-mapcat sl:seq-substitute
               sl:seq-substitute-if sl:seq-reductions sl:seq-concatenate
               sl:seq-interleave sl:seq-split sl:seq-split-at
               sl:seq-split-with sl:seq-partition sl:seq-partition-by))
            (:set
             '(sl:seq-filter sl:seq-remove sl:seq-remove-if sl:seq-take
               sl:seq-drop sl:seq-take-while sl:seq-drop-while sl:seq-subseq
               sl:seq-take-nth sl:seq-remove-duplicates sl:seq-dedupe
               sl:seq-trim-left)))
          :test #'eq))

(defun policy-nested-p (operation)
  (member operation '(sl:seq-split sl:seq-split-at sl:seq-split-with
                      sl:seq-partition sl:seq-partition-by) :test #'eq))

(defun policy-deferred-outer-p (operation)
  (member operation '(sl:seq-split sl:seq-partition sl:seq-partition-by)
          :test #'eq))

(defun policy-builtin-dict-p (source)
  (or (hash-table-p source)
      (eq (class-of source) (find-class 'sl:dict))
      (eq (class-of source) (find-class 'sl:ordered-dict))))

(defun policy-ordered-operation-p (operation &key (role :result))
  (and (policy-roster-p :dict-ordered operation)
       (or (not (policy-nested-p operation)) (eq role :piece))))

(defun policy-kind (source operation &key (role :result))
  "Classify without observing SOURCE. STRING is a candidate, subject to widening.
For multi-source operations the owner must first establish common source type.
User split pairs have a lazy outer container and ordinary source-type pieces."
  (cond
    ((or (eq operation 'sl:seq-tree-seq)
         (eq operation 'sl:seq-member)
         (and (not (eq role :piece)) (policy-deferred-outer-p operation))
         (and (eq operation 'sl:seq-drop-last) (not (vectorp source))))
     :lazy)
    ((listp source) :list)
    ((vectorp source)
     (if (and (policy-nested-p operation) (not (eq role :piece)))
         :vector
         (if (stringp source) :string :vector)))
    ((hash-table-p source)
     (cond
       ((policy-ordered-operation-p operation :role role) :ordered-dict)
       ((and (not (policy-nested-p operation))
             (policy-roster-p :dict operation))
        :hash-table)
       (t :lazy)))
    ((eq (class-of source) (find-class 'sl:dict))
     (cond
       ((policy-ordered-operation-p operation :role role) :ordered-dict)
       ((and (not (policy-nested-p operation))
             (policy-roster-p :dict operation))
        :dict)
       (t :lazy)))
    ((eq (class-of source) (find-class 'sl:hash-set))
     (if (and (not (policy-nested-p operation))
              (policy-roster-p :set operation))
         :hash-set :lazy))
    ((eq (class-of source) (find-class 'sl:ordered-dict))
     (cond
       ((policy-ordered-operation-p operation :role role) :ordered-dict)
       ((and (not (policy-nested-p operation))
             (policy-roster-p :dict operation))
        :ordered-dict)
       (t :collector)))
    ((typep source 'sl:lazy-seq) :lazy)
    ((and (not (eq role :piece))
          (member operation '(sl:seq-split-at sl:seq-split-with) :test #'eq))
     :lazy)
    ((nondefault-primary-p #'sl:make-collector-for (list source) 0)
     :collector)
    (t :lazy)))

(defun policy-eager-p (source operation)
  "Decide call-time traversal only for single-source sequence-producing
operations, including MEMBER; this does not decide whether the returned
sequence is lazy. Scalar queries and reductions, and construction or conversion
timing, are outside this helper; their owners retain their own short-circuit and
multi-source timing decisions."
  (cond
    ((member operation '(sl:seq-reverse sl:seq-sort sl:seq-stable-sort
                         sl:seq-take-last sl:seq-trim-right sl:seq-trim)
             :test #'eq)
     t)
    ((or (policy-deferred-outer-p operation)
         (eq operation 'sl:seq-tree-seq))
     nil)
    ((eq operation 'sl:seq-drop-last) (vectorp source))
    ((member operation '(sl:seq-split-at sl:seq-split-with) :test #'eq)
     ;; Section 6.1.1 defers user-Collector splitting reconstruction as well.
     (or (listp source) (vectorp source)))
    ((eq operation 'sl:seq-member) t)
    (t (not (eq :lazy (policy-kind source operation))))))

(defun policy-reconstruct (source operation elements
                           &key (role :result) (padding nil) (options nil))
  "Immediately reconstruct finite proper lists ELEMENTS and actual used PADDING.
Never use this helper to prebuffer an unbounded lazy operation. User Collector
options are forwarded unchanged; all refusals and nonlocal exits propagate."
  (let* ((kind (policy-kind source operation :role role))
         (items (if padding (append elements padding) elements))
         (target source)
         (collector-options options))
    (when (eq kind :lazy)
      (return-from policy-reconstruct (open-view items)))
    (case kind
      (:ordered-dict
       (setf target (find-class 'sl:ordered-dict)))
      (:hash-table
       (setf collector-options (list :test (hash-table-test source))))
      ((:vector :string)
       (let* ((outer-p (and (policy-nested-p operation)
                            (not (eq role :piece))))
              (preserving-p (or (policy-roster-p :vector operation)
                                (and (eq role :piece)
                                     (policy-nested-p operation))))
              (actual (array-element-type source))
              (wide-p
               (or outer-p
                   (and (stringp source) (not (every #'characterp items)))
                   (and (eq operation 'sl:seq-partition) (eq role :piece)
                        (some (lambda (element) (not (typep element actual)))
                              padding)))))
         (cond
           (wide-p
            (setf target (find-class 'vector)
                  collector-options '(:element-type t)))
           ((stringp source)
            ;; Character-changing results need not fit a base-string's type.
            (setf collector-options
                  (list :element-type (if preserving-p actual 'character))))
           (t
            (setf collector-options
                  (list :element-type (if preserving-p actual t))))))))
    (let ((collector (make-collector target collector-options)))
      (dolist (element items) (sl:collector-accumulate collector element))
      (sl:collector-result collector))))

(defun policy-common-p (sources operation)
  (let* ((first (car sources)) (kind (policy-kind first operation)))
    (and (not (eq kind :lazy))
         (every (lambda (source)
                  (and (eq kind (policy-kind source operation))
                       (or (not (eq kind :collector))
                           (eq (class-of source) (class-of first)))))
                (cdr sources)))))

(defstruct (policy-region (:constructor make-policy-region (view start end)))
  view start end (index 0) (done-p nil))

(defun policy-open-region (source &key (start 0) (end nil))
  "Validate syntax and retain one view, without testing source-dependent bounds."
  (check-region-bounds start end end)
  (make-policy-region (open-view source) start end))

(defun policy-region-step (state)
  "Return EMPTY-P, ELEMENT, absolute INDEX. Commit only successful view steps."
  (when (policy-region-done-p state)
    (return-from policy-region-step (values t nil nil)))
  ;; Reach START even for START=END: an empty region cannot hide invalid START.
  (loop while (< (policy-region-index state) (policy-region-start state))
        do (multiple-value-bind (empty element rest)
               (view-step (policy-region-view state))
             (declare (ignore element))
             (when empty
               (raise-type-error (policy-region-start state)
                                 `(integer 0 ,(policy-region-index state))))
             (setf (policy-region-view state) rest)
             (incf (policy-region-index state))))
  ;; Do not observe the node at END, including when END equals START.
  (when (and (policy-region-end state)
             (>= (policy-region-index state) (policy-region-end state)))
    (setf (policy-region-done-p state) t)
    (return-from policy-region-step (values t nil nil)))
  (multiple-value-bind (empty element rest)
      (view-step (policy-region-view state))
    (if empty
        (progn
          (setf (policy-region-done-p state) t)
          (values t nil nil))
        (let ((index (policy-region-index state)))
          (setf (policy-region-view state) rest)
          (incf (policy-region-index state))
          (values nil element index)))))

(defun policy-key (designator)
  (if (null designator) #'identity (usable-function designator)))

(defun policy-count (count)
  (when count (check-seq-index count))
  count)

(defun policy-size (size &key (positive nil))
  (check-seq-index size)
  (when (and positive (zerop size)) (raise-program-error))
  size)

(defun construction-target (designator)
  "Return a fresh Collector and false, or NIL and true for LAZY-SEQ."
  (let (name options)
    (cond ((symbolp designator) (setf name designator))
          ((consp designator)
           (unless (symbolp (car designator)) (raise-program-error))
           (setf name (car designator) options (cdr designator))
           (validate-collector-options options))
          (t (raise-program-error)))
    (if (string= (symbol-name name) "LAZY-SEQ")
        (progn
          (when options (raise-program-error))
          (values nil t))
        (values (make-collector (resolve-target-designator name) options) nil))))

(defun construction-collect-view (collector view)
  (do-view-elements (element view :result (values (sl:collector-result collector)))
    (sl:collector-accumulate collector element)))

(defun sequence-into (target-designator source)
  (multiple-value-bind (collector lazy-p) (construction-target target-designator)
    (if lazy-p
        (open-view source)
        (do-view-elements (element source :result (sl:collector-result collector))
          (sl:collector-accumulate collector element)))))

(defmethod sl:seq-into ((target-designator t) (source t))
  (sequence-into target-designator source))

(defmethod sl:seq-into ((target-designator t) (source list))
  (sequence-into target-designator source))

(defmethod sl:seq-into ((target-designator t) (source vector))
  (sequence-into target-designator source))

(defun join-view (sequences separator separator-p)
  (let ((outer (open-view sequences)) (piece nil) (seen-piece-p nil)
        (separator-view nil) (separator-open-p nil) (separator-cursor nil)
        (phase :outer))
    (labels ((next-node ()
               (sl:make-lazy-seq
                (lambda ()
                  ;; Empty pieces are skipped iteratively, not via a chain of
                  ;; recursively forced wrappers. Commit only successful steps.
                  (loop
                   (ecase phase
                     (:outer
                      (multiple-value-bind (empty element rest) (view-step outer)
                        (when empty (return nil))
                        (let ((view (open-view element)))
                          (setf outer rest piece view phase :piece-start))))
                     (:piece-start
                      (if (nth-value 0 (view-step piece))
                          (setf phase :outer)
                          (setf phase (if (and seen-piece-p separator-p)
                                          :separator-start :piece))))
                     (:separator-start
                      ;; Retain exactly one memoized view for every insertion.
                      ;; A lazy target can stream even an unbounded separator.
                      (unless separator-open-p
                        (setf separator-view (open-view separator)
                              separator-open-p t))
                      (setf separator-cursor separator-view phase :separator))
                     (:separator
                      (multiple-value-bind (empty element rest)
                          (view-step separator-cursor)
                        (if empty
                            (setf phase :piece)
                            (progn
                              (setf separator-cursor rest)
                              (return (sl:lazy-cons element (next-node)))))))
                     (:piece
                      (multiple-value-bind (empty element rest) (view-step piece)
                        (if empty
                            (setf phase :outer)
                            (progn
                              (setf piece rest seen-piece-p t)
                              (return (sl:lazy-cons element (next-node)))))))))))))
      (next-node))))

(defun sequence-join (target-designator sequences separator separator-p)
  (multiple-value-bind (collector lazy-p) (construction-target target-designator)
    (let ((view (join-view sequences separator separator-p)))
      (if lazy-p view (construction-collect-view collector view)))))

(defmethod sl:seq-join ((target-designator t) (sequences t)
                        &rest options &key (separator nil separator-p))
  (validate-collector-options options '(:separator))
  (sequence-join target-designator sequences separator separator-p))

(defmethod sl:seq-join ((target-designator t) (sequences list)
                        &rest options &key (separator nil separator-p))
  (validate-collector-options options '(:separator))
  (sequence-join target-designator sequences separator separator-p))

(defmethod sl:seq-join ((target-designator t) (sequences vector)
                        &rest options &key (separator nil separator-p))
  (validate-collector-options options '(:separator))
  (sequence-join target-designator sequences separator separator-p))
