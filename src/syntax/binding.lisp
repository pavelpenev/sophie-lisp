;;;; Sequential and conditional binding, using the shared opaque pattern compiler.
(in-package #:sophie-lisp.internal)

(defun binding-syntax-list (syntax)
  (unless (and (listp syntax)
               (handler-case (list-length syntax) (type-error () nil)))
    (raise-program-error "Expected a finite proper binding syntax list."))
  syntax)

(defstruct (binding-clause (:constructor make-binding-clause
                               (kind expression patterns &optional keys)))
  kind expression patterns keys)

(defun binding-variable-pattern (name)
  ;; NIL is an empty pattern, but is never an access or multiple-value variable.
  (unless (and name (symbolp name))
    (raise-program-error "Expected a binding variable."))
  (parse-pattern name :bind))

(defun parse-binding-clause (syntax)
  (binding-syntax-list syntax)
  (let* ((arity (length syntax))
         (marker (second syntax))
         (marker-name (and (symbolp marker) (symbol-name marker))))
    (cond
      ((member marker-name '("?" "@") :test #'equal)
       (unless (and (= arity 3)
                    (eq marker (if (equal marker-name "?") 'sl:? 'sl:@)))
         (raise-program-error "Malformed or foreign binding marker."))
       (binding-syntax-list (first syntax))
       (let ((patterns nil) (keys nil))
         (dolist (access (first syntax))
           (cond
             ((symbolp access)
              (let ((pattern-node (binding-variable-pattern access)))
                ;; Only a bare underscore suppresses the access itself.
                (unless (string= (symbol-name access) "_")
                  (push pattern-node patterns)
                  (push access keys))))
             (t
              (binding-syntax-list access)
              (unless (= (length access) 2)
                (raise-program-error "Malformed access binding."))
              (push (binding-variable-pattern (first access)) patterns)
              (push (second access) keys))))
         (make-binding-clause (if (eq marker 'sl:?) :ref :slot)
                               (third syntax) (nreverse patterns) (nreverse keys))))
      ((= arity 2)
       (make-binding-clause :pattern (second syntax)
                             (list (parse-pattern (first syntax) :bind))))
      ((>= arity 3)
       (make-binding-clause :values (car (last syntax))
                             (mapcar #'binding-variable-pattern (butlast syntax))))
      (t (raise-program-error "Malformed binding clause.")))))

(defun binding-clauses (syntax shortcut-p)
  (binding-syntax-list syntax)
  (mapcar #'parse-binding-clause
          (if (and shortcut-p (= (length syntax) 2) (symbolp (first syntax)))
              (list syntax)
              syntax)))

(defun compile-binding-clause (clause continuation declarations failure-block)
  (let* ((patterns (binding-clause-patterns clause))
         (kind (binding-clause-kind clause))
         (subject (gensym "SUBJECT-"))
         (temporaries (if (eq kind :values)
                          (mapcar (lambda (pattern-node) (declare (ignore pattern-node))
                                    (gensym "VALUE-"))
                                  patterns)
                          (list subject)))
         (body continuation))
    (labels ((apply-pattern (pattern-node value next)
               (compile-pattern pattern-node value next :context :bind
                                :bound-declaration-map declarations)))
      (case kind
        (:pattern (setf body (apply-pattern (first patterns) subject body)))
        (:values
         (loop for pattern-node in (reverse patterns)
               for value in (reverse temporaries)
               do (setf body (apply-pattern pattern-node value body))))
        ((:ref :slot)
         (loop for pattern-node in (reverse patterns)
               for key in (reverse (binding-clause-keys clause))
               for value = (gensym "ACCESS-")
               do (setf body
                        `(let ((,value (,(if (eq kind :ref) 'sl:ref 'slot-value)
                                        ,subject ',key)))
                           (declare (ignorable ,value))
                           ,(apply-pattern pattern-node value body))))))
      ;; Test the captured primary value before any pattern, binding, or access.
      (when failure-block
        (setf body `(if ,(first temporaries) ,body
                       (return-from ,failure-block nil))))
      (if (eq kind :values)
          `(multiple-value-bind ,temporaries ,(binding-clause-expression clause)
             (declare (ignorable ,@temporaries))
             ,body)
          `(let ((,subject ,(binding-clause-expression clause)))
             (declare (ignorable ,subject))
             ,body)))))

(defun expand-bindings (syntax forms conditional-p &optional else-form)
  (let ((clauses (binding-clauses syntax conditional-p)))
    (multiple-value-bind (declarations body-forms) (parse-leading-declarations forms)
      (multiple-value-bind (map free)
          (classify-declarations
           declarations
           (loop for clause in clauses append
                 (loop for pattern-node in (binding-clause-patterns clause)
                       append (pattern-bound-names pattern-node))))
        (let* ((success (and conditional-p (gensym "SUCCESS-")))
               (failure (and conditional-p (gensym "FAILURE-")))
               (body (emit-declared-body free body-forms)))
          (when conditional-p (setf body `(return-from ,success ,body)))
          (dolist (clause (reverse clauses))
            (setf body (compile-binding-clause clause body map failure)))
          ;; Failure leaves every clause's lexical and dynamic scope before ELSE.
          ;; The success exit carries exactly the body's values, including zero.
          (if conditional-p
              `(block ,success (block ,failure ,body) ,else-form)
              body))))))

(defmacro sl:bind (&rest arguments)
  "Sequential LET*-style binding with Sophie patterns. Each clause binds a
variable, pattern, or multiple-value form; marker clauses obtain values with
SL:REF (?) or SLOT-VALUE (@). Malformed clause or pattern syntax, invalid
binding variables, or misplaced markers signal PROGRAM-ERROR at
macro-expansion time."
  (binding-syntax-list arguments)
  (unless arguments (raise-program-error "BIND requires a clause list."))
  (expand-bindings (first arguments) (rest arguments) nil))

(defmacro sl:when-bind (&rest arguments)
  "Conditional binding: test each clause's primary value, bind and evaluate the
body if all are true. Returns NIL if any test fails. Malformed clause or
pattern syntax, invalid binding variables, or misplaced markers signal
PROGRAM-ERROR at macro-expansion time."
  (binding-syntax-list arguments)
  (unless arguments (raise-program-error "WHEN-BIND requires clauses."))
  (expand-bindings (first arguments) (rest arguments) t))

(defmacro sl:if-bind (&rest arguments)
  "Conditional binding: test each clause's primary value, bind and evaluate the
then-form if all are true. Evaluate the optional ELSE form (default NIL) with
no bindings if any test fails. Malformed clause or pattern syntax, invalid
binding variables, or misplaced markers signal PROGRAM-ERROR at
macro-expansion time."
  (binding-syntax-list arguments)
  (unless (<= 2 (length arguments) 3)
    (raise-program-error "IF-BIND requires clauses, a then form, and optionally an else form."))
  ;; A branch is an ordinary expression, never a declaration-body prefix.
  (expand-bindings (first arguments) (list `(progn ,(second arguments)))
                    t (third arguments)))

(defmacro sl:doseq (binding &body body)
  "Traverse a seqable SOURCE with either (PATTERN SOURCE) or ((PATTERN INDEX)
SOURCE) bindings. There is no result-form position; normal completion returns
NIL, while RETURN exits the implicit NIL block explicitly. A non-seqable
source signals TYPE-ERROR; malformed syntax or an invalid pattern signals
PROGRAM-ERROR."
  (pattern-proper-list binding)
  (unless (= (length binding) 2)
    (raise-program-error "DOSEQ requires (pattern source), without a result form."))
  (let* ((syntax (first binding))
         (indexed (and (consp syntax) (consp (cdr syntax))
                       (null (cddr syntax)) (symbolp (second syntax))))
         (index (and indexed (second syntax)))
         (pattern (parse-pattern (if indexed (first syntax) syntax) :doseq))
         (cursor (gensym "CURSOR-"))
         (element (gensym "ELEMENT-"))
         (empty-p (gensym "EMPTY-"))
         (rest (gensym "REST-"))
         (position (gensym "POSITION-"))
         (again (gensym "AGAIN-")))
    ;; The index is a variable, not an element pattern (including when named _).
    (when indexed
      (let ((*pattern-plain-variables* t)) (pattern-variable index)))
    (multiple-value-bind (declarations forms) (parse-leading-declarations body)
      (multiple-value-bind (bound free)
          (classify-declarations declarations
                                 (append (pattern-bound-names pattern)
                                         (when indexed (list index))))
        (let ((iteration (emit-declared-body free (list `(tagbody ,@forms)))))
          (when indexed
            (setf iteration
                  `(let ((,index ,position))
                     ,@(when (gethash index bound)
                         `((declare ,@(gethash index bound))))
                     ,iteration)))
          (setf iteration (compile-pattern pattern element iteration
                                          :context :doseq
                                          :bound-declaration-map bound))
          `(block nil
             ;; Resolve the frozen private traversal boundary through external
             ;; CL operators, without exposing a private operator in expansion.
             (let ((,cursor (funcall
                             (load-time-value (symbol-function 'make-view-cursor) t)
                             ,(second binding)))
                   ,@(when indexed `((,position 0))))
               (tagbody
                  ,again
                  (multiple-value-bind (,empty-p ,element ,rest)
                      (funcall (load-time-value (symbol-function 'view-cursor-step) t)
                               ,cursor)
                    (declare (ignorable ,element))
                    (when ,empty-p (return nil))
                    ,iteration
                    ;; Commit the step only after the body succeeds: RETURN,
                    ;; THROW and outer GO never demand another position.
                    (funcall (load-time-value (symbol-function 'view-cursor-advance) t)
                             ,cursor ,rest))
                  ,@(when indexed `((incf ,position)))
                  (go ,again)))))))))
