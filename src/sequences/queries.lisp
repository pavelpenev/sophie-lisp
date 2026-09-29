;;;; Chapter 6 scalar last query.

(in-package #:sophie-lisp.internal)

(defmethod sl:seq-last ((source t))
  ;; SEQ-LAST is a scalar query: it owns its complete traversal and never
  ;; invokes the reconstruction policy or a Collector.
  (let ((seen nil)
        (seen-p nil))
    (do-view-elements (element source
                              :result (if seen-p
                                          seen
                                          (raise-simple-error
                                            "SEQ-LAST requires a non-empty source.")))
      (setf seen element
            seen-p t))))

(defun find-query (argument source &key test test-supplied-p predicate-p key
                                     start end end-supplied-p from-end position-p)
  (let* ((callback (if predicate-p
                       (usable-function argument)
                       nil))
         (test-function (if predicate-p
                            nil
                            (if test-supplied-p
                                (usable-function test)
                                #'sl:equals)))
         (key-function (policy-key key)))
    (check-region-bounds start end end-supplied-p)
    (labels ((matchesp (element)
               (let ((keyed (funcall key-function element)))
                 (if predicate-p
                     (funcall callback keyed)
                     (funcall test-function argument keyed))))
             (answer (element index)
               (if position-p index element)))
      (if from-end
          ;; Reach the whole region before applying callbacks, right to left.
          (let ((entries nil))
            (do-view-elements (element source :index index
                                      :start start :end end)
              (push (cons element index) entries))
            (dolist (entry entries nil)
              (when (matchesp (car entry))
                (return (answer (car entry) (cdr entry))))))
          (do-view-elements (element source :index index
                                    :start start :end end)
            (when (matchesp element)
              (return (answer element index))))))))

(defmethod sl:seq-find ((item t) (source t)
                        &rest options &key (test nil test-supplied-p) key
                        (start 0) (end nil end-supplied-p) from-end)
  (validate-collector-options options '(:test :key :start :end :from-end))
  (find-query item source :test test :test-supplied-p test-supplied-p
              :key key :start start :end end :end-supplied-p end-supplied-p
              :from-end from-end))

(defmethod sl:seq-find-if ((predicate t) (source t)
                           &rest options &key key (start 0) (end nil end-supplied-p)
                           from-end)
  (validate-collector-options options '(:key :start :end :from-end))
  (find-query predicate source :predicate-p t :key key :start start :end end
              :end-supplied-p end-supplied-p :from-end from-end))

(defmethod sl:seq-position ((item t) (source t)
                            &rest options &key (test nil test-supplied-p) key
                            (start 0) (end nil end-supplied-p) from-end)
  (validate-collector-options options '(:test :key :start :end :from-end))
  (find-query item source :test test :test-supplied-p test-supplied-p
              :key key :start start :end end :end-supplied-p end-supplied-p
              :from-end from-end :position-p t))

(defmethod sl:seq-position-if ((predicate t) (source t)
                               &rest options &key key (start 0) (end nil end-supplied-p)
                               from-end)
  (validate-collector-options options '(:key :start :end :from-end))
  (find-query predicate source :predicate-p t :key key :start start :end end
              :end-supplied-p end-supplied-p :from-end from-end :position-p t))

(defun member-tail-view (cursor rest)
  "Return a deferred suffix from the uncommitted position after a match."
  (case (view-cursor-kind cursor)
    (:list (list-view rest))
    (:vector (vector-view (view-cursor-current cursor) rest
                          (view-cursor-end cursor)))
    (:generic rest)))

(defmethod sl:seq-member ((item t) (source t)
                          &rest options &key (test nil test-supplied-p) key)
  (validate-collector-options options '(:test :key))
  ;; Search synchronously and retain the unobserved suffix on a hit. Keep
  ;; protocol and lazy sources on their original retained-view path.
  (let ((test-function (if test-supplied-p (usable-function test) #'sl:equals))
        (key-function (policy-key key)))
    (if (eager-direct-source-p source)
        (let ((cursor (make-view-cursor source)))
          (loop
           (multiple-value-bind (empty-p element rest) (view-cursor-step cursor)
             (when empty-p (return nil))
             (when (funcall test-function item (funcall key-function element))
               (return (sl:lazy-cons element (member-tail-view cursor rest))))
             (view-cursor-advance cursor rest))))
        (let ((view (open-view source)))
          (loop
           (multiple-value-bind (empty-p element rest) (view-step view)
             (when empty-p (return nil))
             (when (funcall test-function item (funcall key-function element))
               (return (sl:lazy-cons element rest)))
             (setf view rest)))))))

(defun member-count (argument source &key predicate-p test test-supplied-p key
                                       start end end-supplied-p from-end)
  (let* ((predicate (when predicate-p (usable-function argument)))
         (test-function (unless predicate-p
                          (if test-supplied-p (usable-function test) #'sl:equals)))
         (key-function (policy-key key)))
    (check-region-bounds start end end-supplied-p)
    (labels ((matchp (element)
               (let ((keyed (funcall key-function element)))
                 (if predicate-p
                     (funcall predicate keyed)
                     (funcall test-function argument keyed))))
             (count-forward ()
               (let ((count 0))
                 (do-view-elements (element source :start start :end end
                                             :result count)
                   (when (matchp element) (incf count))))))
      (if from-end
          ;; Buffer before invoking callbacks, preserving reverse callback order.
          (let ((entries nil) (count 0))
            (do-view-elements (element source :start start :end end)
              (push element entries))
            (dolist (element entries count)
              (when (matchp element) (incf count))))
          (count-forward)))))

(defmethod sl:seq-count ((item t) (source t)
                         &rest options &key (test nil test-supplied-p) key
                         (start 0) (end nil end-supplied-p) from-end)
  (validate-collector-options options '(:test :key :start :end :from-end))
  (member-count item source :test test :test-supplied-p test-supplied-p
               :key key :start start :end end :end-supplied-p end-supplied-p
               :from-end from-end))

(defmethod sl:seq-count-if ((predicate t) (source t)
                            &rest options &key key (start 0) (end nil end-supplied-p)
                            from-end)
  (validate-collector-options options '(:key :start :end :from-end))
  (member-count predicate source :predicate-p t :key key :start start :end end
               :end-supplied-p end-supplied-p :from-end from-end))

(defstruct (search-eager-region
             (:constructor make-search-eager-region (cursor start end)))
  cursor start end (index 0) (done-p nil))

(defun search-region-step (state)
  (unless (search-eager-region-p state)
    (return-from search-region-step (policy-region-step state)))
  (when (search-eager-region-done-p state)
    (return-from search-region-step (values t nil nil)))
  (let ((cursor (search-eager-region-cursor state)))
    (loop while (< (search-eager-region-index state)
                   (search-eager-region-start state))
          do (multiple-value-bind (empty element rest) (view-cursor-step cursor)
               (declare (ignore element))
               (when empty
                 (raise-type-error (search-eager-region-start state)
                                   `(integer 0 ,(search-eager-region-index state))))
               (view-cursor-advance cursor rest)
               (incf (search-eager-region-index state))))
    (when (and (search-eager-region-end state)
               (>= (search-eager-region-index state)
                   (search-eager-region-end state)))
      (setf (search-eager-region-done-p state) t)
      (return-from search-region-step (values t nil nil)))
    (multiple-value-bind (empty element rest) (view-cursor-step cursor)
      (if empty
          (progn
            (setf (search-eager-region-done-p state) t)
            (values t nil nil))
          (let ((index (search-eager-region-index state)))
            (view-cursor-advance cursor rest)
            (incf (search-eager-region-index state))
            (values nil element index))))))

(defun search-region-index (state)
  (if (search-eager-region-p state)
      (search-eager-region-index state)
      (policy-region-index state)))

(defun search-region-start (state)
  (if (search-eager-region-p state)
      (search-eager-region-start state)
      (policy-region-start state)))

(defun (setf search-region-end) (end state)
  (if (search-eager-region-p state)
      (setf (search-eager-region-end state) end)
      (setf (policy-region-end state) end)))

(defun search-open-region (source start end end-supplied-p)
  (check-region-bounds start end end-supplied-p)
  (if (eager-direct-source-p source)
      (make-search-eager-region (make-view-cursor source) start
                                (and end-supplied-p end))
      (make-policy-region (open-view source) start
                          (and end-supplied-p end))))


(defun search-test-function (test test-supplied-p)
  (if test-supplied-p (usable-function test) #'sl:equals))

(defun search-read-pattern (state key-function)
  ;; Pattern forcing is complete and precedes any subject observation.
  (let ((values nil))
    (loop
     (multiple-value-bind (empty-p element index) (search-region-step state)
       (declare (ignore index))
       (when empty-p (return (nreverse values)))
       (push (funcall key-function element) values)))))

(defun search-empty-search (state start from-end)
  (if from-end
      (let ((answer start))
        (loop
         (multiple-value-bind (empty-p element index)
             (search-region-step state)
           (declare (ignore element))
           (if empty-p
               (return answer)
               (setf answer (1+ index))))))
      (progn
        ;; Only the START2 boundary is needed.  An empty selected region still
        ;; validates its start, but never forces the node at that boundary.
        (setf (search-region-end state) start)
        (search-region-step state)
        start)))

(defun search-search (pattern source &key test test-supplied-p key
                                       start1 end1 end1-supplied-p
                                       start2 end2 end2-supplied-p from-end)
  ;; All syntactic bounds are checked before the pattern is forced.  This keeps
  ;; malformed calls from observing either lazy source.
  (check-seq-index start1)
  (check-seq-index start2)
  (when (and end1-supplied-p end1)
    (check-seq-index end1)
    (when (< end1 start1) (raise-type-error end1 `(integer ,start1 *))))
  (when (and end2-supplied-p end2)
    (check-seq-index end2)
    (when (< end2 start2) (raise-type-error end2 `(integer ,start2 *))))
  (let* ((test-function (search-test-function test test-supplied-p))
         (key-function (policy-key key))
         (pattern-state (search-open-region pattern start1 end1 end1-supplied-p))
         (pattern-keys (search-read-pattern pattern-state key-function))
         (subject-state (search-open-region source start2 end2 end2-supplied-p))
         (pattern-length (length pattern-keys)))
    (if (zerop pattern-length)
        (search-empty-search subject-state start2 from-end)
        (let ((window nil) (answer nil))
          (loop
           (multiple-value-bind (empty-p element index)
               (search-region-step subject-state)
             (when empty-p (return answer))
             (setf window (append window
                                  (list (cons index (funcall key-function element)))))
             (when (> (length window) pattern-length)
               (setf window (cdr window)))
             (when (= (length window) pattern-length)
               (let ((matched
                      (loop for pattern-key in pattern-keys
                            for entry in window
                            always (funcall test-function pattern-key (cdr entry)))))
                 (when matched
                   (if from-end
                       (setf answer (caar window))
                       (return (caar window))))))))))))

(defmethod sl:seq-search ((pattern t) (source t)
                          &rest options &key (test nil test-supplied-p) key
                          (start1 0) (end1 nil end1-supplied-p)
                          (start2 0) (end2 nil end2-supplied-p) from-end)
  (validate-collector-options options '(:test :key :start1 :end1 :start2 :end2 :from-end))
  (search-search pattern source :test test :test-supplied-p test-supplied-p
                 :key key :start1 start1 :end1 end1 :end1-supplied-p end1-supplied-p
                 :start2 start2 :end2 end2 :end2-supplied-p end2-supplied-p
                 :from-end from-end))

(defun search-mismatch-forward (state1 step2 test-function key-function)
  (loop
   (multiple-value-bind (empty1 element1 index1) (search-region-step state1)
     ;; Even an exhausted left region needs the corresponding right node to
     ;; distinguish simultaneous exhaustion from a proper prefix.
     (multiple-value-bind (empty2 element2) (funcall step2)
       (cond
         (empty1
          (return (unless empty2 (search-region-index state1))))
         (empty2 (return index1))
         (t
          (let ((left (funcall key-function element1))
                (right (funcall key-function element2)))
            (unless (funcall test-function left right)
              (return index1)))))))))

(defun search-mismatch-from-end (state1 step2 test-function key-function)
  ;; Discover both ends before aligning pairs.  Buffer raw elements: no key
  ;; may run before its corresponding right-hand element is available, and
  ;; an unpaired element never receives a callback.
  (let ((left nil) (right nil) (left-done nil) (right-done nil)
        (probed-left nil) (probed-right nil))
    (loop
     (unless left-done
       (multiple-value-bind (empty element index) (search-region-step state1)
         (setf probed-left t)
         (if empty
             (setf left-done t)
             (push (cons index element) left))))
     ;; After the first step of both regions, if the left is already
     ;; exhausted and the right is not, the left start is the mismatch
     ;; position.  Do not continue stepping the right: doing so would
     ;; force the right terminal node unnecessarily.
     (when (and probed-left probed-right left-done (null left))
       (return-from search-mismatch-from-end
         (if right-done
             nil
             (search-region-start state1))))
     (unless right-done
       (multiple-value-bind (empty element) (funcall step2)
         (setf probed-right t)
         (if empty
             (setf right-done t)
             (push element right))))
     (when (and left-done right-done) (return)))
    ;; PUSH already put the rightmost elements first.  Walking the two lists
    ;; directly is linear; repeated NTH into forward lists would be quadratic.
    (loop while (and left right)
          do (let ((left-key (funcall key-function (cdar left)))
                   (right-key (funcall key-function (car right))))
               (unless (funcall test-function left-key right-key)
                 (return-from search-mismatch-from-end (1+ (caar left)))))
          (pop left)
          (pop right))
    (cond
      (left (1+ (caar left)))
      (right (search-region-start state1)))))

(defmethod sl:seq-mismatch ((source1 t) (source2 t)
                            &rest options &key (test nil test-supplied-p) key
                            (start1 0) (end1 nil end1-supplied-p)
                            (start2 0) (end2 nil end2-supplied-p) from-end)
  (validate-collector-options options '(:test :key :start1 :end1 :start2 :end2 :from-end))
  ;; Validate both sets of syntactic bounds before activating either source.
  (check-seq-index start1)
  (check-seq-index start2)
  (when (and end1-supplied-p end1)
    (check-seq-index end1)
    (when (< end1 start1) (raise-type-error end1 `(integer ,start1 *))))
  (when (and end2-supplied-p end2)
    (check-seq-index end2)
    (when (< end2 start2) (raise-type-error end2 `(integer ,start2 *))))
  (let* ((test-function (search-test-function test test-supplied-p))
         (key-function (policy-key key))
         (state1 (search-open-region source1 start1 end1 end1-supplied-p))
         (state2 nil))
    (flet ((step2 ()
             ;; Source validation is observable too.  Do not open SOURCE2
             ;; until SOURCE1's first step (including its bounds) succeeds.
             (unless state2
               (setf state2 (search-open-region source2 start2 end2 end2-supplied-p)))
             (search-region-step state2)))
      (if from-end
          (search-mismatch-from-end state1 #'step2 test-function key-function)
          (search-mismatch-forward state1 #'step2 test-function key-function)))))

(defun search-truth (predicate source more-sources some-p)
  (let ((predicate-function (usable-function predicate)))
    (if (null more-sources)
        (do-view-elements (element source :result (if some-p nil t))
          (let ((result (funcall predicate-function element)))
            (if some-p
                (when result (return result))
                (unless result (return nil)))))
        ;; Tuple traversal must remain lockstep, with later sources unopened
        ;; until the preceding source has supplied its element.
        (let* ((sources (cons source more-sources))
               (views (make-list (length sources)))
               (opened (make-list (length sources))))
          (setf (first views) (open-view source)
                (first opened) t)
          (loop
           (let ((elements nil) (complete-p t))
             (loop for index from 0 below (length sources)
                   do (unless (nth index opened)
                        (setf (nth index views) (open-view (nth index sources))
                              (nth index opened) t))
                      (multiple-value-bind (empty-p element rest)
                          (view-step (nth index views))
                        (if empty-p
                            (progn (setf complete-p nil) (return))
                            (progn
                              (setf (nth index views) rest)
                              (push element elements)))))
             (unless complete-p
               (return (if some-p nil t)))
             (let ((result (apply predicate-function
                                  (nreverse elements))))
               (if some-p
                   (when result (return result))
                   (unless result (return nil))))))))))

(defmethod sl:seq-every ((predicate t) (source t) &rest more-sources)
  (search-truth predicate source more-sources nil))

(defmethod sl:seq-some ((predicate t) (source t) &rest more-sources)
  (search-truth predicate source more-sources t))

(defun truth-negation (predicate source more-sources mode)
  (let ((predicate-function (usable-function predicate)))
    (if (null more-sources)
        (do-view-elements (element source
                                   :result (if (eq mode :notevery) nil t))
          (let ((result (funcall predicate-function element)))
            (ecase mode
              (:notevery (when (null result) (return t)))
              (:notany (when result (return nil))))))
        (let* ((sources (cons source more-sources))
               (views (make-list (length sources)))
               (opened (make-list (length sources))))
          (setf (first views) (open-view source)
                (first opened) t)
          (loop
           (let ((elements nil) (complete-p t))
             (loop for index from 0 below (length sources)
                   do (unless (nth index opened)
                        (setf (nth index views) (open-view (nth index sources))
                              (nth index opened) t))
                      (multiple-value-bind (empty-p element rest)
                          (view-step (nth index views))
                        (if empty-p
                            (progn (setf complete-p nil) (return))
                            (progn
                              (setf (nth index views) rest)
                              (push element elements)))))
             (unless complete-p
               (return (if (eq mode :notevery) nil t)))
             (let ((result (apply predicate-function
                                  (nreverse elements))))
               (ecase mode
                 (:notevery (when (null result) (return t)))
                 (:notany (when result (return nil)))))))))))

(defmethod sl:seq-notevery ((predicate t) (source t) &rest more-sources)
  (truth-negation predicate source more-sources :notevery))

(defmethod sl:seq-notany ((predicate t) (source t) &rest more-sources)
  (truth-negation predicate source more-sources :notany))

(defun extremum-extreme (source key default default-supplied-p maximize-p)
  (let ((key-function (policy-key key))
        (best nil)
        (best-key nil)
        (seen-p nil))
    (do-view-elements (element source
                              :result (if seen-p
                                          best
                                          (if default-supplied-p
                                              default
                                              (raise-simple-error
                                                "SEQ-MIN/MAX requires a non-empty source."))))
      (let ((keyed (funcall key-function element)))
        (if (not seen-p)
            (setf best element best-key keyed seen-p t)
            (let ((ordering (sl:compare keyed best-key)))
              (when (eq ordering :unequal)
                (raise-simple-error "The source contains incomparable keys."))
              (when (if maximize-p
                        (eq ordering :greater)
                        (eq ordering :less))
                (setf best element best-key keyed))))))))

(defmethod sl:seq-min ((source t)
                       &rest options &key key (default nil default-supplied-p))
  (validate-collector-options options '(:key :default))
  (extremum-extreme source key default default-supplied-p nil))

(defmethod sl:seq-max ((source t)
                       &rest options &key key (default nil default-supplied-p))
  (validate-collector-options options '(:key :default))
  (extremum-extreme source key default default-supplied-p t))
