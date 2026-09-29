;;;; Explicit alist/plist and dictionary conversions.
(in-package #:sophie-lisp.internal)

(defun validated-alist-entries (alist)
  "Validate the complete finite alist before hashing any key."
  (unless (listp alist)
    (raise-type-error alist 'list))
  (let ((tail alist)
        (seen (make-hash-table :test #'eq))
        (entries nil))
    (loop
      (cond
        ((null tail)
         (return (nreverse entries)))
        ((not (consp tail))
         (raise-type-error alist 'list))
        ((gethash tail seen)
         (raise-type-error alist 'list))
        (t
         (setf (gethash tail seen) t)
         (let ((entry (car tail)))
           (unless (consp entry)
             (raise-type-error entry 'cons))
           (push entry entries))
         (setf tail (cdr tail)))))))

(defun sl:alist-dict (alist)
  "Convert a proper alist to a persistent EQUALS dictionary. The last equal key
and value win. Signals TYPE-ERROR for malformed input."
  (let ((entries (validated-alist-entries alist)))
    (loop with result = (sl:dict)
          for entry in entries
          do (setf result
                   (sl:dict-set result (car entry) (cdr entry)))
          finally (return result))))

(defun require-dict-conversion-source (dictionary)
  (unless (sl:dictp dictionary)
    (raise-type-error dictionary '(satisfies sl:dictp)))
  dictionary)

(defun dict-conversion-pairs (dictionary)
  "Eagerly copy dictionary associations into fresh temporary pairs."
  (let ((view (open-view (require-dict-conversion-source dictionary)))
        (pairs nil))
    (loop
      (multiple-value-bind (empty-p entry rest) (view-step view)
        (if empty-p
            (return (nreverse pairs))
            (progn
              (push (cons (sl:entry-key entry)
                          (sl:entry-value entry))
                    pairs)
              (setf view rest)))))))

(defun sl:dict-alist (dictionary)
  "Convert a dictionary to a fresh alist, retaining keys and values. Signals
TYPE-ERROR unless DICTIONARY satisfies SL:DICTP."
  (dict-conversion-pairs dictionary))

(defun sl:dict-plist (dictionary)
  "Convert a dictionary to a fresh plist, retaining keys and values. Signals
TYPE-ERROR unless DICTIONARY satisfies SL:DICTP."
  (mapcan (lambda (pair) (list (car pair) (cdr pair)))
          (dict-conversion-pairs dictionary)))


(defun dict-group-traverse (source callback)
  "Call CALLBACK on each element of SOURCE in one retained traversal."
  (do-view-elements (element source)
    (funcall callback element)))

(defmethod sl:dict-frequencies ((sequence t))
  "Eagerly count all elements of SEQUENCE under EQUALS."
  (let ((result (sl:dict)))
    (dict-group-traverse
     sequence
     (lambda (element)
       (multiple-value-bind (count present-p)
           (sl:dict-ref result element)
         (setf result
               (sl:dict-set result element
                            (if present-p (1+ count) 1))))))
    result))

(defmethod sl:dict-group-by ((key-function t) (sequence t))
  "Eagerly group SEQUENCE elements by the primary callback value; each result
value is the list of the elements that produced that key, in source order.
KEY-FUNCTION is a function designator; a non-designator signals TYPE-ERROR."
  (let ((function (usable-function key-function))
        (groups (sl:dict)))
    (dict-group-traverse
     sequence
     (lambda (element)
       (let ((group-key (funcall function element)))
         (multiple-value-bind (group present-p)
             (sl:dict-ref groups group-key)
           (setf groups
                 (sl:dict-set groups group-key
                              (cons element (if present-p group nil))))))))
    ;; The accumulated conses are private to GROUPS.  Replacing each value with
    ;; a fresh reverse preserves source order without mutating an input.
    (let ((view (open-view groups))
          (result groups))
      (loop
        (multiple-value-bind (empty-p entry rest) (view-step view)
          (when empty-p (return result))
          (setf result
                (sl:dict-set result
                             (sl:entry-key entry)
                             (reverse (sl:entry-value entry))))
          (setf view rest))))))

(defmethod sl:dict-count-by ((key-function t) (sequence t))
  "Eagerly count elements by the primary result of KEY-FUNCTION under EQUALS.
KEY-FUNCTION is a function designator; a non-designator signals TYPE-ERROR."
  (let ((function (usable-function key-function))
        (counts nil))
    (dict-group-traverse
     sequence
     (lambda (element)
       (let* ((key (funcall function element))
              (entry (find key counts :test #'sl:equals :key #'car)))
         (if entry
             (setf (car entry) key
                   (cdr entry) (1+ (cdr entry)))
             (setf counts (append counts (list (cons key 1))))))))
    (let ((result (sl:dict)))
      (dolist (entry counts result)
        (setf result (sl:dict-set result (car entry) (cdr entry)))))))

(defmethod sl:dict-zipmap ((keys t) (values t))
  "Eagerly pair corresponding elements, stopping at the shorter source. Later
pairs overwrite earlier ones on a repeated key (last-wins)."
  ;; Opening both views validates both operands before any pair is installed,
  ;; but does not force either lazy source.
  (let ((key-view (open-view keys))
        (value-view (open-view values))
        (result (sl:dict)))
    (loop
      ;; The key step is deliberately first.  An observed key end prevents a
      ;; later value tail from being forced.
      (multiple-value-bind (key-empty-p key rest-keys)
          (view-step key-view)
        (when key-empty-p (return result))
        (multiple-value-bind (value-empty-p value rest-values)
            (view-step value-view)
          (when value-empty-p (return result))
          (setf result (sl:dict-set result key value)
                key-view rest-keys
                value-view rest-values))))))

(defmethod sl:dict-reduce-kv ((function t) initial-value dict)
  (usable-function function)
  (let ((view (open-view (if (sl:dictp dict)
                              dict
                              (raise-type-error dict '(satisfies sl:dictp)))))
        (accumulator initial-value))
    (loop
      (multiple-value-bind (empty-p entry rest) (view-step view)
        (when empty-p (return accumulator))
        (unless (typep entry 'sl:map-entry)
          (raise-type-error entry 'sl:map-entry))
        (setf accumulator
              (funcall function accumulator
                       (sl:entry-key entry)
                       (sl:entry-value entry)))
        (setf view rest)))))

(defun dict-project (source accessor)
  "Return a lazy projection of one retained entry view."
  (let ((view (open-view source)))
    (labels ((project (current)
               (when current
                 (make-lazy-node
                  (lambda ()
                    (multiple-value-bind (empty-p entry rest)
                        (view-step current)
                      (unless empty-p
                        (sl:lazy-cons (funcall accessor entry)
                                      (project rest)))))))))
      (project view))))

(defmethod sl:dict-keys ((collection t))
  (dict-project collection #'sl:entry-key))

(defmethod sl:dict-vals ((collection t))
  (dict-project collection #'sl:entry-value))
