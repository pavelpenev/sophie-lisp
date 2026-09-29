;;;; Ordered-dict benchmarks: the Sophie ordered dictionary surface.
;;;;
;;;; Matrix D covers the ordered-dict protocol. CL has no ordered dictionary,
;;;; so most benches here have no baseline and carry a note that their
;;;; numbers are absolute. The one baseline, HT-REF-ORDERED (category
;;;; :ORDERED-DICT-BASELINE), measures the nearest CL lookup shape, GETHASH
;;;; on an :TEST #'EQUAL hash table, for ORDERED-DICT-REF (category
;;;; :ORDERED-DICT) to be read against; it is registered first so the
;;;; comparison bench can reference it by registration order.
;;;;
;;;; Sizing follows the suite rules: (10 100 1000 10000) for every bench; ECL
;;;; caps sizes at 10000 through the harness host seam. No reader feature
;;;; conditionals appear in this file; host differences live in
;;;; benchmarks/host.lisp.

(in-package #:sophie-lisp.benchmarks)

;;; Input builders. Every builder runs inside :SETUP, outside the timed
;;; region; persistent inputs are rebuilt fresh per rep by the harness.

(defun ranged-ordered-dict (start count)
  "Return a COUNT-pair ordered dict with fixnum keys START to
START+COUNT-1, each mapped to its triple, inserted in ascending key order."
  (loop with result = (ordered-dict)
        for key from start below (+ start count)
        do (setf result (dict-set result key (* key 3)))
        finally (return result)))

(defun ranged-equal-table (start count)
  "Return a COUNT-entry hash table with fixnum keys START to START+COUNT-1,
each mapped to its triple, under :TEST #'EQUAL."
  (loop with table = (make-hash-table :test #'equal)
        for key from start below (+ start count)
        do (setf (gethash key table) (* key 3))
        finally (return table)))

(defun lcg-next (state)
  "Return the next state of the 31-bit linear congruential generator
X = 1103515245*X + 12345 mod 2^31 from STATE."
  (mod (+ (* 1103515245 state) 12345) 2147483648))

(defun shuffled-keys (n)
  "Return a vector of the fixnums 0 to N-1 in a deterministically shuffled
order: a Fisher-Yates shuffle driven by LCG-NEXT from the seed N, drawing
each swap index from the generator's upper bits, so the same size always
produces the same key order without host RANDOM."
  (let ((keys (coerce (loop for key below n collect key) 'vector))
        (state (max 1 n)))
    (loop for index from (- n 1) downto 1
          do (setf state (lcg-next state))
             (rotatef (aref keys index)
                      (aref keys (mod (ash state -16) index)))
          finally (return keys))))

;;; Shared note text. The one comparison bench pairs the caveat with its own
;;; specifics through ORDERED-DICT-NOTE.

(alexandria:define-constant +ordered-dict-caveat+
  "Sophie: persistent ordered dict, AVL order tree plus key index, structural
equality, CLOS generic; CL: mutable :TEST #'EQUAL hash table, direct call."
  :test #'equal
  :documentation "Shared semantics caveat carried by the ordered dict
comparison bench.")

(defun ordered-dict-note (specific)
  "Return the note for the ordered dict comparison bench: the shared
semantics caveat followed by the bench's SPECIFIC text."
  (concatenate 'string +ordered-dict-caveat+ " " specific))

;;; CL baseline. CL has no ordered dictionary, so the one baseline measures
;;; the nearest lookup shape only.

(define-bench ht-ref-ordered
  (:category :ordered-dict-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (ranged-equal-table 0 n) (floor n 2)))
  (:call (context) (gethash (cdr context) (car context)))
  (:note "GETHASH hit on an N-entry :TEST #'EQUAL table with fixnum keys; CL
has no ordered dictionary, so this plain lookup is the nearest baseline shape
for ORDERED-DICT-REF."))

;;; Sophie benches. Ops returning new structures start every timed call from
;;; the same prebuilt input and discard the result, measuring one persistent
;;; update from the same base.

(define-bench ordered-dict-make-sequential
  (:category :ordered-dict)
  (:sizes (10 100 1000 10000))
  (:setup (n)
    (cons (loop for key below n collect key)
          (loop for key below n collect (* key 3))))
  (:call (context)
    (loop with result = (ordered-dict)
          for key in (car context)
          for value in (cdr context)
          do (setf result (dict-set result key value))
          finally (return result)))
  (:note "Construction of an N-pair ordered dict from prebuilt key and value
lists with sequential keys 0 to N-1, the AVL order tree's best case with no
rebalancing; no CL equivalent exists, so the numbers are absolute."))

(define-bench ordered-dict-make-random
  (:category :ordered-dict)
  (:sizes (10 100 1000 10000))
  (:setup (n)
    (let ((keys (shuffled-keys n)))
      (cons keys (loop for key across keys collect (* key 3)))))
  (:call (context)
    (loop with result = (ordered-dict)
          for key across (car context)
          for value in (cdr context)
          do (setf result (dict-set result key value))
          finally (return result)))
  (:note "Construction of an N-pair ordered dict from deterministically
shuffled keys, a Fisher-Yates shuffle driven by a 31-bit LCG seeded from N,
exercising AVL rebalancing on the inserts; no CL equivalent exists, so the
numbers are absolute."))

(define-bench ordered-dict-ref
  (:category :ordered-dict)
  (:baseline ht-ref-ordered)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (ranged-ordered-dict 0 n) (floor n 2)))
  (:call (context) (dict-ref (car context) (cdr context)))
  (:note (ordered-dict-note
           "Hit lookup through the ordered dict's key index and AVL-backed
structure against the baseline's plain hash table lookup; CL has no ordered
dictionary, so the baseline measures the unordered CL equivalent of the same
lookup.")))

(define-bench ordered-dict-set
  (:category :ordered-dict)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (ranged-ordered-dict 0 n) (floor n 2)))
  (:call (context) (dict-set (car context) (cdr context) 0))
  (:note "One persistent update of a present key from the same base each
call: an O(log N) path copy in the key index plus one AVL node replacement;
no CL equivalent exists, so the numbers are absolute."))

(define-bench ordered-dict-set-new
  (:category :ordered-dict)
  (:sizes (10 100 1000 10000))
  (:setup (n)
    (cons (ranged-ordered-dict 0 n) (+ (floor n 2) 1/2)))
  (:call (context) (dict-set (car context) (cdr context) 0))
  (:note "One persistent insert of a fresh key from the same base each call:
the probe key N/2+1/2 lands strictly between two present keys, mid-order in
the AVL tree, so the insert copies an O(log N) path in both structures and
may rebalance; no CL equivalent exists, so the numbers are absolute."))

(define-bench ordered-dict-iteration
  (:category :ordered-dict)
  (:sizes (10 100 1000 10000))
  (:setup (n) (ranged-ordered-dict 0 n))
  (:call (context)
    (loop with seq = (dict-keys context)
          with total = 0
          until (seq-emptyp seq)
          do (seq-first seq)
             (incf total)
             (setf seq (seq-rest seq))
          finally (return total)))
  (:note "Full consumption of the lazy key seq of an N-pair ordered dict in
insertion order, the type's selling point. Realization choice: a
SEQ-FIRST/SEQ-REST traversal counting the elements, where each SEQ-EMPTYP
and SEQ-REST forces the next lazy cell and SEQ-FIRST reads the memoized
element, so the whole seq is realized; no CL equivalent exists, so the
numbers are absolute."))

(define-bench ordered-dict-equals
  (:category :ordered-dict)
  (:sizes (10 100 1000 10000))
  (:setup (n)
    (cons (ranged-ordered-dict 0 n) (ranged-ordered-dict 0 n)))
  (:call (context) (equals (car context) (cdr context)))
  (:note "Order-sensitive structural equality on two independently built
equal N-pair ordered dicts, the SL:EQUALS worst case since every entry is
compared in insertion order; no CL equivalent exists, so the numbers are
absolute."))
