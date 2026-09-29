;;;; Persistent sets share trie structure, never dictionary semantics.
(in-package #:sophie-lisp.internal)

(defclass sl:hash-set ()
  ((root :initarg :root :reader set-root)
   (count :initarg :count :reader set-count :type (integer 0 *)))
  (:documentation
   "Persistent immutable hash set using SL:EQUALS for element matching."))

;;; The marker is a private value, not an element returned by set traversal.
;;; DEFVAR preserves its identity if this file is loaded again.
(defvar *set-marker* (make-symbol "SET-PRESENT"))

(defun set-from-root (root count)
  "Wrap an existing persistent ROOT without traversing or copying it."
  (make-instance 'sl:hash-set :root root :count count))

(defmethod sl:hash-set-p ((object t))
  nil)

(defmethod sl:hash-set-p ((object sl:hash-set))
  t)

(defun set-insert (set element)
  ;; A duplicate preserves the first representative and the entire old root.
  (multiple-value-bind (root delta changed-p)
      (trie-put (set-root set) element *set-marker*
                (sl:hash-code element) nil)
    (if changed-p
        (set-from-root root (+ (set-count set) delta))
        set)))

(defun set-delete (set element)
  (multiple-value-bind (root removed-p)
      (trie-remove (set-root set) element (sl:hash-code element))
    (if removed-p
        (set-from-root root (1- (set-count set)))
        set)))

(defun sl:hash-set (&rest elements)
  "Eagerly construct a persistent set, retaining first representatives."
  (let ((set (set-from-root nil 0)))
    (dolist (element elements set)
      (setf set (set-insert set element)))))

(defun set-edit-materialize (sequence)
  "Eagerly copy and deduplicate one generic seqable under EQUALS."
  (let ((result (set-from-root nil 0)))
    (do-view-elements (element sequence :result result)
      (setf result (set-insert result element)))))

(defmethod sl:set-add (item (sequence sl:hash-set))
  (set-insert sequence item))

(defmethod sl:set-add (item (sequence t))
  (set-insert (set-edit-materialize sequence) item))

(defmethod sl:set-remove (item (sequence sl:hash-set))
  (set-delete sequence item))

(defmethod sl:set-remove (item (sequence t))
  (set-delete (set-edit-materialize sequence) item))

(defmethod sl:set-member (item (sequence sl:hash-set))
  (multiple-value-bind (value present-p)
      (trie-ref (set-root sequence) item (sl:hash-code item))
    (declare (ignore value))
    present-p))

(defmethod sl:set-member (item (sequence t))
  (let ((view (open-view sequence)))
    (loop
      (multiple-value-bind (empty-p element rest) (view-step view)
        (when empty-p (return nil))
        (when (sl:equals item element)
          (return t))
        (setf view rest)))))

(defmethod sl:set-size ((sequence sl:hash-set))
  (set-count sequence))

(defmethod sl:set-size ((sequence t))
  (set-count (set-edit-materialize sequence)))

(defmethod sl:set-subset-p ((first-set t) (second-set t))
  ;; Materialize both operands before testing either one.  In particular, an
  ;; empty first operand does not excuse validation or consumption of SECOND-SET.
  (let ((left (set-edit-materialize first-set))
        (right (set-edit-materialize second-set))
        (view nil))
    (setf view (open-view left))
    (loop
      (multiple-value-bind (empty-p element rest) (view-step view)
        (when empty-p (return t))
        (multiple-value-bind (value present-p)
            (trie-ref (set-root right) element (sl:hash-code element))
          (declare (ignore value))
          (unless present-p (return nil)))
        (setf view rest)))))

(defun set-algebra-materialize-operands (first-set second-set more-sets)
  "Materialize every operand once before applying the algebraic operation."
  (loop for operand in (cons first-set (cons second-set more-sets))
        collect (set-edit-materialize operand)))

(defun set-algebra-insert-all (result source)
  (let ((view (open-view source)))
    (loop
      (multiple-value-bind (empty-p element rest) (view-step view)
        (if empty-p
            (return result)
            (setf result (set-insert result element)
                  view rest))))))

(defun set-algebra-union-materialized (operands)
  (let ((result (set-from-root nil 0)))
    (dolist (operand operands result)
      (setf result (set-algebra-insert-all result operand)))))

(defun set-algebra-intersection-materialized (operands)
  (let ((first (first operands))
        (others (rest operands))
        (result (set-from-root nil 0)))
    (let ((view (open-view first)))
      (loop
        (multiple-value-bind (empty-p element rest) (view-step view)
          (if empty-p
              (return result)
              (progn
                (when (every (lambda (operand)
                               (sl:set-member element operand))
                             others)
                  (setf result (set-insert result element)))
                (setf view rest))))))))

(defun set-algebra-minus-materialized (operands)
  (let ((first (first operands))
        (excluded (set-algebra-union-materialized (rest operands)))
        (result (set-from-root nil 0)))
    (let ((view (open-view first)))
      (loop
        (multiple-value-bind (empty-p element rest) (view-step view)
          (if empty-p
              (return result)
              (progn
                (unless (sl:set-member element excluded)
                  (setf result (set-insert result element)))
                (setf view rest))))))))

(defmethod sl:set-union ((first-set t) (second-set t) &rest more-sets)
  (let ((operands (set-algebra-materialize-operands first-set second-set more-sets)))
    (set-algebra-union-materialized operands)))

(defmethod sl:set-intersection ((first-set t) (second-set t) &rest more-sets)
  (let ((operands (set-algebra-materialize-operands first-set second-set more-sets)))
    (set-algebra-intersection-materialized operands)))

(defmethod sl:set-minus ((first-set t) (second-set t) &rest more-sets)
  (let ((operands (set-algebra-materialize-operands first-set second-set more-sets)))
    (set-algebra-minus-materialized operands)))
