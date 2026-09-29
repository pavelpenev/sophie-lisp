(in-package #:sophie-lisp.tests)

(parachute:define-test function-utilities.juxt-result-order
  (let ((events nil))
    (flet ((function-one (left right)
             (push (list :one left right) events)
             (values :one :discarded))
           (function-two (left right)
             (push (list :two left right) events)
             (values :two :discarded)))
      (parachute:is equal '(:one :two)
                    (funcall (sophie-lisp:juxt #'function-one #'function-two)
                             :left :right))
      (parachute:is equal
                    '((:one :left :right) (:two :left :right))
                    (nreverse events)))))

(parachute:define-test function-utilities.juxt-empty
  (parachute:is eq nil
                (funcall (sophie-lisp:juxt) :first :second))
  (parachute:is equal '(nil)
                (multiple-value-list
                 (funcall (sophie-lisp:juxt) 1 2 3))))

(parachute:define-test function-utilities.compose-identity-and-order
  (parachute:is eql :identity
                (funcall (sophie-lisp:compose) :identity))
  ;; FUNCALL arguments contribute only their primary value to IDENTITY.
  (parachute:is equal '(:first)
                (multiple-value-list
                 (funcall (sophie-lisp:compose)
                          (values :first :second))))
  (let ((called nil))
    (let ((function (lambda (value)
                      (setf called value)
                      (values value :extra))))
      (parachute:is equal '(5 :extra)
                    (multiple-value-list
                     (funcall (sophie-lisp:compose function) 5)))
      (parachute:is = 5 called)))
  (let ((events nil))
    (flet ((rightmost (left right)
             (push (list :rightmost left right) events)
             (values (+ left right) :right-extra))
           (middle (value)
             (push (list :middle value) events)
             (values (* value 2) :middle-extra))
           (leftmost (value)
             (push (list :leftmost value) events)
             (values (1- value) :left-extra)))
      (parachute:is equal '(9 :left-extra)
                    (multiple-value-list
                     (funcall (sophie-lisp:compose #'leftmost
                                                   #'middle
                                                   #'rightmost)
                              2 3)))
      (parachute:is equal
                    '((:rightmost 2 3) (:middle 5) (:leftmost 10))
                    (nreverse events)))))

(parachute:define-test function-utilities.compose-fast-and-mixed-designators
  (let ((calls nil))
    (let ((composed (sl:compose (lambda (value)
                                  (push :left calls)
                                  (values value :extra))
                                (lambda (value)
                                  (push :right calls)
                                  (values value :discarded)))))
      (parachute:is equal '(42 :extra)
                    (multiple-value-list (funcall composed 42)))
      (parachute:is equal '(:right :left) (reverse calls))))
  (let ((name (gensym "COMPOSE-MIXED-")))
    (unwind-protect
         (let ((composed (sl:compose #'1+ name #'1+)))
           (setf (symbol-function name) (lambda (value) (+ value 2)))
           (parachute:is = 5 (funcall composed 1))
           (setf (symbol-function name) (lambda (value) (+ value 3)))
           (parachute:is = 6 (funcall composed 1))
           (fmakunbound name)
           (parachute:fail (funcall composed 1) undefined-function))
      (when (fboundp name) (fmakunbound name)))))

(parachute:define-test function-utilities.late-function-resolution
  (let ((name (gensym "LATE-FUNCTION-")))
    (unwind-protect
         (progn
           (setf (symbol-function name) (lambda (&rest arguments)
                                          (declare (ignore arguments))
                                          :first-definition))
           (let ((juxt (sophie-lisp:juxt name))
                 (compose (sophie-lisp:compose name)))
             (setf (symbol-function name) (lambda (&rest arguments)
                                            (declare (ignore arguments))
                                            :second-definition))
             (parachute:is equal '(:second-definition)
                           (funcall juxt :argument))
             (parachute:is eql :second-definition
                           (funcall compose :argument))))
      (fmakunbound name))))

(parachute:define-test function-utilities.invalid-functions
  (let ((juxt (sophie-lisp:juxt 17))
        (compose (sophie-lisp:compose 17)))
    (parachute:fail (funcall juxt :argument) type-error)
    (parachute:fail (funcall compose :argument) type-error))
  (let ((juxt (sophie-lisp:juxt 'when))
        (compose (sophie-lisp:compose 'when)))
    (parachute:fail (funcall juxt :argument) type-error)
    (parachute:fail (funcall compose :argument) type-error))
  (let ((name (gensym "UNDEFINED-FUNCTION-")))
    (unwind-protect
         (progn
           (setf (symbol-function name) (lambda (value) value))
           (let ((juxt (sophie-lisp:juxt name))
                 (compose (sophie-lisp:compose name)))
             (fmakunbound name)
             (parachute:fail (funcall juxt :argument) undefined-function)
             (parachute:fail (funcall compose :argument) undefined-function)))
      (when (fboundp name) (fmakunbound name))))
  (let ((name (gensym "LATE-DEFINED-FUNCTION-")))
    (unwind-protect
         (let ((juxt (sophie-lisp:juxt name))
               (compose (sophie-lisp:compose name)))
           (setf (symbol-function name) (lambda (value) (list value)))
           (parachute:is equal '((:argument)) (funcall juxt :argument))
           (parachute:is equal '(:argument) (funcall compose :argument)))
      (when (fboundp name) (fmakunbound name)))))

(parachute:define-test function-utilities.multiple-values
  (let ((juxt-arguments nil)
        (compose-arguments nil))
    (flet ((juxt-function (&rest arguments)
             (setf juxt-arguments arguments)
             (values :juxt-primary :juxt-extra))
           (right-function (&rest arguments)
             (setf compose-arguments (list :right arguments))
             (values :right-primary :right-extra))
           (left-function (value)
             (setf compose-arguments
                   (append compose-arguments (list :left value)))
             (values :left-primary :left-extra)))
      (parachute:is equal '(:juxt-primary)
                    (funcall (sophie-lisp:juxt #'juxt-function) 1 2 3))
      (parachute:is equal '(1 2 3) juxt-arguments)
      (parachute:is equal '(:left-primary :left-extra)
                    (multiple-value-list
                     (funcall (sophie-lisp:compose #'left-function
                                                   #'right-function)
                              :a :b)))
      (parachute:is equal '(:right (:a :b) :left :right-primary)
                    compose-arguments)
      (parachute:true (not (member :right-extra compose-arguments))))))

(defun xfn-check (expected form &optional (modes '(:interpret :compile)))
  (dolist (mode modes)
    (let ((function
            (if (eq mode :interpret)
                (let* (#+sbcl (sb-ext:*evaluator-mode* :interpret))
                  (eval `(lambda () ,form)))
                (multiple-value-bind (function warnings failure)
                    (compile nil `(lambda () ,form))
                  (declare (ignore warnings))
                  (when failure (error "X-FN fixture failed compilation: ~S" form))
                  function))))
      (parachute:is equalp expected (multiple-value-list (funcall function))))))

(defun xfn-syntax-error (form)
  (parachute:fail (macroexpand-1 form) program-error))

(defconstant +xfn-constant+ 23)
(defvar *xfn-events* nil)
(define-condition xfn-sentinel (error) ())
(defclass xfn-access ()
  ((name :initarg :name :reader xfn-name)
   (items :initarg :items :reader xfn-items)))
(defmethod sl:ref ((object xfn-access) key &optional (default nil supplied))
  (push (list (xfn-name object) key supplied) *xfn-events*)
  (let ((pair (assoc key (xfn-items object))))
    (if pair (values (cdr pair) t) (values default nil))))

(parachute:define-test fbind.evaluation-and-empty-bindings
  (xfn-check '((:first :second :body) 7 :extra)
    '(let ((events nil))
       (sl:fbind ((xfn-local-a (progn (push :first events) (lambda () 7)))
                  (xfn-local-b (progn (push :second events) (lambda () 8))))
         (push :body events)
         (values (reverse events) (xfn-local-a) :extra))))
  (xfn-check '(nil) '(sl:fbind ()))
  (xfn-check '(1)
    '(let ((n 0))
       (sl:fbind ((xfn-unused (progn (incf n) #'identity)))) n)))

(parachute:define-test fbind.recursion-and-mutual-recursion
  (xfn-check '(120)
    '(sl:fbind ((xfn-factorial
                 (lambda (n) (if (zerop n) 1 (* n (xfn-factorial (1- n)))))))
       (xfn-factorial 5)))
  (xfn-check '(t nil)
    '(sl:fbind ((xfn-even (lambda (n) (if (zerop n) t (xfn-odd (1- n)))))
                (xfn-odd (lambda (n) (if (zerop n) nil (xfn-even (1- n))))))
       (values (xfn-even 10) (xfn-odd 10))))
  (xfn-check '(17)
    '(sl:fbind ((xfn-ready (lambda () 17))
                (xfn-later (let ((value (xfn-ready))) (lambda () value))))
       (xfn-later)))
  (xfn-check '(29)
    '(funcall (sl:fbind ((xfn-a (lambda () (xfn-b)))
                         (xfn-b (lambda () 29))) #'xfn-a))))

(parachute:define-test fbind.early-calls-and-errors
  (xfn-check '(:early)
    '(handler-case (sl:fbind ((xfn-a (progn (xfn-a) #'identity))) nil)
       (program-error () :early)))
  (xfn-check '(:early)
    '(handler-case
         (sl:fbind ((xfn-a (progn (xfn-b) #'identity)) (xfn-b #'identity)) nil)
       (program-error () :early)))
  (xfn-check '((:bad (:first)))
    '(let ((events nil))
       (list (handler-case
                 (sl:fbind ((xfn-a (progn (push :first events) 'identity))
                            (xfn-b (progn (push :late events) #'identity)))
                   (push :body events))
               (program-error () :bad))
             (reverse events))))
  (xfn-check '(:propagated)
    '(handler-case (sl:fbind ((xfn-a (error 'xfn-sentinel))) (xfn-a))
       (xfn-sentinel () :propagated)))
  (xfn-check '(:propagated)
    '(handler-case
         (sl:fbind ((xfn-a (lambda () (error 'xfn-sentinel)))) (xfn-a))
       (xfn-sentinel () :propagated))))

(parachute:define-test fbind.syntax-validation
  (dolist (bindings '(((xfn-a #'identity) (xfn-a #'identity))
                      ((nil #'identity)) ((t #'identity)) ((:bad #'identity))
                      ((+xfn-constant+ #'identity)) ((42 #'identity))
                      ((xfn-a)) ((xfn-a #'identity :extra))
                      ((xfn-a . identity))))
    (xfn-syntax-error `(sl:fbind ,bindings nil))))

(parachute:define-test fbind.declarations
  ;; As with LABELS, free SPECIAL governs the body, not the enclosing LET
  ;; binding or the computed function expression's lexical references.
  (xfn-check '(:lexical :dynamic)
    '(progv '(xfn-free) '(:dynamic)
       (let ((xfn-free :lexical))
         (sl:fbind ((xfn-a (lambda () xfn-free)))
           (declare (special xfn-free) (optimize (safety 3) (debug 3)))
           (values (xfn-a) xfn-free)))))
  (xfn-check '(9 :extra)
    '(sl:fbind ((xfn-a (lambda (x) (values x :extra))))
       (declare (ftype (function (integer) (values integer keyword)) xfn-a)
                (notinline xfn-a) (optimize (safety 3)))
       (xfn-a 9))))

(parachute:define-test fn.patterns
  (xfn-check '((1 2 3 4 5))
    '(funcall (sl:fn ((a . b) #(c _) (:entry d #(e))) (list a b c d e))
       '(1 . 2) #(3 :ignored :extra) (sl:map-entry 4 #(5))))
  (xfn-check '((10 20 ((:first 0 nil) (:first 1 nil) (:second 0 nil))))
    '(let ((*xfn-events* nil))
       (funcall (sl:fn (#(a _) #(b)) (list a b (reverse *xfn-events*)))
         (make-instance 'xfn-access :name :first :items '((0 . 10)))
         (make-instance 'xfn-access :name :second :items '((0 . 20))))))
  (xfn-check '(3)
    '(funcall (sl:fn ((&whole w a &optional (b 2 bp) &rest rest &aux (c (+ a b))))
                (declare (ignore w bp rest)) c) '(1))))

(parachute:define-test fn.optional-key-and-aux-parameters
  (xfn-check '(7 8 nil nil 9 nil 10 :extra)
    '(funcall (sl:fn (#(a) &optional (b (1+ a) bp)
                      &rest rest &key (c (1+ b) cp) &aux (d (1+ c)))
                (values a b bp rest c cp d :extra)) #(7)))
  ;; ECL's compiler mis-binds an &OPTIONAL supplied-p variable to the &REST
  ;; list when the inner lambda also has &KEY and &ALLOW-OTHER-KEYS (verified
  ;; with a minimal compiled APPLY), so the compiled leg of this form is
  ;; excluded there; the interpreted leg runs on every host.
  (xfn-check '(7 20 t (:c 30 :other 40) 30 t 31)
    '(funcall (sl:fn (#(a) &optional (b (1+ a) bp)
                      &rest rest &key (c (1+ b) cp) &allow-other-keys
                      &aux (d (1+ c)))
                (values a b bp rest c cp d)) #(7) 20 :c 30 :other 40)
    #+ecl '(:interpret)
    #-ecl '(:interpret :compile))
  (xfn-check '(12 12 12 12)
    '(flet ((xfn-read () (declare (special xfn-local)) xfn-local))
       (funcall (sl:fn ((:entry _ #(xfn-local))
                        &optional (b (xfn-read)) &key (c (xfn-read))
                        &aux (d (xfn-read)))
                  (declare (special xfn-local)) (values xfn-local b c d))
         (sl:map-entry :key #(12)))))
  (xfn-check '(3 3 4 4)
    '(flet ((xfn-read () (declare (special xfn-local)) xfn-local))
       (funcall (sl:fn ((#(xfn-local) &optional (first (xfn-read)))
                        (:entry _ xfn-local) &optional (last (xfn-read)))
                  (declare (special xfn-local))
                  (values first first xfn-local last))
         '(#(3)) (sl:map-entry :key 4))))
  (xfn-check '(:lexical :lexical :lexical :dynamic)
    '(progv '(xfn-free) '(:dynamic)
       (let ((xfn-free :lexical))
         (funcall (sl:fn ((&optional (a xfn-free))
                          &optional (b xfn-free) &key (c xfn-free))
                    (declare (special xfn-free) (optimize (safety 3)))
                    (values a b c xfn-free)) nil))))
  (xfn-check '(5 5)
    '(flet ((xfn-read () (declare (special xfn-local)) xfn-local))
       (funcall (sl:fn (&optional (xfn-local 5) (b (xfn-read)))
                  (declare (special xfn-local)) (values xfn-local b)))))
  (xfn-check '(6 6)
    '(flet ((xfn-read () (declare (special xfn-local)) xfn-local))
       (funcall (sl:fn (&key (xfn-local 6) (b (xfn-read)))
                  (declare (special xfn-local)) (values xfn-local b)))))
  (xfn-check '(7 7)
    '(flet ((xfn-read () (declare (special xfn-local)) xfn-local))
       (funcall (sl:fn (&aux (xfn-local 7) (b (xfn-read)))
                  (declare (special xfn-local)) (values xfn-local b)))))
  (xfn-check '(8)
    '(funcall (sl:fn (&key ((:external x) 8)) x)) ))

(parachute:define-test fn.syntax-and-arity-errors
  (dolist (form '((sl:fn ()) (sl:fn (a) (declare (ignore a)))
                  (sl:fn (#(42)) nil) (sl:fn ((:entry a)) nil)
                  (sl:fn (sl:?) nil) (sl:fn (&optional (#(x) nil)) nil)
                  (sl:fn (&rest #(x)) nil) (sl:fn (&key (#(x) nil)) nil)
                  (sl:fn (&aux (#(x) nil)) nil)))
    (xfn-syntax-error form))
  (dolist (marker (list 'sl:? 'sl:@ (make-symbol "?") (make-symbol "@")))
    (dolist (parameters (list (list '&optional marker)
                              (list '&optional (list 'x nil marker))
                              (list '&rest marker)
                              (list '&key marker)
                              (list '&key (list 'x nil marker))
                              (list '&aux (list marker nil))))
      (xfn-syntax-error `(sl:fn ,parameters nil))))
  (xfn-check '(nil) '(funcall (sl:fn () nil)))
  ;; Runtime indirection avoids a host compile-time wrong-arity warning being
  ;; mistaken for the required runtime PROGRAM-ERROR.
  ;; Wrong arity signals PROGRAM-ERROR on every supported host. An unknown
  ;; keyword prescribes the host's own condition (SBCL: PROGRAM-ERROR, ECL:
  ;; SIMPLE-ERROR), so only "an error is signaled" is portable there.
  (dolist (call '((xfn-call (sl:fn (a) a) nil)
                  (xfn-call (sl:fn (a) a) '(1 2))))
    (xfn-check '(t) `(handler-case ,call (program-error () t))))
  ;; ECL's compiler validates constant keyword argument lists while COMPILING
  ;; a call (it signals SIMPLE-ERROR for both the odd-length list and the
  ;; unknown keyword), so the compiled legs are excluded there; the
  ;; interpreted legs run on every host.
  (xfn-check '(t)
    '(handler-case (xfn-call (sl:fn (&key x) x) '(:x))
       (program-error () t))
    #+ecl '(:interpret)
    #-ecl '(:interpret :compile))
  (xfn-check '(t)
    '(handler-case (xfn-call (sl:fn (&key x) x) '(:unknown 1))
       (error () t))
    #+ecl '(:interpret)
    #-ecl '(:interpret :compile))
  (xfn-check '(t)
    '(handler-case (funcall (sl:fn (#(a b)) (list a b)) #(1))
       (type-error () t)))
  (xfn-check '(t)
    '(handler-case (funcall (sl:fn ((:entry a b)) (list a b)) '(1 . 2))
       (type-error () t))))

(parachute:define-test fn.lexical-context-and-laziness
  (xfn-check '((10 :caller :macro))
    '(let ((argument :caller))
       (macrolet ((xfn-local-macro (x) `(list ,x argument :macro)))
         (funcall (sl:fn (#(x)) (xfn-local-macro x)) #(10)))))
  (xfn-check '((1 2))
    '(let ((n 0))
       (let ((source (sl:lazy-seq (progn (incf n) (sl:lazy-cons 2 nil)))))
         (list (funcall (sl:fn (#(x)) (declare (ignore x)) n) source)
               (funcall (sl:fn (#(x)) x) source)))))
  (xfn-check '(:escaped)
    '(catch 'xfn-exit
       (funcall (sl:fn (x) (declare (ignore x)) (throw 'xfn-exit :escaped)) 1))))

(defun xfn-call (function arguments)
  (apply function arguments))

(defun threading-macroexpands-to-program-error-p (form)
  (handler-case
      (progn
        (macroexpand-1 form)
        nil)
    (program-error () t)))

(parachute:define-test threading.basic-threading
  (parachute:is = 20
                (sophie-lisp:-> 2 (cl:+ 3) (cl:* 4)))
  (parachute:is = 1/4
                (sophie-lisp:->> 2 (cl:- 10) (cl:/ 2)))
  (parachute:is equal '(:a :b)
                (multiple-value-list
                 (sophie-lisp:-> (values :a :b))))
  (parachute:is equal '(:a :b)
                (multiple-value-list
                 (sophie-lisp:->> (values :a :b))))
  (parachute:is equal '(:a :b)
                (multiple-value-list
                 (sophie-lisp:~> (values :a :b))))
  (parachute:is equal '(:initial :second :third)
                (multiple-value-list
                 (sophie-lisp:-> :initial (cl:values :second :third))))
  (parachute:is equal '(:second :third :initial)
                (multiple-value-list
                 (sophie-lisp:->> :initial (cl:values :second :third))))
  (parachute:is equal '(:first :initial :second)
                (multiple-value-list
                 (sophie-lisp:~> :initial
                                 (cl:values :first sophie-lisp:<>
                                            :second))))
  (flet ((threading-primary (value)
           (values (list :primary value) :discarded)))
    (parachute:is equal '((:primary :seed) :final)
                  (sophie-lisp:-> :seed threading-primary
                                  (cl:list :final))))
  (let ((evaluations 0))
    (parachute:is = 12
                  (sophie-lisp:-> (progn (incf evaluations) 3)
                                  (cl:+ 1)
                                  (cl:* 3)))
    (parachute:is = 1 evaluations)))

(parachute:define-test threading.forms-and-errors
  (parachute:is equal '(3 :first)
                (sophie-lisp:-> 3 (cl:list :first)))
  (parachute:is equal '(:last 3)
                (sophie-lisp:->> 3 (cl:list :last)))
  (parachute:is equal '(:body)
                (sophie-lisp:-> t (cl:when (cl:list :body))))
  (parachute:is equal '(:body)
                (sophie-lisp:-> :seed
                                (cl:progn (cl:list :body))))
  (parachute:is eql :seed
                (sophie-lisp:->> :seed
                                 (cl:progn (cl:list :body))))
  (dolist (form (list '(sophie-lisp:-> 1 :keyword-step)
                      '(sophie-lisp:-> 1 (:keyword-step 2))
                      '(sophie-lisp:-> 1 (cl:+ . 2))
                      '(sophie-lisp:-> 1 (42 2))
                      '(sophie-lisp:->> 1 nil)))
    (parachute:true (threading-macroexpands-to-program-error-p form))))

(parachute:define-test as-thread.binding-and-values
  (parachute:is equal '(:bound :final-extra)
                (multiple-value-list
                 (sophie-lisp:as-> :initial value
                   (values :bound :discarded)
                   (values value :final-extra))))
  (let ((outside 99))
    (parachute:is = 109
                  (sophie-lisp:as-> 10 value
                    (let ((capture (lambda () (+ value outside))))
                      (funcall capture))
                    value)))
  (let ((value :outer))
    (parachute:is equal '(:inner :last)
                  (multiple-value-list
                   (sophie-lisp:as-> :first value
                     (let ((value :inner))
                       (values value :ignored))
                     (values value :last)))))
  (parachute:is equal '((value 7))
                (sophie-lisp:as-> 7 value
                  (cl:list 'value value)
                  (cl:list value)))
  (parachute:is equal '((value 7))
                (sophie-lisp:as-> 7 value
                  `(value ,value)
                  (cl:list value)))
  (parachute:is equal '(:macro 5)
                (macrolet ((threading-local-macro (form)
                             `(cl:list :macro ,form)))
                  (sophie-lisp:as-> 5 value
                    (threading-local-macro value))))
  (parachute:is eql :done
                (sophie-lisp:as-> :start value
                  (progn :discarded)
                  :done))
  (parachute:is eql :constant
                (sophie-lisp:as-> :start value
                  :constant))
  (parachute:is equal '(:left :right)
                (multiple-value-list
                 (sophie-lisp:as-> :seed value
                   (values :left :ignored)
                   (values value :right))))
  (parachute:is equal '((:seed))
                (sophie-lisp:as-> :seed value
                  (cl:list value)
                  (cl:list value)))
  (parachute:is equal '(:outer :inner)
                (let ((value :outer))
                  (sophie-lisp:as-> :inner value
                    (progn value)
                    (cl:list :outer value)))))

(parachute:define-test as-thread.syntax-validation
  (dolist (form (list '(sophie-lisp:as-> 0 1 (cl:1+ 1))
                      '(sophie-lisp:as-> 0 :keyword (cl:1+ 1))
                      '(sophie-lisp:as-> 0 nil (cl:1+ 1))
                      '(sophie-lisp:as-> 0 t (cl:1+ 1))
                      '(sophie-lisp:as-> 0 cl:pi (cl:1+ 1))
                      '(sophie-lisp:as-> 0 sophie-lisp:? (cl:1+ 1))
                      '(sophie-lisp:as-> 0 sophie-lisp:@ (cl:1+ 1))))
    (parachute:true (threading-macroexpands-to-program-error-p form)))
  (parachute:true
   (threading-macroexpands-to-program-error-p
    '(sophie-lisp:as-> 0 value))))

(parachute:define-test placeholder-threading.substitution-and-errors
  (parachute:is = 4
                (sophie-lisp:~> 3 (cl:+ 1 sophie-lisp:<>)))
  (parachute:is = 4
                (sophie-lisp:~> 3 cl:1+))
  (let ((sophie-lisp:<> :nested))
    (parachute:is equal '(3 (:nested))
                  (sophie-lisp:~> 3
                                  (cl:list sophie-lisp:<>
                                          (cl:list sophie-lisp:<>)))))
  (parachute:is equal
                (cl:list 3 'sophie-lisp:<>)
                (sophie-lisp:~> 3
                                (cl:list sophie-lisp:<>
                                        'sophie-lisp:<>)))
  (let ((other (cl:make-symbol "<>")))
    (parachute:is equal
                  (list 'cl:list 3 other)
                  (macroexpand-1
                   (list 'sophie-lisp:~> 3
                         (list 'cl:list 'sophie-lisp:<> other)))))
  (dolist (form (list '(sophie-lisp:~> 1 (cl:list 2))
                      '(sophie-lisp:~> 1 (cl:list sophie-lisp:<> sophie-lisp:<>))
                      '(sophie-lisp:~> 1 (:bad sophie-lisp:<>))
                      '(sophie-lisp:~> 1 (cl:list . sophie-lisp:<>))
                      '(sophie-lisp:~> 1 :bad)))
    (parachute:true (threading-macroexpands-to-program-error-p form))))

(parachute:define-test threading.hygiene-and-markers
  (let ((sophie-lisp:? :question)
        (sophie-lisp:@ :at)
        (sophie-lisp:<> :hole))
    (parachute:is equal
                  (cl:list 9 sophie-lisp:? sophie-lisp:@ sophie-lisp:<>)
                  (sophie-lisp:-> 9
                                  (cl:list sophie-lisp:?
                                          sophie-lisp:@
                                          sophie-lisp:<>)))
    (parachute:is equal
                  (cl:list sophie-lisp:? 3 sophie-lisp:@)
                  (sophie-lisp:~> 3
                                  (cl:list sophie-lisp:? sophie-lisp:<>
                                          sophie-lisp:@))))
  (flet ((threading-local-list (value) (cl:cons :lexical value)))
    (parachute:is equal '(:lexical . 7)
                  (sophie-lisp:-> 7 threading-local-list)))
  (let ((threaded-value :caller))
    (parachute:is equal '(7 :caller)
                  (sophie-lisp:-> 7 (cl:list threaded-value))))
)
