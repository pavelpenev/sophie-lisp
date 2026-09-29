;;;; Shared, expansion-time pattern compiler. No public binding macros live here.
(in-package #:sophie-lisp.internal)

;;; Consumer contract: ASTs are opaque. PATTERN-BOUND-NAMES returns a fresh list
;;; of variable symbols in establishment order (including repeated occurrences).
;;; DECLARATIONS and FREE-DECLARATIONS are lists of declaration *clauses*, not
;;; DECLARE forms. The bound map is an EQ hash table: name -> clause list; the
;;; same clauses apply at every occurrence. Consumers may use GETHASH for their
;;; own simple/index/access bindings, or pass the map unchanged to COMPILE-PATTERN.
(defstruct (pattern-node (:constructor pattern-node (kind data names)))
  kind data names)

(defun pattern-bound-names (pattern-node)
  (copy-list (pattern-node-names pattern-node)))

(defvar *pattern-plain-variables* nil)

(defun pattern-variable (name &optional (ignore-marker (not *pattern-plain-variables*)))
  ;; Ignored patterns establish no variable, even for a keyword or constant.
  (when (and (not *pattern-plain-variables*) ignore-marker
             (symbolp name) (string= (symbol-name name) "_"))
    (return-from pattern-variable nil))
  (unless (and (symbolp name) name (not (constantp name))
               (not (member name lambda-list-keywords))
               (not (member (symbol-name name) '("?" "@") :test #'string=)))
    (raise-program-error "Invalid pattern variable ~S." name))
  name)

(defun pattern-proper-list (object)
  (let ((seen (make-hash-table :test #'eq)))
    (loop for tail = object then (cdr tail)
          while (consp tail)
          do (when (gethash tail seen) (raise-program-error "Circular syntax."))
          (setf (gethash tail seen) t)
          finally (unless (null tail) (raise-program-error "Expected a proper syntax list."))))
  object)

(defun parse-pattern (syntax context)
  (unless (member context '(:bind :fn :doseq))
    (raise-program-error "Unknown pattern context ~S." context))
  (let ((active (make-hash-table :test #'eq)))
    (labels ((node (kind data children)
               (pattern-node kind data
                             (mapcan #'pattern-bound-names children)))
             (variable (syntax)
               (let ((name (pattern-variable syntax)))
                 (pattern-node :variable name (and name (list name)))))
             (parse (syntax)
               (when (and (or (consp syntax) (vectorp syntax)) (gethash syntax active))
                 (raise-program-error "Circular pattern syntax."))
               (setf (gethash syntax active) t)
               (unwind-protect
                    (cond ((null syntax) (pattern-node :empty nil nil))
                          ((symbolp syntax) (variable syntax))
                          ((and (vectorp syntax) (not (stringp syntax))
                               (not (typep syntax 'bit-vector)))
                           (let ((children (map 'list #'parse syntax)))
                             (node :vector children children)))
                          ((consp syntax)
                           (if (eq (car syntax) :entry)
                               (progn
                                 (pattern-proper-list syntax)
                                 (unless (= (length syntax) 3)
                                   (raise-program-error "Entry pattern arity."))
                                 (let ((children (mapcar #'parse (cdr syntax))))
                                   (node :entry children children)))
                               (parse-list syntax)))
                          (t (raise-program-error "Invalid pattern ~S." syntax)))
                 (remhash syntax active)))
             (parse-list (syntax)
               (let ((tail syntax)
                     (state :required)
                     (steps nil)
                     (children nil)
                     (keyp nil)
                     (allow nil)
                     (seen (make-hash-table :test #'eq)))
                 (labels ((take ()
                            (unless (consp tail)
                              (raise-program-error "Missing lambda-list operand."))
                            (when (gethash tail seen)
                              (raise-program-error "Circular lambda list."))
                            (setf (gethash tail seen) t)
                            (pop tail))
                          (add (kind pattern &optional initial-form supplied key)
                            (let ((pattern-node (parse pattern))
                                  (supplied-pattern (and supplied (variable supplied))))
                              (push (list kind pattern-node initial-form
                                          supplied-pattern key)
                                    steps)
                              (push pattern-node children)
                              (when supplied-pattern (push supplied-pattern children))))
                          (entry (item kind)
                            (let* ((parts
                                    (if (consp item)
                                        (pattern-proper-list item)
                                        (list item)))
                                   (count (length parts))
                                   (pattern (first parts))
                                   (key nil))
                              (unless
                                  (<= 1 count
                                      (if (eq kind :aux)
                                          2
                                          3))
                                (raise-program-error
                                 "Malformed lambda-list entry."))
                              (when (eq kind :key)
                                (if (consp pattern)
                                    (progn
                                      (pattern-proper-list pattern)
                                      (unless
                                          (and (= (length pattern) 2)
                                               (symbolp (first pattern)))
                                        (raise-program-error
                                         "Malformed explicit key."))
                                      (setf key (first pattern)
                                            pattern (second pattern)))
                                    (progn
                                      (unless (symbolp pattern)
                                        (raise-program-error
                                         "A compound key pattern needs an explicit key."))
                                      (setf key
                                            (intern (symbol-name pattern)
                                                    :keyword)))))
                              (when (and (= count 3) (null (third parts)))
                                (raise-program-error "NIL supplied-p variable."))
                              (add kind pattern (second parts) (third parts)
                                   key))))
                   (loop while (consp tail)
                         for item = (take)
                         do (cond
                              ((eq item '&whole)
                               (unless
                                   (and (eq state :required)
                                        (= (hash-table-count seen) 1))
                                 (raise-program-error "Misplaced &WHOLE."))
                               (add :whole (take)))
                              ((eq item '&optional)
                               (unless (eq state :required)
                                 (raise-program-error "Misplaced &OPTIONAL."))
                               (setf state :optional))
                              ((member item '(&rest &body))
                               (unless (member state '(:required :optional))
                                 (raise-program-error "Misplaced rest parameter."))
                               (add :rest (take)) (setf state :after-rest))
                              ((eq item '&key)
                               (unless
                                   (member state
                                           '(:required :optional :after-rest))
                                 (raise-program-error "Misplaced &KEY."))
                               (setf keyp t
                                     state :key))
                              ((eq item '&allow-other-keys)
                               (unless (eq state :key)
                                 (raise-program-error
                                  "Misplaced &ALLOW-OTHER-KEYS."))
                               (setf allow t
                                     state :after-keys))
                              ((eq item '&aux)
                               (when (eq state :aux)
                                 (raise-program-error "Repeated &AUX."))
                               (setf state :aux))
                              ((member item lambda-list-keywords)
                               (raise-program-error
                                "Invalid destructuring keyword ~S." item))
                              ((eq state :required) (add :required item))
                              ((member state '(:optional :key :aux))
                               (entry item state))
                              (t
                               (raise-program-error
                                "Unexpected lambda-list entry."))))
                   (when tail
                     (unless (member state '(:required :optional))
                       (raise-program-error "Misplaced dotted tail."))
                     (add :rest tail)
                     (setf state :after-rest))
                   (node :list (list (nreverse steps) keyp allow)
                         (nreverse children))))))
      (parse syntax))))

(defun parse-leading-declarations (forms)
  (pattern-proper-list forms)
  (let ((clauses nil))
    (loop while (and (consp (first forms)) (eq (caar forms) 'declare))
          do (let ((declaration (pop forms)))
               (pattern-proper-list declaration)
               (dolist (clause (cdr declaration))
                 (pattern-proper-list clause)
                 (unless (and clause (symbolp (car clause)))
                   (raise-program-error "Malformed declaration."))
                 (push clause clauses))))
    (values (nreverse clauses) forms)))

(defun classify-declarations (declarations bound-name-occurrences)
  (let ((map (make-hash-table :test #'eq)) (free nil)
        (declared (loop for clause in declarations
                        when (eq (car clause) 'declaration) append (cdr clause))))
    (dolist (clause declarations)
      (let* ((kind (car clause))
             (prefix
              (cond ((eq kind 'type) (subseq clause 0 2))
                    ((member kind '(special ignore ignorable dynamic-extent)) (list kind))
                    ;; Ask about the empty type, not T: even an unknown type is
                    ;; trivially a subtype of T. Unknown declarations stay intact.
                    ((and (not (member kind
                                       (append declared
                                               '(optimize declaration ftype
                                                 inline notinline))))
                          (handler-case (nth-value 1 (subtypep kind nil))
                            (error () nil)))
                     (list 'type kind))))
             (names (if (eq kind 'type) (cddr clause) (cdr clause))))
        (if prefix
            (dolist (name names)
              (let ((part (append prefix (list name))))
                (if (member name bound-name-occurrences :test #'eq)
                    (push part (gethash name map))
                    (push part free))))
            (push clause free))))
    (maphash (lambda (name clauses) (setf (gethash name map) (nreverse clauses))) map)
    (values map (nreverse free))))

(defun emit-bound-binding (name init-form body declaration-clauses
                           &optional automatically-ignorable-p)
  (if (and (symbolp name) (string= (symbol-name name) "_"))
      `(progn ,init-form ,body)
      `(let ((,name ,init-form))
         ,@(when (and automatically-ignorable-p
                      (not (some (lambda (clause)
                                   (member (first clause) '(ignore ignorable)))
                                 declaration-clauses)))
             `((declare (ignorable ,name))))
         ,@(when declaration-clauses `((declare ,@declaration-clauses)))
         ,body)))

(defun emit-declared-body (free-declarations body-forms)
  `(locally ,@(when free-declarations `((declare ,@free-declarations)))
     ,@(or body-forms '(nil))))

(defun compile-pattern (pattern-ast subject-variable continuation
                        &key (context :bind) bound-declaration-map)
  (labels ((bind (pattern-node value body)
             (compile-pattern pattern-node value body :context context
                              :bound-declaration-map bound-declaration-map))
           (project (pattern-node form body)
             (let ((value (gensym "COMPONENT-")))
               `(let ((,value ,form))
                  (declare (ignorable ,value))
                  ,(bind pattern-node value body)))))
    (case (pattern-node-kind pattern-ast)
      (:variable
       (let ((name (pattern-node-data pattern-ast)))
         (if name
             (emit-bound-binding name subject-variable continuation
                                 (and bound-declaration-map (gethash name bound-declaration-map))
                                 (eq context :doseq))
             continuation)))
      (:empty `(destructuring-bind () ,subject-variable ,continuation))
      ((:vector :entry)
       (let* ((children (pattern-node-data pattern-ast))
              (entryp (eq (pattern-node-kind pattern-ast) :entry))
              (body continuation))
         (loop for pattern-node in (reverse children)
               for index downfrom (1- (length children)) do
               (setf body
                     (project pattern-node (if entryp
                                               `(,(if (zerop index)
                                                   'sl:entry-key
                                                   'sl:entry-value)
                                                 ,subject-variable)
                                               `(sl:ref ,subject-variable ,index)) body)))
         (if entryp
             `(progn
                (unless (typep ,subject-variable 'sl:map-entry)
                  (error 'type-error :datum ,subject-variable :expected-type 'sl:map-entry))
                ,body)
             body)))
      (:list
       (destructuring-bind (steps keyp allow) (pattern-node-data pattern-ast)
         (labels
             ((stage (remaining cursor checked validated)
                (cond
                  ;; Native key validation, with no source defaults, only after
                  ;; positional/rest bindings. Each real key/default is staged below.
                  ((and keyp (not validated)
                        (or (null remaining) (member (caar remaining) '(:key :aux))))
                   (let* ((keys (remove-if-not (lambda (step) (eq (first step) :key)) steps))
                          (key-variables
                           (mapcar (lambda (step)
                                     (declare (ignore step))
                                     (gensym "KEY-"))
                                   keys)))
                     `(destructuring-bind
                            (&key ,@(mapcar (lambda (step v)
                                              `((,(fifth step) ,v)))
                                            keys key-variables)
                                  ,@(when allow '(&allow-other-keys)))
                        ,cursor
                        ,@(when key-variables `((declare (ignore ,@key-variables))))
                        ,(stage remaining cursor t t))))
                  ((null remaining)
                   (if checked continuation `(destructuring-bind () ,cursor ,continuation)))
                  (t
                   (destructuring-bind (kind pattern-node initial-form supplied key) (car remaining)
                     (let ((value (gensym "ELEMENT-")) (rest (gensym "TAIL-"))
                           (present (gensym "PRESENT-")))
                       (flet ((finish (next tail-checked)
                                (let ((body (stage (cdr remaining) next tail-checked validated)))
                                  (when supplied (setf body (bind supplied present body)))
                                  (bind pattern-node value body))))
                         (case kind
                           (:whole `(let ((,value ,subject-variable))
                                      (declare (ignorable ,value))
                                      ,(finish cursor checked)))
                           (:required `(destructuring-bind (,value . ,rest) ,cursor
                                         (declare (ignorable ,value))
                                         ,(finish rest checked)))
                           (:optional
                            `(destructuring-bind
                                   (&optional (,value ,initial-form ,present) &rest ,rest)
                                 ,cursor
                               (declare (ignorable ,value ,present))
                               ,(finish rest checked)))
                           (:rest `(let ((,value ,cursor))
                                     (declare (ignorable ,value))
                                     ,(finish cursor t)))
                           (:aux
                            (let ((body `(let ((,value ,initial-form))
                                          (declare (ignorable ,value))
                                          ,(finish cursor t))))
                              (if checked body `(destructuring-bind () ,cursor ,body))))
                           (:key
                            `(destructuring-bind
                                   (&key ((,key ,value) ,initial-form ,present)
                                   &allow-other-keys)
                                 ,cursor
                                 (declare (ignorable ,value ,present))
                                 ,(finish cursor t)))))))))))
           (stage steps subject-variable nil nil))))
      (otherwise (raise-program-error "Not a pattern AST.")))))

(defun compile-pattern-lambda-list (lambda-list declarations body-forms)
  (pattern-proper-list lambda-list)
  (unless body-forms (raise-program-error "FN requires a body form."))
  (let ((required nil) (arguments nil) (tail lambda-list) (names nil))
    (loop while (and tail (not (member (car tail) lambda-list-keywords)))
          for pattern-node = (parse-pattern (pop tail) :fn)
          do (push pattern-node required) (push (gensym "ARGUMENT-") arguments)
          (setf names (append names (pattern-bound-names pattern-node))))
    ;; Ordinary tail parameters are plain variables, even when named underscore.
    ;; Their initializers remain untouched in the native inner lambda.
    (let* ((ordinary (let ((*pattern-plain-variables* t)) (parse-pattern tail :fn)))
           (steps (and (eq (pattern-node-kind ordinary) :list)
                       (first (pattern-node-data ordinary))))
           (ordinary-names nil))
      (dolist (step steps)
        (unless (and (member (first step) '(:optional :rest :key :aux))
                     (eq (pattern-node-kind (second step)) :variable))
          (raise-program-error "Only required FN arguments admit patterns."))
        (push (pattern-node-data (second step)) ordinary-names)
        (when (fourth step)
          (push (pattern-node-data (fourth step)) ordinary-names)))
      (when (or (member '&body tail) (member '&whole tail))
        (raise-program-error "Not an ordinary function lambda list."))
      (unless (= (length ordinary-names) (length (remove-duplicates ordinary-names)))
        (raise-program-error "Duplicate ordinary parameters."))
      (multiple-value-bind (map free)
          (classify-declarations declarations (append names ordinary-names))
        (let* ((rest (gensym "ARGUMENTS-"))
               (clauses (mapcan (lambda (name) (copy-list (gethash name map))) ordinary-names))
               (body `(apply (function (lambda ,tail
                               ,@(when clauses `((declare ,@clauses)))
                               ,(emit-declared-body free body-forms))) ,rest)))
          (loop for pattern-node in required for argument in arguments do
            (setf body
                  (compile-pattern pattern-node argument body
                                   :context :fn
                                   :bound-declaration-map map)))
          `(lambda (,@(reverse arguments) &rest ,rest) ,body))))))
