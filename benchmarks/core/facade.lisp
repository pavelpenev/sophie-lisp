;;;; Facade benchmarks: the Sophie REF, SEQ-INTO, and Collector surfaces
;;;; against the plain CL forms they stand in front of.
;;;;
;;;; Matrix I covers SL:REF on vectors, hash tables, dicts, and lists;
;;;; SL:SEQ-INTO for every eager target; and the Collector protocol for the
;;;; list, vector, string, hash-table, and dict targets. The CL baselines
;;;; come first (category :FACADE-BASELINE) so every Sophie bench (category
;;;; :FACADE) can reference its baseline by registration order. Every
;;;; comparison bench carries a :TIER fairness label and a note with the
;;;; shared caveat: the Sophie side goes through CLOS generic dispatch and
;;;; the collector protocol, while the baselines are direct calls.
;;;;
;;;; SL:SEQ-INTO takes its target designator first and resolves a name
;;;; symbol internally; SL:MAKE-COLLECTOR-FOR is the raw generic function
;;;; and dispatches on class objects and prototype instances, never on name
;;;; symbols, so the collector benches pass (FIND-CLASS ...) targets.
;;;;
;;;; Sizing follows the suite rules: (10 100 1000 10000) for every bench;
;;;; ECL caps sizes at 10000 through the harness host seam. :TEST #'EQUAL
;;;; is kept uniformly on the hash-table shapes, even for fixnum keys where
;;;; ANSI's default EQL test would be faster, because the Sophie
;;;; hash-table collector defaults to :TEST #'EQUAL. No reader feature
;;;; conditionals appear in this file; host differences live in
;;;; benchmarks/host.lisp.

(in-package #:sophie-lisp.benchmarks)

;;; Input builders. Every builder runs inside :SETUP, outside the timed
;;; region; persistent inputs are rebuilt fresh per rep by the harness.

(defun facade-vector (n)
  "Return a fresh N-element vector of fixnums, each element its triple."
  (coerce (loop for index below n collect (* index 3)) 'vector))

(defun facade-list (n)
  "Return a fresh N-element list of fixnums 0 to N-1."
  (loop for index below n collect index))

(defun facade-char-list (n)
  "Return a fresh N-element list of characters cycling the lowercase
letters, so every position carries content the string target must observe."
  (loop for index below n
        collect (code-char (+ 97 (mod index 26)))))

(defun facade-equal-table (n)
  "Return a fresh N-entry hash table under :TEST #'EQUAL with fixnum keys 0
to N-1, each mapped to its triple."
  (loop with table = (make-hash-table :test #'equal)
        for key below n
        do (setf (gethash key table) (* key 3))
        finally (return table)))

(defun facade-dict (n)
  "Return a fresh N-pair persistent dict with fixnum keys 0 to N-1, each
mapped to its triple."
  (loop with result = (dict)
        for key below n
        do (setf result (dict-set result key (* key 3)))
        finally (return result)))

(defun facade-entries (n)
  "Return a fresh N-element list of SL:MAP-ENTRY objects, key I mapped to
its triple, the element shape the dict-side collector targets require."
  (loop for key below n
        collect (map-entry key (* key 3))))

(defun facade-alist (n)
  "Return a fresh N-element alist with fixnum keys 0 to N-1, each mapped to
its triple, the plain CL input shape for the hash-table baselines."
  (loop for key below n
        collect (cons key (* key 3))))

;;; Shared note text. Every comparison bench pairs the caveat with its own
;;; specifics through FACADE-NOTE.

(alexandria:define-constant +facade-caveat+
  "Sophie: CLOS generic facade, collector protocol; CL: direct call."
  :test #'equal
  :documentation "Shared fairness caveat carried by every facade comparison
bench.")

(defun facade-note (specific)
  "Return the note for one facade comparison bench: the shared fairness
caveat followed by the bench's SPECIFIC text."
  (concatenate 'string +facade-caveat+ " " specific))

;;; CL baselines. Each builds its input inside :SETUP, outside the timed
;;; region, and measures the plain CL form in :CALL.

(define-bench cl-elt-vector
  (:category :facade-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (facade-vector n) (floor n 2)))
  (:call (context) (elt (car context) (cdr context)))
  (:note "ELT on an N-element vector at the mid index; the direct CL
element access."))

(define-bench cl-gethash-equal
  (:category :facade-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (facade-equal-table n) (floor n 2)))
  (:call (context) (gethash (cdr context) (car context)))
  (:note "GETHASH hit on an N-entry :TEST #'EQUAL table with fixnum keys;
:TEST #'EQUAL is kept even for fixnum keys, where ANSI's default EQL test
would be faster, so the table shape matches the Sophie hash-table
collector's default test."))

(define-bench cl-coerce-vector
  (:category :facade-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (facade-list n))
  (:call (context) (coerce context 'vector))
  (:note "COERCE of an N-element list of fixnums to a vector."))

(define-bench cl-coerce-list
  (:category :facade-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (facade-vector n))
  (:call (context) (coerce context 'list))
  (:note "COERCE of an N-element vector of fixnums to a list."))

(define-bench cl-coerce-string
  (:category :facade-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (facade-char-list n))
  (:call (context) (coerce context 'string))
  (:note "COERCE of an N-element list of characters to a string."))

(define-bench cl-loop-collect
  (:category :facade-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (facade-list n))
  (:call (context) (loop for element in context collect element))
  (:note "LOOP COLLECT building an N-element list from a prebuilt N-element
list of fixnums."))

(define-bench cl-loop-collect-vector
  (:category :facade-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (facade-list n))
  (:call (context)
    (loop with buffer = (make-array 16 :adjustable t :fill-pointer 0)
          for element in context
          do (vector-push-extend element buffer
                                 (max 1 (array-total-size buffer)))
          finally (return (copy-seq buffer))))
  (:note "The CL push-extend idiom for building a vector element by element:
VECTOR-PUSH-EXTEND into a geometrically growing adjustable buffer, finalized
with COPY-SEQ to an exact-length simple vector, mirroring the Sophie vector
collector's buffer-plus-copy shape."))

(define-bench cl-loop-into-hashtable
  (:category :facade-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (facade-alist n))
  (:call (context)
    (loop with table = (make-hash-table :test #'equal)
          for pair in context
          do (setf (gethash (car pair) table) (cdr pair))
          finally (return table)))
  (:note "Manual LOOP building an N-entry :TEST #'EQUAL hash table from a
prebuilt alist; the CL counterpart of collecting keyed entries into a
table."))

;;; Sophie REF benches. Each measures one SL:REF call on a prebuilt input
;;; at a present key; REF returns the value and a presence flag as two
;;; values through generic dispatch.

(define-bench ref-vector
  (:category :facade)
  (:baseline cl-elt-vector)
  (:tier :dispatch)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (facade-vector n) (floor n 2)))
  (:call (context) (ref (car context) (cdr context)))
  (:note (facade-note
           "SL:REF on an N-element vector at the mid index; the generic
facade adds CLOS dispatch and the two-value presence protocol over the
baseline's direct ELT, so the ratio is the constant dispatch factor.")))

(define-bench ref-hashtable
  (:category :facade)
  (:baseline cl-gethash-equal)
  (:tier :dispatch)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (facade-equal-table n) (floor n 2)))
  (:call (context) (ref (car context) (cdr context)))
  (:note (facade-note
           "SL:REF on an N-entry :TEST #'EQUAL hash table at a present
fixnum key; REF forwards to SL:DICT-REF, adding generic dispatch and the
supplied-default check over the baseline's direct GETHASH.")))

(define-bench ref-dict
  (:category :facade)
  (:baseline cl-gethash-equal)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (facade-dict n) (floor n 2)))
  (:call (context) (ref (car context) (cdr context)))
  (:note (facade-note
           "SL:REF on an N-pair persistent dict at a present fixnum key.
The dict is persistent and matches keys under structural equality, while
the GETHASH baseline mutates a :TEST #'EQUAL table, so the ratio measures
the trie walk plus dispatch against a different container semantics; read
with the persistence caveat.")))

(define-bench ref-list
  (:category :facade)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (facade-list n) (floor n 2)))
  (:call (context) (ref (car context) (cdr context)))
  (:note "SL:REF on an N-element list at the mid index. Absolute: the
honest CL counterpart, ELT on a list at the same index, shares the O(N)
spine walk, so pairing against the vector ELT baseline would conflate the
list-versus-vector access cost with dispatch; read the dispatch factor
against REF-VECTOR instead."))

;;; Sophie SEQ-INTO benches. Each measures one SL:SEQ-INTO call collecting
;;; a prebuilt source into a fresh target; the source is never mutated.

(define-bench seq-into-vector
  (:category :facade)
  (:baseline cl-coerce-vector)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (facade-list n))
  (:call (context) (seq-into 'vector context))
  (:note (facade-note
           "SL:SEQ-INTO collecting an N-element list into a fresh vector
through the collector protocol; the baseline is the direct COERCE, so the
ratio is the protocol cost over the primitive.")))

(define-bench seq-into-list
  (:category :facade)
  (:baseline cl-coerce-list)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (facade-vector n))
  (:call (context) (seq-into 'list context))
  (:note (facade-note
           "SL:SEQ-INTO collecting an N-element vector into a fresh list
through the collector protocol; the baseline is the direct COERCE.")))

(define-bench seq-into-string
  (:category :facade)
  (:baseline cl-coerce-string)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (facade-char-list n))
  (:call (context) (seq-into 'string context))
  (:note (facade-note
           "SL:SEQ-INTO collecting an N-element list of characters into a
fresh string through the collector protocol; the baseline is the direct
COERCE.")))

(define-bench seq-into-hashtable
  (:category :facade)
  (:baseline cl-loop-into-hashtable)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (facade-entries n))
  (:call (context) (seq-into 'hash-table context))
  (:note (facade-note
           "SL:SEQ-INTO collecting N SL:MAP-ENTRY objects into a fresh
:TEST #'EQUAL hash table. The Sophie side reads entries through the
traversal view and pays REMHASH plus SETF GETHASH per entry, while the
baseline reads alist conses with one direct SETF GETHASH each, so the input
shapes differ by one structure kind.")))

(define-bench seq-into-dict
  (:category :facade)
  (:sizes (10 100 1000 10000))
  (:setup (n) (facade-entries n))
  (:call (context) (seq-into 'dict context))
  (:note "SL:SEQ-INTO collecting N SL:MAP-ENTRY objects into a persistent
dict; no CL equivalent for the dict target exists, so no baseline."))

(define-bench seq-into-hash-set
  (:category :facade)
  (:sizes (10 100 1000 10000))
  (:setup (n) (facade-list n))
  (:call (context) (seq-into 'hash-set context))
  (:note "SL:SEQ-INTO collecting N distinct fixnums into a persistent hash
set; no CL equivalent for the set target exists, so no baseline."))

(define-bench seq-into-ordered-dict
  (:category :facade)
  (:sizes (10 100 1000 10000))
  (:setup (n) (facade-entries n))
  (:call (context) (seq-into 'ordered-dict context))
  (:note "SL:SEQ-INTO collecting N SL:MAP-ENTRY objects into a persistent
ordered dict; no CL equivalent for the ordered-dict target exists, so no
baseline."))

;;; Sophie Collector benches. Each timed call builds a fresh collector,
;;; accumulates every element of the prebuilt source, and finalizes the
;;; result, so the source is never mutated and the full protocol cost sits
;;; inside the timed region.

(define-bench collector-list
  (:category :facade)
  (:baseline cl-loop-collect)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (facade-list n))
  (:call (context)
    (let ((collector (make-collector-for (find-class 'list))))
      (loop for element in context
            do (collector-accumulate collector element))
      (collector-result collector)))
  (:note (facade-note
           "The Collector protocol for the list target: MAKE-COLLECTOR-FOR,
N COLLECTOR-ACCUMULATE calls, and the reversing COLLECTOR-RESULT, against
the baseline's LOOP COLLECT.")))

(define-bench collector-vector
  (:category :facade)
  (:baseline cl-loop-collect-vector)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (facade-list n))
  (:call (context)
    (let ((collector (make-collector-for (find-class 'vector))))
      (loop for element in context
            do (collector-accumulate collector element))
      (collector-result collector)))
  (:note (facade-note
           "The Collector protocol for the vector target: MAKE-COLLECTOR-FOR,
N type-checked VECTOR-PUSH-EXTEND accumulates, and the exact-length
finalization copy, against the baseline's push-extend idiom.")))

(define-bench collector-string
  (:category :facade)
  (:sizes (10 100 1000 10000))
  (:setup (n) (facade-char-list n))
  (:call (context)
    (let ((collector (make-collector-for (find-class 'string))))
      (loop for element in context
            do (collector-accumulate collector element))
      (collector-result collector)))
  (:note "The Collector protocol for the string target: MAKE-COLLECTOR-FOR,
N character-checked accumulates, and the exact-length string finalization.
Absolute: CL has no single canonical element-by-element string-building
idiom; the nearest CL shapes are the batch COERCE of CL-COERCE-STRING and
the push-extend idiom of CL-LOOP-COLLECT-VECTOR, so no baseline is
paired."))

(define-bench collector-hashtable
  (:category :facade)
  (:baseline cl-loop-into-hashtable)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (facade-entries n))
  (:call (context)
    (let ((collector (make-collector-for (find-class 'hash-table))))
      (loop for element in context
            do (collector-accumulate collector element))
      (collector-result collector)))
  (:note (facade-note
           "The Collector protocol for the hash-table target:
MAKE-COLLECTOR-FOR, N SL:MAP-ENTRY accumulates each paying REMHASH plus
SETF GETHASH, and the table finalization, against the baseline's alist
LOOP.")))

(define-bench collector-dict
  (:category :facade)
  (:sizes (10 100 1000 10000))
  (:setup (n) (facade-entries n))
  (:call (context)
    (let ((collector (make-collector-for (find-class 'dict))))
      (loop for element in context
            do (collector-accumulate collector element))
      (collector-result collector)))
  (:note "The Collector protocol for the dict target: MAKE-COLLECTOR-FOR,
N SL:MAP-ENTRY accumulates buffered into a vector, and the DICT-COLLECT
finalization under structural equality; no CL equivalent for the dict
target exists, so no baseline."))
