;;;; Streaming selection; only last-match selection buffers a finite region.
(in-package #:sophie-lisp.internal)

(defun selection-finish (source operation stream)
  (if (policy-eager-p source operation)
      (policy-reconstruct
       source operation
       (loop with items = nil
             do (multiple-value-bind (empty element rest) (view-step stream)
                  (when empty (return (nreverse items)))
                  (push element items)
                  (setf stream rest))))
      stream))

(defun selection-result (source operation predicate key start end count from-end filter-p)
  ;; END doubles as the flag because this site originally checked END non-NIL.
  (check-region-bounds start end end)
  (policy-count count)
  (when (and filter-p (eql count 0))
    (return-from selection-result (policy-reconstruct source operation nil)))
  ;; Last-match selection needs its complete classified prefix before emitting.
  ;; A positive FROM-END count selects matches from the right, so it cannot
  ;; use the forward fast path without buffering the entire region first.
  (when (and (eager-direct-source-p source)
             (not (and from-end count (plusp count))))
    (let ((items nil) (key-ready nil) keyed (last-index -1))
      (if filter-p
          (do-view-elements (element source :start start :end end :index index)
            (setf last-index index)
            (when (or (null count) (plusp count))
              (unless key-ready
                (setf keyed (funcall key element) key-ready t))
              (when (funcall predicate keyed)
                (push element items)
                (when count (decf count))))
            (setf key-ready nil)
            (when (eql count 0) (return)))
          (do-view-elements (element source :index index)
            (setf last-index index)
            (let* ((selected (and (>= index start) (or (null end) (< index end))))
                   (match (and selected (or (null count) (plusp count))
                               (progn
                                 (unless key-ready
                                   (setf keyed (funcall key element) key-ready t))
                                 (funcall predicate keyed)))))
              (unless match (push element items))
              (when (and match count) (decf count))
              (setf key-ready nil))))
      ;; -1 means no element was reached; one plus the last index is the
      ;; reachable length, including the valid empty region at its end.
      (when (and (not filter-p) (< (1+ last-index) start))
        (raise-type-error start `(integer 0 ,(1+ last-index))))
      (return-from selection-result
        (policy-reconstruct source operation (nreverse items)))))
  (let ((cursor (make-view-cursor source)) (index 0) (key-ready nil) keyed
        (buffer nil) (prepared nil))
    (labels
        ((matchesp (element)
           (unless key-ready
             (setf keyed (funcall key element) key-ready t))
           (funcall predicate keyed))
         (advance (rest)
           (view-cursor-advance cursor rest)
           (setf key-ready nil)
           (incf index))
         (check-end ()
           (when (< index start) (raise-type-error start `(integer 0 ,index))))
         (stream ()
           (sl:make-lazy-seq
            (lambda ()
              (loop
               (when (and filter-p
                          (or (eql count 0) (and end (>= index end))))
                 (return nil))
               (multiple-value-bind (empty element rest) (view-cursor-step cursor)
                 (when empty (check-end) (return nil))
                 (let* ((selected (and (>= index start) (or (null end) (< index end))))
                        (match (and selected (or (null count) (plusp count))
                                    (matchesp element)))
                        (retain (if filter-p match (not match))))
                   (when (and match count) (decf count))
                   (advance rest)
                   (when retain (return (sl:lazy-cons element (stream))))))))))
         (prepare ()
           (unless prepared
             (loop
              (when (and end (>= index end)) (return))
              (multiple-value-bind (empty element rest) (view-cursor-step cursor)
                (when empty (check-end) (return))
                (let ((match (and (>= index start) (matchesp element))))
                  (push (cons element match) buffer)
                  (advance rest))))
             (let ((remaining count) (items nil))
               (dolist (entry buffer)
                 (let ((selected (and (cdr entry) (plusp remaining))))
                   (when selected (decf remaining))
                   (when (if filter-p selected (not selected))
                     (push (car entry) items))))
               (setf buffer items prepared t count 0))))
         (buffer-stream ()
           (sl:make-lazy-seq
            (lambda ()
              (prepare)
              (if buffer
                  (let ((element (pop buffer)))
                    (sl:lazy-cons element (buffer-stream)))
                  (if filter-p nil (stream)))))))
      (selection-finish source operation
                        (if (and from-end count (plusp count))
                            (buffer-stream) (stream))))))

(defmethod sl:seq-filter (predicate (source t)
                          &rest options &key from-end (start 0) end key count)
  (validate-collector-options options '(:key :start :end :from-end :count))
  (usable-function predicate)
  (selection-result source 'sl:seq-filter predicate (policy-key key)
                    start end count from-end t))

(defmethod sl:seq-remove (item (source t)
                          &rest options &key (test #'sl:equals) key (start 0) end from-end count)
  (validate-collector-options options '(:test :key :start :end :from-end :count))
  (usable-function test)
  (selection-result source 'sl:seq-remove
                    (lambda (value) (funcall test item value)) (policy-key key)
                    start end count from-end nil))

(defmethod sl:seq-remove-if (predicate (source t)
                             &rest options &key key (start 0) end from-end count)
  (validate-collector-options options '(:key :start :end :from-end :count))
  (usable-function predicate)
  (selection-result source 'sl:seq-remove-if predicate (policy-key key)
                    start end count from-end nil))

(defun selection-prefix (view count take-p)
  (sl:make-lazy-seq
   (lambda ()
     (if take-p
         (unless (zerop count)
           (multiple-value-bind (empty element rest) (view-step view)
             (unless empty
               (sl:lazy-cons element (selection-prefix rest (1- count) t)))))
         (progn
           (loop while (plusp count)
                 do (multiple-value-bind (empty element rest) (view-step view)
                      (declare (ignore element))
                      (when empty (return))
                      (setf view rest)
                      (decf count)))
           view)))))

(defun selection-while (view predicate take-p)
  (sl:make-lazy-seq
   (lambda ()
     (loop
      (multiple-value-bind (empty element rest) (view-step view)
        (when empty (return nil))
        (let ((match (funcall predicate element)))
          (cond
            (take-p
             (return (when match
                       (sl:lazy-cons element (selection-while rest predicate t)))))
            (match (setf view rest))
            (t (return (sl:lazy-cons element rest))))))))))

(defmethod sl:seq-take (count (source t))
  (policy-size count)
  (if (zerop count)
      (policy-reconstruct source 'sl:seq-take nil)
      (selection-finish source 'sl:seq-take
                        (selection-prefix (open-view source) count t))))

(defmethod sl:seq-drop (count (source t))
  (policy-size count)
  (selection-finish source 'sl:seq-drop
                    (selection-prefix (open-view source) count nil)))

(defmethod sl:seq-take-while (predicate (source t))
  (usable-function predicate)
  (selection-finish source 'sl:seq-take-while
                    (selection-while (open-view source) predicate t)))

(defmethod sl:seq-drop-while (predicate (source t))
  (usable-function predicate)
  (selection-finish source 'sl:seq-drop-while
                    (selection-while (open-view source) predicate nil)))

(defun selection-region-stream (region)
  (sl:make-lazy-seq
   (lambda ()
     (multiple-value-bind (empty element index) (policy-region-step region)
       (declare (ignore index))
       (unless empty
         (sl:lazy-cons element (selection-region-stream region)))))))

(defun selection-vector-subseq (source start end)
  "Copy the validated reachable vector region into fresh policy-preserving storage."
  (let ((active-end (active-vector-end source)))
    (when (> start active-end)
      (raise-type-error start `(integer 0 ,active-end)))
    (let* ((limit (if end (min end active-end) active-end))
           (result (make-array (- limit start)
                               :element-type
                               (upgraded-array-element-type
                                (array-element-type source)))))
      (replace result source :start2 start :end2 limit)
      result)))

(defmethod sl:seq-subseq ((source t) start &optional end)
  ;; Opening the region owns all syntax checks and their error order, even for
  ;; the empty fast path; the fast path re-raises step-time bounds errors itself,
  ;; while the generic oracle keeps its independent region drain.
  (let ((region (policy-open-region source :start start :end end)))
    (if (and (vectorp source)
             (not *force-generic-traversal*)
             (policy-eager-p source 'sl:seq-subseq)
             (member (policy-kind source 'sl:seq-subseq) '(:vector :string))
             (pristine-vector-collector-protocol-p source))
        (selection-vector-subseq source start end)
        (selection-finish source 'sl:seq-subseq
                          (selection-region-stream region)))))

(defun selection-stride (view stride skip)
  (sl:make-lazy-seq
   (lambda ()
     (loop while (plusp skip)
           do (multiple-value-bind (empty element rest) (view-step view)
                (declare (ignore element))
                (when empty (return))
                (setf view rest)
                (decf skip)))
     (multiple-value-bind (empty element rest) (view-step view)
       (unless empty
         (sl:lazy-cons element (selection-stride rest stride (1- stride))))))))

(defmethod sl:seq-take-nth (stride (source t))
  (policy-size stride :positive t)
  (selection-finish source 'sl:seq-take-nth
                    (selection-stride (open-view source) stride 0)))

;;; Post-B4 worst-host crossover measurement: 384-768 entries; indexed
;;; wins at 768 on SBCL, CCL, and ECL (worst host ECL: 1.23x).
;;; At 384 indexed is 1.55x slower on ECL; retain linear through 768.
(defconstant +selection-distinct-index-threshold+ 768)

(defun selection-distinct-linear-result (entries test from-end)
  (let ((seen nil) (items nil))
    (dolist (entry (if from-end entries (reverse entries)))
      (unless (some (lambda (prior) (funcall test prior (cdr entry))) seen)
        (push (cdr entry) seen)
        (push (car entry) items)))
    (open-view (if from-end items (nreverse items)))))

(defun selection-distinct-indexed-result (entries test from-end kind standard)
  (let* ((index (case kind
                  (:table (make-hash-table :test standard))
                  (:hash (make-hash-table :test 'eql))))
         (retained (when (eq kind :hash)
                     (make-array 0 :adjustable t :fill-pointer 0)))
         (overflow nil)
         (seen nil)
         (items nil))
    ;; Chapter 7 requires EQUALS-matching hashable values to share a hash;
    ;; only the candidate's bucket and unhashable overflow can match.
    ;; Walk bucket positions and overflow positions in merged descending
    ;; (newest-first) order, as in SEEN.
    (dolist (entry (if from-end entries (reverse entries)))
      (let ((candidate (cdr entry)))
        (multiple-value-bind (hash hashable-p)
            (if (eq kind :hash)
                (safe-key-hash candidate)
                (values nil nil))
          (unless
              (case kind
                (:table (nth-value 1 (gethash candidate index)))
                (:hash
                 (if (not hashable-p)
                     (some (lambda (prior) (funcall test prior candidate)) seen)
                     (let* ((bucket (gethash hash index))
                            (bucket-index (if bucket (1- (length bucket)) -1))
                            (remaining overflow))
                       (loop while (or (>= bucket-index 0) remaining)
                             for position = (if (and (>= bucket-index 0)
                                                     (or (null remaining)
                                                         (> (aref bucket bucket-index)
                                                            (car remaining))))
                                                (prog1 (aref bucket bucket-index)
                                                  (decf bucket-index))
                                                (pop remaining))
                             thereis (funcall test (aref retained position)
                                              candidate))))))
            (case kind
              (:table (setf (gethash candidate index) t))
              (:hash
               (let ((position (length retained)))
                 (vector-push-extend candidate retained)
                 (if hashable-p
                     (let ((bucket (or (gethash hash index)
                                       (setf (gethash hash index)
                                             (make-array 0 :adjustable t
                                                         :fill-pointer 0)))))
                       (vector-push-extend position bucket))
                     (push position overflow)))))
            (when (eq kind :hash) (push candidate seen))
            (push (car entry) items)))))
    (open-view (if from-end items (nreverse items)))))

(defun selection-distinct (region test key from-end)
  (let ((entries nil) (complete nil) (pending nil) element)
    (sl:make-lazy-seq
     (lambda ()
       ;; Pending retains a reached position across a failed KEY. Completed
       ;; keys are kept separately from comparisons and never recomputed.
       (unless complete
         (loop
          (unless pending
            (multiple-value-bind (empty value index) (policy-region-step region)
              (declare (ignore index))
              (when empty (setf complete t) (return))
              (setf element value pending t)))
          (let ((keyed (funcall key element)))
            (push (cons element keyed) entries)
            (setf pending nil))))
       (if (<= (length entries) +selection-distinct-index-threshold+)
           (selection-distinct-linear-result entries test from-end)
           (multiple-value-bind (kind standard) (index-kind-for-test test)
             (if (eq kind :linear)
                 (selection-distinct-linear-result entries test from-end)
                 (selection-distinct-indexed-result entries test from-end
                                                    kind standard))))))))

(defmethod sl:seq-remove-duplicates ((source t)
                                     &rest options &key (test #'sl:equals) key
                                     (start 0) end from-end)
  (validate-collector-options options '(:test :key :start :end :from-end))
  (usable-function test)
  (let ((key (policy-key key)))
    (selection-finish source 'sl:seq-remove-duplicates
                      (selection-distinct
                       (policy-open-region source :start start :end end)
                       test key from-end))))

(defun selection-dedupe (view test previous present-p)
  (sl:make-lazy-seq
   (lambda ()
     (loop
      (multiple-value-bind (empty element rest) (view-step view)
        (when empty (return nil))
        (let ((duplicate (and present-p (funcall test previous element))))
          ;; PREVIOUS is the source predecessor, even if it was omitted.
          (setf view rest previous element present-p t)
          (unless duplicate
            (return (sl:lazy-cons element
                                  (selection-dedupe rest test element t))))))))))

(defmethod sl:seq-dedupe ((source t) &rest options &key (test #'sl:equals))
  (validate-collector-options options '(:test))
  (usable-function test)
  (selection-finish source 'sl:seq-dedupe
                    (selection-dedupe (open-view source) test nil nil)))

(defun selection-whitespace-p (character)
  ;; Intentional ASCII codes for this prototype; see the sequence implementation notes.
  (member (char-code character) '(9 10 11 12 13 32)))

(defmethod sl:seq-trim-left ((source t) &rest options &key (predicate nil supplied-p))
  (validate-collector-options options '(:predicate))
  (setf predicate (trim-with-predicate source predicate supplied-p))
  (selection-finish source 'sl:seq-trim-left
                    (selection-while (open-view source) predicate nil)))

(defun selection-reductions (view function accumulator present-p)
  (sl:make-lazy-seq
   (lambda ()
     (multiple-value-bind (empty element rest) (view-step view)
       (unless empty
         (let ((value (if present-p (funcall function accumulator element) element)))
           (sl:lazy-cons value (selection-reductions rest function value t))))))))

(defmethod sl:seq-reductions (function (source t)
                              &rest options &key (initial-value nil supplied-p))
  (validate-collector-options options '(:initial-value))
  (usable-function function)
  (let* ((view (open-view source))
         (tail (selection-reductions view function initial-value supplied-p)))
    (selection-finish source 'sl:seq-reductions
                      (if supplied-p (sl:lazy-cons initial-value tail) tail))))
