(in-package #:sophie-lisp.tests)

(defun x-readtable-standard-snapshot (readtable)
  "Capture the standard character syntax and only the standard #. dispatch.

The dispatch function itself is deliberately not compared across readtable
copies: COPY-READTABLE may allocate a distinct dispatch closure."
  (let ((snapshot (reader-definition-snapshot readtable)))
    (list (remove 35 (first snapshot) :key #'first)
          (remove-if-not (lambda (entry) (= 46 (first entry)))
                         (second snapshot)))))

(defun x-readtable-pristine-standard-p (readtable)
  (reader-definitions-equal-p
   (x-readtable-standard-snapshot (copy-readtable nil))
   (x-readtable-standard-snapshot readtable)
   :dispatch-identities-p nil))

(defun x-readtable-same-table-p (readtable before)
  (reader-definitions-equal-p before (reader-definition-snapshot readtable)
                              :dispatch-identities-p t))

(parachute:define-test reader.core-readtable-isolation
  (let* ((core (named-readtables:find-readtable :sl-core-syntax))
         (standard-before (reader-definition-snapshot nil))
         (core-before (reader-definition-snapshot core))
         (standard-dot-before
           (get-dispatch-macro-character #\# #\. nil))
         (core-dot-before
           (get-dispatch-macro-character #\# #\. core))
         (standard-array-dispatch
           (get-dispatch-macro-character #\# #\A nil)))
    (parachute:true (typep core 'readtable))
    (parachute:is eq core (named-readtables:find-readtable :sl-core-syntax))
    (parachute:false (eq core *readtable*))
    (parachute:true (x-readtable-pristine-standard-p core))
    (parachute:true standard-array-dispatch)
    (parachute:is eq standard-array-dispatch
                  (get-dispatch-macro-character #\# #\a nil))
    (let ((*readtable* *readtable*))
      (setf *readtable* core)
      (parachute:is eq core *readtable*)
      (parachute:is eq core-dot-before
                    (get-dispatch-macro-character #\# #\. *readtable*))
      (let ((*read-eval* t))
        (parachute:is = 3 (read-from-string "#.(+ 1 2)"))))
    (parachute:true (x-readtable-same-table-p core core-before))
    (parachute:true (x-readtable-same-table-p nil standard-before))
    (parachute:is eq standard-dot-before
                  (get-dispatch-macro-character #\# #\. nil))))

;;;; Eight independent acceptance cases; all reader activation is dynamically
;;;; scoped to copied tables. Oracles use ANSI PRINC, not Sophie helpers.

(declaim (special sophie-lisp:*list-delimiter*))
(defvar *x-int-events* nil)
(defvar *x-int-circular* nil)
(defvar *x-int-list-to-mutate* nil)
(defvar *x-int-object* nil)
(defvar *x-int-action* nil)

(defun x-int-read (text &key (read-suppress nil) (read-eval *read-eval*))
  (let ((*readtable*
          (copy-readtable (named-readtables:find-readtable :sl-core-syntax)))
        (*read-suppress* read-suppress)
        (*read-eval* read-eval))
    (read-from-string text)))

(defun x-int-eval (text)
  (eval (x-int-read text)))

(defun x-int-mark (tag value)
  (push tag *x-int-events*)
  value)

(defun x-int-condition (thunk)
  (handler-case
      #+sbcl (sb-ext:with-timeout 1 (funcall thunk))
      #-sbcl (funcall thunk)
    (condition (condition) condition)))

(defun x-int-dot-suppressed-p ()
  "Whether this host suppresses #. under *READ-SUPPRESS* instead of
signaling the *READ-EVAL* violation: SBCL suppresses, CCL signals."
  (handler-case
      (let ((*read-suppress* t) (*read-eval* nil))
        (read-from-string "#.(identity nil)")
        t)
    (reader-error () nil)))

(defun x-int-symbol-audit-p (object predicate)
  (let ((seen (make-hash-table :test #'eq)))
    (labels ((walk (object)
               (cond
                 ((symbolp object) (funcall predicate object))
                 ((or (consp object) (vectorp object))
                  (or (gethash object seen)
                      (progn
                        (setf (gethash object seen) t)
                        (if (consp object)
                            (and (walk (car object)) (walk (cdr object)))
                            (loop for element across object
                                  always (walk element))))))
                 (t t))))
      (walk object))))

(defun x-int-no-private-symbols-p (object)
  (x-int-symbol-audit-p
   object (lambda (symbol)
            (not (eq (symbol-package symbol)
                     (find-package :sophie-lisp.internal))))))

(defun x-int-public-expansion-p (object &optional retained)
  ;; RETAINED is an explicit source-symbol allowlist, never an allowance for
  ;; arbitrary keywords. The principal expansion probes use public-only input.
  (x-int-symbol-audit-p
   object
   (lambda (symbol)
     (or (member symbol retained :test #'eq)
         (if (null (symbol-package symbol))
             (let ((name (symbol-name symbol)))
               (or (zerop (length name)) (char/= #\% (char name 0))))
             (multiple-value-bind (public status)
                 (find-symbol (symbol-name symbol) :sophie-lisp)
               (and (eq public symbol) (eq status :external))))))))

(defun x-int-escaped-template ()
  (format nil "#?\"~C$ ~C@ ~C~C ~C\" ~Cn ~Ct ~Cr | $x @x $$ @@ $ @\""
          #\\ #\\ #\\ #\\ #\\ #\\ #\\ #\\))

(defun x-int-bad-escape-template ()
  (format nil "#?\"~Cq\"" #\\))

(defun x-int-eof-after-backslash-template ()
  (format nil "#?\"unfinished~C" #\\))

(defstruct x-int-mutator)

(defmethod print-object ((object x-int-mutator) stream)
  (declare (ignore object))
  (write-string "1" stream)
  ;; Destroy both the original later CAR and its spine at the first print.
  (when *x-int-list-to-mutate*
    (setf (cadr *x-int-list-to-mutate*) :changed
          (cdr *x-int-list-to-mutate*) nil))
  (setf sophie-lisp:*list-delimiter* "|"))

(defstruct x-int-printer callback)

(defmethod print-object ((object x-int-printer) stream)
  (funcall (x-int-printer-callback object) stream))

(define-condition x-int-user-condition (error) ())

(defun x-int-at-stage (stage)
  (let* ((*x-int-object*
           (make-x-int-printer
            :callback (lambda (stream)
                        (funcall *x-int-action*)
                        (write-string "P" stream))))
         (sophie-lisp:*list-delimiter*
           (if (eq stage :delimiter) *x-int-object* " ")))
    (x-int-eval
     (ecase stage
       (:form "#?\"${(funcall sophie-lisp.tests::*x-int-action*)}\"")
       (:element "#?\"@{(list sophie-lisp.tests::*x-int-object*)}\"")
       (:delimiter "#?\"@{(list 1 2)}\"")))))

(parachute:define-test interpolation.plain-text
  (let* ((ambient *readtable*)
         (value (x-int-read "#?\"plain text\"")))
    (parachute:true (stringp value))
    (parachute:is string= "plain text" value)
    (parachute:is eq ambient *readtable*))
  (parachute:is string= "" (x-int-read "#?\"\"")))

(parachute:define-test interpolation.scalar-forms
  (let ((*x-int-events* nil))
    (parachute:is string= "17"
                  (x-int-eval
                   "#?\"${(sophie-lisp.tests::x-int-mark :first :ignored) (sophie-lisp.tests::x-int-mark :last (values 17 99))}\""))
    (parachute:is equal '(:last :first) *x-int-events*))
  (parachute:is string= (princ-to-string nil) (x-int-eval "#?\"${(values)}\""))
  (parachute:is string= "23" (x-int-eval "#?\"${23}\""))
  (parachute:is string= "17" (x-int-eval "#?\"${(values 17 99)}\""))
  (let* ((*package* (find-package :sophie-lisp.tests))
         (form (x-int-read "#?\"before-${(+ x (bump 2))}-after\""))
         (lambda-form `(lambda (x) (flet ((bump (n) (+ n 1))) ,form))))
    (parachute:is string= "before-23-after" (funcall (eval lambda-form) 20))
    (parachute:is string= "before-23-after" (funcall (compile nil lambda-form) 20)))
  ;; Every source symbol here is already public, so any added keyword fails.
  (dolist (package (list (find-package :cl-user) (find-package :sophie-lisp.tests)))
    (let ((*package* package))
      (dolist (text '("#?\"${(cl:values 17 99)}\""
                      "#?\"@{(cl:list 1 2 3)}\""))
        (let ((form (x-int-read text)))
          (parachute:true (x-int-no-private-symbols-p form))
          (parachute:true (x-int-public-expansion-p form))))))
  (parachute:true
   (x-int-public-expansion-p (x-int-read "#?\"${:retained}\"") '(:retained))))

(parachute:define-test interpolation.sequence-forms
  (let ((*x-int-events* nil))
    (parachute:is string= "1 2 3"
                  (x-int-eval
                   "#?\"@{(sophie-lisp.tests::x-int-mark :first nil) (sophie-lisp.tests::x-int-mark :last (list 1 2 3))}\""))
    (parachute:is equal '(:last :first) *x-int-events*))
  (let ((*x-int-events* nil) (*print-case* :downcase))
    (parachute:is string= "left|a b|right"
                  (let ((sophie-lisp:*list-delimiter* " "))
                    (x-int-eval
                     "#?\"left|@{(sophie-lisp.tests::x-int-mark :values (list 'a 'b))}|right\"")))
    (parachute:is equal '(:values) *x-int-events*))
  (parachute:is string= "LR" (x-int-eval "#?\"L@{nil}R\""))
  (parachute:is string= "7" (x-int-eval "#?\"@{(list 7)}\""))
  (parachute:is string= "" (x-int-eval "#?\"@{(values)}\""))
  (parachute:is string= "4 5" (x-int-eval "#?\"@{(values (list 4 5) 99)}\""))
  (let ((form (x-int-read "#?\"@{(list 4 5)}\"")))
    (parachute:true (x-int-no-private-symbols-p form)))
  ;; Validation precedes even the first element's printer for a dotted list.
  (let* ((*x-int-events* nil)
         (*x-int-object* (make-x-int-printer
                         :callback (lambda (s) (push :printed *x-int-events*)
                                     (write-string "bad" s)))))
    (parachute:true
     (typep (x-int-condition
             (lambda () (x-int-eval "#?\"@{(cons sophie-lisp.tests::*x-int-object* 2)}\"")))
            'type-error))
    (parachute:false *x-int-events*)))

(parachute:define-test interpolation.printing-and-conditions
  (let ((*x-int-events* nil) (*print-base* 16) (*print-radix* nil)
        (*print-case* :downcase) (*print-readably* nil))
    (parachute:is string=
                  (with-output-to-string (s)
                    (princ 255 s) (princ "|" s) (princ 10 s)
                    (princ " " s) (princ 11 s) (princ "|" s) (princ 12 s))
                  (x-int-eval
                   "#?\"${(sophie-lisp.tests::x-int-mark :one 255)}|@{(sophie-lisp.tests::x-int-mark :two (list 10 11))}|${(sophie-lisp.tests::x-int-mark :three 12)}\""))
    (parachute:is equal '(:three :two :one) *x-int-events*))
  (let ((*x-int-events* nil))
    (x-int-read "#?\"${(sophie-lisp.tests::x-int-mark :not-yet 1)}\"")
    (parachute:false *x-int-events*))
  ;; Each row independently varies a component of the dynamic printer context.
  ;; PRINC's mandated bindings of ESCAPE/READABLY are part of the oracle too.
  (dolist (setting '((*print-case* :downcase) (*print-base* 16)
                     (*print-radix* t) (*print-length* 1) (*print-level* 1)
                     (*print-circle* t) (*print-escape* t) (*print-readably* t)))
    (progv (list (first setting)) (list (second setting))
      (let* ((shared (list 'alpha 255 "quoted"))
             (*x-int-object* (list shared shared (list (list 'beta)))))
        (parachute:is string= (princ-to-string *x-int-object*)
                      (x-int-eval "#?\"${sophie-lisp.tests::*x-int-object*}\""))
        (parachute:is string=
                      (with-output-to-string (s)
                        (princ *x-int-object* s) (princ " " s) (princ 255 s))
                      (x-int-eval "#?\"@{(list sophie-lisp.tests::*x-int-object* 255)}\"")))))
  (let* ((*x-int-events* nil)
         (*x-int-object*
           (make-x-int-printer :callback
                              (lambda (s) (push :print *x-int-events*)
                                (write-string "P" s)))))
    (parachute:is string= "P|P 2|3"
                  (x-int-eval
                   "#?\"${(sophie-lisp.tests::x-int-mark :scalar sophie-lisp.tests::*x-int-object*)}|@{(sophie-lisp.tests::x-int-mark :list (list sophie-lisp.tests::*x-int-object* 2))}|${(sophie-lisp.tests::x-int-mark :last 3)}\""))
    (parachute:is equal '(:scalar :print :list :print :last)
                  (reverse *x-int-events*)))
  ;; Ordinary conditions, caller-defined restarts, and nonlocal exits at all
  ;; three user-code boundaries; no Sophie-specific restart is assumed.
  (dolist (stage '(:form :element :delimiter))
    (let* ((condition (make-condition 'x-int-user-condition))
           (*x-int-action* (lambda () (error condition))))
      (parachute:is eq condition (x-int-condition (lambda () (x-int-at-stage stage)))))
    (let* ((condition (make-condition 'x-int-user-condition))
           (observed nil)
           (*x-int-action*
             (lambda () (restart-case (error condition) (user-continue () 7)))))
      (parachute:is string= (ecase stage (:form "7") (:element "P") (:delimiter "1P2"))
                    (handler-bind ((x-int-user-condition
                                     (lambda (c) (setf observed c)
                                       (invoke-restart 'user-continue))))
                      (x-int-at-stage stage)))
      (parachute:is eq condition observed))
    (let* ((token (list :token))
           (*x-int-action* (lambda () (throw 'x-int-exit token))))
      (parachute:is eq token (catch 'x-int-exit (x-int-at-stage stage))))))

(parachute:define-test interpolation.escapes
  (let ((expected (format nil "$ @ ~C \" ~C ~C ~C | $x @x $$ @@ $ @"
                          #\\ #\Newline #\Tab #\Return)))
    (parachute:is string= expected (x-int-eval (x-int-escaped-template))))
  (loop for code in '(#\$ #\@ #\\ #\" #\n #\t #\r)
        for expected in '(#\$ #\@ #\\ #\" #\Newline #\Tab #\Return)
        do (parachute:is string= (string expected)
                         (x-int-read (format nil "#?\"~C~C\"" #\\ code))))
  (parachute:is string= "${literal} @{literal}"
                (x-int-read (format nil "#?\"~C${literal} ~C@{literal}\"" #\\ #\\)))
  (parachute:is string= "$x @x $$ @@ $ @" (x-int-read "#?\"$x @x $$ @@ $ @\"")))

(parachute:define-test interpolation.nested-syntax-and-errors
  (parachute:is string= "}" (x-int-eval "#?\"${\"a}b\" #\\}}\""))
  (parachute:is string= "A}B" (x-int-eval "#?\"${(symbol-name '|A}B|)}\""))
  (parachute:is string= "A}B" (x-int-eval "#?\"${(symbol-name 'A\\}B)}\""))
  (parachute:is string= "outer inner 3"
                (x-int-eval "#?\"outer ${#?\"inner ${3}\"}\""))
  (parachute:is string= (princ-to-string '(1 . 2))
                (x-int-eval "#?\"${'(1 . 2)}\""))
  (parachute:is string= "9" (x-int-eval "#?\"${#| } #| } |# |# 9}\""))
  (parachute:is string= "8"
                (x-int-eval (format nil "#?\"${; } ignored~%8}\"")))
  (dolist (text (list "#?\"${}\"" "#?\"@{}\"" (x-int-bad-escape-template)
                      "#?\"${.}\"" "#?\"@{.}\"" "#1?\"text\"" "#?x"
                      "#?\"${#| only comment |#}\""
                      (format nil "#?\"@{; only comment~%}\"")))
    (parachute:true
     (typep (x-int-condition (lambda () (x-int-read text))) 'reader-error)))
  (dolist (text '("#?\"@{42}\"" "#?\"@{(cons 1 2)}\""))
    (parachute:true
     (typep (x-int-condition (lambda () (x-int-eval text))) 'type-error)))
  (let ((cycle (list :cycle)))
    (setf (cdr cycle) cycle)
    (let* ((*x-int-circular* cycle)
           (condition
             (x-int-condition
              (lambda () (x-int-eval "#?\"@{sophie-lisp.tests::*x-int-circular*}\"")))))
      (parachute:true (typep condition 'type-error))
      #+sbcl (parachute:false (typep condition 'sb-ext:timeout))))
  (dolist (text (list "#?" "#?\"unfinished" "#?\"${1"
                      (x-int-eof-after-backslash-template)))
    (parachute:true
     (typep (x-int-condition (lambda () (x-int-read text))) 'end-of-file)))
  (let ((*read-eval* nil))
    (parachute:true
     (typep (x-int-condition (lambda () (x-int-read "#?\"${#.(+ 1 2)}\"")))
            'reader-error)))
  (parachute:is string= "3" (eval (x-int-read "#?\"${#.(+ 1 2)}\"" :read-eval t))))

(parachute:define-test interpolation.list-delimiter
  (parachute:is string= " " sophie-lisp:*list-delimiter*)
  (parachute:is string= "1, 2"
                (let ((sophie-lisp:*list-delimiter* ", "))
                  (x-int-eval "#?\"@{(list 1 2)}\"")))
  (let ((sophie-lisp:*list-delimiter* ", ") (*x-int-list-to-mutate* nil))
    (parachute:is string= "1, 2, 3|4|5"
                  (x-int-eval
                   "#?\"@{(setf sophie-lisp.tests::*x-int-list-to-mutate* (list (sophie-lisp.tests::make-x-int-mutator) 2 3)) sophie-lisp.tests::*x-int-list-to-mutate*}|@{(list 4 5)}\""))
    (parachute:true (null (cdr *x-int-list-to-mutate*)))
    (parachute:is string= "|" sophie-lisp:*list-delimiter*))
  (let ((sophie-lisp:*list-delimiter* "old"))
    (parachute:is string= "1new2"
                  (x-int-eval "#?\"@{(setf sophie-lisp:*list-delimiter* \"new\") (list 1 2)}\"")))
  (dolist (delimiter (list nil 17 #\: '(a b)))
    (let ((sophie-lisp:*list-delimiter* delimiter))
      (parachute:is string=
                    (with-output-to-string (s) (princ 1 s) (princ delimiter s) (princ 2 s))
                    (x-int-eval "#?\"@{(list 1 2)}\""))))
  (let* ((*x-int-events* nil)
         (delimiter (make-x-int-printer
                     :callback (lambda (s)
                                 (push :delimiter *x-int-events*)
                                 (setf sophie-lisp:*list-delimiter* "changed")
                                 (write-string "/" s))))
         (sophie-lisp:*list-delimiter* delimiter))
    (parachute:is string= "" (x-int-eval "#?\"@{nil}\""))
    (parachute:false *x-int-events*)
    (parachute:is string= "1" (x-int-eval "#?\"@{(list 1)}\""))
    (parachute:false *x-int-events*)
    (parachute:is string= "1/2/3" (x-int-eval "#?\"@{(list 1 2 3)}\""))
    (parachute:is equal '(:delimiter :delimiter) *x-int-events*)
    (parachute:is string= "changed" sophie-lisp:*list-delimiter*)))

(parachute:define-test interpolation.read-suppression
  (let ((ambient *readtable*) (*x-int-events* nil))
    (dolist (text (append (list (format nil "#?\"${} ~Cq @{.}\" :after" #\\)
                                "#19?\"${} @{.}\" :after")
                          ;; CCL enforces #.'s *READ-EVAL* check even under
                          ;; *READ-SUPPRESS* and aborts the read; the #. fixture
                          ;; applies only where the host suppresses #. (SBCL).
                          (when (x-int-dot-suppressed-p)
                            (list "#?\"${#.(push :bad sophie-lisp.tests::*x-int-events*)}\" :after"))))
      (with-input-from-string (stream text)
        (let ((*readtable* (copy-readtable (named-readtables:find-readtable :sl-core-syntax))))
          (let ((*read-suppress* t) (*read-eval* nil))
            (parachute:true (null (read stream))))
          (parachute:is eq :after (read stream))))
      (parachute:is eq ambient *readtable*))
    (parachute:false *x-int-events*))
  (dolist (suffix '("x" " :after" "#|comment|# :after"))
    (with-input-from-string (stream (concatenate 'string "#7?" suffix))
      (let ((*readtable* (copy-readtable (named-readtables:find-readtable :sl-core-syntax))))
        (let ((*read-suppress* t))
          ;; Ordinary READ may consume one trailing whitespace character; use
          ;; its preserving variant to observe the dispatch's exact boundary.
          (parachute:true (null (read-preserving-whitespace stream))))
        (parachute:is eql (char suffix 0) (peek-char nil stream)))))
  (dolist (text (list "#?" "#7?" "#?\"unterminated" "#?\"${1"
                      (x-int-eof-after-backslash-template)))
    (parachute:true
     (typep (x-int-condition (lambda () (x-int-read text :read-suppress t)))
            'end-of-file))))

(defvar *literal-effects* nil)
(defclass literal-key () ())
(defmethod sl:hash-code ((key literal-key))
  (declare (ignore key)) (push :hash *literal-effects*) 97)

(defun literal-read (text)
  ;; Most cases splice the read form into lambdas whose variables belong to the
  ;; test package. Bind it explicitly rather than relying on runner state.
  (let ((*package* (find-package :sophie-lisp.tests))
        (*readtable* (named-readtables:find-readtable :sl-core-syntax)))
    (read-from-string text)))

(defun literal-large-text (dispatch count &optional pairs)
  (with-output-to-string (out)
    (format out "#~A(" dispatch)
    (dotimes (i count)
      (if pairs (format out "~D ~D " i (- i)) (format out "~D " i)))
    (write-char #\) out)))

;; The 1,024-element cases below cannot exercise CALL-ARGUMENTS-LIMIT
;; directly; compliance is structural: LITERAL-CAPTURE uses a flat LET,
;; followed by per-element updates rather than one n-ary call.
(parachute:define-test reader-literals.vector-literals
  (let* ((*literal-effects* nil)
         (form (literal-read "#v((progn (push :one *literal-effects*) x)
                                 (progn (push :two *literal-effects*) (values y :extra)))"))
         (fn (compile nil `(lambda (x y) ,form))))
    (parachute:false *literal-effects*)
    (let ((first (funcall fn :a :b)) (second (funcall fn :c :d)))
      (parachute:is equal '(:two :one :two :one) *literal-effects*)
      (parachute:is equalp #(:a :b) first)
      (parachute:is equalp #(:c :d) second)
      (parachute:false (eq first second))
      (parachute:true (adjustable-array-p first))
      (parachute:true (array-has-fill-pointer-p first))
      (parachute:is = 2 (fill-pointer first))
      (setf (aref first 0) :changed)
      (parachute:is eq :c (aref second 0))))
  (let ((empty (eval (literal-read "#V()"))))
    (parachute:is = 0 (length empty))
    (parachute:true (adjustable-array-p empty))
    (parachute:is = 0 (fill-pointer empty)))
  (let* ((form (literal-read (literal-large-text #\v 1024))) (result (eval form)))
    (parachute:is = 1024 (length result))
    (parachute:is = 1023 (aref result 1023))))

(parachute:define-test reader-literals.hash-table-literals
  (dolist (test '(eq eql equal equalp))
    ;; Uninterned and escaped mixed-case names still designate the CL test.
    (let ((result (eval (literal-read (format nil "#H(#:|~(~A~)| :k 1)" test)))))
      (parachute:is eq test (hash-table-test result))
      (parachute:is = 1 (gethash :k result))))
  (dolist (text '("#h(:equal 1)" "#h('equal 1)"))
    (let ((result (eval (literal-read text))))
      (parachute:is eq 'equal (hash-table-test result))
      (parachute:is = 1 (hash-table-count result))))
  (parachute:is = 1 (gethash :equal (eval (literal-read "#h(:equal 1)"))))
  (parachute:is = 1 (gethash 'equal (eval (literal-read "#h('equal 1)"))))
  (let* ((*literal-effects* nil)
         (form (literal-read "#h((progn (push :k1 *literal-effects*) (copy-seq x))
                                 (progn (push :v1 *literal-effects*) 1)
                                 (progn (push :k2 *literal-effects*) (copy-seq x))
                                 (progn (push :v2 *literal-effects*) 2))"))
         (fn (compile nil `(lambda (x) ,form))))
    (parachute:false *literal-effects*)
    (let ((a (funcall fn "key")) (b (funcall fn "key")))
      (parachute:is equal '(:v2 :k2 :v1 :k1 :v2 :k2 :v1 :k1) *literal-effects*)
      (parachute:false (eq a b))
      (parachute:is = 1 (hash-table-count a))
      (parachute:is = 2 (gethash "key" a))
      (setf (gethash "key" a) 9)
      (parachute:is = 2 (gethash "key" b))))
  (let* ((form (literal-read (literal-large-text #\h 1024 t))) (result (eval form)))
    (parachute:is = 1024 (hash-table-count result))
    (parachute:is = -1023 (gethash 1023 result)))
  (let ((result (eval (literal-read "#h((values) :nil-key :nil-value (values))"))))
    (parachute:is eq :nil-key (gethash nil result))
    (parachute:false (gethash :nil-value result))
    (parachute:true (nth-value 1 (gethash :nil-value result)))
    (parachute:is = 2 (hash-table-count result))))

(parachute:define-test reader-literals.dictionary-literals
  (let* ((*literal-effects* nil)
         (form (literal-read "#d((progn (push :k1 *literal-effects*) k1)
                                 (progn (push :v1 *literal-effects*) :old)
                                 (progn (push :k2 *literal-effects*) k2)
                                 (progn (push :v2 *literal-effects*) :new))"))
         (fn (compile nil `(lambda (k1 k2) ,form)))
         (k1 (copy-seq "same")) (k2 (copy-seq "same")))
    (parachute:false *literal-effects*)
    (let ((result (funcall fn k1 k2)) (direct (sl:dict k1 :old k2 :new)))
      (parachute:is equal '(:v2 :k2 :v1 :k1) *literal-effects*)
      (parachute:true (typep result 'sl:dict))
      (parachute:is eq #'sl:equals (sl:dict-test result))
      (parachute:is = 1 (sl:dict-size result))
      (parachute:is eq :new (sl:dict-ref result k1))
      (parachute:is eq (sl:dict-ref direct k1) (sl:dict-ref result k1))))
  (parachute:is = 1 (sl:dict-size (eval (literal-read "#D(1 :old 1.0 :new)"))))
  (parachute:is = 0 (sl:dict-size (eval (literal-read "#d()"))))
  (let* ((form (literal-read (literal-large-text #\d 1024 t))) (result (eval form)))
    (parachute:is = 1024 (sl:dict-size result))
    (parachute:is = -1023 (sl:dict-ref result 1023)))
  (let* ((*literal-effects* nil) (key (make-instance 'literal-key))
         (form (literal-read "#d(key (progn (push :captured *literal-effects*) :value))"))
         (fn (compile nil `(lambda (key) ,form))))
    (funcall fn key)
    (parachute:is eq :captured (first (reverse *literal-effects*)))
    (parachute:true (member :hash *literal-effects*)))
  (let ((result (eval (literal-read "#d((values) :nil-key :nil-value (values))"))))
    (parachute:is eq :nil-key (sl:dict-ref result nil))
    (parachute:false (sl:dict-ref result :nil-value))
    (parachute:true (nth-value 1 (sl:dict-ref result :nil-value)))
    (parachute:is = 2 (sl:dict-size result))))

(parachute:define-test reader-literals.set-literals
  (let* ((*literal-effects* nil)
         (form (literal-read "#u((progn (push :first *literal-effects*) x)
                                 (progn (push :second *literal-effects*) y))"))
         (fn (compile nil `(lambda (x y) ,form))))
    (parachute:false *literal-effects*)
    (let ((result (funcall fn 1 1.0)) (direct (sl:hash-set 1 1.0)))
      (parachute:is equal '(:second :first) *literal-effects*)
      (parachute:true (sl:hash-set-p result))
      (parachute:is = 1 (sl:seq-length result))
      (parachute:is = (sl:seq-length direct) (sl:seq-length result))))
  (parachute:true (sl:hash-set-p (eval (literal-read "#U()"))))
  (let* ((form (literal-read (literal-large-text #\u 1024))) (result (eval form)))
    (parachute:is = 1024 (sl:seq-length result)))
  ;; Item-first SET-ADD and capture-before-insertion are observable without
  ;; redefining standardized constructors or methods.
  (let* ((*literal-effects* nil) (key (make-instance 'literal-key))
         (form (literal-read "#u(key (progn (push :captured *literal-effects*) :last))"))
         (fn (compile nil `(lambda (key) ,form))) (result (funcall fn key)))
    (parachute:is = 2 (sl:seq-length result))
    (parachute:is eq :captured (first (reverse *literal-effects*)))
    (parachute:true (member :hash *literal-effects*))))

(parachute:define-test reader-literals.read-eval-and-packages
  (let ((*literal-effects* nil) (*read-eval* t))
    (dolist (dispatch '("v" "h" "d" "u"))
      (let ((text (if (member dispatch '("h" "d") :test #'equal)
                      (format nil "#~A(:key #.(progn (push :read *literal-effects*) 9))" dispatch)
                      (format nil "#~A(#.(progn (push :read *literal-effects*) 9))" dispatch))))
        (literal-read text)
        (parachute:is eq :read (pop *literal-effects*))
        (let ((*read-eval* nil)) (parachute:fail (literal-read text) reader-error))
        (let ((*read-suppress* t)) (parachute:false (literal-read text)))
        (parachute:false *literal-effects*))))
  (let* ((*package* (find-package 'cl-user))
         (*readtable* (copy-readtable (named-readtables:find-readtable :sl-core-syntax))))
    (set-macro-character #\! (lambda (stream char) (declare (ignore stream char)) :custom)
                         nil *readtable*)
    (let ((result (eval (read-from-string "#v(! #d(:key #u(1 1.0)) 'literal-source-symbol)"))))
      (parachute:is eq :custom (aref result 0))
      (parachute:is = 1 (sl:seq-length (sl:dict-ref (aref result 1) :key)))
      (parachute:is eq (find-package 'cl-user) (symbol-package (aref result 2))))
    ;; Read the WHOLE lambda in CL-USER, not the test-package splice helper.
    (let ((fn (compile nil (read-from-string "(lambda (x) #v(x #d(:x x)))"))))
      (parachute:is = 42 (sl:dict-ref (aref (funcall fn 42) 1) :x)))
    ;; This source has only numbers and keywords. Every other symbol is
    ;; introduced, and must be an exact SL external or a non-percent gensym.
    (let ((pending (list (read-from-string "#v(1 #d(:a 2) #u(3))"))))
      (loop while pending for object = (pop pending) do
        (cond ((consp object) (push (car object) pending) (push (cdr object) pending))
              ((and (symbolp object) (not (keywordp object)))
               (if (symbol-package object)
                   (multiple-value-bind (symbol status)
                       (find-symbol (symbol-name object) :sophie-lisp)
                     (parachute:is eq object symbol)
                     (parachute:is eq :external status))
                   (parachute:false
                    (and (plusp (length (symbol-name object)))
                         (char= #\% (char (symbol-name object) 0)))))))))))

(parachute:define-test reader-literals.syntax-errors
  (dolist (text '("#h(:a)" "#h(eq :a)" "#d(:a)" "#d(equal)"))
    (parachute:fail (literal-read text) reader-error))
  (dolist (dispatch '("v" "h" "d" "u"))
    (dolist (suffix '(" ()" ";comment" "x" "(. 1)" "(1 . 2)"))
      (parachute:fail (literal-read (format nil "#~A~A" dispatch suffix)) reader-error))
    (parachute:fail (literal-read (format nil "#2~A()" dispatch)) reader-error)
    (parachute:fail (literal-read (format nil "#~A" dispatch)) end-of-file)
    (parachute:fail (literal-read (format nil "#~A(" dispatch)) end-of-file)))

(parachute:define-test reader-literals.read-suppression
  (dolist (text '("#v(#h(:odd) #d(:odd) #u(1))" "#h(eq :odd)" "#d(:odd)"
                  "#u(#d(:odd))" "#2v()" "#2h(:odd)" "#2d(:odd)" "#2u()"))
    (let ((*readtable* (named-readtables:find-readtable :sl-core-syntax)))
      (with-input-from-string (stream (concatenate 'string text " :after"))
        (let ((*read-suppress* t)) (parachute:false (read stream)))
        (parachute:is eq :after (read stream)))))
  (dolist (dispatch '("v" "h" "d" "u"))
    (let ((*readtable* (named-readtables:find-readtable :sl-core-syntax)))
      (with-input-from-string (stream (format nil "#~Ax :after" dispatch))
        (let ((*read-suppress* t)) (parachute:false (read stream)))
        (parachute:is char= #\x (peek-char nil stream))))
    (let ((*read-suppress* t))
      (parachute:fail (literal-read (format nil "#~A" dispatch)) end-of-file)
      (parachute:fail (literal-read (format nil "#~A(" dispatch)) end-of-file))))

(defvar *x-op-read-capture* nil)

(defun x-op-core-readtable ()
  (or (ignore-errors (named-readtables:find-readtable :sl-core-syntax))
      (error "SL-CORE-SYNTAX is not registered")))

(defun x-op-read (text &key (package *package*) (read-eval t) (read-suppress nil))
  (let ((*package* package)
        (*readtable* (x-op-core-readtable))
        (*read-eval* read-eval)
        (*read-suppress* read-suppress))
    (read-from-string text)))

(defun x-op-signals-p (type thunk)
  (handler-case
      (progn (funcall thunk) nil)
    (condition (condition)
      (typep condition type))))

(defun x-op-reader-error-p (text)
  (x-op-signals-p 'reader-error (lambda () (x-op-read text))))

(defun x-op-program-error-p (form)
  (x-op-signals-p 'program-error (lambda () (macroexpand-1 form))))

(defun x-op-reader-lambda (form)
  (and (consp form) (eq (car form) 'cl:lambda) form))

(defun x-op-expansion-lambda (expansion)
  (cond
    ((x-op-reader-lambda expansion) expansion)
    ((and (consp expansion)
          (eq (car expansion) 'cl:function)
          (consp (second expansion))
          (eq (car (second expansion)) 'cl:lambda))
     (second expansion))))

(defun x-op-lambda-body (lambda-form)
  (find-if-not (lambda (form)
                 (and (consp form) (eq (car form) 'cl:declare)))
               (cddr lambda-form)))

(defun x-op-generated-variable-p (object)
  (and (symbolp object)
       (null (symbol-package object))
       (plusp (length (symbol-name object)))
       (char/= #\% (char (symbol-name object) 0))))

(defun x-op-lambda-declares-ignorable-p (lambda-form variable)
  (some (lambda (form)
          (and (consp form)
               (eq (car form) 'cl:declare)
               (some (lambda (declaration)
                       (and (consp declaration)
                            (eq (car declaration) 'cl:ignorable)
                            (member variable (cdr declaration) :test #'eq)))
                     (cdr form))))
        (cddr lambda-form)))

(parachute:define-test reader-op.placeholder-parameters
  (let* ((lambda-form (x-op-read "#^(list % %1 %01 %2 %& %2)"))
         (parameters (second lambda-form))
         (body (x-op-lambda-body lambda-form))
         (first-parameter (first parameters))
         (second-parameter (second parameters))
         (rest-parameter (fourth parameters)))
    (parachute:true (x-op-reader-lambda lambda-form))
    (parachute:is = 4 (length parameters))
    (parachute:is eq 'cl:&rest (third parameters))
    (parachute:true (x-op-generated-variable-p first-parameter))
    (parachute:true (x-op-generated-variable-p second-parameter))
    (parachute:true (x-op-generated-variable-p rest-parameter))
    (parachute:false (char= #\% (char (symbol-name first-parameter) 0)))
    (parachute:false (char= #\% (char (symbol-name second-parameter) 0)))
    (parachute:false (char= #\% (char (symbol-name rest-parameter) 0)))
    (parachute:is eq first-parameter (second body))
    (parachute:is eq first-parameter (third body))
    (parachute:is eq first-parameter (fourth body))
    (parachute:is eq second-parameter (fifth body))
    (parachute:is eq rest-parameter (sixth body))
    (parachute:is eq second-parameter (seventh body)))
  (let* ((lambda-form (x-op-read "#^(list %2)"))
         (parameters (second lambda-form)))
    (parachute:is = 2 (length parameters))
    (parachute:true (x-op-lambda-declares-ignorable-p
                     lambda-form (first parameters)))
    (parachute:false (x-op-lambda-declares-ignorable-p
                      lambda-form (second parameters))))
  (let ((lambda-form (x-op-read "#^(quote :no-placeholders)")))
    (parachute:false (second lambda-form))
    (parachute:true (null (second lambda-form)))
    (parachute:is eq 'cl:quote (car (x-op-lambda-body lambda-form)))))

(parachute:define-test reader-op.structural-copying
  (let* ((first-placeholder (make-symbol "%1"))
         (second-placeholder (make-symbol "%2"))
         (vector (vector second-placeholder))
         (opaque (make-hash-table :test #'eq))
         (nested (list 'sophie-lisp:op (list 'cl:list second-placeholder)))
         (expression (list 'cl:list first-placeholder vector opaque nested))
         (input (list 'sophie-lisp:op expression)))
    (setf (gethash second-placeholder opaque) :opaque)
    (macroexpand-1 input)
    (parachute:is eq first-placeholder (second expression))
    (parachute:is eq second-placeholder (aref vector 0))
    (parachute:is eq :opaque (gethash second-placeholder opaque))))

(parachute:define-test reader-op.syntax-and-suppression
  (parachute:true (x-op-reader-error-p "#^()"))
  (parachute:true (x-op-reader-error-p "#^(list %1 . %2)"))
  (parachute:true (x-op-reader-error-p "#^((list %1) . %2)"))
  (let* ((lambda-form (x-op-read "#^(list (cons %1 . %2))"))
         (parameters (second lambda-form))
         (nested (second (x-op-lambda-body lambda-form))))
    (parachute:is = 2 (length parameters))
    (parachute:is eq 'cl:cons (car nested))
    (parachute:is eq (first parameters) (cadr nested))
    (parachute:is eq (second parameters) (cddr nested)))
  (with-input-from-string (stream "#^(list %1) 73")
    (let ((*readtable* (x-op-core-readtable)))
      (let ((first-form (read stream))
            (trailing (read stream nil :eof)))
        (parachute:true (x-op-reader-lambda first-form))
        (parachute:is = 73 trailing))))
  (parachute:is eq nil (x-op-read "#^(list %1)" :read-suppress t))
  (parachute:is eq nil (x-op-read "#^(list bad . %2)" :read-suppress t))
  (parachute:is eq nil (x-op-read "#^ x" :read-suppress t))
  (parachute:true (x-op-reader-error-p "#^ list"))
  (parachute:true (x-op-reader-error-p "#1^(list %1)"))
  (parachute:true
   (x-op-signals-p 'end-of-file (lambda () (x-op-read "#^")))))

(parachute:define-test reader-op.placeholder-validation
  (dolist (name '("%0" "%foo" "%1x" "%+1"))
    (parachute:true
     (x-op-reader-error-p
      (format nil "#^(list ~A)" name)))
    (let ((expression (list 'cl:list (make-symbol name))))
      (parachute:true
       (x-op-program-error-p (list 'sophie-lisp:op expression)))))
  (let ((too-large-name
          (format nil "%~D" (1+ cl:lambda-parameters-limit))))
    (parachute:true
     (x-op-reader-error-p
      (format nil "#^(list ~A)" too-large-name)))
    (parachute:true
     (x-op-program-error-p
      (list 'sophie-lisp:op
            (list 'cl:list (make-symbol too-large-name))))))
  (let ((maximum-name
          (format nil "%~D" cl:lambda-parameters-limit)))
    (parachute:true
     (x-op-reader-error-p
      (format nil "#^(list ~A %&)" maximum-name)))
    (parachute:true
     (x-op-program-error-p
      (list 'sophie-lisp:op
            (list 'cl:list (make-symbol maximum-name)
                  (make-symbol "%&")))))))

(parachute:define-test reader-op.read-time-evaluation
  (let* ((*x-op-read-capture* nil)
         (lambda-form
           (x-op-read
            "#^(list #.(setf *x-op-read-capture*
                             (cons (make-symbol \"%1\") nil)))"))
         (parameters (second lambda-form))
         (body (x-op-lambda-body lambda-form))
         (captured *x-op-read-capture*))
    (parachute:true (consp captured))
    (parachute:is eq captured (second body))
    (parachute:is eq (first parameters) (car captured)))
  (let* ((*x-op-read-capture* nil)
         (lambda-form
           (x-op-read
            "#^(list #.(setf *x-op-read-capture*
                             (vector (make-symbol \"%2\"))))"))
         (parameters (second lambda-form))
         (body (x-op-lambda-body lambda-form))
         (captured *x-op-read-capture*))
    (parachute:true (vectorp captured))
    (parachute:is = 2 (length parameters))
    (parachute:is eq captured (second body))
    (parachute:is eq (second parameters) (aref captured 0)))
  (let* ((standard-dot (get-dispatch-macro-character #\# #\. nil))
         (core (x-op-core-readtable)))
    (parachute:true standard-dot)
    (let ((*readtable* core) (*read-eval* t))
      (parachute:is = 3 (read-from-string "#.(+ 1 2)")))
    (parachute:is eq standard-dot
                  (get-dispatch-macro-character #\# #\. nil)))
  (parachute:true
   (x-op-signals-p
    'reader-error
    (lambda ()
      (x-op-read "#^(list #.(+ 1 2))" :read-eval nil)))))

(parachute:define-test reader-op.circular-structure
  (let* ((placeholder (make-symbol "%1"))
         (vector (vector placeholder))
         (expression (list 'cl:list vector))
         (input (list 'sophie-lisp:op expression)))
    (macroexpand-1 input)
    (macroexpand-1 input)
    (parachute:is eq placeholder (aref vector 0)))
  (let* ((placeholder (make-symbol "%1"))
         (cycle (cons placeholder nil)))
    (setf (cdr cycle) cycle)
    (macroexpand-1 (list 'sophie-lisp:op cycle))
    (parachute:is eq placeholder (car cycle))
    (parachute:is eq cycle (cdr cycle)))
  (let* ((placeholder (make-symbol "%1"))
         (cycle (make-array 2))
         (expression (list 'cl:list cycle)))
    (setf (aref cycle 0) placeholder
          (aref cycle 1) cycle)
    (macroexpand-1 (list 'sophie-lisp:op expression))
    (parachute:is eq placeholder (aref cycle 0))
    (parachute:is eq cycle (aref cycle 1)))
  (let* ((placeholder (make-symbol "%1"))
         (table (make-hash-table :test #'eq))
         (expression (list 'cl:list table placeholder)))
    (setf (gethash placeholder table) :untouched)
    (macroexpand-1 (list 'sophie-lisp:op expression))
    (parachute:is eq :untouched (gethash placeholder table))))

(parachute:define-test reader-op.runtime-and-macro-usage
  (let ((caller-value :caller))
    (declare (ignorable caller-value))
    (parachute:is eql :argument
                  (let ((%1 caller-value))
                    (funcall (sophie-lisp:op %1) :argument))))
  (parachute:is equal '(:argument (:argument))
                (multiple-value-list
                 (funcall (sophie-lisp:op (cl:values %1 (cl:list %1)))
                          :argument)))
  (let* ((lambda-form (x-op-read "#^(+ %1)"))
         (parameters (second lambda-form)))
    (parachute:is eq 'cl:lambda (car lambda-form))
    (parachute:is = 1 (length parameters))
    (parachute:true (x-op-generated-variable-p (first parameters)))
    (parachute:is eq 'cl:+ (car (x-op-lambda-body lambda-form))))
  (let* ((package (make-package (symbol-name (gensym "X-OP-HOSTILE-"))
                                :use nil)))
    (unwind-protect
         (let* ((lambda-form (x-op-read "#^(foo %1)" :package package))
                (body (x-op-lambda-body lambda-form)))
           (parachute:is eq 'cl:lambda (car lambda-form))
           (parachute:is eq (find-symbol "FOO" package) (car body)))
      (delete-package package)))
  (let ((ordinary (copy-readtable nil))
        (ambient *readtable*)
        (input (list 'sophie-lisp:op (list 'cl:list (make-symbol "%1")))))
    (let ((*readtable* ordinary))
      (let ((expansion (macroexpand-1 input)))
        (parachute:is equal '((:argument))
                      (multiple-value-list (funcall (eval expansion) :argument)))))
    (parachute:is eq ambient *readtable*))
  (parachute:true (x-op-program-error-p '(sophie-lisp:op)))
  (parachute:true
   (x-op-program-error-p '(sophie-lisp:op (cl:list %1) extra)))
  (parachute:true
   (x-op-program-error-p
    (cons 'sophie-lisp:op
          (cons (list 'cl:list (make-symbol "%1"))
                (make-symbol "TAIL"))))))

(defvar *xri-effects* 0)
(defvar *xri-payload* nil)

(defun xri-table ()
  (or (named-readtables:find-readtable :sl-core-syntax)
      (error "Completed Sophie readtable is absent")))

(defun xri-read (text)
  (read-from-string text))

(defun xri-symbols (object)
  "Identity-safe structural inventory, not a reader implementation oracle."
  (let ((seen (make-hash-table :test #'eq)) (symbols nil))
    (labels ((visit (x)
               (cond ((symbolp x) (pushnew x symbols :test #'eq))
                     ((or (consp x) (vectorp x))
                      (unless (gethash x seen)
                        (setf (gethash x seen) t)
                        (if (consp x)
                            (progn (visit (car x)) (visit (cdr x)))
                            (map nil #'visit x)))))))
      (visit object))
    symbols))

(defun xri-generated-p (symbol)
  (and (symbolp symbol) (null (symbol-package symbol))
       (plusp (length (symbol-name symbol)))
       (char/= #\% (char (symbol-name symbol) 0))))

(defun xri-public-p (symbol)
  (multiple-value-bind (found status)
      (find-symbol (symbol-name symbol) :sophie-lisp)
    (and (eq symbol found) (eq status :external))))

(defun xri-snapshot (table)
  "Compare identities only before/after on THIS table, never across copies."
  (list (readtable-case (or table (copy-readtable nil)))
        (loop for code below 128 for char = (code-char code)
              collect (multiple-value-list (get-macro-character char table)))
        (loop for code below 128
              collect (get-dispatch-macro-character #\# (code-char code) table))))

(defun xri-body (form)
  (find-if-not (lambda (x) (and (consp x) (eq (car x) 'declare)))
               (cddr form)))

(parachute:define-test reader.hostile-package-identities
  (let* ((ambient *readtable*)
         (package (make-package (symbol-name (gensym "XRI-HOSTILE-")) :use nil))
         (core (xri-table)))
    (unwind-protect
         (let ((*package* package) (*readtable* core) (*read-eval* t))
           ;; A no-use package gives EVERY unqualified operator a hostile identity.
           (dolist (name '("LAMBDA" "LET" "LET*" "PROGN" "VECTOR" "DICT"
                           "HASH-SET" "MAKE-ARRAY" "NIL" "T" "SOURCE"))
             (intern name package))
           (loop for char across "^VHD U?" unless (char= char #\Space) do
             (parachute:true (get-dispatch-macro-character #\# char core))
             (parachute:is eq (get-dispatch-macro-character #\# char core)
                           (get-dispatch-macro-character #\# (char-downcase char) core)))
           (dolist (text '("#^(source %2 %&)" "#v(source)" "#h(source 2)"
                           "#d(source 2)" "#u(source)" "#?\"${source}\""))
             (let* ((first (xri-read text)) (second (xri-read text))
                    (source (find-symbol "SOURCE" package))
                    (symbols (xri-symbols first))
                    (generated (remove-if-not #'xri-generated-p symbols)))
               (parachute:true (member source symbols))
               (parachute:true (every (lambda (s)
                                       (or (eq s source) (xri-public-p s)
                                           (xri-generated-p s))) symbols))
               (parachute:false (intersection generated (xri-symbols second)))
               (parachute:true (xri-public-p (car first)))))
           (parachute:false (package-use-list package))
           (parachute:is eq package *package*)
           (parachute:is = 19 (funcall (eval (xri-read "#^(cl:+ % 1)")) 18))
           (dolist (text '("#v(1)" "#V(1)" "#h(1 2)" "#H(1 2)"
                           "#d(1 2)" "#D(1 2)" "#u(1)" "#U(1)"))
             (parachute:true (consp (xri-read text)))))
      (delete-package package))
    (parachute:is eq ambient *readtable*)))

(parachute:define-test reader.custom-reader-context
  (let* ((*readtable* (copy-readtable (xri-table)))
         (*package* (find-package :sophie-lisp.tests))
         (*read-eval* t) (*xri-effects* 0)
         (calls nil) (table *readtable*) (package *package*))
    (set-macro-character
     #\! (lambda (stream char)
           (declare (ignore stream char))
           (push (list *package* *readtable* *read-suppress* *read-eval*) calls)
           17) nil table)
    (dolist (text '("#^(list !)" "#v(!)" "#h(! 1)" "#d(! 1)" "#u(!)"
                    "#?\"${!}\""))
      (setf calls nil)
      (xri-read text)
      (parachute:is = 1 (length calls))
      (parachute:is eq package (first (first calls)))
      ;; Interpolation may copy a table to delimit braces; its custom macro must survive.
      (parachute:is eq (get-macro-character #\! table)
                    (get-macro-character #\! (second (first calls))))
      (parachute:false (third (first calls)))
      (parachute:true (fourth (first calls))))
    (dolist (text '("#^((incf sophie-lisp.tests::*xri-effects*))"
                    "#v((incf sophie-lisp.tests::*xri-effects*))"
                    "#h(1 (incf sophie-lisp.tests::*xri-effects*))"
                    "#d(1 (incf sophie-lisp.tests::*xri-effects*))"
                    "#u((incf sophie-lisp.tests::*xri-effects*))"
                    "#?\"${(incf sophie-lisp.tests::*xri-effects*)}\""))
      (xri-read text)
      (parachute:is = 0 *xri-effects*))
    (let ((form (xri-read "#v(#h(:k #v(3)) #d(:k #u(4)) #^(+ % 1) #?\"plain\")")))
      (let ((value (eval form)))
        (parachute:is = 3 (aref (gethash :k (aref value 0)) 0))
        (parachute:true (sl:dictp (aref value 1)))
        (parachute:is = 9 (funcall (aref value 2) 8))
        (parachute:is string= "plain" (aref value 3))))
    (let ((before (xri-snapshot table)))
      (parachute:fail (xri-read "#?\"${#v(1 . 2)}\"") reader-error)
      (parachute:is eq table *readtable*)
      (parachute:is equal before (xri-snapshot table))
      (parachute:is eq package *package*)
      (parachute:is = 17 (xri-read "!")))))

(parachute:define-test reader.read-suppression
  (let ((*readtable* (copy-readtable (xri-table))) (*read-eval* nil)
        (*xri-effects* 0) (observed nil))
    (set-macro-character #\! (lambda (s c) (declare (ignore s c))
                              (push (list *read-suppress* *read-eval*) observed) nil))
    (dolist (text (append
                   ;; CCL enforces #.'s *READ-EVAL* check even under
                   ;; *READ-SUPPRESS* and aborts the read; the #. fixture
                   ;; applies only where the host suppresses #. (SBCL does).
                   (when (x-int-dot-suppressed-p)
                     '("#9^(bad ! #.(incf sophie-lisp.tests::*xri-effects*))"))
                   '("#9v(! #h(1) #d(2) #^() #?\"${}\")"
                     "#9h(!)" "#9d(!)" "#9u(!)" "#9?\"${!} @{} \\q\""
                     "#^()" "#h(1)" "#d(1)" "#?\"${}\""
                     "#v(#?\"${#d(1)}\")" "#?\"${#v(#h(1) #^())}\"")))
      (with-input-from-string (stream (concatenate 'string text " :after"))
        (let ((*read-suppress* t)) (parachute:is eq nil (read stream)))
        (parachute:is eq :after (read stream))
        (parachute:is eq :eof (read stream nil :eof))
        (parachute:is = 0 *xri-effects*)))
    (parachute:is = (if (x-int-dot-suppressed-p) 6 5) (length observed))
    (parachute:true (every (lambda (x) (equal x '(t nil))) observed))))

(parachute:define-test reader.dispatch-boundaries
  (let ((*readtable* (xri-table)) (*read-eval* nil))
    (loop for sub across "^vhdu?" for opening = (if (char= sub #\?) #\" #\() do
      ;; Preserve whitespace to isolate handler consumption from READ itself.
      (dolist (suffix '(" " ";comment" "x"))
        (let ((text (format nil "#~C~A" sub suffix)))
          (with-input-from-string (stream text)
            (parachute:fail (read stream) reader-error)
            (parachute:is char= (char suffix 0) (peek-char nil stream)))
          (with-input-from-string (stream text)
            (let ((*read-suppress* t)) (parachute:is eq nil (read-preserving-whitespace stream)))
            (parachute:is char= (char suffix 0) (peek-char nil stream)))))
      (dolist (suppressed '(nil t))
        (let ((*read-suppress* suppressed))
          (parachute:fail (xri-read (format nil "#~C" sub)) end-of-file)
          (parachute:fail (xri-read (format nil "#~C~C" sub opening)) end-of-file)))
      (let ((valid (if (char= sub #\?) "\"plain\"" "(list)")))
        (parachute:fail (xri-read (format nil "#2~C~A" sub valid)) reader-error))
      (parachute:fail (xri-read (if (char= sub #\?) "#?\"${.}\""
                                  (format nil "#~C(.)" sub))) reader-error)
      (with-input-from-string
          (stream (if (char= sub #\?) "#?\"plain\" :after"
                      (if (find sub "hd") (format nil "#~C(1 2) :after" sub)
                          (format nil "#~C(list) :after" sub))))
        (read stream)
        (parachute:is eq :after (read stream))
        (parachute:is eq :eof (read stream nil :eof))))
    ;; Protected braces and adjacent forms belong to their nested objects.
    (dolist (text '("#?\"${#\\}}\" :after" "#?\"${\"}\"}\" :after"
                    "#?\"${'|A}B|}\" :after" "#?\"${#v(#?\"}\")}\" :after"))
      (with-input-from-string (stream text)
        (parachute:true (consp (read stream)))
        (parachute:is eq :after (read stream))))))

(parachute:define-test reader.read-time-evaluation-and-graphs
  (let* ((*readtable* (copy-readtable (xri-table)))
         (*package* (find-package :sophie-lisp.tests))
         (*read-eval* t) (*xri-effects* 0)
         (dot (get-dispatch-macro-character #\# #\. *readtable*))
         (before (xri-snapshot *readtable*)))
    (let* ((form (xri-read "#^(list %1 #.(intern \"%1\"))"))
           (parameter (first (second form))) (body (xri-body form)))
      (parachute:true (xri-generated-p parameter))
      (parachute:is eq parameter (second body))
      (parachute:is eq parameter (third body)))
    (let* ((form (xri-read "#^(list % #v(%) #h(:k %) #d(:k %) #u(%) #?\"${%}\")"))
           (value (funcall (eval form) 23)))
      (parachute:false (find-if (lambda (s) (and (plusp (length (symbol-name s)))
                                                (char= #\% (char (symbol-name s) 0))))
                               (xri-symbols form)))
      (parachute:is = 23 (aref (second value) 0))
      (parachute:is = 23 (gethash :k (third value)))
      (parachute:is = 23 (sl:dict-ref (fourth value) :k))
      (parachute:is string= "23" (sixth value)))
    ;; Aliased graph from #. is deliberately not copied/provenance-excluded.
    (let* ((cell (cons '%1 nil)) (vector (vector '%1 cell))
           (opaque (make-hash-table)) (*xri-payload* (list cell vector opaque)))
      (setf (cdr cell) cell (gethash :hidden opaque) '%bad)
      (let* ((form #+sbcl
                   (sb-ext:with-timeout 5
                     (xri-read "#^(list %1 #.sophie-lisp.tests::*xri-payload*)"))
                   #-sbcl
                   (xri-read "#^(list %1 #.sophie-lisp.tests::*xri-payload*)"))
             (parameter (first (second form))))
        (parachute:is eq parameter (car cell))
        (parachute:is eq parameter (aref vector 0))
        (parachute:is eq cell (cdr cell))
        (parachute:is eq '%bad (gethash :hidden opaque))))
    (let* ((vector (make-array 2 :initial-element '%1)) (*xri-payload* vector))
      (setf (aref vector 1) vector)
      (let ((form #+sbcl
                  (sb-ext:with-timeout 5
                    (xri-read "#^(list #.sophie-lisp.tests::*xri-payload*)"))
                  #-sbcl
                  (xri-read "#^(list #.sophie-lisp.tests::*xri-payload*)")))
        (parachute:is eq (first (second form)) (aref vector 0))
        (parachute:is eq vector (aref vector 1))))
    (dolist (text '("#^(list #.(incf sophie-lisp.tests::*xri-effects*))"
                    "#v(#.(incf sophie-lisp.tests::*xri-effects*))"
                    "#h(1 #.(incf sophie-lisp.tests::*xri-effects*))"
                    "#d(1 #.(incf sophie-lisp.tests::*xri-effects*))"
                    "#u(#.(incf sophie-lisp.tests::*xri-effects*))"
                    "#?\"${#.(incf sophie-lisp.tests::*xri-effects*)}\""))
      (let ((old *xri-effects*))
        (xri-read text)
        (parachute:is = (1+ old) *xri-effects*)
        (let ((*read-eval* nil)) (parachute:fail (xri-read text) reader-error))
        (parachute:is = (1+ old) *xri-effects*)
        (let ((*read-suppress* t)) (parachute:is eq nil (xri-read text)))
        (parachute:is = (1+ old) *xri-effects*)
        (parachute:is eq dot (get-dispatch-macro-character #\# #\. *readtable*))))
    (let ((*xri-payload* (vector '%bad)))
      (parachute:fail (xri-read "#^(list #.sophie-lisp.tests::*xri-payload*)") reader-error))
    (parachute:is equal before (xri-snapshot *readtable*))
    (set-macro-character #\! (lambda (s c) (declare (ignore s c))
                              (throw 'xri-unwind :escaped)))
    (let ((custom-before (xri-snapshot *readtable*)))
      (parachute:is eq :escaped (catch 'xri-unwind (xri-read "#?\"${#v(!)}\"")))
      (parachute:is equal custom-before (xri-snapshot *readtable*)))
    (parachute:is = 3 (xri-read "#.(+ 1 2)"))
    (parachute:is eq dot (get-dispatch-macro-character #\# #\. *readtable*))))

;; The cold child below runs under the roswell DEFAULT implementation
;; (SBCL) with an SB-EXT debugger form, regardless of the host running
;; this suite; it never counts as CCL/ECL coverage.
(defun xri-cold-check (mode)
  "Cold child: dependencies first, then poison ambient state, then load Sophie.
Current ASDF components, not a hand-maintained abbreviated source list,
are loaded. Child output is isolated."
  (let* ((root (asdf:system-source-directory "sophie-lisp"))
         (directory
           (uiop:ensure-directory-pathname
            (string-trim '(#\Newline #\Return)
                         (uiop:run-program
                          (list "mktemp" "-d"
                                (namestring
                                 (merge-pathnames "xri-cold-XXXXXXXXXX"
                                                  (uiop:temporary-directory))))
                          :input nil :output :string))))
         (script (merge-pathnames "cold.lisp" directory))
         (result (merge-pathnames "result.sexp" directory)))
    (unwind-protect
        (progn
      (ensure-directories-exist script)
      (with-open-file (out script :direction :output :if-exists :error)
        (let ((*package* (find-package :sophie-lisp.tests)) (*print-pretty* nil)
              (*print-case* :upcase) (*print-readably* nil) (*print-escape* t))
          ;; Emit the ASDF-touching prologue as text: WRITE would serialize
          ;; ASDF symbols with host-specific home-package qualifiers (SBCL
          ;; prints ASDF/SYSTEM-REGISTRY:*CENTRAL-REGISTRY*, ECL prints
          ;; ASDF/FIND-SYSTEM:*CENTRAL-REGISTRY*), which the child's own
          ;; ASDF need not be able to read back.
          (format out "(require :asdf)~%")
          (format out "(setf asdf:*central-registry* nil)~%")
          (format out "(asdf:initialize-source-registry~%")
          (format out " '(:source-registry (:directory ~S)~%" (namestring root))
          (dolist (system '("named-readtables" "closer-mop" "alexandria"
                            "bordeaux-threads" "trivial-garbage"))
            (format out "   (:directory ~S)~%"
                    (namestring (asdf:system-source-directory system))))
          (format out "   :ignore-inherited-configuration))~%")
          (format out "(asdf:initialize-output-translations~%")
          (format out " '(:output-translations (t ~S)~%"
                  (namestring (merge-pathnames "fasls/" directory)))
          (format out "   :ignore-inherited-configuration))~%")
          (format out "(dolist (s '~S)~%"
                  '("named-readtables" "closer-mop" "alexandria"
                    "bordeaux-threads" "trivial-garbage"))
          (format out "  (asdf:load-system s))~%")
          (format out "(assert (not (find-package \"SOPHIE-LISP\")))~%")
          (format out "(defstruct xri-standard-structure value)~%")
          (format out "(asdf:load-asd ~S)~%"
                  (namestring (merge-pathnames "sophie-lisp.asd" root)))
          ;; Printed unqualified fixture names are read in child CL-USER. No parent
          ;; package or helper definition is required in the cold process.
          (write
           `(labels ((snapshot (table)
                       (list
                        (loop for i below 128 collect
                          (multiple-value-list (get-macro-character (code-char i) table)))
                        (loop for i below 128 collect
                          (get-dispatch-macro-character #\# (code-char i) table))))
                     (files (component)
                       (if (typep component 'asdf:parent-component)
                           (mapcan #'files (asdf:component-children component))
                           (list (asdf:component-pathname component)))))
              (let* ((ambient (copy-readtable nil)) (*readtable* ambient)
                     (package *package*) (uses (copy-list (package-use-list package)))
                     (standard-before (snapshot nil))
                     (pristine (copy-readtable nil)))
                (set-macro-character #\$ (lambda (s c) (declare (ignore s c)) :poison) nil ambient)
                (set-syntax-from-char #\! #\Space ambient nil)
                (set-dispatch-macro-character #\# #\Z
                  (lambda (s c n) (declare (ignore s c n)) :poison) ambient)
                (let ((ambient-before (snapshot ambient)))
                  ,(if (string= mode "compiled")
                       '(asdf:load-system "sophie-lisp" :force t)
                       '(dolist (source (files (asdf:find-system "sophie-lisp"))) (load source)))
                  (assert (eq ambient *readtable*))
                  (assert (eq package *package*))
                  (assert (equal uses (package-use-list package)))
                  (assert (equal standard-before (snapshot nil)))
                  (assert (equal ambient-before (snapshot ambient)))
                  (let* ((core (named-readtables:find-readtable :sl-core-syntax))
                         (core-before (snapshot core)))
                    (assert core)
                    (loop for c across "^vhdu?" do
                      (assert (get-dispatch-macro-character #\# c core)))
                    (let ((*readtable* core))
                      (assert (eq package *package*))
                      (assert (eq (intern "$" package) (read-from-string "$")))
                      (assert (eq (intern "A!B" package) (read-from-string "A!B")))
                      (assert (null (get-dispatch-macro-character #\# #\Z core)))
                      ;; Behavioral comparison across copies, including standard
                      ;; defined dispatch families with readable, noncyclic fixtures.
                      (dolist (text '("(1 . 2)" "'car" "#'car" "\"text\"" "#\\Space"
                                      "#(1 2)" "#*101" "#b101" "#B101" "#o17" "#O17"
                                      "#x1f" "#X1f" "#16r1f" "#16R1f" "#c(1 2)" "#C(1 2)"
                                      "#2a((1 2)(3 4))" "#2A((1 2)(3 4))"
                                      "#p\"relative\"" "#P\"relative\""
                                      "#s(xri-standard-structure :value 7)"
                                      "#S(xri-standard-structure :value 7)"
                                      "#.(+ 1 2)" "#+(and) 3" "#-(or) 3"
                                      "#|comment|# 3" "(#1=(a b) #1#)"))
                        (let ((expected (let ((*readtable* pristine)) (read-from-string text))))
                          (assert (equalp expected (read-from-string text)))))
                      (let ((symbol (read-from-string "#:uninterned")))
                        (assert (string= "UNINTERNED" (symbol-name symbol)))
                        (assert (null (symbol-package symbol)))))
                    (assert (eq ambient *readtable*))
                    (assert (equal core-before (snapshot core)))
                    (assert (equal standard-before (snapshot nil)))
                    (assert (equal ambient-before (snapshot ambient)))
                    (with-open-file (s ,(namestring result) :direction :output :if-exists :error)
                      (write '(:cold-reader :passed) :stream s))))))
           :stream out)
          (terpri out)))
      (multiple-value-bind (stdout stderr code)
          (uiop:run-program
           (list "timeout" "100s" "ros" "run" "--non-interactive" "--eval"
                 "(sb-ext:disable-debugger)" "--load" (namestring script))
           :input nil :output :string :error-output :string :ignore-error-status t)
        (with-open-file (log (merge-pathnames "child.log" directory)
                             :direction :output :if-exists :error)
          (write-string stdout log)
          (write-string stderr log))
        (unless (zerop code)
          (error "Cold reader ~A child exit ~D~%~A~%~A" mode code stdout stderr)))
      (with-open-file (in result)
        (let ((*read-eval* nil))
          (and (equal '(:cold-reader :passed) (read in))
               (eq :eof (read in nil :eof))))))
      ;; The deletion is the UNWIND-PROTECT cleanup, so the function returns
      ;; the result check's value: UIOP's DELETE-DIRECTORY-TREE return value
      ;; is unspecified (NIL on ECL), which the former stray body placement
      ;; silently returned instead.
      (ignore-errors
        (uiop:delete-directory-tree directory :validate t)))))

(defvar *x-print-force-count* 0)
(defvar *x-print-interpolation-object* nil)

(defun x-print-current (object)
  (with-output-to-string (stream)
    (write object :stream stream)))

(defun x-print-unreadable (object)
  (let ((*print-readably* nil) (*print-escape* t) (*print-pretty* nil)
        (*print-circle* nil) (*print-level* nil) (*print-length* nil)
        (*print-base* 10) (*print-radix* nil) (*print-case* :upcase))
    (x-print-current object)))

(defun x-print-readable (object)
  (let ((*print-readably* t) (*print-escape* t) (*print-pretty* nil)
        (*print-circle* nil) (*print-level* nil) (*print-length* nil)
        (*print-base* 10) (*print-radix* nil) (*print-case* :upcase))
    (x-print-current object)))

(defun x-print-caught-condition (thunk)
  (handler-case
      (progn (funcall thunk) nil)
    (condition (condition) condition)))

(defun x-print-read-eval (text)
  (let ((*package* (find-package :sophie-lisp.tests))
        (*readtable* (copy-readtable
                      (named-readtables:find-readtable :sl-core-syntax)))
        (*read-eval* nil))
    (eval (read-from-string text))))

(defun x-print-interpolate (object)
  (let ((*x-print-interpolation-object* object))
    (x-print-read-eval
     "#?\"${sophie-lisp.tests::*x-print-interpolation-object*}\"")))

(defun x-print-digit-label-p (text)
  (loop for i below (length text)
        when (char= #\# (char text i))
          do (let ((j (1+ i)))
               (loop while (and (< j (length text))
                                (digit-char-p (char text j)))
                     do (incf j))
               (when (and (> j (1+ i))
                          (< j (length text))
                          (char= #\= (char text j)))
                 (return t)))))

(defvar *x-print-child-visits* 0)

(define-condition x-print-child-error (error) ())

(defclass x-print-sentinel ()
  ((condition :initarg :condition :reader x-print-sentinel-condition)))

(defmethod print-object ((object x-print-sentinel) stream)
  (declare (ignore stream))
  (incf *x-print-child-visits*)
  (error (x-print-sentinel-condition object)))

;; A public-protocol subclass deliberately has no resident trie elements.
;; Its two immutable elements are visible only through the open protocols.
(defclass x-print-public-set (sl:hash-set) ())

(defmethod sl:seqablep ((object x-print-public-set)) t)

(defmethod sl:seq-emptyp ((object x-print-public-set)) nil)

(defmethod sl:seq-first ((object x-print-public-set)) 731)

(defmethod sl:seq-rest ((object x-print-public-set)) (list 947))

(defmethod sl:seq-length ((object x-print-public-set)) 2)

(defun x-print-member-p (item sequence)
  ;; These finite fixtures use the container provider's coherent public rest.
  ;; Test emptiness, not FIRST: NIL is an ordinary element, and order is ignored.
  (loop for rest = sequence then (sl:seq-rest rest)
        until (sl:seq-emptyp rest)
        thereis (sl:equals item (sl:seq-first rest))))

(defun x-print-controls (object &key level length pretty readable circle)
  (let ((*print-readably* readable) (*print-escape* t)
        (*print-level* level) (*print-length* length)
        (*print-pretty* pretty) (*print-circle* circle)
        (*print-base* 10) (*print-radix* nil) (*print-case* :upcase))
    (x-print-current object)))

;; Only use this on numeric/keyword fixtures, never strings containing spaces.
(defun x-print-compact (text)
  (remove-if (lambda (char) (find char '(#\Space #\Tab #\Newline #\Return)))
             text))

(defun x-print-matching-label-p (text)
  (and (stringp text)
       (loop for i below (length text)
             thereis
             (and (char= #\# (char text i))
                  (let ((j (1+ i)))
                    (loop while (and (< j (length text))
                                     (digit-char-p (char text j)))
                          do (incf j))
                    (and (> j (1+ i)) (< j (length text))
                         (char= #\= (char text j))
                         (search (concatenate 'string (subseq text i j) "#")
                                 text :start2 (1+ j))))))))

(parachute:define-test printing.map-entry
  ;; MAP-ENTRY is tested as its own value. Its fields are lazy nodes whose
  ;; counters make any accidental field observation visible.
  (let* ((*x-print-force-count* 0)
         (key (sl:make-lazy-seq
               (lambda ()
                 (incf *x-print-force-count*)
                 (sl:lazy-cons :key-tail nil))))
         (value (sl:make-lazy-seq
                 (lambda ()
                   (incf *x-print-force-count*)
                   (sl:lazy-cons :value-tail nil))))
         (entry (sl:map-entry key value))
         (printed (x-print-unreadable entry)))
    (parachute:true (typep entry 'sl:map-entry))
    (parachute:false (sl:seqablep entry))
    (parachute:false (fboundp '(setf sl:entry-key)))
    (parachute:false (fboundp '(setf sl:entry-value)))
    (parachute:is eq key (sl:entry-key entry))
    (parachute:is eq value (sl:entry-value entry))
    (parachute:true (stringp printed))
    (parachute:true (plusp (length printed)))
    (parachute:is = 0 *x-print-force-count*))
  ;; Debug-style printer variables do not turn MAP-ENTRY into a traversal.
  (let* ((*x-print-force-count* 0)
         (entry (sl:map-entry
                 (sl:make-lazy-seq
                  (lambda () (incf *x-print-force-count*) nil))
                 (sl:make-lazy-seq
                  (lambda () (incf *x-print-force-count*) nil))))
         (printed (let ((*print-readably* nil) (*print-escape* nil)
                        (*print-pretty* t) (*print-circle* t)
                        (*print-level* 0) (*print-length* 0))
                    (x-print-current entry))))
    (parachute:true (stringp printed))
    (parachute:is = 0 *x-print-force-count*))
  ;; Additional independent contract coverage.
  (progn
    (dolist (pretty '(nil t))
      (let* ((*x-print-child-visits* 0)
             (sentinel (make-instance 'x-print-sentinel
                                     :condition (make-condition 'x-print-child-error)))
             (entry (sl:map-entry sentinel sentinel)))
        (parachute:true (stringp (x-print-controls entry :pretty pretty)))
        (parachute:is = 0 *x-print-child-visits*)))))

(parachute:define-test printing.map-entry-readable-errors
  (let* ((*x-print-force-count* 0)
         (entry (sl:map-entry
                 (sl:make-lazy-seq
                  (lambda () (incf *x-print-force-count*) nil))
                 (sl:make-lazy-seq
                  (lambda () (incf *x-print-force-count*) nil))))
         (condition (x-print-caught-condition
                     (lambda () (x-print-readable entry)))))
    (parachute:true (typep condition 'print-not-readable))
    (parachute:is = 0 *x-print-force-count*))
  ;; Additional independent contract coverage.
  (progn
    (let* ((entry (sl:map-entry :key :value))
           (condition (x-print-caught-condition
                       (lambda () (x-print-readable entry)))))
      (parachute:true (and (typep condition 'print-not-readable)
                           (eq entry (print-not-readable-object condition)))))))

(parachute:define-test printing.lazy-sequences
  (let* ((*x-print-force-count* 0)
         (node (sl:make-lazy-seq
                (lambda ()
                  (incf *x-print-force-count*)
                  (sl:lazy-cons :forced nil))))
         (printed (x-print-unreadable node)))
    (parachute:true (stringp printed))
    (parachute:is = 0 *x-print-force-count*)
    (parachute:true (sl:lazy-seq-p node))
    (let ((condition (x-print-caught-condition
                      (lambda () (x-print-readable node)))))
      (parachute:true (typep condition 'print-not-readable)))
    (parachute:is = 0 *x-print-force-count*)
    ;; These settings must not force an unresolved node; no alternate unreadable
    ;; spelling is made normative here.
    (dolist (settings '((nil nil t 0 0)
                        (t nil nil 1 1)
                        (nil t t nil 1)))
      (destructuring-bind (escape pretty circle level length) settings
        (let ((*print-readably* nil) (*print-escape* escape)
              (*print-pretty* pretty) (*print-circle* circle)
              (*print-level* level) (*print-length* length))
          (parachute:true (stringp (x-print-current node))))
        (parachute:is = 0 *x-print-force-count*)))
    ;; A later public observation still performs the one deferred computation;
    ;; printing did not resolve or memoize the node.
    (parachute:is eq :forced (sl:seq-first node))
    (parachute:is = 1 *x-print-force-count*)
    (x-print-unreadable node)
    (parachute:is = 1 *x-print-force-count*))
  ;; Additional independent contract coverage.
  (progn
    (let* ((*x-print-force-count* 0)
           (empty (sl:make-lazy-seq
                   (lambda () (incf *x-print-force-count*) nil))))
      (parachute:true (sl:seq-emptyp empty))
      (parachute:is = 1 *x-print-force-count*)
      (dolist (pretty '(nil t))
        (parachute:true (stringp (x-print-controls empty :pretty pretty)))
        (parachute:is = 1 *x-print-force-count*))
      (parachute:true (sl:seq-emptyp empty))
      (parachute:is = 1 *x-print-force-count*))
    (let* ((head-count 0) (tail-count 0)
           (tail (sl:make-lazy-seq
                  (lambda () (incf tail-count) (sl:lazy-cons :tail nil))))
           (node (sl:make-lazy-seq
                  (lambda () (incf head-count) (sl:lazy-cons :head tail)))))
      (parachute:is eq :head (sl:seq-first node))
      (dolist (pretty '(nil t))
        (parachute:true (stringp (x-print-controls node :pretty pretty :circle t)))
        (parachute:is = 0 tail-count))
      (let ((condition (x-print-caught-condition
                        (lambda () (x-print-readable node)))))
        (parachute:true (and (typep condition 'print-not-readable)
                             (eq node (print-not-readable-object condition)))))
      (parachute:is = 0 tail-count)
      (parachute:is eq :head (sl:seq-first node))
      (parachute:is = 1 head-count)
      (parachute:is eq :tail (sl:seq-first tail))
      (parachute:is = 1 tail-count)
      (x-print-unreadable node)
      (parachute:is eq :tail (sl:seq-first tail))
      (parachute:is = 1 tail-count))))

(parachute:define-test printing.dictionaries
  (let* ((dict (sl:dict :alpha 1 :beta "two" :gamma #\G :delta nil))
         (plain (x-print-unreadable dict))
         (readable (x-print-readable dict))
         (roundtrip (x-print-read-eval readable)))
    (parachute:true (search "#d(" plain :test #'char-equal))
    (parachute:true (search "#d(" readable :test #'char-equal))
    (parachute:true (typep roundtrip 'sl:dict))
    (parachute:is = 4 (sl:dict-size roundtrip))
    (dolist (pair '((:alpha 1) (:beta "two") (:gamma #\G) (:delta nil)))
      (let ((values (multiple-value-list
                     (sl:dict-ref roundtrip (first pair)))))
        (parachute:is = 2 (length values))
        (parachute:is equal (second pair) (first values))
        (parachute:true (second values))))
    ;; No order is inferred from the printed association sequence.
    (parachute:is = 4 (sl:dict-size dict)))
  ;; Both key and value positions are unreadable when they contain a direct
  ;; MAP-ENTRY; the entry is not copied into a printable surrogate.
  (let ((entry (sl:map-entry :nested 1)))
    (dolist (dict (list (sl:dict :value entry)
                        (sl:dict entry :value)))
      (let ((condition (x-print-caught-condition
                        (lambda () (x-print-readable dict)))))
        (parachute:true (typep condition 'print-not-readable)))))
  ;; ANSI child printer controls are retained for ordinary children. Only the
  ;; fact of truncation is normative here, not a particular dict order.
  (let* ((dict (sl:dict :payload (list :a :b :c)))
         (full (let ((*print-readably* nil) (*print-length* nil)
                     (*print-level* nil) (*print-circle* nil))
                 (x-print-current dict)))
         (short (let ((*print-readably* nil) (*print-length* 1)
                      (*print-level* nil) (*print-circle* nil))
                  (x-print-current dict)))
         (shallow (let ((*print-readably* nil) (*print-length* nil)
                        (*print-level* 0) (*print-circle* nil))
                    (x-print-current dict))))
    (parachute:false (string= full short))
    (parachute:true (search "..." short))
    (parachute:false (string= full shallow)))
  ;; Additional independent contract coverage.
  (progn
    (parachute:is string-equal "#d()" (x-print-unreadable (sl:dict)))
    (parachute:is string-equal "#d()" (x-print-readable (sl:dict)))
    (dolist (pretty '(nil t))
      (let ((dict (sl:dict 11 101 22 202)))
        (parachute:is string-equal "#d(...)"
                      (x-print-controls dict :length 0 :pretty pretty))
        (parachute:true
         (member (x-print-controls dict :length 1 :pretty pretty)
                 '("#d(11 101 ...)" "#d(22 202 ...)") :test #'string-equal))
        (let ((exact (x-print-controls dict :length 2 :pretty pretty)))
          (parachute:false (search "..." exact))
          (let ((copy (x-print-read-eval exact)))
            (parachute:is = 2 (sl:dict-size copy))
            (parachute:is = 101 (sl:dict-ref copy 11))
            (parachute:is = 202 (sl:dict-ref copy 22))))
        (parachute:is string= "#" (x-print-controls dict :level 0 :pretty pretty))))))

(parachute:define-test printing.sets
  (let* ((set (sl:hash-set :alpha 1 "two" #\G nil))
         (plain (x-print-unreadable set))
         (readable (x-print-readable set))
         (roundtrip (x-print-read-eval readable)))
    (parachute:true (search "#u(" plain :test #'char-equal))
    (parachute:true (search "#u(" readable :test #'char-equal))
    (parachute:true (typep roundtrip 'sl:hash-set))
    (parachute:is = 5 (sl:seq-length roundtrip))
    (dolist (element '(:alpha 1 "two" #\G nil))
      (parachute:true (x-print-member-p element roundtrip)))
    ;; Independent traversal order is unspecified.
    (parachute:is = 5 (sl:seq-length set)))
  (let* ((entry (sl:map-entry :nested 1))
         (set (sl:hash-set entry))
         (condition (x-print-caught-condition
                     (lambda () (x-print-readable set)))))
    (parachute:true (typep condition 'print-not-readable)))
  ;; Additional independent contract coverage.
  (progn
    (parachute:is string-equal "#u()" (x-print-unreadable (sl:hash-set)))
    (parachute:is string-equal "#u()" (x-print-readable (sl:hash-set)))
    (dolist (pretty '(nil t))
      (let ((set (sl:hash-set 11 22)))
        (parachute:is string-equal "#u(...)"
                      (x-print-controls set :length 0 :pretty pretty))
        (parachute:true
         (member (x-print-controls set :length 1 :pretty pretty)
                 '("#u(11 ...)" "#u(22 ...)") :test #'string-equal))
        (let ((exact (x-print-controls set :length 2 :pretty pretty)))
          (parachute:false (search "..." exact))
          (let ((copy (x-print-read-eval exact)))
            (parachute:is = 2 (sl:seq-length copy))
            (parachute:true (x-print-member-p 11 copy))
            (parachute:true (x-print-member-p 22 copy))))
        (parachute:is string= "#" (x-print-controls set :level 0 :pretty pretty))))
    (let* ((set (make-instance 'x-print-public-set))
           (copy (x-print-read-eval (x-print-readable set))))
      (parachute:is = 2 (sl:seq-length copy))
      (parachute:true (x-print-member-p 731 copy))
      (parachute:true (x-print-member-p 947 copy)))))

(parachute:define-test printing.nested-printing
  (let* ((entry (sl:map-entry :key :value))
         (dict (sl:dict :entry entry))
         (set (sl:hash-set entry)))
    (dolist (object (list dict set))
      (let ((condition (x-print-caught-condition
                        (lambda ()
                          (let ((*print-readably* t) (*print-escape* t))
                            (x-print-current object))))))
        (parachute:true (typep condition 'print-not-readable)))))
  ;; Direct PRINC is the oracle, including implementation-specific spelling.
  (let* ((entry (sl:map-entry :key :value))
         (*print-readably* nil) (*print-escape* nil)
         (*print-case* :downcase) (*print-base* 16) (*print-radix* t)
         (*print-level* 1) (*print-length* 1) (*print-circle* t)
         (direct (with-output-to-string (stream) (princ entry stream)))
         (interpolated (x-print-interpolate entry)))
    (parachute:is string= direct interpolated)
    (parachute:true (plusp (length direct))))
  (let* ((object (list 'alpha 255))
         (*print-readably* nil) (*print-escape* nil)
         (*print-case* :downcase) (*print-base* 16) (*print-radix* t)
         (direct (with-output-to-string (stream) (princ object stream)))
         (interpolated (x-print-interpolate object)))
    (parachute:is string= direct interpolated)
    ;; Native printers may spell radix digits as #xFF even with :DOWNCASE.
    (parachute:true (search "ff" direct :test #'char-equal)))
  ;; Native -> Sophie -> Sophie -> native depth must remain one context.
  ;; Exact per-level truncation strings are reference-host output: hosts
  ;; count PRINT-OBJECT and PPRINT-LOGICAL-BLOCK descents toward
  ;; *PRINT-LEVEL* differently (CCL elides one level later), and the host
  ;; owns depth tracking by design (see PRINT-CONTAINER). Pin the exact
  ;; strings on SBCL; every host must still collapse at level 0 and print
  ;; the full structure once the level is deep enough.
  (dolist (pretty '(nil t))
    (let ((object (list (sl:dict :k (sl:hash-set (list 7))))))
      #+sbcl
      (loop for level from 0
            for expected in '("#" "(#)" "(#d(:K#))"
                              "(#d(:K#u(#)))" "(#d(:K#u((7))))")
            do (parachute:is string-equal expected
                             (x-print-compact
                              (x-print-controls object :level level
                                                       :pretty pretty))))
      (parachute:is string-equal "#"
                    (x-print-compact (x-print-controls object :level 0
                                                        :pretty pretty)))
      (parachute:is string-equal "(#d(:K#u((7))))"
                    (x-print-compact (x-print-controls object :level 10
                                                        :pretty pretty)))))
  ;; Readable printing bypasses both limits, including at native boundaries;
  ;; it must reach the original unreadable child rather than eliding it.
  ;; Keep lazy nodes in value positions: hashing a lazy set element is itself
  ;; an observation and could force the fixture before printing begins.
  (let* ((entry (sl:map-entry :nested :entry))
         (lazy (sl:make-lazy-seq (lambda () (error "Printer forced lazy child"))))
         (fixtures (list (cons (sl:dict :k (list entry)) entry)
                         (cons (sl:dict (list entry) :v) entry)
                         (cons (sl:hash-set (list entry)) entry)
                         (cons (sl:dict :k (sl:dict :inner lazy)) lazy))))
    (dolist (pretty '(nil t))
      (dolist (limits '((0 nil) (nil 0) (0 0)))
        (dolist (fixture fixtures)
          (let ((condition
                  (x-print-caught-condition
                   (lambda ()
                     (x-print-controls (car fixture) :readable t :pretty pretty
                                       :level (first limits)
                                       :length (second limits))))))
            (parachute:true
             (and (typep condition 'print-not-readable)
                  (eq (cdr fixture) (print-not-readable-object condition)))))))))
  ;; Propagate the same condition object, not a reconstructed replacement.
  (let* ((*x-print-child-visits* 0)
         (original (make-condition 'x-print-child-error))
         (child (make-instance 'x-print-sentinel :condition original)))
    (dolist (pretty '(nil t))
      (dolist (readable '(nil t))
        (dolist (object (list (sl:dict :k child) (sl:hash-set child)))
          (parachute:is eq original
                        (x-print-caught-condition
                         (lambda () (x-print-controls object :pretty pretty
                                                             :readable readable))))))))
  (parachute:is = 2
                (sl:dict-size
                 (x-print-read-eval
                  (x-print-controls (sl:dict 1 11 2 22) :readable t
                                    :level 0 :length 0))))
  (parachute:is = 2
                (sl:seq-length
                 (x-print-read-eval
                  (x-print-controls (sl:hash-set 1 2) :readable t
                                    :level 0 :length 0)))))

(parachute:define-test printing.persistence-and-cycles
  (let* ((payload (list :payload))
         (dict (sl:dict :payload payload :other :value))
         (set (sl:hash-set :one :two))
         (raw (list :first :original :second 2 :first :hidden))
         (raw-before (copy-list raw))
         (view (sl:plist-dict-view raw)))
    (x-print-unreadable dict)
    (x-print-unreadable set)
    (x-print-unreadable view)
    (parachute:is = 2 (sl:dict-size dict))
    (parachute:is eq payload (sl:dict-ref dict :payload))
    (parachute:is = 2 (sl:seq-length set))
    (parachute:true (x-print-member-p :one set))
    (parachute:is equal raw-before raw)
    (parachute:is eq :original (sl:dict-ref view :first)))
  (let* ((*x-print-force-count* 0)
         (lazy-value (sl:make-lazy-seq
                      (lambda ()
                        (incf *x-print-force-count*)
                        (sl:lazy-cons :late nil))))
         (dict (sl:dict :lazy lazy-value)))
    (x-print-unreadable dict)
    (parachute:is = 0 *x-print-force-count*)
    (parachute:is eq lazy-value (sl:dict-ref dict :lazy)))
  ;; A bounded cyclic printer probe, never a cyclic reader/evaluator oracle.
  (let* ((cycle (list :cycle)) (dict (sl:dict :cycle cycle)))
    (setf (cdr cycle) cycle)
    (let ((output
            (handler-case
                #+sbcl (sb-ext:with-timeout 2
                         (let ((*print-readably* nil) (*print-escape* t)
                               (*print-circle* t) (*print-level* nil)
                               (*print-length* nil))
                           (x-print-current dict)))
                #-sbcl
                (let ((*print-readably* nil) (*print-escape* t)
                      (*print-circle* t) (*print-level* nil)
                      (*print-length* nil))
                  (x-print-current dict))
              (condition (condition) condition))))
      (parachute:true (stringp output))
      (parachute:true (and (stringp output) (x-print-digit-label-p output)))
      (parachute:true (x-print-matching-label-p output))))
  ;; Repeated child across associations, and shared native/Sophie boundaries.
  ;; Require a definition AND a reference carrying the same decimal label.
  (let* ((child (list 867))
         (dict (sl:dict :a child :b child))
         (set (sl:hash-set child)))
    (dolist (pretty '(nil t))
      (dolist (object (list dict (list child dict) (list child set)))
        (let ((output (x-print-controls object :circle t :pretty pretty)))
          (parachute:true (x-print-digit-label-p output))
          (parachute:true (x-print-matching-label-p output)))))
    (parachute:is eq child (sl:dict-ref dict :a))
    (parachute:is eq child (sl:seq-first set))))

;; No round-trip assertion is made for non-self-evaluating or unreadable
;; children. Readable round trips are tested only for self-evaluating domains.
