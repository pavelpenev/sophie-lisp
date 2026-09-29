;;;; Internal eager traversal; *force-generic-traversal* is a per-traversal test seam.
;;;; Use DO-VIEW-ELEMENTS for synchronous whole-source drains; view cursors for
;;;; resumable/deferred steps (commit after callback); direct-build dispatch for
;;;; eager-policy results; generic OPEN-VIEW for all other sources.

(in-package #:sophie-lisp.internal)

(defvar *force-generic-traversal* nil
  "Test-only switch: route eager traversals and cursors through OPEN-VIEW/VIEW-STEP.")

(defstruct (view-cursor (:constructor allocate-view-cursor (kind current index end)))
  kind current index end)

(defun make-view-cursor (source)
  "Retain one source view; stepping does not commit until VIEW-CURSOR-ADVANCE."
  (cond
    (*force-generic-traversal*
     (allocate-view-cursor :generic (open-view source) 0 nil))
    ((listp source)
     ;; Defensive: built-in lists and vectors are always seqable.
     (require-seqable source)
     (allocate-view-cursor :list source 0 nil))
    ((vectorp source)
     (require-seqable source)
     (allocate-view-cursor :vector source 0 (active-vector-end source)))
    (t (allocate-view-cursor :generic (open-view source) 0 nil))))

(defun view-cursor-step (cursor)
  "Return EMPTY-P, ELEMENT, and the next position, without committing it."
  (case (view-cursor-kind cursor)
    (:list
     (let ((tail (view-cursor-current cursor)))
       (if (null tail)
           (values t nil nil)
           (progn
             (unless (listp tail) (raise-type-error tail 'list))
             (values nil (car tail) (cdr tail))))))
    (:vector
     (let ((index (view-cursor-index cursor)))
       (if (= index (view-cursor-end cursor))
           (values t nil nil)
           (values nil (aref (view-cursor-current cursor) index) (1+ index)))))
    (:generic (view-step (view-cursor-current cursor)))))

(defun view-cursor-advance (cursor rest)
  "Commit REST only after the consumer's callback has succeeded."
  (if (eq :vector (view-cursor-kind cursor))
      (setf (view-cursor-index cursor) rest)
      (setf (view-cursor-current cursor) rest)))

(defmacro do-view-elements ((element source &key index (start 0) end (result nil))
                            &body body)
  "Visit SOURCE in order, binding ELEMENT and optional absolute INDEX.
RETURN in BODY exits the traversal. RESULT is evaluated on normal completion.
START must be reachable even when START equals END. No next element is
observed before BODY runs; only consumer-owned eager views are bypassed."
  (let ((sequence (gensym "SOURCE-"))
        (begin (gensym "START-"))
        (limit (gensym "END-"))
        (generic-p (gensym "GENERIC-"))
        (position (gensym "POSITION-"))
        (tail (gensym "TAIL-"))
        (next (gensym "NEXT-"))
        (view (gensym "VIEW-"))
        (rest (gensym "REST-"))
        (empty-p (gensym "EMPTY-"))
        (vector-end (gensym "VECTOR-END-"))
        (body-index (or index (gensym "INDEX-"))))
    (when (and index (not (symbolp index)))
      (raise-program-error "DO-VIEW-ELEMENTS :INDEX must be a variable: ~S" index))
    (let* ((declarations (loop for form in body
                               while (and (consp form) (eq (car form) 'declare))
                               collect form))
           (forms (nthcdr (length declarations) body)))
      `(let* ((,sequence ,source)
              (,begin ,start)
              (,limit ,end)
              (,generic-p *force-generic-traversal*))
         (check-seq-index ,begin)
         (when ,limit
           (check-seq-index ,limit)
           (when (< ,limit ,begin)
             (raise-type-error ,limit `(integer ,,begin *))))
         (cond
           ((and (not ,generic-p) (listp ,sequence))
            (require-seqable ,sequence)
            (loop with ,tail = ,sequence
                  for ,position from 0
                  do (when (and ,limit (>= ,position ,limit)
                                (>= ,position ,begin))
                       (return ,result))
                     (when (null ,tail)
                       (when (< ,position ,begin)
                         (raise-type-error ,begin `(integer 0 ,,position)))
                       (return ,result))
                     (unless (listp ,tail) (raise-type-error ,tail 'list))
                     (let ((,next (cdr ,tail)))
                       (if (< ,position ,begin)
                           (setf ,tail ,next)
                           (let ((,element (car ,tail))
                                 (,body-index ,position))
                             (declare (ignorable ,element ,body-index))
                             ,@declarations
                             (setf ,tail ,next)
                             ,@forms)))))
           ((and (not ,generic-p) (vectorp ,sequence))
            (require-seqable ,sequence)
            (let ((,vector-end (active-vector-end ,sequence)))
              (when (> ,begin ,vector-end)
                (raise-type-error ,begin `(integer 0 ,,vector-end)))
              (loop for ,position from ,begin
                    do (when (and ,limit (>= ,position ,limit))
                         (return ,result))
                       (when (= ,position ,vector-end)
                         (return ,result))
                       (let ((,element (aref ,sequence ,position))
                             (,body-index ,position))
                         (declare (ignorable ,element ,body-index))
                         ,@declarations
                         ,@forms))))
           (t
            (loop with ,view = (open-view ,sequence)
                  for ,position from 0
                  do (when (and ,limit (>= ,position ,limit)
                                (>= ,position ,begin))
                       (return ,result))
                     (multiple-value-bind (,empty-p ,element ,rest)
                         (view-step ,view)
                       (declare (ignorable ,element))
                       ,@declarations
                       (when ,empty-p
                         (when (< ,position ,begin)
                           (raise-type-error ,begin `(integer 0 ,,position)))
                         (return ,result))
                       (setf ,view ,rest)
                       (when (>= ,position ,begin)
                         (let ((,body-index ,position))
                           (declare (ignorable ,body-index))
                           ,@forms))))))))))
