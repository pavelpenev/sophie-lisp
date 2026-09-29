(in-package #:sophie-lisp.tests)

(defparameter *required-generic-signatures*
  '((:function "SEQABLEP" (object))
    (:function "SEQ-EMPTYP" (source))
    (:function "SEQ-FIRST" (source))
    (:function "SEQ-REST" (source))
    (:function "SEQ-REF" (source index &optional default))
    (:setf "SEQ-REF" (new-value source index &optional default))
    (:function "SEQ-LENGTH" (source))
    (:function "MAKE-COLLECTOR-FOR" (target &rest options &key))
    (:function "COLLECTOR-ACCUMULATE" (collector element))
    (:function "COLLECTOR-RESULT" (collector))
    (:function "SEQ-LAST" (source))
    (:function "SEQ-FIND" (item source &key test key start end from-end))
    (:function "SEQ-FIND-IF" (predicate source &key key start end from-end))
    (:function "SEQ-POSITION" (item source &key test key start end from-end))
    (:function "SEQ-POSITION-IF" (predicate source &key key start end from-end))
    (:function "SEQ-MEMBER" (item source &key test key))
    (:function "SEQ-COUNT" (item source &key test key start end from-end))
    (:function "SEQ-COUNT-IF" (predicate source &key key start end from-end))
    (:function "SEQ-SEARCH"
               (pattern source &key test key start1 end1 start2 end2 from-end))
    (:function "SEQ-MISMATCH"
               (source1 source2 &key test key start1 end1 start2 end2 from-end))
    (:function "SEQ-EVERY" (predicate source &rest more-sources))
    (:function "SEQ-SOME" (predicate source &rest more-sources))
    (:function "SEQ-NOTEVERY" (predicate source &rest more-sources))
    (:function "SEQ-NOTANY" (predicate source &rest more-sources))
    (:function "SEQ-MIN" (source &key key default))
    (:function "SEQ-MAX" (source &key key default))
    (:function "SEQ-REDUCE"
               (function source &key key start end from-end initial-value))
    (:function "SEQ-MAP" (function sequence &rest more-sequences))
    (:function "SEQ-MAP-INDEXED" (function seq))
    (:function "SEQ-FILTER"
               (predicate sequence &key from-end start end key count))
    (:function "SEQ-KEEP" (function seq))
    (:function "SEQ-REMOVE"
               (item sequence &key test key start end from-end count))
    (:function "SEQ-REMOVE-IF"
               (predicate sequence &key key start end from-end count))
    (:function "SEQ-SUBSTITUTE"
               (newitem olditem sequence &key test key start end from-end count))
    (:function "SEQ-SUBSTITUTE-IF"
               (newitem predicate sequence &key key start end from-end count))
    (:function "SEQ-MAPCAT" (function seq))
    (:function "SEQ-TAKE" (n sequence))
    (:function "SEQ-DROP" (n sequence))
    (:function "SEQ-TAKE-WHILE" (predicate sequence))
    (:function "SEQ-DROP-WHILE" (predicate sequence))
    (:function "SEQ-SUBSEQ" (sequence start &optional end))
    (:function "SEQ-TAKE-NTH" (n seq))
    (:function "SEQ-REMOVE-DUPLICATES"
               (sequence &key test key start end from-end))
    (:function "SEQ-DEDUPE" (seq &key test))
    (:function "SEQ-TRIM-LEFT" (sequence &key predicate))
    (:function "SEQ-REDUCTIONS" (function seq &key initial-value))
    (:function "SEQ-CONCATENATE" (sequence &rest more-sources))
    (:function "SEQ-INTERLEAVE" (&rest sources))
    (:function "SEQ-SPLIT"
               (sequence &key delimiter predicate test))
    (:function "SEQ-SPLIT-AT" (n seq))
    (:function "SEQ-SPLIT-WITH" (predicate seq))
    (:function "SEQ-PARTITION" (n seq &key step pad))
    (:function "SEQ-PARTITION-BY" (key-fn seq &key test))
    (:function "SEQ-TREE-SEQ" (branch-fn children-fn tree))
    (:function "SEQ-DROP-LAST" (n seq))
    (:function "SEQ-REVERSE" (sequence))
    (:function "SEQ-SORT" (sequence &key test key))
    (:function "SEQ-STABLE-SORT" (sequence &key test key))
    (:function "SEQ-TAKE-LAST" (n sequence))
    (:function "SEQ-TRIM-RIGHT" (sequence &key predicate))
    (:function "SEQ-TRIM" (sequence &key predicate))
    (:function "SEQ-INTO" (target-designator source))
    (:function "SEQ-JOIN" (target-designator seqs &key separator))
    (:function "EQUALS" (object1 object2))
    (:function "COMPARE" (a b))
    (:function "HASH-CODE" (object))
    (:function "REF" (object key &optional default))
    (:setf "REF" (new-value object key &optional default))
    (:function "DICTP" (object))
    (:function "DICT-REF" (dict key &optional default))
    (:setf "DICT-REF" (new-value dict key &optional default))
    (:function "DICT-TEST" (dict))
    (:function "DICT-SIZE" (dict))
    (:function "DICT-SET" (dict key value))
    (:function "DICT-WITHOUT" (dict key))
    (:function "DICT-COLLECT" (source entries &key test))
    (:function "DICT-KEYS" (collection))
    (:function "DICT-KEYS-MAP" (function dict &key collision))
    (:function "DICT-VALS" (collection))
    (:function "DICT-VALUES-MAP" (function dict))
    (:function "DICT-FREQUENCIES" (seq))
    (:function "DICT-GROUP-BY" (key-fn seq))
    (:function "DICT-COUNT-BY" (key-fn seq))
    (:function "DICT-REDUCE-KV" (fn initial-value dict))
    (:function "DICT-SELECT-KEYS" (dict keys))
    (:function "DICT-REMOVE-KEYS" (dict keys))
    (:function "DICT-ZIPMAP" (keys vals))
    (:function "DICT-MERGE" (d1 d2 &key collision))
    (:function "DICT-MERGE-WITH" (combine d1 d2))
    (:function "DICT-TRANSFORM" (fn dict &key collision))
    (:function "DICT-MEMBER" (dict key))
    (:function "DICT-MERGE*" (d1 d2 &rest more-dicts))
    (:function "DICT-UPDATE" (dict key fn &key default))
    (:function "DICT-UPDATE-IN" (dict keys fn &key default))
    (:function "DICT-SET-IN" (dict keys value))
    (:function "DICT-REF-IN" (dict keys &optional default))
    (:function "HASH-SET-P" (object))
    (:function "SET-MEMBER" (item sequence))
    (:function "SET-ADD" (item sequence))
    (:function "SET-REMOVE" (item sequence))
    (:function "SET-UNION" (s1 s2 &rest more-sets))
    (:function "SET-INTERSECTION" (s1 s2 &rest more-sets))
    (:function "SET-MINUS" (s1 s2 &rest more-sets))
    (:function "SET-SUBSET-P" (s1 s2))
    (:function "SET-SIZE" (sequence))))

(defun lambda-list-structure (lambda-list)
  (let ((mode :required) (required 0) (optional 0) (rest-p nil) (keys nil))
    (dolist (item lambda-list)
      (cond ((member item '(&optional &rest &body &key &allow-other-keys))
             (setf mode item))
            ((eq mode :required) (incf required))
            ((eq mode '&optional) (incf optional))
            ((member mode '(&rest &body)) (setf rest-p t mode :after-rest))
            ((eq mode '&key)
             (let* ((variable (if (consp item) (first item) item))
                    (name (if (consp variable) (first variable) variable)))
               (push (list (string-upcase (symbol-name name)) (consp item)) keys)))))
    (list required optional rest-p (sort keys #'string< :key #'first))))

(defun generic-function-designator-for (kind name)
  (let ((symbol (find-symbol name (test-package :sophie-lisp-extensions))))
    (when (eq kind :setf)
      (setf symbol (and symbol (list 'setf symbol))))
    symbol))

(defun generic-signature-matches-p (entry)
  (destructuring-bind (kind name expected-lambda-list) entry
    (let ((designator (generic-function-designator-for kind name)))
      (and designator
           (eq (nth-value 1 (find-symbol name
                                         (test-package
                                          :sophie-lisp-extensions)))
               :external)
           (fboundp designator)
           (typep (fdefinition designator) 'generic-function)
           (equal (lambda-list-structure expected-lambda-list)
                  (lambda-list-structure
                   (closer-mop:generic-function-lambda-list
                    (fdefinition designator))))))))

(defun function-designator-signals-type-error-p (safety designator)
  (let ((probe
          (compile nil
                   `(lambda ()
                      (declare (optimize (safety ,safety)))
                      (handler-case
                          (progn
                            (sophie-lisp:seq-map ',designator nil)
                            nil)
                        (type-error () t))))))
    (funcall probe)))

(parachute:define-test api.validate-exports-and-generic-signatures
  (parachute:true (normative-sophie-exports-match-p))
  (parachute:true (public-symbols-have-sophie-home-p))
  (dolist (entry *required-generic-signatures*)
    ;; This is deliberately a declaration check: zero or partial method sets
    ;; are acceptable here, while a non-GF function or a wrong lambda list is
    ;; not. Behavior of each protocol belongs to its owning later unit.
    (let* ((kind (first entry))
           (name (second entry))
           (designator (generic-function-designator-for kind name)))
      (multiple-value-bind (symbol status)
          (find-symbol name (test-package :sophie-lisp-extensions))
        (declare (ignore symbol))
        (let* ((function-kind
             (cond ((null designator) :missing-designator)
                   ((not (fboundp designator)) :unbound)
                   ((typep (fdefinition designator) 'generic-function)
                    :generic-function)
                   (t (type-of (fdefinition designator)))))
           (observed-lambda-list
             (when (and designator
                        (fboundp designator)
                        (typep (fdefinition designator) 'generic-function))
               (closer-mop:generic-function-lambda-list
                (fdefinition designator)))))
      (parachute:true
       (generic-signature-matches-p entry)
       "Generic signature mismatch for ~S: export status ~S, function kind ~S, observed lambda list ~S"
       entry status function-kind observed-lambda-list))))))

(parachute:define-test api.resolve-function-designators-and-format-errors
  (let ((callback (gensym "CALLBACK-")))
    (setf (symbol-function callback) (lambda (value) (list :first-definition value)))
    (unwind-protect
         (progn
           (let ((function-object (lambda (value) (list :function-object value))))
             (parachute:is equal '((:function-object :argument))
                           (sophie-lisp:seq-map function-object '(:argument))))
           (parachute:is equal '((:first-definition :argument))
                         (sophie-lisp:seq-map callback '(:argument)))
           (setf (symbol-function callback)
                 (lambda (value) (list :second-definition value)))
           (parachute:is equal '((:second-definition :argument))
                         (sophie-lisp:seq-map callback '(:argument)))
           (dolist (designator (list 'when 'if (gensym "UNDEFINED-")))
             (dolist (safety '(0 3))
               (parachute:true
                (function-designator-signals-type-error-p safety designator))))
           (let ((condition
                   (handler-case
                       (progn
                         (macroexpand-1 '(sophie-lisp:-> :initial :invalid))
                         nil)
                     (program-error (caught) caught))))
             (parachute:true (typep condition 'program-error))
             (parachute:true (typep condition 'simple-condition))
             (parachute:is equal "Invalid threading step: ~A"
                           (simple-condition-format-control condition))
             (parachute:is equal '(":INVALID")
                           (simple-condition-format-arguments condition))
             (parachute:is string= "Invalid threading step: :INVALID"
                           (with-output-to-string (stream)
                             (princ condition stream)))))
      (fmakunbound callback))))

(parachute:define-test api.function-designator-type-error-expected-type
  (dolist (designator (list 'when 'if (gensym "UNDEFINED-")))
    (let ((condition
            (handler-case
                (progn
                  (sophie-lisp:seq-map designator nil)
                  nil)
              (type-error (caught) caught))))
      (parachute:true (typep condition 'type-error))
      ;; Appendix A requires TYPE-ERROR; the exact expected-type pins the
      ;; implementation-specific function-designator predicate.
      (parachute:is equal
                    '(satisfies
                      sophie-lisp.internal::usable-function-designator-p)
                    (type-error-expected-type condition))
      (parachute:is eq designator (type-error-datum condition))
      (parachute:false
       (typep (type-error-datum condition)
              (type-error-expected-type condition))))))

(defparameter *normative-sophie-export-names*
  '("*LIST-DELIMITER*"
    "->"
    "->>"
    "ALIST-DICT"
    "AS->"
    "BIND"
    "COLLECTOR-ACCUMULATE"
    "COLLECTOR-RESULT"
    "COMPARE"
    "COMPOSE"
    "CYCLE"
    "DICT"
    "DICT-ALIST"
    "DICT-COLLECT"
    "DICT-FREQUENCIES"
    "DICT-GROUP-BY"
    "DICT-COUNT-BY"
    "DICT-REDUCE-KV"
    "DICT-REMOVE-KEYS"
    "DICT-SELECT-KEYS"
    "DICT-KEYS"
    "DICT-KEYS-MAP"
    "DICT-MEMBER"
    "DICT-MERGE"
    "DICT-MERGE*"
    "DICT-MERGE-WITH"
    "DICT-PLIST"
    "DICT-REF"
    "DICT-REF-IN"
    "DICT-SET"
    "DICT-SET-IN"
    "DICT-SIZE"
    "DICT-TEST"
    "DICT-TRANSFORM"
    "DICT-UPDATE"
    "DICT-UPDATE-IN"
    "DICT-VALS"
    "DICT-VALUES-MAP"
    "DICT-WITHOUT"
    "DICT-ZIPMAP"
    "DICTP"
    "DOSEQ"
    "ENTRY-KEY"
    "ENTRY-VALUE"
    "EQUALS"
    "FBIND"
    "FN"
    "GT"
    "GTE"
    "HASH-CODE"
    "HASH-SET"
    "HASH-SET-P"
    "IF-BIND"
    "ITERATE"
    "JUXT"
    "LAZY-CONS"
    "LAZY-SEQ"
    "LAZY-SEQ-P"
    "LT"
    "LTE"
    "MAKE-COLLECTOR-FOR"
    "MAKE-LAZY-SEQ"
    "MAP-ENTRY"
    "OP"
    "ORDERED-DICT"
    "ORDERED-DICT-P"
    "PLIST-DICT"
    "PLIST-DICT-VIEW"
    "RANGE"
    "REF"
    "REPEATEDLY"
    "SEQ-CONCATENATE"
    "SEQ-COUNT"
    "SEQ-COUNT-IF"
    "SEQ-DEDUPE"
    "SEQ-DROP"
    "SEQ-DROP-LAST"
    "SEQ-DROP-WHILE"
    "SEQ-EMPTYP"
    "SEQ-EVERY"
    "SEQ-FILTER"
    "SEQ-FIND"
    "SEQ-FIND-IF"
    "SEQ-FIRST"
    "SEQ-INTERLEAVE"
    "SEQ-INTO"
    "SEQ-JOIN"
    "SEQ-KEEP"
    "SEQ-LAST"
    "SEQ-LENGTH"
    "SEQ-MAP"
    "SEQ-MAP-INDEXED"
    "SEQ-MAPCAT"
    "SEQ-MAX"
    "SEQ-MEMBER"
    "SEQ-MIN"
    "SEQ-MISMATCH"
    "SEQ-NOTANY"
    "SEQ-NOTEVERY"
    "SEQ-PARTITION"
    "SEQ-PARTITION-BY"
    "SEQ-POSITION"
    "SEQ-POSITION-IF"
    "SEQ-REDUCE"
    "SEQ-REDUCTIONS"
    "SEQ-REF"
    "SEQ-REMOVE"
    "SEQ-REMOVE-DUPLICATES"
    "SEQ-REMOVE-IF"
    "SEQ-REST"
    "SEQ-REVERSE"
    "SEQ-SEARCH"
    "SEQ-SOME"
    "SEQ-SORT"
    "SEQ-SPLIT"
    "SEQ-SPLIT-AT"
    "SEQ-SPLIT-WITH"
    "SEQ-STABLE-SORT"
    "SEQ-SUBSEQ"
    "SEQ-SUBSTITUTE"
    "SEQ-SUBSTITUTE-IF"
    "SEQ-TAKE"
    "SEQ-TAKE-LAST"
    "SEQ-TAKE-NTH"
    "SEQ-TAKE-WHILE"
    "SEQ-TREE-SEQ"
    "SEQ-TRIM"
    "SEQ-TRIM-LEFT"
    "SEQ-TRIM-RIGHT"
    "SEQABLEP"
    "SET-ADD"
    "SET-INTERSECTION"
    "SET-MEMBER"
    "SET-MINUS"
    "SET-REMOVE"
    "SET-SIZE"
    "SET-SUBSET-P"
    "SET-UNION"
    "SL-CORE-SYNTAX"
    "?"
    "@"
    "<>"
    "WHEN-BIND"
    "~>"))

(defun test-package (name)
  (or (find-package name)
      (error "Required package is absent: ~A" name)))

(defun external-symbols-of (package)
  (let ((symbols nil))
    (do-external-symbols (symbol package (nreverse symbols))
      (push symbol symbols))))

(defun package-set-equal-p (left right)
  (and (= (length left) (length right))
       (every (lambda (package)
                (member package right :test #'eq))
              left)
       (every (lambda (package)
                (member package left :test #'eq))
              right)))

(defun symbol-set-equal-p (left right)
  (and (= (length left) (length right))
       (every (lambda (symbol)
                (member symbol right :test #'eq))
              left)
       (every (lambda (symbol)
                (member symbol left :test #'eq))
              right)))

(defun normative-sophie-exports-match-p ()
  (let* ((extensions (test-package :sophie-lisp-extensions))
         (actual (external-symbols-of extensions)))
    (and (= 144 (length *normative-sophie-export-names*))
         (= 144 (length (remove-duplicates *normative-sophie-export-names*
                                           :test #'string=)))
         (= 144 (length actual))
         (every (lambda (name)
                  (multiple-value-bind (symbol status)
                      (find-symbol name extensions)
                    (and symbol
                         (eq status :external)
                         (eq (symbol-package symbol) extensions))))
                *normative-sophie-export-names*)
         (equal (sort (mapcar #'symbol-name actual) #'string<)
                (sort (copy-list *normative-sophie-export-names*) #'string<)))))

(defun public-symbols-have-sophie-home-p ()
  (let* ((extensions (test-package :sophie-lisp-extensions))
         (common-lisp (test-package :common-lisp))
         (sophie (test-package :sophie-lisp))
         (extension-symbols (external-symbols-of extensions))
         (common-symbols (external-symbols-of common-lisp))
         (sophie-symbols (external-symbols-of sophie)))
    (and
     (every (lambda (symbol) (eq (symbol-package symbol) extensions))
            extension-symbols)
     (every (lambda (symbol)
              (multiple-value-bind (found status)
                  (find-symbol (symbol-name symbol) sophie)
                (and (eq found symbol) (eq status :external))))
            (append common-symbols extension-symbols))
     (notany (lambda (symbol)
               (eq (nth-value 1 (find-symbol (symbol-name symbol) common-lisp))
                   :external))
             extension-symbols)
     (= (length sophie-symbols)
        (+ (length common-symbols) (length extension-symbols)))
     (symbol-set-equal-p sophie-symbols
                         (append common-symbols extension-symbols)))))

(defun reader-definition-snapshot (readtable)
  (list
   (loop for code below char-code-limit
         for character = (code-char code)
         when character
           collect (multiple-value-bind (function terminating-p)
                       (get-macro-character character readtable)
                     (when function (list code function terminating-p)))
         into definitions
         finally (return (remove nil definitions)))
   (loop for code below char-code-limit
         for character = (code-char code)
         for function = (and character
                             (get-dispatch-macro-character #\# character readtable))
         when function
           collect (list code function))))

(defun reader-definitions-equal-p (left right &key (dispatch-identities-p t))
  (labels ((entries-equal-p (left-entries right-entries compare-functions-p)
             (and (= (length left-entries) (length right-entries))
                  (every (lambda (left-entry right-entry)
                           (and (= (first left-entry) (first right-entry))
                                (or (not compare-functions-p)
                                    (eq (second left-entry) (second right-entry)))
                                (eql (third left-entry) (third right-entry))))
                         left-entries right-entries))))
    (and (entries-equal-p (first left) (first right) t)
         (entries-equal-p (second left) (second right) dispatch-identities-p))))

(defun standard-reader-definitions-preserved-p (readtable)
  ;; The ambient readtable may legitimately carry host extensions the standard
  ;; readtable lacks (CCL's initial readtable defines #$, #&, #>, and #_
  ;; before any user code runs), so preservation means every standard
  ;; definition is present and unchanged and no Sophie dispatch character
  ;; leaked into READTABLE. Fresh-process children below compare exact
  ;; identities against a true pre-load snapshot.
  (let* ((pristine (copy-readtable nil))
         (expected (reader-definition-snapshot pristine))
         (actual (reader-definition-snapshot readtable)))
    ;; COPY-READTABLE creates a fresh dispatch table on SBCL, so its dispatch
    ;; closures cannot be EQ to those in READTABLE.
    (setf (first expected) (remove 35 (first expected) :key #'first)
          (first actual) (remove 35 (first actual) :key #'first))
    (and (every (lambda (entry)
                  (let ((resident (find (first entry) (first actual)
                                        :key #'first)))
                    (and resident
                         (eq (second entry) (second resident))
                         (eql (third entry) (third resident)))))
                (first expected))
         (every (lambda (entry)
                  (find (first entry) (second actual) :key #'first))
                (second expected))
         (notany (lambda (code)
                   (get-dispatch-macro-character #\# (code-char code) readtable))
                 (mapcar #'char-code '(#\? #\^ #\v #\h #\d #\u))))))

(parachute:define-test api.preserve-package-boundaries
  (let* ((common-lisp (test-package :common-lisp))
         (extensions (test-package :sophie-lisp-extensions))
         (sophie (test-package :sophie-lisp))
         (sl-user (test-package :sl-user))
         (internal (test-package :sophie-lisp.internal)))
    (parachute:true (null (package-use-list extensions)))
    (parachute:true (package-set-equal-p (package-use-list sophie)
                                         (list common-lisp extensions)))
    (parachute:true (package-set-equal-p (package-use-list sl-user)
                                         (list sophie)))
    (parachute:is equal '("SL")
                  (sort (copy-list (package-nicknames sophie)) #'string<))
    (parachute:is equal '("SL-EXT")
                  (sort (copy-list (package-nicknames extensions)) #'string<))
    (parachute:true (null (package-nicknames sl-user)))
    (parachute:true (null (external-symbols-of sl-user)))
    (parachute:true (null (external-symbols-of internal)))
    (parachute:true (package-set-equal-p (package-use-list internal)
                                         (list common-lisp extensions)))
    (multiple-value-bind (helper status)
        (find-symbol "USABLE-FUNCTION" internal)
      (parachute:true (and helper (eq status :internal))))
    (parachute:true (normative-sophie-exports-match-p)
                    "Normative Sophie export names must exactly match the extension package")
    (parachute:true (public-symbols-have-sophie-home-p)
                    "Public symbols must retain their prescribed home packages")
    ;; NIL is a symbol, not an absent FIND-SYMBOL result: status is decisive.
    (multiple-value-bind (symbol status) (find-symbol "NIL" sophie)
      (parachute:is eq cl:nil symbol)
      (parachute:is eq :external status))
    (let ((common-symbols (external-symbols-of common-lisp))
          (sophie-symbols (external-symbols-of sophie)))
      (parachute:is = (length common-symbols)
                    (count-if (lambda (symbol)
                                (member symbol sophie-symbols :test #'eq))
                              common-symbols))
      (parachute:is = (+ (length common-symbols)
                         (length (external-symbols-of extensions)))
                    (length sophie-symbols))
      (dolist (symbol common-symbols)
        (multiple-value-bind (found status)
            (find-symbol (symbol-name symbol) sophie)
          (parachute:is eq symbol found)
          (parachute:is eq :external status))))))

(defun f-api-project-root ()
  (asdf:system-source-directory "sophie-lisp"))


(defun f-api-fixture-source (root dependency-roots)
  (with-output-to-string (stream)
    ;; This child-process fixture intentionally targets SBCL for debugger and exit control.
    (format stream "(sb-ext:disable-debugger)~%")
    (format stream "(require :asdf)~%")
    (format stream "(setf asdf:*central-registry* nil)~%")
    (format stream
            "(asdf:initialize-source-registry '(:source-registry (:directory ~S) ~{(:directory ~S)~} :ignore-inherited-configuration))~%"
            root dependency-roots)
    (format stream "(dolist (system '~S) (asdf:load-system system))~%"
            '("named-readtables" "closer-mop" "alexandria"
              "bordeaux-threads" "trivial-garbage"))
    ;; SBCL's compilation support may load SB-CLTL2 while loading Sophie FASLs.
    ;; Establish that host package before taking the noninterference baseline.
    (format stream "(require :sb-cltl2)~%")
    (format stream "(defparameter *sophie-package-names* '(\"SL-USER\" \"SOPHIE-LISP\" \"SOPHIE-LISP-EXTENSIONS\" \"SOPHIE-LISP.INTERNAL\"))~%")
    (format stream "(defun snapshot-package-symbols (package)~%")
    (format stream "  (sort (loop for symbol being the symbols of package~%")
    (format stream "              collect (multiple-value-bind (found status)~%")
    (format stream "                          (find-symbol (symbol-name symbol) package)~%")
    (format stream "                        (declare (ignore found))~%")
    (format stream "                        (list (symbol-name symbol) status)))~%")
    (format stream "        #'string< :key #'first))~%")
    (format stream "(defun snapshot-package (package)~%")
    (format stream "  (list (package-name package)~%")
    (format stream "        (sort (copy-list (package-nicknames package)) #'string<)~%")
    (format stream "        (sort (mapcar #'package-name (package-use-list package)) #'string<)~%")
    ;; Check every existing package's metadata, but restrict symbol-table checks
    ;; to CL and the public dependency packages.  Loading a system can intern
    ;; keywords and loader/compiler bookkeeping symbols in other host packages.
    (format stream "        (when (member package~%")
    (format stream "                      (mapcar #'find-package~%")
    (format stream "                              '(\"COMMON-LISP\" \"NAMED-READTABLES\" \"CLOSER-MOP\" \"ALEXANDRIA\")))~%")
    (format stream "          (snapshot-package-symbols package))))~%")
    (format stream "(defun snapshot-packages ()~%")
    (format stream "  (sort (loop for package in (list-all-packages)~%")
    (format stream "              collect (snapshot-package package))~%")
    (format stream "        #'string< :key #'first))~%")
    (format stream "(defun same-package-snapshots-p (before after)~%")
    (format stream "  (every (lambda (snapshot)~%")
    (format stream "           (equal snapshot (assoc (first snapshot) after :test #'string=)))~%")
    (format stream "         before))~%")
    (format stream "(defun package-names (snapshots) (mapcar #'first snapshots))~%")
    (format stream "(defun snapshot-reader (readtable)~%")
    (format stream "  (list~%")
    (format stream "   (loop for code below char-code-limit~%")
    (format stream "         for character = (code-char code)~%")
    (format stream "         when (and character (get-macro-character character readtable))~%")
    (format stream "           collect (multiple-value-bind (function terminating-p)~%")
    (format stream "                       (get-macro-character character readtable)~%")
    (format stream "                     (list code function terminating-p)))~%")
    (format stream "   (loop for code below char-code-limit~%")
    (format stream "         for character = (code-char code)~%")
    (format stream "         for function = (and character~%")
    (format stream "                             (get-dispatch-macro-character #\\# character readtable))~%")
    (format stream "         when function~%")
    (format stream "           collect (list code function))))~%")
    (format stream "(defun same-reader-p (left right)~%")
    (format stream "  (labels ((same-entries-p (a b)~%")
    (format stream "             (and (= (length a) (length b))~%")
    (format stream "                  (every (lambda (x y)~%")
    (format stream "                           (and (= (first x) (first y))~%")
    (format stream "                                (eq (second x) (second y))~%")
    (format stream "                                (eql (third x) (third y))))~%")
    (format stream "                         a b))))~%")
    (format stream "    (and (same-entries-p (first left) (first right))~%")
    (format stream "         (same-entries-p (second left) (second right)))))~%")
    (format stream "(handler-case~%")
    (format stream "    (progn~%")
    (format stream "      (let ((before-packages (snapshot-packages))~%")
    (format stream "            (before-readtable *readtable*)~%")
    (format stream "            (before-reader (snapshot-reader *readtable*)))~%")
    (format stream "        (asdf:load-system \"sophie-lisp\")~%")
    (format stream "        (let ((after-packages (snapshot-packages)))~%")
    (format stream "          (unless (and (same-package-snapshots-p before-packages after-packages)~%")
    (format stream "                       (equal (sort (set-difference (package-names after-packages)~%")
    (format stream "                                                    (package-names before-packages)~%")
    (format stream "                                                    :test #'string=)~%")
    (format stream "                                    #'string<)~%")
    (format stream "                              *sophie-package-names*)~%")
    (format stream "                       (eq before-readtable *readtable*)~%")
    (format stream "                       (same-reader-p before-reader~%")
    (format stream "                                      (snapshot-reader *readtable*)))~%")
    (format stream "            (error \"F-API noninterference: packages-preserved=~~S added=~~S readtable-preserved=~~S reader-preserved=~~S\"~%")
    (format stream "                   (same-package-snapshots-p before-packages after-packages)~%")
    (format stream "                   (set-difference (package-names after-packages) (package-names before-packages) :test #'string=)~%")
    (format stream "                   (eq before-readtable *readtable*)~%")
    (format stream "                   (same-reader-p before-reader (snapshot-reader *readtable*))))))~%")
    (format stream "        (format t \"F-API-NONINTERFERENCE-PASSED~~%\"))~%")
    (format stream "  (error (condition)~%")
    (format stream "    (format *error-output* \"F-API-NONINTERFERENCE-FAILED: ~~A~~%\" condition)~%")
    (format stream "    (sb-ext:exit :code 1)))~%")
    (format stream "(sb-ext:exit :code 0)~%")))
(defun f-api-ros-available-p ()
  (handler-case
      (multiple-value-bind (output error-output status)
          (uiop:run-program '("ros" "--version")
                            :input nil :output :string :error-output :string
                            :ignore-error-status t)
        (declare (ignore output error-output))
        (and (integerp status) (zerop status)))
    (error () nil)))


;; The child below is the roswell DEFAULT implementation (SBCL) with
;; hardcoded SB-EXT forms in its script: it exercises SBCL regardless of
;; the host running this suite, so it never counts as CCL/ECL coverage.
(defun run-f-api-noninterference-fixture ()
  (let* ((root (uiop:ensure-directory-pathname (f-api-project-root)))
         (scratchpad
           (uiop:ensure-directory-pathname (uiop:temporary-directory)))
         (fixture (merge-pathnames
                   (format nil "f-api-noninterference-~D-~D.lisp"
                           (get-universal-time) (random 1000000000))
                   scratchpad))
         ;; Pass the parent's resolved dependency locations to the isolated child.
         (dependency-roots
           (mapcar (lambda (system)
                     (namestring (asdf:system-source-directory system)))
                   '("named-readtables" "closer-mop" "alexandria"
                     "bordeaux-threads" "trivial-garbage"))))
    (unwind-protect
         (handler-case
             (progn
               (ensure-directories-exist fixture)
               (with-open-file (stream fixture :direction :output :if-exists :error
                                :if-does-not-exist :create)
                 (write-string (f-api-fixture-source (namestring root)
                                                      dependency-roots)
                               stream))
               (multiple-value-bind (output error-output status)
                   (uiop:run-program
                    (list "ros" "run" "--non-interactive"
                          "--eval" "(sb-ext:disable-debugger)"
                          "--load" (namestring fixture))
                    :input nil :output :string :error-output :string
                    :ignore-error-status t)
                 (list :status status :output output :error-output error-output)))
           (file-error (condition)
             (list :status :unavailable :output ""
                   :error-output (princ-to-string condition)))
           (error (condition)
             (list :status :launch-error :output ""
                   :error-output (princ-to-string condition))))
      (when (probe-file fixture)
        (ignore-errors (delete-file fixture))))))

;; The child below is the roswell DEFAULT implementation (SBCL), so it
;; never counts as CCL/ECL coverage on any host running this suite.
(defun run-f-api-compile-only-fixture ()
  (let* ((root (uiop:ensure-directory-pathname (f-api-project-root)))
         (scratchpad
           (uiop:ensure-directory-pathname (uiop:temporary-directory)))
         (source (merge-pathnames "src/packages.lisp" root))
         (fixture (merge-pathnames
                   (format nil "f-api-compile-only-~D-~D.lisp"
                           (get-universal-time) (random 1000000000))
                   scratchpad))
         (fasl (merge-pathnames
                (format nil "f-api-compile-only-~D-~D.fasl"
                        (get-universal-time) (random 1000000000))
                scratchpad)))
    (unwind-protect
         (handler-case
             (progn
               (ensure-directories-exist fixture)
               (with-open-file (stream fixture :direction :output :if-exists :error
                                :if-does-not-exist :create)
                 (write-string
                  (with-output-to-string (source-stream)
                    (format source-stream "(sb-ext:disable-debugger)~%")
                    (format source-stream "(compile-file ~S :output-file ~S)~%"
                            (namestring source) (namestring fasl))
                    (format source-stream
                            "(unless (eq :external (nth-value 1 (find-symbol \"CAR\" (find-package :sophie-lisp))))~%")
                    (format source-stream
                            "  (error \"SL:CAR is not external after compile-file.\"))~%")
                    (format source-stream
                            "(format t \"F-API-COMPILE-ONLY-PASSED~~%\")~%")
                    (format source-stream "(sb-ext:exit :code 0)~%"))
                  stream))
               (multiple-value-bind (output error-output status)
                   (uiop:run-program
                    (list "ros" "run" "--non-interactive"
                          "--eval" "(sb-ext:disable-debugger)"
                          "--load" (namestring fixture))
                    :input nil :output :string :error-output :string
                    :ignore-error-status t)
                 (list :status status :output output :error-output error-output)))
           (file-error (condition)
             (list :status :unavailable :output ""
                   :error-output (princ-to-string condition)))
           (error (condition)
             (list :status :launch-error :output ""
                   :error-output (princ-to-string condition))))
      (when (probe-file fixture)
        (ignore-errors (delete-file fixture)))
      (when (probe-file fasl)
        (ignore-errors (delete-file fasl))))))

(parachute:define-test api.compile-only-common-lisp-exports
  (let ((result (if (f-api-ros-available-p)
                    (run-f-api-compile-only-fixture)
                    (list :status :unavailable :output ""
                          :error-output "Roswell executable is unavailable"))))
    (if (eq :unavailable (getf result :status))
        (parachute:skip "Roswell or a writable temporary directory is unavailable")
        (progn
          (parachute:is eql 0 (getf result :status)
                        "Child status ~S; stdout:~%~A~%stderr:~%~A"
                        (getf result :status) (getf result :output)
                        (getf result :error-output))
          (parachute:true
           (search "F-API-COMPILE-ONLY-PASSED" (getf result :output))
           "Child output:~%~A~%stderr:~%~A"
           (getf result :output) (getf result :error-output))
          (parachute:false
           (search "also exports"
                   (concatenate 'string
                                (getf result :output)
                                (getf result :error-output))))))))
(parachute:define-test api.preserve-reader-and-package-state
  (let* ((active-readtable *readtable*)
         (active-package *package*)
         (sl-user (test-package :sl-user)))
    (parachute:true (standard-reader-definitions-preserved-p active-readtable))
    (let ((*package* sl-user)
          (*readtable* active-readtable))
      (multiple-value-bind (form position)
          (read-from-string "(+ 1 2)")
        (declare (ignore position))
        (parachute:is equal '(+ 1 2) form))
      (parachute:true (eq active-readtable *readtable*)))
    (parachute:true (eq active-package *package*))
    (let ((values
           (let ((sophie-lisp:*list-delimiter* :lexically-bound)
                 (sophie-lisp:-> :lexically-bound)
                 (sophie-lisp:->> :lexically-bound)
                 (sophie-lisp:alist-dict :lexically-bound)
                 (sophie-lisp:as-> :lexically-bound)
                 (sophie-lisp:bind :lexically-bound)
                 (sophie-lisp:collector-accumulate :lexically-bound)
                 (sophie-lisp:collector-result :lexically-bound)
                 (sophie-lisp:compare :lexically-bound)
                 (sophie-lisp:compose :lexically-bound)
                 (sophie-lisp:cycle :lexically-bound)
                 (sophie-lisp:dict :lexically-bound)
                 (sophie-lisp:dict-alist :lexically-bound)
                 (sophie-lisp:dict-collect :lexically-bound)
                 (sophie-lisp:dict-frequencies :lexically-bound)
                 (sophie-lisp:dict-group-by :lexically-bound)
                 (sophie-lisp:dict-count-by :lexically-bound)
                 (sophie-lisp:dict-reduce-kv :lexically-bound)
                 (sophie-lisp:dict-remove-keys :lexically-bound)
                 (sophie-lisp:dict-select-keys :lexically-bound)
                 (sophie-lisp:dict-keys :lexically-bound)
                 (sophie-lisp:dict-keys-map :lexically-bound)
                 (sophie-lisp:dict-member :lexically-bound)
                 (sophie-lisp:dict-merge :lexically-bound)
                 (sophie-lisp:dict-merge* :lexically-bound)
                 (sophie-lisp:dict-merge-with :lexically-bound)
                 (sophie-lisp:dict-plist :lexically-bound)
                 (sophie-lisp:dict-ref :lexically-bound)
                 (sophie-lisp:dict-ref-in :lexically-bound)
                 (sophie-lisp:dict-set :lexically-bound)
                 (sophie-lisp:dict-set-in :lexically-bound)
                 (sophie-lisp:dict-size :lexically-bound)
                 (sophie-lisp:dict-test :lexically-bound)
                 (sophie-lisp:dict-transform :lexically-bound)
                 (sophie-lisp:dict-update :lexically-bound)
                 (sophie-lisp:dict-update-in :lexically-bound)
                 (sophie-lisp:dict-vals :lexically-bound)
                 (sophie-lisp:dict-values-map :lexically-bound)
                 (sophie-lisp:dict-without :lexically-bound)
                 (sophie-lisp:dict-zipmap :lexically-bound)
                 (sophie-lisp:dictp :lexically-bound)
                 (sophie-lisp:doseq :lexically-bound)
                 (sophie-lisp:entry-key :lexically-bound)
                 (sophie-lisp:entry-value :lexically-bound)
                 (sophie-lisp:equals :lexically-bound)
                 (sophie-lisp:fbind :lexically-bound)
                 (sophie-lisp:fn :lexically-bound)
                 (sophie-lisp:gt :lexically-bound)
                 (sophie-lisp:gte :lexically-bound)
                 (sophie-lisp:hash-code :lexically-bound)
                 (sophie-lisp:hash-set :lexically-bound)
                 (sophie-lisp:hash-set-p :lexically-bound)
                 (sophie-lisp:if-bind :lexically-bound)
                 (sophie-lisp:iterate :lexically-bound)
                 (sophie-lisp:juxt :lexically-bound)
                 (sophie-lisp:lazy-cons :lexically-bound)
                 (sophie-lisp:lazy-seq :lexically-bound)
                 (sophie-lisp:lazy-seq-p :lexically-bound)
                 (sophie-lisp:lt :lexically-bound)
                 (sophie-lisp:lte :lexically-bound)
                 (sophie-lisp:make-collector-for :lexically-bound)
                 (sophie-lisp:make-lazy-seq :lexically-bound)
                 (sophie-lisp:map-entry :lexically-bound)
                 (sophie-lisp:op :lexically-bound)
                 (sophie-lisp:ordered-dict :lexically-bound)
                 (sophie-lisp:ordered-dict-p :lexically-bound)
                 (sophie-lisp:plist-dict :lexically-bound)
                 (sophie-lisp:plist-dict-view :lexically-bound)
                 (sophie-lisp:range :lexically-bound)
                 (sophie-lisp:ref :lexically-bound)
                 (sophie-lisp:repeatedly :lexically-bound)
                 (sophie-lisp:seq-concatenate :lexically-bound)
                 (sophie-lisp:seq-count :lexically-bound)
                 (sophie-lisp:seq-count-if :lexically-bound)
                 (sophie-lisp:seq-dedupe :lexically-bound)
                 (sophie-lisp:seq-drop :lexically-bound)
                 (sophie-lisp:seq-drop-last :lexically-bound)
                 (sophie-lisp:seq-drop-while :lexically-bound)
                 (sophie-lisp:seq-emptyp :lexically-bound)
                 (sophie-lisp:seq-every :lexically-bound)
                 (sophie-lisp:seq-filter :lexically-bound)
                 (sophie-lisp:seq-find :lexically-bound)
                 (sophie-lisp:seq-find-if :lexically-bound)
                 (sophie-lisp:seq-first :lexically-bound)
                 (sophie-lisp:seq-interleave :lexically-bound)
                 (sophie-lisp:seq-into :lexically-bound)
                 (sophie-lisp:seq-join :lexically-bound)
                 (sophie-lisp:seq-keep :lexically-bound)
                 (sophie-lisp:seq-last :lexically-bound)
                 (sophie-lisp:seq-length :lexically-bound)
                 (sophie-lisp:seq-map :lexically-bound)
                 (sophie-lisp:seq-map-indexed :lexically-bound)
                 (sophie-lisp:seq-mapcat :lexically-bound)
                 (sophie-lisp:seq-max :lexically-bound)
                 (sophie-lisp:seq-member :lexically-bound)
                 (sophie-lisp:seq-min :lexically-bound)
                 (sophie-lisp:seq-mismatch :lexically-bound)
                 (sophie-lisp:seq-notany :lexically-bound)
                 (sophie-lisp:seq-notevery :lexically-bound)
                 (sophie-lisp:seq-partition :lexically-bound)
                 (sophie-lisp:seq-partition-by :lexically-bound)
                 (sophie-lisp:seq-position :lexically-bound)
                 (sophie-lisp:seq-position-if :lexically-bound)
                 (sophie-lisp:seq-reduce :lexically-bound)
                 (sophie-lisp:seq-reductions :lexically-bound)
                 (sophie-lisp:seq-ref :lexically-bound)
                 (sophie-lisp:seq-remove :lexically-bound)
                 (sophie-lisp:seq-remove-duplicates :lexically-bound)
                 (sophie-lisp:seq-remove-if :lexically-bound)
                 (sophie-lisp:seq-rest :lexically-bound)
                 (sophie-lisp:seq-reverse :lexically-bound)
                 (sophie-lisp:seq-search :lexically-bound)
                 (sophie-lisp:seq-some :lexically-bound)
                 (sophie-lisp:seq-sort :lexically-bound)
                 (sophie-lisp:seq-split :lexically-bound)
                 (sophie-lisp:seq-split-at :lexically-bound)
                 (sophie-lisp:seq-split-with :lexically-bound)
                 (sophie-lisp:seq-stable-sort :lexically-bound)
                 (sophie-lisp:seq-subseq :lexically-bound)
                 (sophie-lisp:seq-substitute :lexically-bound)
                 (sophie-lisp:seq-substitute-if :lexically-bound)
                 (sophie-lisp:seq-take :lexically-bound)
                 (sophie-lisp:seq-take-last :lexically-bound)
                 (sophie-lisp:seq-take-nth :lexically-bound)
                 (sophie-lisp:seq-take-while :lexically-bound)
                 (sophie-lisp:seq-tree-seq :lexically-bound)
                 (sophie-lisp:seq-trim :lexically-bound)
                 (sophie-lisp:seq-trim-left :lexically-bound)
                 (sophie-lisp:seq-trim-right :lexically-bound)
                 (sophie-lisp:seqablep :lexically-bound)
                 (sophie-lisp:set-add :lexically-bound)
                 (sophie-lisp:set-intersection :lexically-bound)
                 (sophie-lisp:set-member :lexically-bound)
                 (sophie-lisp:set-minus :lexically-bound)
                 (sophie-lisp:set-remove :lexically-bound)
                 (sophie-lisp:set-size :lexically-bound)
                 (sophie-lisp:set-subset-p :lexically-bound)
                 (sophie-lisp:set-union :lexically-bound)
                 (sophie-lisp:sl-core-syntax :lexically-bound)
                 (sophie-lisp:? :lexically-bound)
                 (sophie-lisp:@ :lexically-bound)
                 (sophie-lisp:<> :lexically-bound)
                 (sophie-lisp:when-bind :lexically-bound)
                 (sophie-lisp:~> :lexically-bound))
             (list sophie-lisp:*list-delimiter*
                   sophie-lisp:->
                   sophie-lisp:->>
                   sophie-lisp:alist-dict
                   sophie-lisp:as->
                   sophie-lisp:bind
                   sophie-lisp:collector-accumulate
                   sophie-lisp:collector-result
                   sophie-lisp:compare
                   sophie-lisp:compose
                   sophie-lisp:cycle
                   sophie-lisp:dict
                   sophie-lisp:dict-alist
                   sophie-lisp:dict-collect
                   sophie-lisp:dict-frequencies
                   sophie-lisp:dict-group-by
                   sophie-lisp:dict-count-by
                   sophie-lisp:dict-reduce-kv
                   sophie-lisp:dict-keys
                   sophie-lisp:dict-keys-map
                   sophie-lisp:dict-member
                   sophie-lisp:dict-merge
                   sophie-lisp:dict-merge*
                   sophie-lisp:dict-merge-with
                   sophie-lisp:dict-plist
                   sophie-lisp:dict-ref
                   sophie-lisp:dict-ref-in
                   sophie-lisp:dict-remove-keys
                   sophie-lisp:dict-select-keys
                   sophie-lisp:dict-set
                   sophie-lisp:dict-set-in
                   sophie-lisp:dict-size
                   sophie-lisp:dict-test
                   sophie-lisp:dict-transform
                   sophie-lisp:dict-update
                   sophie-lisp:dict-update-in
                   sophie-lisp:dict-vals
                   sophie-lisp:dict-values-map
                   sophie-lisp:dict-without
                   sophie-lisp:dict-zipmap
                   sophie-lisp:dictp
                   sophie-lisp:doseq
                   sophie-lisp:entry-key
                   sophie-lisp:entry-value
                   sophie-lisp:equals
                   sophie-lisp:fbind
                   sophie-lisp:fn
                   sophie-lisp:gt
                   sophie-lisp:gte
                   sophie-lisp:hash-code
                   sophie-lisp:hash-set
                   sophie-lisp:hash-set-p
                   sophie-lisp:if-bind
                   sophie-lisp:iterate
                   sophie-lisp:juxt
                   sophie-lisp:lazy-cons
                   sophie-lisp:lazy-seq
                   sophie-lisp:lazy-seq-p
                   sophie-lisp:lt
                   sophie-lisp:lte
                   sophie-lisp:make-collector-for
                   sophie-lisp:make-lazy-seq
                   sophie-lisp:map-entry
                   sophie-lisp:op
                   sophie-lisp:ordered-dict
                   sophie-lisp:ordered-dict-p
                   sophie-lisp:plist-dict
                   sophie-lisp:plist-dict-view
                   sophie-lisp:range
                   sophie-lisp:ref
                   sophie-lisp:repeatedly
                   sophie-lisp:seq-concatenate
                   sophie-lisp:seq-count
                   sophie-lisp:seq-count-if
                   sophie-lisp:seq-dedupe
                   sophie-lisp:seq-drop
                   sophie-lisp:seq-drop-last
                   sophie-lisp:seq-drop-while
                   sophie-lisp:seq-emptyp
                   sophie-lisp:seq-every
                   sophie-lisp:seq-filter
                   sophie-lisp:seq-find
                   sophie-lisp:seq-find-if
                   sophie-lisp:seq-first
                   sophie-lisp:seq-interleave
                   sophie-lisp:seq-into
                   sophie-lisp:seq-join
                   sophie-lisp:seq-keep
                   sophie-lisp:seq-last
                   sophie-lisp:seq-length
                   sophie-lisp:seq-map
                   sophie-lisp:seq-map-indexed
                   sophie-lisp:seq-mapcat
                   sophie-lisp:seq-max
                   sophie-lisp:seq-member
                   sophie-lisp:seq-min
                   sophie-lisp:seq-mismatch
                   sophie-lisp:seq-notany
                   sophie-lisp:seq-notevery
                   sophie-lisp:seq-partition
                   sophie-lisp:seq-partition-by
                   sophie-lisp:seq-position
                   sophie-lisp:seq-position-if
                   sophie-lisp:seq-reduce
                   sophie-lisp:seq-reductions
                   sophie-lisp:seq-ref
                   sophie-lisp:seq-remove
                   sophie-lisp:seq-remove-duplicates
                   sophie-lisp:seq-remove-if
                   sophie-lisp:seq-rest
                   sophie-lisp:seq-reverse
                   sophie-lisp:seq-search
                   sophie-lisp:seq-some
                   sophie-lisp:seq-sort
                   sophie-lisp:seq-split
                   sophie-lisp:seq-split-at
                   sophie-lisp:seq-split-with
                   sophie-lisp:seq-stable-sort
                   sophie-lisp:seq-subseq
                   sophie-lisp:seq-substitute
                   sophie-lisp:seq-substitute-if
                   sophie-lisp:seq-take
                   sophie-lisp:seq-take-last
                   sophie-lisp:seq-take-nth
                   sophie-lisp:seq-take-while
                   sophie-lisp:seq-tree-seq
                   sophie-lisp:seq-trim
                   sophie-lisp:seq-trim-left
                   sophie-lisp:seq-trim-right
                   sophie-lisp:seqablep
                   sophie-lisp:set-add
                   sophie-lisp:set-intersection
                   sophie-lisp:set-member
                   sophie-lisp:set-minus
                   sophie-lisp:set-remove
                   sophie-lisp:set-size
                   sophie-lisp:set-subset-p
                   sophie-lisp:set-union
                   sophie-lisp:sl-core-syntax
                   sophie-lisp:?
                   sophie-lisp:@
                   sophie-lisp:<>
                   sophie-lisp:when-bind
                   sophie-lisp:~>))))
      (parachute:is = 144 (length values))
      (parachute:true (every (lambda (value) (eq :lexically-bound value)) values)))
    (let ((core-readtable
            (ignore-errors
              (named-readtables:find-readtable :sl-core-syntax))))
      (parachute:true (or (null core-readtable)
                          (not (eq active-readtable core-readtable)))))
    (parachute:true (eq active-readtable *readtable*))
    (let ((result (if (f-api-ros-available-p)
                      (run-f-api-noninterference-fixture)
                      (list :status :unavailable :output ""
                            :error-output "Roswell executable is unavailable"))))
      (if (eq :unavailable (getf result :status))
          (parachute:skip "Roswell or a writable temporary directory is unavailable")
          (progn
            (parachute:is eql 0 (getf result :status)
                          "Child status ~S; stdout:~%~A~%stderr:~%~A"
                          (getf result :status) (getf result :output)
                          (getf result :error-output))
            (parachute:true
             (search "F-API-NONINTERFERENCE-PASSED" (getf result :output))
             "Child output:~%~A~%stderr:~%~A"
             (getf result :output) (getf result :error-output)))))))
