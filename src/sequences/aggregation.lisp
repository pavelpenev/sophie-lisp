;;;; Complete call-time traversal, followed by representation reconstruction.
(in-package #:sophie-lisp.internal)

(defun materialize-elements (source)
  (let ((elements nil))
    (do-view-elements (element source :result (nreverse elements))
      (push element elements))))

(defun stable-merge-sort (elements test key)
  "Bottom-up stable merge sort: O(n log n) comparisons, O(n) workspace.
Keys are deliberately evaluated at each comparison, not decorated or cached."
  (let* ((input (coerce elements 'vector))
         (size (length input))
         (output (make-array size)))
    (loop for width = 1 then (* 2 width)
          while (< width size)
          do (loop for start from 0 below size by (* 2 width)
                   for middle = (min size (+ start width))
                   for end = (min size (+ middle width))
                   do (let ((left start) (right middle) (destination start))
                        (loop while (and (< left middle) (< right end))
                              do (if (funcall test (funcall key (aref input right))
                                              (funcall key (aref input left)))
                                     (setf (aref output destination)
                                           (aref input (prog1 right (incf right))))
                                     (setf (aref output destination)
                                           (aref input (prog1 left (incf left)))))
                                 (incf destination))
                        (loop while (< left middle)
                              do (setf (aref output destination)
                                       (aref input (prog1 left (incf left))))
                                 (incf destination))
                        (loop while (< right end)
                              do (setf (aref output destination)
                                       (aref input (prog1 right (incf right))))
                                 (incf destination))))
          (rotatef input output))
    (coerce input 'list)))

(defun promoted-builtin-dict-p (source)
  (and (policy-builtin-dict-p source)
       (not (eq (class-of source) (find-class 'sl:ordered-dict)))))

(defun normalize-ordered-dict (sequence operation)
  (policy-reconstruct sequence operation (materialize-elements sequence)))

(defmethod sl:seq-reverse ((sequence t))
  (if (promoted-builtin-dict-p sequence)
      (let ((normalized (normalize-ordered-dict sequence 'sl:seq-reverse)))
        (policy-reconstruct normalized 'sl:seq-reverse
                            (nreverse (materialize-elements normalized))))
      (policy-reconstruct sequence 'sl:seq-reverse
                          (nreverse (materialize-elements sequence)))))

(defun sort-elements (sequence operation test key)
  (let ((predicate (usable-function test))
        (key-function (policy-key key)))
    (if (promoted-builtin-dict-p sequence)
        (let ((normalized (normalize-ordered-dict sequence operation)))
          (policy-reconstruct
           normalized operation
           (stable-merge-sort (materialize-elements normalized) predicate key-function)))
        (policy-reconstruct
         sequence operation
         (stable-merge-sort (materialize-elements sequence) predicate key-function)))))

(defmethod sl:seq-sort ((sequence t) &rest options &key (test #'sl:lt) key)
  (validate-collector-options options '(:test :key))
  (sort-elements sequence 'sl:seq-sort test key))

(defmethod sl:seq-stable-sort ((sequence t) &rest options &key (test #'sl:lt) key)
  (validate-collector-options options '(:test :key))
  (sort-elements sequence 'sl:seq-stable-sort test key))

(defun collect-last-elements (count source)
  "Grow a ring only to MIN(COUNT, source length), then reuse its cells."
  (let ((head nil) (tail nil) (size 0) (oldest nil))
    (do-view-elements
        (element source
                 :result (if oldest
                             (loop repeat size for cell = oldest then (cdr cell)
                                   collect (car cell))
                             head))
      (cond
        ((< size count)
         (let ((cell (list element)))
           (if tail (setf (cdr tail) cell) (setf head cell))
           (setf tail cell)
           (incf size)
           (when (= size count)
             (setf (cdr tail) head oldest head))))
        (t (setf (car oldest) element oldest (cdr oldest)))))))

(defmethod sl:seq-take-last (count (sequence t))
  (policy-size count)
  (policy-reconstruct sequence 'sl:seq-take-last
                      (unless (zerop count) (collect-last-elements count sequence))))

(defun trim-with-predicate (source predicate supplied-p)
  (cond (supplied-p
         (unless predicate (raise-program-error))
         (usable-function predicate))
        ((stringp source) #'selection-whitespace-p)
        (t (raise-program-error "A non-string trim requires :PREDICATE."))))

(defun trim-elements (source operation predicate supplied-p both-p)
  (let ((test (trim-with-predicate source predicate supplied-p))
        (elements nil) (trailing 0) (leading-p both-p))
    (do-view-elements (element source)
      ;; Evaluate once for every reached element, including interior runs.
      (let ((matches (funcall test element)))
        (unless (and leading-p matches)
          (setf leading-p nil)
          (push element elements)
          (setf trailing (if matches (1+ trailing) 0)))))
    (policy-reconstruct source operation (nreverse (nthcdr trailing elements)))))

(defmethod sl:seq-trim-right ((sequence t) &rest options
                              &key (predicate nil supplied-p))
  (validate-collector-options options '(:predicate))
  (trim-elements sequence 'sl:seq-trim-right predicate supplied-p nil))

(defmethod sl:seq-trim ((sequence t) &rest options
                          &key (predicate nil supplied-p))
  (validate-collector-options options '(:predicate))
  (trim-elements sequence 'sl:seq-trim predicate supplied-p t))

(defun reduce-reduce (function source &key key start end end-supplied-p from-end
                                      initial-value initial-supplied-p)
  (let* ((function (usable-function function))
         (key-function (policy-key key))
         (elements nil))
    ;; Validate before opening the source.
    (check-region-bounds start end end-supplied-p)
    ;; Retain only the selected finite region. Key and combiner calls follow
    ;; complete traversal, preserving their order and orientation.
    (do-view-elements (element source :start start
                                     :end (and end-supplied-p end))
      (push element elements))
    (setf elements (if from-end elements (nreverse elements)))
    (let ((keyed (mapcar key-function elements)))
      (if from-end
          (if initial-supplied-p
              (let ((accumulator initial-value))
                (dolist (element keyed accumulator)
                  (setf accumulator (funcall function element accumulator))))
              (if (null keyed)
                  (raise-simple-error "SEQ-REDUCE requires a non-empty source.")
                  (let ((accumulator (car keyed)))
                    (dolist (element (cdr keyed) accumulator)
                      (setf accumulator (funcall function element accumulator))))))
          (if initial-supplied-p
              (let ((accumulator initial-value))
                (dolist (element keyed accumulator)
                  (setf accumulator (funcall function accumulator element))))
              (if (null keyed)
                  (raise-simple-error "SEQ-REDUCE requires a non-empty source.")
                  (let ((accumulator (car keyed)))
                    (dolist (element (cdr keyed) accumulator)
                      (setf accumulator (funcall function accumulator element))))))))))

(defmethod sl:seq-reduce ((function t) (source t)
                          &rest options &key key (start 0) (end nil end-supplied-p)
                          from-end
                          (initial-value nil initial-supplied-p))
  (validate-collector-options options '(:key :start :end :from-end :initial-value))
  (reduce-reduce function source :key key :start start :end end
                 :end-supplied-p end-supplied-p :from-end from-end
                 :initial-value initial-value :initial-supplied-p initial-supplied-p))
