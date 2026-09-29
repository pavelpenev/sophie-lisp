;;;; Sophie reader syntax: readtable bootstrap, interpolation, collection literals,
;;;; operator shorthand, and printing.

(in-package #:sophie-lisp.internal)

(defvar *sl-core-syntax-readtable* nil
  "The registered pristine base readtable used by Sophie reader handlers.")

(defun sl-core-syntax-readtable ()
  "Return the registered SL-CORE-SYNTAX readtable."
  (or *sl-core-syntax-readtable*
      (error "SL-CORE-SYNTAX has not been initialized.")))

(defun register-sl-core-syntax-dispatch (sub-character function)
  "Install one handler-owned dispatch sub-character on SL-CORE-SYNTAX.
The caller owns FUNCTION and registers its dispatch only after defining it."
  (set-dispatch-macro-character #\# sub-character function
                                (sl-core-syntax-readtable)))

(eval-when (:compile-toplevel :load-toplevel :execute)
  ;; COPY-READTABLE with NIL is the ANSI baseline, independent of the
  ;; dynamically active *READTABLE*.  Handlers are registered later in this file.
  (setf *sl-core-syntax-readtable* (copy-pristine-readtable))
  (register-named-readtable :sl-core-syntax *sl-core-syntax-readtable*)
  (register-named-readtable 'sl:sl-core-syntax *sl-core-syntax-readtable*))


;;; Interpolation

(defvar sophie-lisp:*list-delimiter* " "
  "Object printed between successive elements of a list interpolation.")

(defun interpolation-unmatched-brace (stream character)
  (declare (ignore character))
  (error 'reader-error :stream stream))

(defun read-interpolation-forms (stream)
  ;; READ-DELIMITED-LIST handles whitespace, zero-valued reader macros, and
  ;; recursive objects rather than attempting to scan Lisp tokens as text.
  ;; The terminating macro also delimits an immediately preceding symbol.
  ;; Escaped symbols, strings, and character literals retain their CL syntax.
  (let ((*readtable* (copy-readtable *readtable*)))
    (set-macro-character #\} #'interpolation-unmatched-brace nil *readtable*)
    (let ((forms (read-delimited-list #\} stream t)))
      (when (and (not *read-suppress*) (null forms))
        (error 'reader-error :stream stream))
      forms)))

(defun list-type-error-form (value)
  `(error (make-condition 'type-error
                          (find-symbol "DATUM" "KEYWORD") ,value
                          (find-symbol "EXPECTED-TYPE" "KEYWORD") 'list)))

(defun interpolation-list-output (forms output)
  ;; No private helper appears in the returned form. Validate the entire
  ;; spine before copying any elements, then snapshot before calling printers.
  (let ((value (gensym "INTERPOLATED-LIST-"))
        (slow (gensym "SLOW-"))
        (fast (gensym "FAST-"))
        (delimiter (gensym "DELIMITER-"))
        (elements (gensym "ELEMENTS-"))
        (element (gensym "ELEMENT-"))
        (first (gensym "FIRST-")))
    `(let ((,value (progn ,@forms)))
       ;; Expose the atom check to the compiler as well as the runtime: a
       ;; literal non-list must not provoke a spurious COPY-LIST type warning.
       (unless (listp ,value)
         ,(list-type-error-form value))
       (let ((,slow ,value) (,fast ,value))
         (loop
           (when (null ,fast) (return))
           (unless (consp ,fast)
             ,(list-type-error-form value))
           (setf ,fast (cdr ,fast))
           (when (null ,fast) (return))
           (unless (consp ,fast)
             ,(list-type-error-form value))
           (setf ,fast (cdr ,fast) ,slow (cdr ,slow))
           (when (eq ,fast ,slow)
             ,(list-type-error-form value))))
       (let ((,delimiter sophie-lisp:*list-delimiter*)
             (,elements (copy-list ,value))
             (,first t))
         (dolist (,element ,elements)
           (unless ,first (princ ,delimiter ,output))
           (setf ,first nil)
           (princ ,element ,output))))))

(defun read-interpolated-template (stream sub-character argument)
  (declare (ignore sub-character))
  ;; PEEK-CHAR does not consume a missing opening delimiter, even suppressed.
  (let ((opening (peek-char nil stream t nil t)))
    (unless (char= opening #\")
      (unless *read-suppress* (error 'reader-error :stream stream))
      (return-from read-interpolated-template nil)))
  (when (and argument (not *read-suppress*))
    (error 'reader-error :stream stream))
  (read-char stream t nil t)
  (let ((literal (make-string-output-stream))
        (parts nil)
        (interpolated nil)
        (output (gensym "TEMPLATE-OUTPUT-")))
    (unwind-protect
         (labels ((flush-literal ()
                    (let ((text (get-output-stream-string literal)))
                      (unless (zerop (length text))
                        (push `(write-string ,text ,output) parts)))))
           (loop
             (let ((character (read-char stream t nil t)))
               (cond
                 ((char= character #\") (return))
                 ((char= character #\\)
                  (let* ((escaped (read-char stream t nil t))
                         (decoded
                           (case escaped
                             (#\$ #\$)
                             (#\@ #\@)
                             (#\\ #\\)
                             (#\" #\")
                             (#\n #\Newline)
                             (#\t #\Tab)
                             (#\r #\Return)
                             (otherwise
                              (unless *read-suppress*
                                (error 'reader-error :stream stream))
                              escaped))))
                    (unless *read-suppress* (write-char decoded literal))))
                 ((and (find character "$@")
                       (eql (peek-char nil stream nil nil t) #\{))
                  (read-char stream t nil t)
                  (flush-literal)
                  (let ((forms (read-interpolation-forms stream)))
                    (setf interpolated t)
                    (unless *read-suppress*
                      (push (if (char= character #\$)
                                `(princ (progn ,@forms) ,output)
                                (interpolation-list-output forms output))
                            parts))))
                 (t (unless *read-suppress* (write-char character literal))))))
           (cond
             (*read-suppress* nil)
             ((not interpolated) (get-output-stream-string literal))
             (t
              (flush-literal)
              `(with-output-to-string (,output) ,@(nreverse parts)))))
      (close literal))))

(eval-when (:load-toplevel :execute)
  (register-sl-core-syntax-dispatch #\? #'read-interpolated-template))


;;; Collection literals

(defun literal-capture (forms variables body)
  ;; LET initializers evaluate left to right, retaining only primary values.
  ;; The variables are fresh and cannot be referenced by source forms. A flat
  ;; binding group avoids compiler stack exhaustion from thousands of nested
  ;; single-binding LETs; LET is not a call and has no call-argument limit.
  `(let ,(loop for form in forms for variable in variables
               collect (list variable form))
     ,body))

(defun literal-expansion (kind forms test)
  (let* ((variables (loop repeat (length forms)
                          collect (gensym "LITERAL-VALUE-")))
         (container (gensym "LITERAL-CONTAINER-"))
         (count (length forms))
         (constructor
          (ecase kind
            (#\v `(make-array ,count
                              (find-symbol "ADJUSTABLE" "KEYWORD") t
                              (find-symbol "FILL-POINTER" "KEYWORD") ,count))
            (#\h `(make-hash-table (find-symbol "TEST" "KEYWORD") ',test))
            (#\d '(sophie-lisp:dict))
            (#\u '(sophie-lisp:hash-set))))
         (updates
          (ecase kind
            (#\v (loop for variable in variables for index from 0
                       collect `(setf (aref ,container ,index) ,variable)))
            (#\h (loop for (key value) on variables by #'cddr
                       collect `(setf (gethash ,key ,container) ,value)))
            (#\d (loop for (key value) on variables by #'cddr
                       collect `(setf ,container
                                      (sophie-lisp:dict-set ,container ,key ,value))))
            (#\u (loop for variable in variables
                       collect `(setf ,container
                                      (sophie-lisp:set-add ,variable ,container)))))))
    ;; All introduced operators are CL symbols reexported by SL, or public SL
    ;; operators. Even keyword arguments are obtained as runtime values, not
    ;; introduced keyword symbols. Source forms retain their original symbols.
    (literal-capture forms
                     variables
                     `(let ((,container ,constructor))
                        ,@updates
                        ,container))))

(defun read-container-literal (stream sub-character argument)
  (let ((opening (peek-char nil stream t nil t)))
    (unless (char= opening #\()
      (unless *read-suppress* (error 'reader-error :stream stream))
      (return-from read-container-literal nil)))
  (when (and argument (not *read-suppress*))
    (error 'reader-error :stream stream))
  (read-char stream t nil t)
  ;; Native recursive reading preserves active macros, package, suppression and
  ;; standard #. behavior. SBCL's READ-DELIMITED-LIST rejects dot tokens as
  ;; forms; CCL's admits a dotted tail, so the proper-list requirement of the
  ;; container grammar is enforced here on every host.
  (let ((forms (read-delimited-list #\) stream t))
        (kind (char-downcase sub-character))
        (test 'equal))
    (when *read-suppress* (return-from read-container-literal nil))
    (unless (reader-proper-list-p forms)
      (error 'reader-error :stream stream))
    (when (and (char= kind #\h)
               (symbolp (first forms))
               (not (keywordp (first forms)))
               (member (symbol-name (first forms)) '("EQ" "EQL" "EQUAL" "EQUALP")
                       :test #'string-equal))
      (setf test
            (require-external "SOPHIE-LISP"
                              (string-upcase (symbol-name (pop forms))))))
    (when (and (find kind "hd") (oddp (length forms)))
      (error 'reader-error :stream stream))
    (literal-expansion kind forms test)))

(eval-when (:load-toplevel :execute)
  (register-sl-core-syntax-dispatch #\v #'read-container-literal)
  (register-sl-core-syntax-dispatch #\h #'read-container-literal)
  (register-sl-core-syntax-dispatch #\d #'read-container-literal)
  (register-sl-core-syntax-dispatch #\u #'read-container-literal))


;;; Operator shorthand

(define-condition placeholder-error (simple-condition program-error) ())

(define-condition placeholder-reader-error (simple-condition reader-error) ())

(defstruct (placeholder-info (:constructor make-placeholder-info ()))
  (highest 0)
  rest
  (variables (make-hash-table :test #'eql)))

(defun placeholder-error (control &rest arguments)
  (error 'placeholder-error :format-control control :format-arguments arguments))

(defun placeholder-variable (symbol placeholder-state)
  "Recognize names, not symbol identities; allocate only referenced parameters."
  (let* ((name (symbol-name symbol))
         (size (length name)))
    (if (or (zerop size) (char/= (char name 0) #\%))
        symbol
        (let ((index
                (cond ((string= name "%") 1)
                      ((string= name "%&") :rest)
                      (t
                       (let ((number 0))
                         (loop for position from 1 below size
                               for digit = (digit-char-p (char name position) 10)
                               do (unless digit
                                    (placeholder-error "Invalid placeholder ~S." name))
                                  ;; Saturate: huge input tokens need no huge bignum.
                                  (setf number
                                        (min (1+ lambda-parameters-limit)
                                             (+ (* number 10) digit))))
                         (when (zerop number)
                           (placeholder-error "Invalid placeholder ~S." name))
                         number)))))
          (if (eq index :rest)
              (setf (placeholder-info-rest placeholder-state) t)
              (setf (placeholder-info-highest placeholder-state)
                    (max index (placeholder-info-highest placeholder-state))))
          (when (> (+ (placeholder-info-highest placeholder-state)
                      (if (placeholder-info-rest placeholder-state) 1 0))
                   lambda-parameters-limit)
            (placeholder-error "Too many lambda shorthand parameters."))
          (or (gethash index (placeholder-info-variables placeholder-state))
              (setf (gethash index (placeholder-info-variables placeholder-state))
                    (gensym "ARG-")))))))

(defun walk-placeholders (object mode)
  "Return the transformed graph and its parameter information.
MODE is :DESTRUCTIVE or :COPY. Memoized shells preserve cons/vector aliases
and cycles in COPY mode without changing any input location. The worklist
also avoids recursion proportional to graph depth. All other objects are opaque,
including lazy nodes: this operation never invokes a sequence protocol.

Backquote policy (including on SBCL): scan the actual reader representation
with precisely this structural traversal, without recognizing backquote or
looking inside opaque implementation objects such as comma structures."
  (unless (member mode '(:destructive :copy))
    (raise-program-error "Invalid placeholder traversal mode."))
  (let ((placeholder-state (make-placeholder-info))
        (visited (make-hash-table :test #'eq))
        (pending nil))
    (labels ((resolve (source)
               (cond
                 ((symbolp source) (placeholder-variable source placeholder-state))
                 ((or (consp source) (vectorp source))
                  (or (gethash source visited)
                      (let ((target (if (eq mode :destructive)
                                        source
                                        (if (consp source)
                                            (cons nil nil)
                                            (copy-seq source)))))
                        ;; Register before following any edge, including self edges.
                        (setf (gethash source visited) target)
                        (push (cons source target) pending)
                        target)))
                 (t source))))
      (let ((result (resolve object)))
        (loop while pending
              for pair = (pop pending)
              for source = (car pair)
              for target = (cdr pair)
              do (if (consp source)
                     (setf (car target) (resolve (car source))
                           (cdr target) (resolve (cdr source)))
                     (dotimes (index (length source))
                       (setf (aref target index) (resolve (aref source index))))))
        (values result placeholder-state)))))

(defun placeholder-lambda (expression mode)
  (multiple-value-bind (body placeholder-state) (walk-placeholders expression mode)
    (let ((parameters nil)
          (unused nil)
          (variables (placeholder-info-variables placeholder-state)))
      (loop for index from 1 to (placeholder-info-highest placeholder-state)
            for variable = (gethash index variables)
            do (unless variable
                 (setf variable (gensym "ARG-")
                       (gethash index variables) variable)
                 (push variable unused))
               (push variable parameters))
      (setf parameters (nreverse parameters))
      (when (placeholder-info-rest placeholder-state)
        (setf parameters
              (append parameters
                      (list (require-external :sophie-lisp "&REST")
                            (gethash :rest variables)))))
      (list* (require-external :sophie-lisp "LAMBDA") parameters
             (append (when unused
                       (list (list (require-external :sophie-lisp "DECLARE")
                                   (cons (require-external :sophie-lisp "IGNORABLE")
                                         (nreverse unused)))))
                     (list body))))))

(defun reader-proper-list-p (object)
  (let ((seen (make-hash-table :test #'eq)))
    (loop
      (cond ((null object) (return t))
            ((or (not (consp object)) (gethash object seen)) (return nil)))
      (setf (gethash object seen) t
            object (cdr object)))))

(defun read-placeholder-lambda (stream sub-character argument)
  (declare (ignore sub-character))
  (flet ((fail (control &rest arguments)
           (error 'placeholder-reader-error :stream stream
                  :format-control control :format-arguments arguments)))
    ;; PEEK-CHAR neither skips whitespace nor consumes an absent delimiter.
    ;; Its ordinary EOF signaling also applies during suppression.
    (unless (char= (peek-char nil stream t nil t) #\()
      (if *read-suppress*
          (return-from read-placeholder-lambda nil)
          (fail "Expected an immediate opening parenthesis after #^.")))
    (when (and argument (not *read-suppress*))
      (fail "#^ does not accept a numeric dispatch argument."))
    ;; Retain the active readtable, including its standard #. reader.
    ;; READ-DELIMITED-LIST rejects outer standalone dot tokens while allowing
    ;; nested dotted objects to be read recursively.
    (read-char stream t nil t)
    (let ((expression (read-delimited-list #\) stream t)))
      (when *read-suppress*
        (return-from read-placeholder-lambda nil))
      (unless (and (consp expression) (reader-proper-list-p expression))
        (fail "#^ requires a nonempty proper expression list."))
      (handler-case (placeholder-lambda expression :destructive)
        (placeholder-error (condition)
          (error 'placeholder-reader-error :stream stream
                 :format-control (simple-condition-format-control condition)
                 :format-arguments (simple-condition-format-arguments condition)))))))

(defmacro sophie-lisp:op (&whole form &rest arguments)
  "Macro form of the #^() lambda shorthand: replace placeholders in EXPRESSION at
expansion time, without mutating it, and return the corresponding function.
Placeholders %, %1, %2, ... denote required arguments; %& denotes the rest
argument. A malformed macro form, invalid placeholder, or excessive parameter
count signals PROGRAM-ERROR at macro-expansion time."
  (declare (ignore arguments))
  (unless (and (consp form) (consp (cdr form)) (null (cddr form)))
    (raise-program-error "OP requires exactly one expression in a proper macro form."))
  (list (require-external :sophie-lisp "FUNCTION")
        (placeholder-lambda (second form) :copy)))

(eval-when (:load-toplevel :execute)
  (register-sl-core-syntax-dispatch #\^ #'read-placeholder-lambda))


;;; Printing

(defmethod print-object ((object sl:lazy-seq) stream)
  ;; Implementation-defined, deliberately opaque even for resolved nodes. Never
  ;; inspect a thunk, element, tail, or memoization state while printing.
  (print-unreadable-object (object stream)
    (write-string "LAZY-SEQ ..." stream))
  object)

(defmethod print-object ((object sl:map-entry) stream)
  ;; Unlike a dictionary's traversal entries, an entry printed as a value is
  ;; always unreadable. Omit its fields rather than accidentally observing them.
  (print-unreadable-object (object stream)
    (write-string "MAP-ENTRY ..." stream))
  object)

(defun print-container (object stream prefix entryp)
  "Print one container level using a coherent public traversal.
PRINT-LENGTH counts associations for dictionaries and elements for sets. Child
objects retain the ambient printer context, including shared/circular identity."
  ;; NIL means that this block describes a non-list object. The host printer
  ;; owns depth tracking (also with PRINT-PRETTY false) and circularity; do not
  ;; restart it with an intermediate string or a fresh printer binding.
  (pprint-logical-block (stream nil :prefix prefix :suffix ")")
    (let ((count 0)
          (view (open-view object)))
      (cl:loop
        (multiple-value-bind (empty-p element rest)
            (view-step view)
          (when empty-p
            (return))
          (when (plusp count)
            (write-char #\Space stream)
            (pprint-newline :linear stream))
          (when (and (not *print-readably*) *print-length*
                     (>= count *print-length*))
            (write-string "..." stream)
            (return))
          (if entryp
              (progn
                ;; Print the association, not its unreadable MAP-ENTRY wrapper.
                (write (sl:entry-key element) :stream stream)
                (write-char #\Space stream)
                (write (sl:entry-value element) :stream stream))
              (write element :stream stream))
          (incf count)
          (setf view rest)))))
  object)

(defmethod print-object ((object sl:dict) stream)
  (print-container object stream "#d(" t))

(defmethod print-object ((object sl:hash-set) stream)
  (print-container object stream "#u(" nil))
