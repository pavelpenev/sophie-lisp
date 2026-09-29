;;;; Function-composition utilities.

(in-package #:sophie-lisp.internal)

(defun resolve-function-designator (designator)
  "Resolve a retained designator at the point at which it is invoked."
  (cond
    ((functionp designator)
     designator)
    ((symbolp designator)
     (when (or (macro-function designator)
               (special-operator-p designator))
       (raise-type-error designator '(or function symbol)))
     ;; FDEFINITION deliberately supplies the specified UNDEFINED-FUNCTION
     ;; condition when a previously valid symbol has since become unbound.
     (fdefinition designator))
    (t
     (raise-type-error designator '(or function symbol)))))

(defun sl:juxt (&rest functions)
  "Return a function that calls FUNCTIONS left to right on its arguments. The
result is a list of their primary values. With no functions, the result
function returns an empty list. Symbol designators are resolved at invocation
time. A non-designator or macro/special-operator name signals TYPE-ERROR at
invocation; an unbound symbol signals UNDEFINED-FUNCTION."
  (let ((designators functions))
    (lambda (&rest arguments)
      (loop for designator in designators
            collect (apply (resolve-function-designator designator)
                           arguments)))))

(defun sl:compose (&rest functions)
  "Return the right-associative composition of FUNCTIONS. With no functions,
return #'IDENTITY; with one, return a function that invokes it. The rightmost
function receives the arguments, and each function to its left receives the
preceding primary value. The leftmost function, applied last, returns all its
values. Symbol designators are resolved at invocation time. A non-designator
or macro/special-operator name signals TYPE-ERROR at invocation; an unbound
symbol signals UNDEFINED-FUNCTION."
  (let ((designators functions))
    (cond
      ((null designators)
       #'identity)
      ((null (cdr designators))
       (let ((designator (car designators)))
         (if (functionp designator)
             (lambda (&rest arguments) (apply designator arguments))
             (lambda (&rest arguments)
               (apply (resolve-function-designator designator) arguments)))))
      (t
       (let ((first-designator (car designators))
             (last-designator (car (last designators)))
             ;; The middle functions are applied from right to left, after
             ;; LAST-DESIGNATOR and before FIRST-DESIGNATOR.
             (middle-designators (reverse (butlast (rest designators)))))
         (if (every #'functionp designators)
             ;; Function objects are stable. Symbols must still resolve at
             ;; invocation, so they take the original late-resolution path.
             (lambda (&rest arguments)
               (let ((value (apply last-designator arguments)))
                 (dolist (function middle-designators)
                   (setf value (funcall function value)))
                 (funcall first-designator value)))
             (lambda (&rest arguments)
               (let ((value
                       (apply (resolve-function-designator last-designator)
                              arguments)))
                 (dolist (designator middle-designators)
                   (setf value
                         (funcall (resolve-function-designator designator)
                                  value)))
                 (funcall (resolve-function-designator first-designator)
                          value)))))))))

(defmacro sl:fbind (&optional (bindings nil bindings-p) &body body)
  "Establish local functions from (NAME FUNCTION-EXPRESSION) bindings.
Function expressions evaluate eagerly from left to right, and the body returns
its final form's values. Malformed bindings, duplicate or invalid names,
non-function values, and premature local calls signal PROGRAM-ERROR."
  (unless bindings-p (raise-program-error "FBIND requires a binding list."))
  (pattern-proper-list bindings)
  (let ((names nil) (cells nil) (definitions nil) (initializers nil))
    (dolist (binding bindings)
      (pattern-proper-list binding)
      (unless (= (length binding) 2)
        (raise-program-error "FBIND requires (name function-expression) bindings."))
      (let ((name (first binding))
            (cell (gensym "FUNCTION-"))
            (arguments (gensym "ARGUMENTS-"))
            (value (gensym "VALUE-")))
        (unless (and (symbolp name) name (not (constantp name)))
          (raise-program-error "Invalid FBIND function name ~S." name))
        (when (member name names :test #'eq)
          (raise-program-error "Duplicate FBIND function name ~S." name))
        (push name names)
        ;; NIL cannot be an established function, so it also marks unreadiness.
        (push `(,cell nil) cells)
        (push `(,name (&rest ,arguments)
                 (unless ,cell (error 'program-error))
                 (apply ,cell ,arguments))
              definitions)
        (push `(let ((,value ,(second binding)))
                 (unless (functionp ,value) (error 'program-error))
                 (setq ,cell ,value))
              initializers)))
    (multiple-value-bind (declarations forms) (parse-leading-declarations body)
      ;; FLET installs every forwarding closure before any source expression.
      ;; Its definitions use only private cells; recursion in source closures
      ;; resolves normally through these lexical function bindings. Body-only
      ;; declarations must not leak into the computed function expressions.
      `(let ,(nreverse cells)
         (flet ,(nreverse definitions)
           ,@(nreverse initializers)
           ,(emit-declared-body declarations forms))))))

(defmacro sl:fn (&optional (parameter-list nil parameters-p) &body body)
  "Return a function with a parameter list whose required positions may be patterns.
The body returns its final form's values. A missing parameter list or body, or
invalid pattern or lambda-list syntax, signals PROGRAM-ERROR."
  (unless parameters-p (raise-program-error "FN requires a parameter list."))
  (multiple-value-bind (declarations forms) (parse-leading-declarations body)
    `(function ,(compile-pattern-lambda-list parameter-list declarations forms))))

(defun threading-proper-list-p (object)
  "Return true only for a finite proper list, including NIL."
  (loop with slow = object
        with fast = object
        do (cond
             ((null fast) (return t))
             ((atom fast) (return nil))
             ((null (cdr fast)) (return t))
             ((atom (cdr fast)) (return nil))
             (t
              (setf slow (cdr slow)
                    fast (cddr fast))
              (when (eq slow fast)
                (return nil))))))

(defun threading-valid-operator-p (operator)
  (and (symbolp operator)
       (not (null operator))
       (not (keywordp operator))))

(defun threading-invalid-step (step)
  (let ((*print-circle* t)
        (*print-level* 8)
        (*print-length* 16))
    (raise-program-error "Invalid threading step: ~A" (format nil "~S" step))))

(defun threading-call-form (step)
  (cond
    ((threading-valid-operator-p step)
     (list step))
    ((and (consp step)
          (threading-proper-list-p step)
          (threading-valid-operator-p (car step)))
     (copy-list step))
    (t
     (threading-invalid-step step))))

(defun threading-first-step (value step)
  (let ((call (threading-call-form step)))
    (cons (car call) (cons value (cdr call)))))

(defun threading-last-step (value step)
  (let ((call (threading-call-form step)))
    (append (list (car call)) (cdr call) (list value))))

(defun threading-marker-name-p (symbol)
  (and (symbolp symbol)
       (or (string= (symbol-name symbol) "?")
           (string= (symbol-name symbol) "@"))))

(defun threading-valid-binding-variable-p (variable)
  (and (symbolp variable)
       (not (null variable))
       (not (eq variable t))
       (not (keywordp variable))
       (not (threading-marker-name-p variable))
       (not (constantp variable))))

(defun threading-replace-hole (value step)
  (let ((call
          (if (threading-valid-operator-p step)
              (list step 'sl:<>)
              (threading-call-form step))))
    (let ((arguments (copy-list (cdr call))))
      (unless (= (count 'sl:<> arguments :test #'eq) 1)
        (raise-program-error "Threading step must contain exactly one SL:<> hole."))
      (cons (car call)
            (mapcar (lambda (argument)
                      (if (eq argument 'sl:<>) value argument))
                    arguments)))))

(defmacro sl:-> (form &rest steps)
  "Thread FORM into the first argument of each STEP. A malformed step signals
PROGRAM-ERROR at macro-expansion time."
  (reduce #'threading-first-step steps :initial-value form))

(defmacro sl:->> (form &rest steps)
  "Thread FORM into the last argument of each STEP. A malformed step signals
PROGRAM-ERROR at macro-expansion time."
  (reduce #'threading-last-step steps :initial-value form))

(defmacro sl:as-> (form variable &rest steps)
  "Bind VARIABLE to FORM, then successively to the primary value of each
intermediate step; the final step's values are returned. An invalid VARIABLE
or no step signals PROGRAM-ERROR at macro-expansion time."
  (unless (threading-valid-binding-variable-p variable)
    (raise-program-error
     "AS-> variable must be a non-constant, non-keyword symbol other than T, ?, or @."))
  (unless steps
    (raise-program-error "AS-> requires at least one step."))
  `(cl:let* ((,variable ,form)
             ,@(loop for step in (butlast steps)
                     collect `(,variable ,step)))
     ,(car (last steps))))

(defmacro sl:~> (form &rest steps)
  "Thread FORM through the direct SL:<> hole of each STEP. A malformed step
signals PROGRAM-ERROR at macro-expansion time."
  (reduce (lambda (value step)
            (threading-replace-hole value step))
          steps
          :initial-value form))
