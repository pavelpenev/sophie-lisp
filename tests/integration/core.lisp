;;;; Final integration tests. Oracles are CL finite models and normative signatures,
;;;; not outputs sampled from Sophie. Cold-load evidence is a separate child.
(in-package #:sophie-lisp.tests)

;; Host introspection verifies implementation-level function signatures; each
;; host's introspector sits behind a feature guard in INTEGRATION-LAMBDA-LIST.
#+sbcl (eval-when (:compile-toplevel :load-toplevel :execute) (require :sb-introspect))

(defun integration-lambda-list (designator)
  "The host introspector's lambda list for the function DESIGNATOR.
SBCL, CCL, and ECL each expose one; an unknown host gets NIL."
  #+sbcl (sb-introspect:function-lambda-list designator)
  #+ccl (ccl:arglist designator)
  #+ecl (si:function-lambda-list designator)
  #-(or sbcl ccl ecl) nil)

(defun integration-list (source &optional (limit 20000))
  "Bounded public traversal; a broken finite fixture cannot hang the suite."
  (let ((view (sl:seq-into 'sl:lazy-seq source)))
    (loop for i from 0
          until (sl:seq-emptyp view)
          when (= i limit) do (error "Finite integration traversal exceeded ~D" limit)
          collect (sl:seq-first view)
          do (setf view (sl:seq-rest view)))))

(defparameter *integration-functions*
  '((sl:make-lazy-seq 1 0 nil nil) (sl:lazy-cons 2 0 nil nil)
    (sl:lazy-seq-p 1 0 nil nil) (sl:map-entry 2 0 nil nil)
    (sl:entry-key 1 0 nil nil) (sl:entry-value 1 0 nil nil)
    (sl:range 0 0 nil (:start :end :step))
    (sl:repeatedly 1 0 nil (:count)) (sl:iterate 2 0 nil nil)
    (sl:cycle 1 0 nil nil) (sl:lt 2 0 nil nil) (sl:lte 2 0 nil nil)
    (sl:gt 2 0 nil nil) (sl:gte 2 0 nil nil)
    (sl:juxt 0 0 t nil) (sl:compose 0 0 t nil)
    (sl:dict 0 0 t nil) (sl:hash-set 0 0 t nil)
    (sl:alist-dict 1 0 nil nil) (sl:plist-dict 1 0 nil nil)
    (sl:plist-dict-view 1 0 nil nil) (sl:dict-alist 1 0 nil nil)
    (sl:dict-plist 1 0 nil nil)))

(defun integration-call-shape (lambda-list)
  ;; Parameter spelling is not a calling convention; keywords and arity are.
  (let ((mode :required)
        (required 0)
        (optional 0)
        (rest nil)
        (keys nil))
    (dolist (item lambda-list)
      (cond ((member item '(&optional &rest &key &aux &allow-other-keys))
             (setf mode item)
             (when (eq item '&rest)
               (setf rest t)))
            ((eq mode :required) (incf required))
            ((eq mode '&optional) (incf optional))
            ((eq mode '&key)
             (let ((name (if (consp item) (first item) item)))
               (push (if (consp name) (first name)
                         (intern (symbol-name name) :keyword)) keys)))))
    (list required optional rest (sort keys #'string<))))

(defun integration-macro-metadata ()
  ;; Macro parsers may deliberately expose &REST; their BNF is checked by
  ;; expansion and behavior, not by insisting on one implementation lambda list.
  (dolist (form '((sl:op (+ 1 2)) (sl:lazy-seq nil)
                  (sl:doseq (x nil) (declare (ignore x)))
                  (sl:bind ((x 1)) x) (sl:fbind ((f #'1+)) (f 1))
                  (sl:if-bind (x 1) x) (sl:when-bind (x 1) x)
                  (sl:fn (x) x) (sl:-> 1 (1+)) (sl:->> 1 (1+))
                  (sl:as-> 1 x (1+ x)) (sl:~> 1 (+ sl:<> 2))))
    (parachute:true (listp (integration-lambda-list (first form))))
    (multiple-value-bind (expansion expanded) (macroexpand-1 form)
      (parachute:true expanded)
      (parachute:false (eq expansion form))))
  (dolist (form '((sl:op) (sl:op 1 2) (sl:lazy-seq) (sl:lazy-seq nil nil)))
    (parachute:fail (macroexpand-1 form) program-error)))

(parachute:define-test core.validate-public-api-and-reader-syntax
  (parachute:true (normative-sophie-exports-match-p))
  (parachute:true (public-symbols-have-sophie-home-p))
  (dolist (entry *required-generic-signatures*)
    (parachute:true (generic-signature-matches-p entry))
    (let ((gf
           (fdefinition
            (generic-function-designator-for (first entry) (second entry)))))
      (parachute:true (closer-mop:generic-function-methods gf))
      (parachute:true
       (some (lambda (method) (null (method-qualifiers method)))
             (closer-mop:generic-function-methods gf)))))
  (dolist (row *integration-functions*)
    (destructuring-bind
        (name required optional rest keys)
        row
      (parachute:true
       (and (fboundp name) (not (macro-function name))
            (not (typep (fdefinition name) 'generic-function))))
      (parachute:is equal
                    (list required optional rest
                          (sort (copy-list keys) #'string<))
                    (integration-call-shape
                     (integration-lambda-list (fdefinition name))))))
  (dolist
      (name
       '(sophie-lisp-extensions:op sophie-lisp-extensions:lazy-seq
         sophie-lisp-extensions:doseq sophie-lisp-extensions:bind
         sophie-lisp-extensions:fbind sophie-lisp-extensions:if-bind
         sophie-lisp-extensions:when-bind sophie-lisp-extensions:fn
         sophie-lisp-extensions:-> sophie-lisp-extensions:->>
         sophie-lisp-extensions:as-> sophie-lisp-extensions:~>))
    (parachute:true (macro-function name)))
  (dolist
      (name
       '(sophie-lisp-extensions:lazy-seq sophie-lisp-extensions:map-entry
         sophie-lisp-extensions:dict sophie-lisp-extensions:hash-set
         sophie-lisp-extensions:plist-dict-view))
    (parachute:true (find-class name nil)))
  (parachute:true (boundp 'sophie-lisp-extensions:*list-delimiter*))
  (dolist
      (marker
       '(sophie-lisp-extensions:? sophie-lisp-extensions:@
         sophie-lisp-extensions:<>))
    (parachute:false (constantp marker))
    (parachute:is = 41
                  (eval
                   `(let ((,marker 41))
                      ,marker))))
  (do-external-symbols (symbol :sl-ext)
    (unless (eq symbol 'sophie-lisp-extensions:*list-delimiter*)
      (parachute:is = 17
                    (eval
                     `(let ((,symbol 17))
                        ,symbol)))))
  ;; XRI-COLD-CHECK is defined in tests/syntax/reader.lisp, loaded earlier.
  (parachute:true (xri-cold-check "source"))
  (parachute:true (xri-cold-check "compiled"))
  (let ((*readtable*
         (editor-hints.named-readtables:find-readtable :sl-core-syntax))
        (*package* (find-package :cl-user)))
    (parachute:is equalp #(2 3) (eval (read-from-string "#v(2 3)")))
    (parachute:is = 5 (funcall (eval (read-from-string "#^(+ % 2)")) 3))
    (parachute:is = 7
                  (sophie-lisp-extensions:dict-ref
                   (eval (read-from-string "#d(:x 7)")) :x))
    (parachute:is = 2
                  (sophie-lisp-extensions:set-size
                   (eval (read-from-string "#u(1 1 2)"))))
    (parachute:is = 9 (gethash :x (eval (read-from-string "#h(:x 9)")))))
  (let ((*readtable* (copy-readtable nil)) (*package* (find-package :sl-user)))
    (parachute:fail (read-from-string "#v(1)") reader-error)
    (parachute:is eq 'let (read-from-string "LET")))
  (parachute:is equal '(1 2 3) (append '(1 2) '(3)))
  (parachute:false (equal 1 1.0))
  (parachute:true (sophie-lisp-extensions:equals 1 1.0)) (integration-macro-metadata))

(parachute:define-test sequence.preserve-types-and-laziness
  (dolist (type '(bit (unsigned-byte 8) character))
    (let* ((data (if (eq type 'character) '(#\a #\b #\c) '(0 1 0)))
           (source (make-array 5 :element-type type :initial-element (first data)
                               :fill-pointer 3 :adjustable t)))
      (replace source data)
      (dolist (split (list (sl:seq-split-at 0 source)
                          (sl:seq-split-with (constantly nil) source)))
        (let ((pieces (integration-list split)))
          (parachute:is = 2 (length pieces))
          (parachute:is = 0 (length (first pieces)))
          (dolist (piece pieces)
            (parachute:is equal (array-element-type source) (array-element-type piece))
            (parachute:false (eq source piece)))
          (parachute:is equal data (integration-list (second pieces)))))
      (let* ((parts (integration-list (sl:seq-partition 2 source :pad '(:padding))))
             (a (first parts))
             (b (second parts)))
        (parachute:is = 2 (length parts))
        (parachute:is equal (array-element-type source) (array-element-type a))
        (parachute:is eq t (array-element-type b))
        (parachute:is equal (list (third data) :padding) (integration-list b)))
      (let ((copy (sl:seq-drop-last 0 source))
            (empty (sl:seq-drop-last 9 source)))
        (parachute:false (eq copy source))
        (parachute:is equal data (integration-list copy))
        (parachute:is equal (array-element-type source) (array-element-type empty))
        (parachute:is = 0 (length empty)))
      (parachute:is equal data (coerce source 'list))))
  (let ((table (make-hash-table :test 'equal)))
    (setf (gethash :a table) 1 (gethash :b table) 2)
    (dolist (source (list table (sl:dict :a 1 :b 2)))
      (let* ((calls 0)
             (result (sl:seq-filter (lambda (entry) (incf calls)
                                     (oddp (sl:entry-value entry))) source)))
        (parachute:is = 2 calls)
        (parachute:is eq (class-of source) (class-of result))
        (parachute:is = 1 (sl:dict-size result))
        (parachute:is equal '(1 t) (multiple-value-list (sl:dict-ref result :a)))
        (parachute:is = 2 (sl:dict-size source))
        (when (hash-table-p result)
          (parachute:is eq (hash-table-test source) (hash-table-test result))
          (parachute:false (eq source result))))))
  (let* ((forces 0)
         (tail (sl:lazy-seq (progn (incf forces) (throw 'extension-tail :overconsumed))))
         (source (sl:lazy-cons 1 (sl:lazy-cons 2 tail)))
         (result (sl:seq-drop-last 1 source)))
    (parachute:is = 0 forces)
    (parachute:is = 1 (catch 'extension-tail (sl:seq-first result)))
    (parachute:is = 0 forces)
    (parachute:is eq :overconsumed (catch 'extension-tail (sl:seq-first (sl:seq-rest result))))
    (parachute:is = 1 forces))
  (parachute:true (sl:lazy-seq-p (sl:seq-drop-last 0 '(1 2)))))

(defun integration-value-pairs (n)
  "Equal pairs covering every final structural container domain, independently built."
  (let ((a (make-hash-table :test 'eq)) (b (make-hash-table :test 'equal)))
    (setf (gethash :n a) n (gethash :n b) (float n 1d0))
    (list (list n (float n 1d0))
          (list (list n :x) (list (float n 1d0) :x))
          (list (vector n :x) (vector (float n 1d0) :x))
          (list (make-array '(1 1) :initial-element n)
                (make-array '(1 1) :initial-element (float n 1d0)))
          (list (copy-seq "ab") (vector #\a #\b))
          (list (sl:map-entry :n n) (sl:map-entry :n (float n 1d0)))
          (list (sl:lazy-cons n nil) (sl:lazy-cons (float n 1d0) nil))
          (list a b)
          (list (sl:dict :n n :x 2) (sl:dict :x 2.0 :n (float n 1d0)))
          (list (sl:hash-set n :x) (sl:hash-set :x (float n 1d0)))
          (list (sl:plist-dict-view (list :n n :n :ignored :x 2))
                (sl:plist-dict-view (list :x 2.0 :n (float n 1d0)))))))

(parachute:define-test sequence.match-finite-models-and-structural-equality
  (dolist (seed '(20260906 7 1729))
    (let ((state seed))
      (labels ((draw (bound)
                 (setf state (logand #xffffffff (+ (* state 1664525) 1013904223)))
                 (mod (ash state -8) bound)))
        (dotimes (trial 12)
          (let* ((data (loop repeat (+ 1 (draw 20)) collect (draw 16)))
                 (cut (draw (1+ (length data))))
                 (vector (coerce data 'vector)))
            (dolist (source (list (copy-list data) vector (sl:seq-into 'sl:lazy-seq data)))
              (parachute:is equal (subseq data 0 cut) (integration-list (sl:seq-take cut source)))
              (parachute:is equal (subseq data cut) (integration-list (sl:seq-drop cut source)))
              (parachute:is equal (remove-if-not #'oddp data)
                            (integration-list (sl:seq-filter #'oddp source)))
              (parachute:is equal (mapcar #'1+ data) (integration-list (sl:seq-map #'1+ source)))
              (parachute:is = (reduce #'+ data) (sl:seq-reduce #'+ source))
              (parachute:is equal data
                            (integration-list (sl:seq-concatenate (sl:seq-take cut source)
                                                        (sl:seq-drop cut source)))))
            (parachute:is equal data (coerce vector 'list)))
          (dolist (pair (integration-value-pairs (+ 20 (draw 100))))
            (destructuring-bind (a b) pair
              (parachute:true (sl:equals a b))
              (parachute:true (sl:equals b a))
              (parachute:is = (sl:hash-code a) (sl:hash-code b))
              (parachute:is eq :equal (sl:compare a b))
              (let* ((dict (sl:dict a :old b :new))
                     (set (sl:hash-set a b))
                     (frequencies (sl:dict-frequencies (list a b))))
                (parachute:is = 1 (sl:dict-size dict))
                (parachute:is eq :new (sl:dict-ref dict a))
                (parachute:is eq b (sl:entry-key (sl:seq-first dict)))
                (parachute:is = 1 (sl:set-size set))
                (parachute:is eq a (sl:seq-first set))
                (parachute:is = 2 (sl:dict-ref frequencies b))
                (parachute:is = 0 (sl:dict-size (sl:dict-without dict a)))
                (parachute:is = 1 (sl:dict-size dict)))))))))
  (let ((a (sl:dict :x 1)) (b (sl:plist-dict-view '(:x 1))))
    (parachute:false (sl:equals a b))
    (parachute:is eq :unequal (sl:compare a b)))
  (let* ((k1 (copy-seq "x")) (k2 (copy-seq "x"))
         (two (sl:plist-dict-view (list k1 1 k2 1)))
         (one (sl:plist-dict-view (list k1 1 k1 1))))
    (parachute:is = 2 (sl:dict-size two))
    (parachute:is = 1 (sl:dict-size one))
    (parachute:false (sl:equals two one)))
  (let ((tail (sl:lazy-seq (throw 'extension-decisive :overconsumed))))
    (parachute:is eq nil (catch 'extension-decisive
                          (sl:equals (sl:lazy-cons 1 tail) (sl:lazy-cons 2 tail))))
    (parachute:is eq :less (catch 'extension-decisive
                            (sl:compare (sl:lazy-cons 1 tail) (sl:lazy-cons 2 tail))))))
