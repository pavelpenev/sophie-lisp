;;;; Deferred chunks with local padding and memoized keyed lookahead.
(in-package #:sophie-lisp.internal)

(defmethod sl:seq-partition (chunk-size (sequence t) &rest options &key (step chunk-size) pad)
  (validate-collector-options options '(:step :pad))
  (policy-size chunk-size :positive t)
  (policy-size step :positive t)
  (unless (or (null pad) (eq pad t) (sl:seqablep pad))
    (raise-type-error pad '(or null (eql t) (satisfies sl:seqablep))))
  (let ((cursor (make-view-cursor sequence)) (buffer nil) (size 0) (skip 0)
        (eof nil) (done nil) (padding nil) (pad-cursor nil)
        (phase :fill))
    (labels ((produce ()
               (when done (return-from produce nil))
               (when (eq phase :fill)
                 (loop while (plusp skip)
                       do (if buffer
                              (progn (pop buffer) (decf size) (decf skip))
                              (multiple-value-bind (empty element rest)
                                  (view-cursor-step cursor)
                                (declare (ignore element))
                                (when empty
                                  (setf done t)
                                  (return-from produce nil))
                                (view-cursor-advance cursor rest)
                                (decf skip))))
                 (loop while (and (< size chunk-size) (not eof))
                       do (multiple-value-bind (empty element rest)
                              (view-cursor-step cursor)
                            (if empty
                                (setf eof t)
                                (progn
                                  (setf buffer (append buffer (list element)))
                                  (view-cursor-advance cursor rest)
                                  (incf size)))))
                 (when (or (zerop size) (and eof (null pad)))
                   (setf done t)
                   (return-from produce nil))
                 (setf phase :pad))
               (when (eq phase :pad)
                 (when (and eof (not (eq pad t)))
                   (unless pad-cursor
                     (setf pad-cursor (make-view-cursor pad)))
                   (loop while (< (+ size (length padding)) chunk-size)
                         do (multiple-value-bind (empty element rest)
                                (view-cursor-step pad-cursor)
                              (when empty (return))
                              (setf padding (append padding (list element)))
                              (view-cursor-advance pad-cursor rest))))
                 (setf phase :emit))
               (let ((piece (policy-reconstruct sequence 'sl:seq-partition buffer
                                                :role :piece :padding padding)))
                 ;; EOF found during fill identifies an emitted short or padded
                 ;; final chunk; carry it to DONE to prevent a later chunk start.
                 (setf phase :fill
                       skip step
                       padding nil
                       done eof)
                 (sl:lazy-cons piece (sl:make-lazy-seq #'produce)))))
      (sl:make-lazy-seq #'produce))))

(defun partition-keyed-view (key-function cursor)
  (sl:make-lazy-seq
   (lambda ()
     (multiple-value-bind (empty element rest) (view-cursor-step cursor)
       (unless empty
         (let ((key (funcall key-function element)))
           (view-cursor-advance cursor rest)
           (sl:lazy-cons (cons element key)
                         (partition-keyed-view key-function cursor))))))))

(defmethod sl:seq-partition-by (key-function (sequence t) &rest options &key (test #'sl:equals))
  (validate-collector-options options '(:test))
  (usable-function key-function)
  (usable-function test)
  (let ((view (partition-keyed-view key-function (make-view-cursor sequence)))
        (items nil) (previous nil) (phase :scan) (done nil))
    (labels ((produce ()
               (when done (return-from produce nil))
               (when (eq phase :scan)
                 (loop
                  (multiple-value-bind (empty keyed rest) (view-step view)
                    (when empty
                      (setf phase :last)
                      (return))
                    (when (and items (not (funcall test previous (cdr keyed))))
                      (setf phase :emit)
                      (return))
                    (push (car keyed) items)
                    (setf previous (cdr keyed)
                          view rest))))
               (unless items
                 (setf done t)
                 (return-from produce nil))
               (let ((piece (policy-reconstruct sequence 'sl:seq-partition-by
                                                (reverse items) :role :piece)))
                 (setf done (eq phase :last)
                       items nil
                       phase :scan)
                 (sl:lazy-cons piece (sl:make-lazy-seq #'produce)))))
      (sl:make-lazy-seq #'produce))))

(defun split-list (view)
  ;; Synchronous piece drains can use the direct eager traversal for retained
  ;; list/vector views; lazy and extension views retain their protocol path.
  (let ((items nil))
    (do-view-elements (element view :result (nreverse items))
      (push element items))))

(defmethod sl:seq-split ((sequence t) &rest options
                                        &key (delimiter nil delimiter-p)
                                        (predicate nil predicate-p)
                                        (test #'sl:equals test-p))
  (validate-collector-options options '(:delimiter :predicate :test))
  (unless (and (not (eq delimiter-p predicate-p))
               (not (and predicate-p test-p)))
    (raise-program-error))
  (if predicate-p (usable-function predicate) (usable-function test))
  (when (and delimiter-p (null delimiter)) (raise-simple-error "Empty delimiter."))
  (let ((cursor (make-view-cursor sequence))
        (delimiter-cursor nil)
        (delimiter-items nil)
        (delimiter-ready nil)
        (width 1)
        (buffer nil)
        (items nil)
        (eof nil)
        (phase :scan)
        (done nil))
    (labels ((produce ()
               (when done (return-from produce nil))
               (when (and delimiter-p (not delimiter-ready))
                 (unless delimiter-cursor
                   (setf delimiter-cursor
                         (make-view-cursor (if (sl:seqablep delimiter)
                                               delimiter (list delimiter)))))
                 (loop
                  (multiple-value-bind (empty element rest)
                      (view-cursor-step delimiter-cursor)
                    (when empty (return))
                    (push element delimiter-items)
                    (view-cursor-advance delimiter-cursor rest)))
                 (unless delimiter-items (raise-simple-error "Empty delimiter."))
                 (setf delimiter-items (nreverse delimiter-items)
                       width (length delimiter-items) delimiter-ready t))
               (when (eq phase :scan)
                 (loop
                  (loop while (and (< (length buffer) width) (not eof))
                        do (multiple-value-bind (empty element rest)
                               (view-cursor-step cursor)
                             (if empty (setf eof t)
                                 (progn
                                   (setf buffer (append buffer (list element)))
                                   (view-cursor-advance cursor rest)))))
                  (unless buffer
                    (setf phase :last)
                    (return))
                  (let ((boundary
                         (if predicate-p
                             (funcall predicate (car buffer))
                             (and (= (length buffer) width)
                                  (every (lambda (d s) (funcall test d s))
                                         delimiter-items buffer)))))
                    (if boundary
                        (progn (setf buffer nil phase :emit) (return))
                        (push (pop buffer) items)))))
               (let ((piece (policy-reconstruct sequence 'sl:seq-split
                                                (reverse items) :role :piece)))
                 (setf done (eq phase :last) phase :scan items nil)
                 (sl:lazy-cons piece (sl:make-lazy-seq #'produce)))))
      (sl:make-lazy-seq #'produce))))

(defun split-pair (source operation count predicate)
  (let ((cursor (make-view-cursor source))
        (index 0)
        (boundary nil))
    (labels ((prefix-next ()
               (when (or boundary (and count (= index count)))
                 (setf boundary t)
                 (return-from prefix-next nil))
               (multiple-value-bind (empty element rest) (view-cursor-step cursor)
                 (when (or empty (and predicate (not (funcall predicate element))))
                   (setf boundary t)
                   (return-from prefix-next nil))
                 (view-cursor-advance cursor rest)
                 (incf index)
                 (sl:lazy-cons element (sl:make-lazy-seq #'prefix-next)))))
      (let* ((prefix (sl:make-lazy-seq #'prefix-next))
             (scan prefix)
             (suffix (sl:make-lazy-seq
                      (lambda ()
                        (loop
                         (multiple-value-bind (empty element rest) (view-step scan)
                           (declare (ignore element))
                           (when empty (return))
                           (setf scan rest)))
                        ;; The cursor's position is shared with PREFIX; preserve
                        ;; the unobserved tail as a view for lazy piece clients.
                        (case (view-cursor-kind cursor)
                          (:list (list-view (view-cursor-current cursor)))
                          (:vector (vector-view (view-cursor-current cursor)
                                                (view-cursor-index cursor)
                                                (view-cursor-end cursor)))
                          (:generic (view-cursor-current cursor)))))))
        (cond
          ((policy-eager-p source operation)
           (let* ((left (policy-reconstruct source operation (split-list prefix) :role :piece))
                  (right (policy-reconstruct source operation (split-list suffix) :role :piece)))
             (policy-reconstruct source operation (list left right) :role :outer)))
          ((member (policy-kind source operation :role :piece)
                   '(:collector :ordered-dict) :test #'eq)
           ;; Retained piece views stage successful traversal and predicates
           ;; independently of reconstruction. A failed Collector attempt may be
           ;; replaced, but retry reads these same memoized nodes and boundary.
           ;; Each outer node commits only its own successfully finalized piece.
           (sl:make-lazy-seq
            (lambda ()
              (sl:lazy-cons
               (policy-reconstruct source operation (split-list prefix) :role :piece)
               (sl:make-lazy-seq
                (lambda ()
                  (sl:lazy-cons
                   (policy-reconstruct source operation (split-list suffix) :role :piece)
                   nil)))))))
          (t
           (sl:make-lazy-seq
            (lambda ()
              (sl:lazy-cons
               (unless (nth-value 0 (view-step prefix)) prefix)
               (sl:make-lazy-seq
                (lambda ()
                  (sl:lazy-cons (unless (nth-value 0 (view-step suffix)) suffix) nil))))))))))))

(defmethod sl:seq-split-at (count (sequence t))
  (policy-size count)
  (split-pair sequence 'sl:seq-split-at count nil))

(defmethod sl:seq-split-with (predicate (sequence t))
  (usable-function predicate)
  (split-pair sequence 'sl:seq-split-with nil predicate))

(defmethod sl:seq-tree-seq (branch-function children-function (tree t))
  (usable-function branch-function)
  (usable-function children-function)
  (let ((root-p t) (pending tree) (stage :branch) (stack nil)
        (children nil))
    (labels ((produce ()
               (when root-p
                 (setf root-p nil)
                 (return-from produce
                   (sl:lazy-cons tree (sl:make-lazy-seq #'produce))))
               ;; Commit successful callbacks separately: a children failure
               ;; must not repeat a successful branch predicate.
               (when (eq stage :branch)
                 (setf stage (if (funcall branch-function pending) :children :walk)))
               (when (eq stage :children)
                 (setf children (funcall children-function pending) stage :open))
               (when (eq stage :open)
                 (push (open-view children) stack)
                 (setf stage :walk children nil))
               (loop while stack
                     do (multiple-value-bind (empty element rest) (view-step (car stack))
                          (if empty
                              (pop stack)
                              (progn
                                (setf (car stack) rest pending element stage :branch)
                                (return-from produce
                                  (sl:lazy-cons element (sl:make-lazy-seq #'produce)))))))
               nil))
      (sl:make-lazy-seq #'produce))))

(defmethod sl:seq-drop-last (count (sequence t))
  (policy-size count)
  (let ((view (open-view sequence)))
    (if (vectorp sequence)
        (let ((items nil))
          (loop
           (multiple-value-bind (empty element rest) (view-step view)
             (when empty (return))
             (push element items)
             (setf view rest)))
          (setf items (nreverse items))
          (policy-reconstruct sequence 'sl:seq-drop-last
                              (subseq items 0 (max 0 (- (length items) count)))))
        (let ((head nil) (tail nil) (size 0) (done nil))
          (labels ((produce ()
                     (when done (return-from produce nil))
                     (loop while (<= size count)
                           do (multiple-value-bind (empty element rest) (view-step view)
                                (when empty
                                  (setf done t head nil tail nil)
                                  (return-from produce nil))
                                (let ((cell (list element)))
                                  (if tail (setf (cdr tail) cell) (setf head cell))
                                  (setf tail cell view rest)
                                  (incf size))))
                     (let ((value (pop head)))
                       (decf size)
                       (unless head (setf tail nil))
                       (sl:lazy-cons value (sl:make-lazy-seq #'produce)))))
            (sl:make-lazy-seq #'produce))))))
