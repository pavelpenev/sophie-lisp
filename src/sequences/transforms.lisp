;;;; Element-changing sequence operations; each stream owns its retained views.
(in-package #:sophie-lisp.internal)

(defun concrete-source-p (source)
  "Whether SOURCE is a concrete list or vector, independent of traversal mode."
  (or (listp source) (vectorp source)))

(defun eager-direct-source-p (source)
  "Only eager built-ins whose cursor can bypass the generic view protocol."
  (and (not *force-generic-traversal*)
       (concrete-source-p source)))

(defun map-common-p (sources)
  (policy-common-p sources 'sl:seq-map))

(defun map-materialize (source operation stream &optional lazy-result)
  (let ((items nil))
    (loop
     (multiple-value-bind (empty element rest) (view-step stream)
       (when empty
         (return (if lazy-result
                     (open-view (nreverse items))
                     (policy-reconstruct source operation (nreverse items)))))
       (push element items)
       (setf stream rest)))))

(defun map-lockstep (function sources)
  (let ((slots (mapcar (lambda (source) (cons nil source)) sources)))
    (labels ((produce ()
               (let ((arguments nil) (tails nil))
                 (dolist (slot slots)
                   (unless (car slot)
                     ;; Defer each opening until its turn; retain the raw source
                     ;; if opening fails, so a subsequent demand retries it.
                     (setf (cdr slot) (make-view-cursor (cdr slot))
                           (car slot) t))
                   (multiple-value-bind (empty element rest)
                       (view-cursor-step (cdr slot))
                     (when empty (return-from produce nil))
                     (push element arguments)
                     (push rest tails)))
                 (let ((value (apply function (nreverse arguments))))
                   ;; A failed callback leaves all cursors at this tuple.
                   (loop for slot in slots for tail in (nreverse tails)
                         do (view-cursor-advance (cdr slot) tail))
                   (sl:lazy-cons value (sl:make-lazy-seq #'produce))))))
      (sl:make-lazy-seq #'produce))))

(defun map-unary-stream (function source-or-cursor mode &optional deferred-p)
  "Map a source with a deferred cursor when requested. Deferred opening
preserves SEQ-MAP open-at-first-demand semantics."
  (let ((index 0) (inner nil) (inner-p nil)
        (cursor (unless deferred-p source-or-cursor))
        (cursor-ready-p (not deferred-p))
        (callback-result nil) (stage :source))
    (labels ((produce ()
               (loop
                (unless cursor-ready-p
                  ;; SEQ-MAP opens each source at first demand, not at call time.
                  (setf cursor (make-view-cursor source-or-cursor)
                        cursor-ready-p t))
                (when (eq stage :open)
                  ;; Keep a successful callback result across a failed opening.
                  ;; This mirrors TREE-SEQ's staged callback/open protocol.
                  ;; Preserve OPEN-VIEW's SEQABLEP dispatch for user methods.
                  (when (and *force-generic-traversal*
                             (concrete-source-p callback-result))
                    (require-seqable callback-result))
                  (setf inner (make-view-cursor callback-result)
                        inner-p t
                        stage :source))
                (when inner-p
                  (multiple-value-bind (empty element rest) (view-cursor-step inner)
                    (unless empty
                      (view-cursor-advance inner rest)
                      (return (sl:lazy-cons element (sl:make-lazy-seq #'produce))))
                    (setf inner-p nil)))
                (multiple-value-bind (empty element rest) (view-cursor-step cursor)
                  (when empty (return nil))
                  (let ((value (if (eq mode :indexed)
                                   (funcall function index element)
                                   (funcall function element))))
                    (view-cursor-advance cursor rest)
                    (if (eq mode :cat)
                        (progn
                          (setf callback-result value
                                stage :open))
                        (progn
                          (incf index)
                          (unless (and (eq mode :keep) (null value))
                            (return (sl:lazy-cons value (sl:make-lazy-seq #'produce)))))))))))
      (sl:make-lazy-seq #'produce))))

(defmethod sl:seq-map (function (sequence t) &rest more-sequences)
  (usable-function function)
  ;; Concrete sources open in DO-VIEW-ELEMENTS or MAKE-VIEW-CURSOR; keep the
  ;; non-concrete call-time check and the forced-generic control unchanged.
  (when (or *force-generic-traversal* (not (concrete-source-p sequence)))
    (require-seqable sequence))
  (if (and (null more-sequences) (eager-direct-source-p sequence))
      (let ((items nil))
        (do-view-elements (element sequence)
          (push (funcall function element) items))
        (policy-reconstruct sequence 'sl:seq-map (nreverse items)))
      (let* ((sources (cons sequence more-sequences))
             ;; Defer the traversal-mode flag to MAKE-VIEW-CURSOR at first demand
             ;; so the generic-path test seam still works.
             (stream (if (and (null more-sequences)
                              (concrete-source-p sequence))
                         (map-unary-stream function sequence :map t)
                         (map-lockstep function sources))))
        ;; Mixed concrete types change representation, not call-time effects.
        (if (every (lambda (source)
                     (not (eq :lazy (policy-kind source 'sl:seq-map)))) sources)
            (map-materialize sequence 'sl:seq-map stream (not (map-common-p sources)))
            stream))))

(defmethod sl:seq-map-indexed (function (sequence t))
  (usable-function function)
  (if (eager-direct-source-p sequence)
      (let ((items nil))
        (do-view-elements (element sequence :index index)
          (push (funcall function index element) items))
        (policy-reconstruct sequence 'sl:seq-map-indexed (nreverse items)))
      (let ((stream (map-unary-stream function (make-view-cursor sequence) :indexed)))
        (if (policy-eager-p sequence 'sl:seq-map-indexed)
            (map-materialize sequence 'sl:seq-map-indexed stream) stream))))

(defmethod sl:seq-keep (function (sequence t))
  (usable-function function)
  (if (eager-direct-source-p sequence)
      (let ((items nil))
        (do-view-elements (element sequence)
          (let ((value (funcall function element)))
            (when value (push value items))))
        (policy-reconstruct sequence 'sl:seq-keep (nreverse items)))
      (let ((stream (map-unary-stream function (make-view-cursor sequence) :keep)))
        (if (policy-eager-p sequence 'sl:seq-keep)
            (map-materialize sequence 'sl:seq-keep stream) stream))))

(defmethod sl:seq-mapcat (function (sequence t))
  (usable-function function)
  (if (eager-direct-source-p sequence)
      (let ((items nil))
        (do-view-elements (element sequence)
          (let ((inner (funcall function element)))
            ;; The inner traversal opens after the completed callback.
            (do-view-elements (value inner)
              (push value items))))
        (policy-reconstruct sequence 'sl:seq-mapcat (nreverse items)))
      (let ((stream (map-unary-stream function (make-view-cursor sequence) :cat)))
        (if (policy-eager-p sequence 'sl:seq-mapcat)
            (map-materialize sequence 'sl:seq-mapcat stream) stream))))

(defun multi-common-p (sources operation)
  (policy-common-p sources operation))

(defun multi-finish (sources operation stream)
  (if (every (lambda (source) (not (eq :lazy (policy-kind source operation))))
             sources)
      (let ((items nil))
        (loop
         (multiple-value-bind (empty element rest) (view-step stream)
           (when empty
             (return (if (multi-common-p sources operation)
                         (policy-reconstruct (car sources) operation (nreverse items))
                         (open-view (nreverse items)))))
           (push element items) (setf stream rest))))
      stream))

(defmethod sl:seq-concatenate ((sequence t) &rest more-sources)
  (require-seqable sequence)
  (let* ((sources (cons sequence more-sources))
         (pending sources) (view nil) (active nil))
    (labels ((produce ()
               (loop
                (unless active
                  (unless pending (return nil))
                  (setf view (open-view (car pending)) active t
                        pending (cdr pending)))
                (multiple-value-bind (empty element rest) (view-step view)
                  (if empty
                      (setf active nil)
                      (progn
                        (setf view rest)
                        (return (sl:lazy-cons element (sl:make-lazy-seq #'produce)))))))))
      (multi-finish sources 'sl:seq-concatenate (sl:make-lazy-seq #'produce)))))

(defmethod sl:seq-interleave (&rest sources)
  (when (null sources) (return-from sl:seq-interleave nil))
  (let ((slots (mapcar (lambda (source) (cons nil source)) sources))
        (round nil))
    (labels ((produce ()
               (unless round
                 (let ((items nil) (tails nil))
                   (dolist (slot slots)
                     (unless (car slot)
                       (setf (cdr slot) (make-view-cursor (cdr slot))
                             (car slot) t))
                     (multiple-value-bind (empty element rest)
                         (view-cursor-step (cdr slot))
                       (when empty (return-from produce nil))
                       (push element items)
                       (push rest tails)))
                   (setf round (nreverse items))
                   (loop for slot in slots for tail in (nreverse tails)
                         do (view-cursor-advance (cdr slot) tail))))
               (sl:lazy-cons (pop round) (sl:make-lazy-seq #'produce))))
      (multi-finish sources 'sl:seq-interleave (sl:make-lazy-seq #'produce)))))

(defun substitute-result (source operation newitem match key start end count from-end)
  (check-region-bounds start end end)
  (policy-count count)
  (let ((view (open-view source)) (index 0) (key-ready nil) keyed
        (buffer nil) (prepared nil))
    (labels
        ((matchesp (element)
           ;; A successful KEY survives a failed matching callback.
           (unless key-ready
             (setf keyed (funcall key element) key-ready t))
           (funcall match keyed))
         (advance (rest)
           (setf view rest key-ready nil)
           (incf index))
         (check-end ()
           (when (< index start) (raise-type-error start `(integer 0 ,index))))
         (tail-stream ()
           (sl:make-lazy-seq
            (lambda ()
              (multiple-value-bind (empty element rest) (view-step view)
                (if empty
                    (progn (check-end) nil)
                    (let* ((selected (and (>= index start) (or (null end) (< index end))
                                          (or (null count) (plusp count))))
                           (replace (and selected (matchesp element)))
                           (value (if replace newitem element)))
                      (when (and replace count) (decf count))
                      (advance rest)
                      (sl:lazy-cons value (tail-stream))))))))
         (prepare ()
           ;; Last-match selection forces only through END, not the suffix.
           ;; Commit every successfully classified position before the next force.
           (unless prepared
             (loop
              (when (and end (>= index end)) (return))
              (multiple-value-bind (empty element rest) (view-step view)
                (when empty (check-end) (return))
                (let ((replace (and (>= index start) (matchesp element))))
                  (push (cons element replace) buffer)
                  (advance rest))))
             (let ((remaining count) (items nil))
               (dolist (entry buffer)
                 (push (if (and (cdr entry) (plusp remaining))
                           (progn (decf remaining) newitem)
                           (car entry))
                       items))
               (setf buffer items prepared t count 0))))
         (buffer-stream ()
           (sl:make-lazy-seq
            (lambda ()
              (prepare)
              (if buffer
                  (let ((element (pop buffer)))
                    (sl:lazy-cons element (buffer-stream)))
                  (tail-stream)))))
         (materialize (stream)
           (loop with items = nil
                 do (multiple-value-bind (empty element rest) (view-step stream)
                      (when empty (return (nreverse items)))
                      (push element items)
                      (setf stream rest)))))
      (let ((result (if (and from-end count (plusp count))
                        (buffer-stream) (tail-stream))))
        (if (policy-eager-p source operation)
            (policy-reconstruct source operation (materialize result))
            result)))))

(defmethod sl:seq-substitute (newitem olditem (source t)
                              &rest options &key (test #'sl:equals) key (start 0)
                                end from-end count)
  (validate-collector-options options '(:test :key :start :end :from-end :count))
  (usable-function test)
  (let ((key (policy-key key)))
    (substitute-result source 'sl:seq-substitute newitem
                       (lambda (value) (funcall test olditem value))
                       key start end count from-end)))

(defmethod sl:seq-substitute-if (newitem predicate (source t)
                                 &rest options &key key (start 0) end from-end count)
  (validate-collector-options options '(:key :start :end :from-end :count))
  (usable-function predicate)
  (substitute-result source 'sl:seq-substitute-if newitem predicate
                     (policy-key key) start end count from-end))
