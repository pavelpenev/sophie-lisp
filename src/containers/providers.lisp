;;;; Persistent dictionary wrappers over the shared immutable hash trie.
(in-package #:sophie-lisp.internal)

(defclass sl:dict ()
  ((root :initarg :root :reader dict-root)
   (count :initarg :count :reader dict-count :type (integer 0 *)))
  (:documentation
   "Persistent immutable dictionary using SL:EQUALS for key matching."))

(defun dict-from-root (root count)
  "Wrap an existing persistent ROOT without traversing or copying it."
  (make-instance 'sl:dict :root root :count count))

(defmethod sl:dictp ((object sl:dict))
  t)

(defmethod sl:dict-test ((dict sl:dict))
  #'sl:equals)

(defmethod sl:dict-size ((dict sl:dict))
  (dict-count dict))

(defmethod sl:dict-ref ((dict sl:dict) key &optional default)
  (multiple-value-bind (value present-p)
      (trie-ref (dict-root dict) key (sl:hash-code key))
    (if present-p
        (values value t)
        (values default nil))))

(defmethod (setf sl:dict-ref) (new-value (dict sl:dict) key &optional default)
  (declare (ignore new-value key default))
  (error "~A~A"
         "A persistent DICT is immutable and cannot be modified; "
         "use DICT-SET to produce an updated dictionary."))

(defmethod sl:dict-set ((dict sl:dict) key value)
  ;; Even an equal value must not suppress replacement of the key object.
  (multiple-value-bind (root delta)
      (trie-put (dict-root dict) key value (sl:hash-code key) t)
    (dict-from-root root (+ (dict-count dict) delta))))

(defmethod sl:dict-without ((dict sl:dict) key)
  (multiple-value-bind (root removed-p)
      (trie-remove (dict-root dict) key (sl:hash-code key))
    (if removed-p
        (dict-from-root root (1- (dict-count dict)))
        dict)))

(defun sl:dict (&rest key-values)
  "Construct a persistent dictionary from alternating key/value arguments.
Keys match under SL:EQUALS; the last equal key and value win.
Signals PROGRAM-ERROR for an odd argument count."
  ;; Validate the complete arity before invoking any key's value protocols.
  (when (oddp (length key-values))
    (error 'program-error))
  ;; Thread the trie root and entry count directly and wrap once at the end:
  ;; routing each pair through SL:DICT-SET would allocate a fresh SL:DICT
  ;; wrapper per pair only to discard it on the next iteration. The TRIE-PUT
  ;; calls, per-pair order, and replace-key-p semantics are identical to the
  ;; incremental DICT-SET chain, so the resulting trie and count match it
  ;; exactly. SL:DICT is spec-defined as non-generic with no methods, so no
  ;; DICT-SET method (including a user :around method) is specified to run
  ;; during construction.
  (loop with root = nil
        with count = 0
        for (key value) on key-values by #'cddr
        do (multiple-value-bind (new-root delta)
               (trie-put root key value (sl:hash-code key) t)
             (setf root new-root
                   count (+ count delta)))
        finally (return (dict-from-root root count))))

(defun copy-standard-table (table)
  "Return a fresh shallow copy of TABLE with its standard configuration."
  (let ((test (standard-hash-test (hash-table-test table))))
    (let ((copy (make-hash-table
                 :test test
                 :size (hash-table-size table)
                 :rehash-size (hash-table-rehash-size table)
                 :rehash-threshold (hash-table-rehash-threshold table))))
      (maphash (lambda (key value)
                 (setf (gethash key copy) value))
               table)
      copy)))

(defun table-last-put (table key value)
  "Install KEY and VALUE, retaining KEY as the representative on replacement."
  (remhash key table)
  (setf (gethash key table) value))

(defmethod sl:dictp ((object hash-table))
  (declare (ignore object))
  t)

(defmethod sl:dictp ((object t))
  (declare (ignore object))
  nil)

(defmethod sl:dict-ref ((table hash-table) key &optional default)
  (multiple-value-bind (value present-p)
      (gethash key table default)
    (values value present-p)))

(defmethod sl:dict-ref ((object t) key &optional default)
  (declare (ignore key default))
  (raise-type-error object '(satisfies sl:dictp)))

(defmethod sl:dict-test ((table hash-table))
  (standard-hash-test (hash-table-test table)))

(defmethod sl:dict-test ((object t))
  (raise-type-error object '(satisfies sl:dictp)))

(defmethod sl:dict-size ((table hash-table))
  (hash-table-count table))

(defmethod sl:dict-size ((object t))
  (raise-type-error object '(satisfies sl:dictp)))

(defmethod (setf sl:dict-ref) (new-value (table hash-table) key &optional default)
  (declare (ignore default))
  (setf (gethash key table) new-value))

(defmethod (setf sl:dict-ref) (new-value (object t) key &optional default)
  (declare (ignore new-value key default))
  (if (sl:dictp object)
      (raise-program-error "The dictionary does not support DICT-REF mutation.")
      (raise-type-error object '(satisfies sl:dictp))))

(defmethod sl:dict-set ((table hash-table) key value)
  (let ((copy (copy-standard-table table)))
    (table-last-put copy key value)
    copy))

(defmethod sl:dict-set ((object t) key value)
  (declare (ignore key value))
  (if (sl:dictp object)
      (raise-program-error "The dictionary does not support DICT-SET.")
      (raise-type-error object '(satisfies sl:dictp))))

(defmethod sl:dict-without ((table hash-table) key)
  (let ((copy (copy-standard-table table)))
    (remhash key copy)
    copy))

(defmethod sl:dict-without ((object t) key)
  (declare (ignore key))
  (if (sl:dictp object)
      (raise-program-error "The dictionary does not support DICT-WITHOUT.")
      (raise-type-error object '(satisfies sl:dictp))))

(defclass sl:plist-dict-view ()
  ((plist
     :initarg :plist
     :reader plist-view-plist)
   (canonical
     :initarg :canonical
     :reader plist-view-canonical)
   (count
     :initarg :count
     :reader plist-view-count
     :type (integer 0 *)))
  (:documentation
   "Read-only dictionary view over a property list using EQ for key matching."))

(defun plist-analysis (plist)
  "Validate PLIST and return all raw pairs and first-EQ canonical pairs.

The returned vectors contain MAP-ENTRY objects whose fields retain the raw
indicator and value objects.  Validation completes before either vector is
returned."
  (let ((tail plist)
        (seen (make-hash-table :test #'eq))
        (all (make-array 0 :adjustable t :fill-pointer 0))
        (canonical (make-array 0 :adjustable t :fill-pointer 0))
        (indicators (make-hash-table :test #'eq)))
    (labels ((malformed ()
               (signal-malformed-plist plist 'list)))
      (loop
        (cond
          ((null tail)
           (return (values (copy-seq all) (copy-seq canonical))))
          ((not (consp tail))
           (malformed))
          ((gethash tail seen)
           (malformed))
          (t
           (setf (gethash tail seen) t)
           (let ((key (car tail))
                 (value-tail (cdr tail)))
             (cond
               ((null value-tail)
                (raise-program-error))
               ((not (consp value-tail))
                (malformed))
               ((gethash value-tail seen)
                (malformed))
               (t
                (setf (gethash value-tail seen) t)
                (let ((entry (make-map-entry key (car value-tail))))
                  (vector-push-extend entry all)
                  (multiple-value-bind (ignored present-p)
                      (gethash key indicators)
                    (declare (ignore ignored))
                    (unless present-p
                      (setf (gethash key indicators) entry)
                      (vector-push-extend entry canonical))))
                (setf tail (cdr value-tail)))))))))))

(defun sl:plist-dict (plist)
  "Convert PLIST to a persistent dictionary with EQUALS key matching.
For duplicate EQUALS keys, the last association wins. A malformed plist, including
an improper or odd-length plist, signals TYPE-ERROR or PROGRAM-ERROR as specified;
the result does not retain PLIST, so subsequent mutation of PLIST has no effect."
  ;; PLIST-ANALYSIS validates before constructing either representation; this
  ;; constructor consumes raw entries for last-wins EQUALS semantics.
  (multiple-value-bind (entries canonical)
      (plist-analysis plist)
    (declare (ignore canonical))
    (loop with result = (sl:dict)
          for entry across entries
          do (setf result
                   (sl:dict-set result
                                (sl:entry-key entry)
                                (sl:entry-value entry)))
          finally (return result))))

(defun sl:plist-dict-view (plist)
  "Return a read-only dictionary view of PLIST using EQ key matching.
For duplicate EQ keys, the first association is visible. A malformed plist,
including an improper or odd-length plist, signals TYPE-ERROR or PROGRAM-ERROR
as specified. The view retains PLIST; callers retain ownership and must not
mutate its structure while the view exists."
  ;; PLIST-ANALYSIS validates before constructing either representation; this
  ;; view stores first-EQ canonical entries and intentionally ignores raw ones.
  (multiple-value-bind (entries canonical)
      (plist-analysis plist)
    (declare (ignore entries))
    (make-instance 'sl:plist-dict-view
                   :plist plist
                   :canonical canonical
                   :count (length canonical))))

(defmethod sl:dictp ((view sl:plist-dict-view))
  (declare (ignore view))
  t)

(defmethod sl:dict-ref ((view sl:plist-dict-view) key &optional default)
  (do ((tail (plist-view-plist view) (cddr tail)))
      ((null tail) (values default nil))
    (when (eq (car tail) key)
      (return (values (cadr tail) t)))))

(defmethod sl:dict-member ((dictionary sl:plist-dict-view) key)
  ;; This specialization is enumerated by SL:DICT-MEMBER; the plist view's
  ;; first-match EQ lookup coincides with the T default.
  (multiple-value-bind (value present-p) (sl:dict-ref dictionary key)
    (values present-p value)))

(defmethod sl:dict-member ((dictionary t) key)
  (multiple-value-bind (value present-p) (sl:dict-ref dictionary key)
    (values present-p value)))

(defmethod sl:dict-test ((view sl:plist-dict-view))
  (declare (ignore view))
  #'eq)

(defmethod sl:dict-size ((view sl:plist-dict-view))
  (plist-view-count view))

(defmethod sl:dict-set ((view sl:plist-dict-view) key value)
  (declare (ignore key value))
  (raise-program-error "A PLIST-DICT-VIEW is read-only."))

(defmethod sl:dict-without ((view sl:plist-dict-view) key)
  (declare (ignore key))
  (raise-program-error "A PLIST-DICT-VIEW is read-only."))

(defmethod (setf sl:dict-ref)
    (new-value (view sl:plist-dict-view) key &optional default)
  (declare (ignore new-value key default))
  (raise-program-error "A PLIST-DICT-VIEW is read-only."))
