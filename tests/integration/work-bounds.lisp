(in-package #:sophie-lisp.tests)

;;;; Observation hooks are dormant outside the dynamically scoped census tests.
(defvar *census-protocol-work* nil)
(defvar *census-index-lookup-work* nil)
(defvar *census-random-access-work* nil)
(defvar *census-function-work* nil)

(defmethod sl:seq-emptyp :around ((source t))
  (when *census-protocol-work* (incf *census-protocol-work*))
  (call-next-method))

(defmethod sl:seq-first :around ((source t))
  (when *census-protocol-work* (incf *census-protocol-work*))
  (call-next-method))

(defmethod sl:seq-rest :around ((source t))
  (when *census-protocol-work* (incf *census-protocol-work*))
  (call-next-method))

(defmethod sl:seq-length :around ((source t))
  (when *census-random-access-work* (incf *census-random-access-work*))
  (call-next-method))

(defmethod sl:seq-ref :around ((source t) index &optional default)
  (declare (ignore index default))
  (when *census-random-access-work* (incf *census-random-access-work*))
  (call-next-method))

(defmethod sl:dict-ref :around ((dictionary sl:dict) key &optional default)
  (declare (ignore default))
  (when *census-index-lookup-work* (incf *census-index-lookup-work*))
  (call-next-method))

(defun census-with-function-work (names thunk)
  "Call THUNK while counting calls through the named internal functions."
  (let* ((originals (mapcar (lambda (name)
                               (cons name (symbol-function name)))
                             names))
         (*census-function-work* 0))
    (unwind-protect
         (progn
           (dolist (pair originals)
             (let ((name (car pair))
                   (original (cdr pair)))
               (setf (symbol-function name)
                     (lambda (&rest arguments)
                       (incf *census-function-work*)
                       (apply original arguments)))))
           (funcall thunk))
      (dolist (pair originals)
        (setf (symbol-function (car pair)) (cdr pair)))))
  nil)

(defun census-ordered-dict (count)
  (apply #'sl:ordered-dict
         (loop for i below count
               append (list (complexity-work-key i) i))))

(parachute:define-test census.ordered-dict-seqablep-does-not-traverse
  ;; Callback counters alone do not observe a tree-only walk. Count public
  ;; sequence calls and direct AVL entry/branch access as well.
  (let* ((count 1000)
         (*complexity-hash-work* 0)
         (*complexity-equal-work* 0)
         (*census-protocol-work* 0)
         (*census-index-lookup-work* 0)
         (dictionary (census-ordered-dict count)))
    (setf *complexity-hash-work* 0
          *complexity-equal-work* 0
          *census-index-lookup-work* 0)
    (census-with-function-work
     '(sophie-lisp.internal::ordered-node-entry
       sophie-lisp.internal::ordered-node-left
       sophie-lisp.internal::ordered-node-right)
     (lambda ()
       (parachute:true (sl:seqablep dictionary))
       (parachute:is = 0 *census-function-work*)))
    (parachute:is = 0 *complexity-hash-work*)
    (parachute:is = 0 *complexity-equal-work*)
    (parachute:is = 0 *census-protocol-work*)
    (parachute:is = 0 *census-index-lookup-work*)))

(parachute:define-test census.dict-size-is-maintained-without-traversal
  (let* ((count 1000)
         (*complexity-hash-work* 0)
         (*complexity-equal-work* 0)
         (*census-protocol-work* 0)
         (dictionary (loop with result = (sl:dict)
                           for i below count
                           do (setf result (sl:dict-set result (complexity-work-key i) i))
                           finally (return result))))
    (setf *complexity-hash-work* 0 *complexity-equal-work* 0)
    (census-with-function-work
     '(sophie-lisp.internal::trie-next)
     (lambda ()
       (parachute:is = count (sl:dict-size dictionary))
       (parachute:is = 0 *census-function-work*)))
    (parachute:is = 0 *complexity-hash-work*)
    (parachute:is = 0 *complexity-equal-work*)
    (parachute:is = 0 *census-protocol-work*)))

(parachute:define-test census.ordered-dict-lookup-size-and-traversal-bounded-work
  (let* ((count 1000)
         (*complexity-hash-work* 0)
         (*complexity-equal-work* 0)
         (dictionary (census-ordered-dict count)))
    (parachute:is = count (sl:dict-size dictionary))
    (parachute:true (<= count *complexity-hash-work* (* 4 count)))
    (parachute:true (<= *complexity-equal-work* (* 4 count)))
    (let* ((*complexity-hash-work* 0)
           (*complexity-equal-work* 0)
           (*census-index-lookup-work* 0)
           (*census-protocol-work* 0)
           (hit (multiple-value-list
                 (sl:dict-ref dictionary (complexity-work-key (floor count 2)))))
           (miss (multiple-value-list
                  (sl:dict-ref dictionary (complexity-work-key count)))))
      (parachute:is = (floor count 2) (first hit))
      (parachute:true (second hit))
      (parachute:is eq nil (second miss))
      (parachute:true (<= *complexity-hash-work* 8))
      (parachute:true (<= *complexity-equal-work* 8))
      (parachute:is = 2 *census-index-lookup-work*)
      (parachute:is = 0 *census-protocol-work*))
    (let* ((*complexity-hash-work* 0)
           (*complexity-equal-work* 0)
           (*census-index-lookup-work* 0)
           (*census-protocol-work* 0)
           (*census-random-access-work* 0))
      (census-with-function-work
       '(sophie-lisp.internal::trie-next
         sophie-lisp.internal::ordered-node-entry
         sophie-lisp.internal::ordered-node-left
         sophie-lisp.internal::ordered-node-right)
       (lambda ()
         (let ((size (sl:dict-size dictionary))
               (length (sl:seq-length dictionary)))
           (parachute:is = count size)
           (parachute:is = count length)
           (parachute:is = 0 *census-function-work*))))
      (parachute:is = 0 *complexity-hash-work*)
      (parachute:is = 0 *complexity-equal-work*)
      (parachute:is = 0 *census-index-lookup-work*)
      (parachute:is = 0 *census-protocol-work*)
      (parachute:is = 1 *census-random-access-work*))
    ;; A full public traversal stays linear, without timing or exact-count gates.
    (let* ((dictionary (census-ordered-dict count))
           (*complexity-hash-work* 0)
           (*complexity-equal-work* 0)
           (*census-index-lookup-work* 0)
           (*census-protocol-work* 0)
           (view dictionary)
           (visited 0))
      (loop while (not (sl:seq-emptyp view))
            for entry = (sl:seq-first view)
            do (parachute:true (typep entry 'sl:map-entry))
               (incf visited)
               (setf view (sl:seq-rest view)))
      (parachute:is = count visited)
      (parachute:true (<= *census-protocol-work* (+ (* 4 count) 4)))
      (parachute:true (<= *complexity-hash-work* (* 4 count)))
      (parachute:true (<= *complexity-equal-work* (* 4 count)))
      (parachute:true (<= *census-index-lookup-work* (* 4 count))))))

(parachute:define-test census.container-length-is-non-traversing
  ;; Covers maintained DICT-SIZE/SET-SIZE and the matching SEQ-LENGTH claim.
  (let* ((count 1000)
         (*complexity-hash-work* 0)
         (*complexity-equal-work* 0)
         (dictionary (loop with result = (sl:dict)
                           for i below count
                           do (setf result (sl:dict-set result (complexity-work-key i) i))
                           finally (return result)))
         (set (loop with result = (sl:hash-set)
                    for i below count
                    do (setf result (sl:set-add (complexity-work-key i) result))
                    finally (return result))))
    (let ((*complexity-hash-work* 0)
          (*complexity-equal-work* 0)
          (*census-protocol-work* 0)
          (*census-random-access-work* 0))
      (census-with-function-work
       '(sophie-lisp.internal::trie-next)
       (lambda ()
         (parachute:is = count (sl:seq-length dictionary))
         (parachute:is = count (sl:dict-size dictionary))
         (parachute:is = count (sl:seq-length set))
         (parachute:is = count (sl:set-size set))
         (parachute:is = 0 *census-function-work*)))
      (parachute:is = 0 *complexity-hash-work*)
      (parachute:is = 0 *complexity-equal-work*)
      (parachute:is = 2 *census-random-access-work*)
      (parachute:is = 0 *census-protocol-work*))))

(parachute:define-test census.hash-set-membership-and-add-bounded-work
  (dolist (count '(100 1000 10000))
    (let* ((*complexity-hash-work* 0)
           (*complexity-equal-work* 0)
           (keys (loop for index below count collect (complexity-work-key index)))
           (set (apply #'sl:hash-set keys)))
      (parachute:is = count (sl:set-size set))
      (parachute:true (<= *complexity-hash-work* (* 4 count)))
      (parachute:true (<= *complexity-equal-work* (* 4 count)))
      (let ((*complexity-hash-work* 0)
            (*complexity-equal-work* 0))
        (parachute:true (sl:set-member (complexity-work-key (floor count 2)) set))
        (parachute:true (<= *complexity-hash-work* 8))
        (parachute:true (<= *complexity-equal-work* 8))
        (parachute:false (sl:set-member (complexity-work-key count) set))
        (parachute:true (<= *complexity-hash-work* 8))
        (parachute:true (<= *complexity-equal-work* 8)))
      ;; Generic seqables retain position-bounded traversal rather than hashing.
      (let* ((position (floor count 2))
             (*complexity-hash-work* 0)
             (*complexity-equal-work* 0))
        (parachute:true (sl:set-member (complexity-work-key position) keys))
        (parachute:true (<= *complexity-hash-work* (* 4 (1+ position))))
        (parachute:true (<= *complexity-equal-work* (* 4 (1+ position)))))
      (let ((*complexity-hash-work* 0)
            (*complexity-equal-work* 0))
        (parachute:false (sl:set-member (complexity-work-key count) keys))
        (parachute:true (<= *complexity-hash-work* (* 4 count)))
        (parachute:true (<= *complexity-equal-work* (* 4 count))))
      ;; SET-ADD over an ordinary source materializes a hash-set result.
      (let* ((*complexity-hash-work* 0)
             (*complexity-equal-work* 0)
             (added (sl:set-add (complexity-work-key count) keys)))
        (parachute:true (sl:hash-set-p added))
        (parachute:is = (1+ count) (sl:set-size added))
        (parachute:true (<= *complexity-hash-work* (* 4 (1+ count))))
        (parachute:true (<= *complexity-equal-work* (* 4 (1+ count))))
        (let ((*complexity-hash-work* 0)
              (*complexity-equal-work* 0))
          (parachute:true (sl:set-member (complexity-work-key count) added))
          (parachute:true (<= *complexity-hash-work* 8))
          (parachute:true (<= *complexity-equal-work* 8)))))))
