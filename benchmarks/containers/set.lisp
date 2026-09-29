;;;; Set benchmarks: the Sophie persistent hash-set surface against plain CL
;;;; list set operations.
;;;;
;;;; Matrix C covers the hash-set protocol. The CL baselines come first
;;;; (category :SET-BASELINE) so every Sophie bench (category :SET) can
;;;; reference its baseline by registration order. CL has no set type, so
;;;; the baselines are plain list operations under the default EQL test, and
;;;; every baseline note records the CL list cost: a membership test is an
;;;; O(N) scan, and the algebra is quadratic in the operand sizes. Every
;;;; comparison bench carries a :TIER fairness label and the shared semantics
;;;; caveat through SET-NOTE: Sophie sets are persistent hash-tries under
;;;; SL:EQUALS through CLOS generic dispatch.
;;;;
;;;; Sizing follows the suite rules: (10 100 1000 10000) for every bench; ECL
;;;; caps sizes at 10000 through the harness host seam. No reader feature
;;;; conditionals appear in this file; host differences live in
;;;; benchmarks/host.lisp.

(in-package #:sophie-lisp.benchmarks)

;;; Input builders. Every builder runs inside :SETUP, outside the timed
;;; region; persistent inputs are rebuilt fresh per rep by the harness.

(defun ranged-list (start count)
  "Return a list of the COUNT fixnums from START to START+COUNT-1."
  (loop for key from start below (+ start count) collect key))

(defun ranged-set (start count)
  "Return a persistent set of the COUNT fixnums from START to START+COUNT-1,
built by looped SET-ADD inserts from the empty set. The loop keeps every call
inside CALL-ARGUMENTS-LIMIT at the largest size, unlike one variadic
SL:HASH-SET call over an APPLY-spread argument list."
  (loop with result = (hash-set)
        for key from start below (+ start count)
        do (setf result (set-add key result))
        finally (return result)))

(defun overlap-lists (n)
  "Return a cons of the two overlapping fixnum lists for the set-algebra
benches: the car holds the HALF fixnums 0 to HALF-1 and the cdr holds the
2*QUARTER fixnums from HALF-QUARTER, for HALF = floor(N/2) and QUARTER =
floor(HALF/2), so the lists overlap in QUARTER elements."
  (let* ((half (max 1 (floor n 2)))
         (quarter (max 1 (floor half 2))))
    (cons (ranged-list 0 half)
          (ranged-list (- half quarter) (* 2 quarter)))))

(defun overlap-sets (n)
  "Return a cons of two persistent sets built from the same ranges as
OVERLAP-LISTS, so the set-algebra benches and their baselines see the same
key layout."
  (let* ((half (max 1 (floor n 2)))
         (quarter (max 1 (floor half 2))))
    (cons (ranged-set 0 half)
          (ranged-set (- half quarter) (* 2 quarter)))))

(defun duplicated-elements (n)
  "Return an N-element list with N/10 distinct fixnum elements for the
deduplication benches, cycling (MOD I DISTINCT) over the element positions."
  (let ((distinct (max 1 (floor n 10))))
    (loop for index below n collect (mod index distinct))))

;;; Shared note text. Every comparison bench pairs the caveat with its own
;;; specifics through SET-NOTE.

(alexandria:define-constant +set-caveat+
  "Sophie: persistent hash-trie set under SL:EQUALS with CLOS generic
dispatch; CL: plain list operations under EQL, O(N) scans and copies."
  :test #'equal
  :documentation "Shared semantics caveat carried by every set comparison
bench.")

(defun set-note (specific)
  "Return the note for one set comparison bench: the shared semantics caveat
followed by the bench's SPECIFIC text."
  (concatenate 'string +set-caveat+ " " specific))

;;; CL baselines. Each builds its list inside :SETUP, outside the timed
;;; region, and measures the plain CL form in :CALL.

(define-bench cl-member
  (:category :set-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (ranged-list 0 n) (floor n 2)))
  (:call (context) (member (cdr context) (car context)))
  (:note "CL MEMBER hit on an N-element fixnum list under the default EQL
test, scanning from the front to the probe at position N/2. CL list
operations are O(N): this baseline is a linear scan."))

(define-bench cl-adjoin
  (:category :set-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (ranged-list 0 n) n))
  (:call (context) (adjoin (cdr context) (car context)))
  (:note "CL ADJOIN of an absent fixnum to an N-element list under the
default EQL test. CL list operations are O(N): every call copies the whole
list."))

(define-bench cl-union
  (:category :set-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (overlap-lists n))
  (:call (context) (union (car context) (cdr context)))
  (:note "CL UNION of two lists of about N/2 fixnums overlapping in about
N/4 elements under the default EQL test. CL list set algebra tests each
element with an O(N) MEMBER scan, quadratic in the operand sizes overall."))

(define-bench cl-intersection
  (:category :set-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (overlap-lists n))
  (:call (context) (intersection (car context) (cdr context)))
  (:note "CL INTERSECTION of two lists of about N/2 fixnums overlapping in
about N/4 elements under the default EQL test. CL list set algebra tests
each element with an O(N) MEMBER scan, quadratic in the operand sizes
overall."))

(define-bench cl-set-difference
  (:category :set-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (overlap-lists n))
  (:call (context) (set-difference (car context) (cdr context)))
  (:note "CL SET-DIFFERENCE of two lists of about N/2 fixnums overlapping in
about N/4 elements under the default EQL test. CL list set algebra tests each
element with an O(N) MEMBER scan, quadratic in the operand sizes overall."))

(define-bench cl-subsetp
  (:category :set-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (ranged-list 0 (floor n 2)) (ranged-list 0 n)))
  (:call (context) (subsetp (car context) (cdr context)))
  (:note "CL SUBSETP of an N/2-element list inside an N-element list under
the default EQL test. CL list operations are O(N): each of the N/2 elements
is a linear MEMBER scan, quadratic overall."))

(define-bench cl-remove-duplicates
  (:category :set-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (duplicated-elements n))
  (:call (context) (remove-duplicates context))
  (:note "CL REMOVE-DUPLICATES on an N-element list with N/10 distinct
fixnums under the default EQL test. CL list operations are O(N): the list
algorithm tests each element against the retained remainder, quadratic
overall."))

;;; Sophie benches. Ops returning new structures start every timed call from
;;; the same prebuilt input and discard the result, measuring one persistent
;;; update from the same base.

(define-bench hash-set-make-n
  (:category :set)
  (:sizes (10 100 1000 10000))
  (:setup (n) (ranged-list 0 n))
  (:call (context)
    (loop with result = (hash-set)
          for key in context
          do (setf result (set-add key result))
          finally (return result)))
  (:note "Construction of an N-element persistent set from N distinct fixnums
by N SET-ADD inserts from the empty set. The inserts are loop-driven rather
than one variadic SL:HASH-SET call, keeping every call inside
CALL-ARGUMENTS-LIMIT at the largest size; no CL baseline exists for
persistent set construction, so the numbers are absolute."))

(define-bench set-member-hit
  (:category :set)
  (:baseline cl-member)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (ranged-set 0 n) (floor n 2)))
  (:call (context) (set-member (cdr context) (car context)))
  (:note (set-note
           "Membership hit on the persistent hash-trie, O(log N) expected,
against the baseline's O(N) list scan to the same middle key.")))

(define-bench set-member-miss
  (:category :set)
  (:baseline cl-member)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (ranged-set 0 n) n))
  (:call (context) (set-member (cdr context) (car context)))
  (:note (set-note
           "Membership miss on the persistent hash-trie; the probe key is
one past the last inserted key. The baseline scans to a middle hit, so a CL
miss, a full O(N) scan of about twice that cost, is understated by the
baseline at equal N.")))

(define-bench set-add
  (:category :set)
  (:baseline cl-adjoin)
  (:tier :persistent-vs-copy)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (ranged-set 0 n) n))
  (:call (context) (set-add (cdr context) (car context)))
  (:note (set-note
           "One persistent insert of an absent key from the same base each
call: an O(log N) trie path copy against the baseline's O(N) whole-list
ADJOIN copy.")))

(define-bench set-remove
  (:category :set)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (ranged-set 0 n) (floor n 2)))
  (:call (context) (set-remove (cdr context) (car context)))
  (:note (set-note
           "One persistent removal of a present key from the same base each
call: an O(log N) trie path copy. CL's nearest shape, REMOVE, copies the
whole O(N) list and has no baseline bench here, so the numbers are
absolute.")))

(define-bench set-union
  (:category :set)
  (:baseline cl-union)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (overlap-sets n))
  (:call (context) (set-union (car context) (cdr context)))
  (:note (set-note
           "Union of two persistent sets of about N/2 elements overlapping in
about N/4, rebuilding the result trie insert by insert under SL:EQUALS. The
implementation materializes (re-copies) each persistent operand into a
fresh trie before the algebra runs, adding O(N) per operand to every call;
that copy is real Sophie cost, correctly measured.")))

(define-bench set-intersection
  (:category :set)
  (:baseline cl-intersection)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (overlap-sets n))
  (:call (context) (set-intersection (car context) (cdr context)))
  (:note (set-note
           "Intersection of two persistent sets of about N/2 elements
overlapping in about N/4; every element of the first operand is a trie
membership test against the second. The implementation materializes
(re-copies) each persistent operand into a fresh trie before the algebra
runs, adding O(N) per operand to every call; that copy is real Sophie
cost, correctly measured.")))

(define-bench set-minus
  (:category :set)
  (:baseline cl-set-difference)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (overlap-sets n))
  (:call (context) (set-minus (car context) (cdr context)))
  (:note (set-note
           "Difference of two persistent sets of about N/2 elements
overlapping in about N/4; the excluded elements are unioned first, then
every kept element is a trie membership test against that union. The
implementation materializes (re-copies) each persistent operand into a
fresh trie before the algebra runs, adding O(N) per operand to every call;
that copy is real Sophie cost, correctly measured.")))

(define-bench set-subset-p
  (:category :set)
  (:baseline cl-subsetp)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (ranged-set 0 (floor n 2)) (ranged-set 0 n)))
  (:call (context) (set-subset-p (car context) (cdr context)))
  (:note (set-note
           "Subset test of an N/2-element persistent set inside an N-element
one; each element is an O(log N) trie lookup against the baseline's O(N)
list scans. The implementation materializes (re-copies) each persistent
operand into a fresh trie before the algebra runs, adding O(N) per operand
to every call; that copy is real Sophie cost, correctly measured.")))

(define-bench set-size
  (:category :set)
  (:baseline cl-remove-duplicates)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (duplicated-elements n))
  (:call (context) (set-size context))
  (:note (set-note
           "SET-SIZE eagerly materializes its sequence into a trie and
returns the count of DISTINCT elements under SL:EQUALS, not the list
length; the baseline returns the distinct elements as a fresh list, so the
shared measured work is deduplicating the same N-element input with N/10
distinct elements.")))
