;;;; Generic seq-operation benchmarks: the Sophie seq layer against plain CL
;;;; sequence functions, plus dispatch-over-container costs.
;;;;
;;;; Matrix F covers the generic seq-operation layer. The CL baselines come
;;;; first (category :SEQ-BASELINE) so every Sophie bench (category :SEQ) can
;;;; reference its baseline by registration order. Each baseline measures the
;;;; plain CL form on the same source type and data as the Sophie bench it
;;;; pairs with, and every comparison bench carries a :TIER fairness label and
;;;; the shared semantics caveat through SEQ-NOTE: Sophie ops go through CLOS
;;;; generic dispatch, the reconstruction policy, and structural equality
;;;; defaults, while the CL forms are direct, type-specific calls.
;;;;
;;;; Sizing follows the suite rules: (10 100 1000 10000) for every bench except
;;;; the SEQABLEP gateway benches, which measure one dispatch and run at size
;;;; 1; ECL caps sizes at 10000 through the harness host seam. No reader
;;;; feature conditionals appear in this file; host differences live in
;;;; benchmarks/host.lisp.

(in-package #:sophie-lisp.benchmarks)

;;; Input builders. Every builder runs inside :SETUP, outside the timed
;;; region; inputs are immutable from the timed calls' perspective, so the
;;; harness rebuilds them fresh per rep.

(defun generic-ranged-list (start count)
  "Return a list of the COUNT fixnums from START to START+COUNT-1."
  (loop for key from start below (+ start count) collect key))

(defun generic-ranged-vector (start count)
  "Return a vector of the COUNT fixnums from START to START+COUNT-1."
  (coerce (generic-ranged-list start count) 'vector))

(defun generic-lcg-next (state)
  "Return the next state of the 31-bit linear congruential generator
X = 1103515245*X + 12345 mod 2^31 from STATE."
  (mod (+ (* 1103515245 state) 12345) 2147483648))

(defun generic-shuffled-vector (n)
  "Return a vector of the fixnums 0 to N-1 in a deterministically shuffled
order: a Fisher-Yates shuffle driven by GENERIC-LCG-NEXT from the seed N,
drawing each swap index from the generator's upper bits, so the same size
always produces the same element order without host RANDOM."
  (let ((keys (generic-ranged-vector 0 n))
        (state (max 1 n)))
    (loop for index from (- n 1) downto 1
          do (setf state (generic-lcg-next state))
             (rotatef (aref keys index)
                      (aref keys (mod (ash state -16) index)))
          finally (return keys))))

(defun generic-duplicated-elements (n)
  "Return an N-element list with N/10 distinct fixnum elements for the
deduplication benches, cycling (MOD I DISTINCT) over the element positions."
  (let ((distinct (max 1 (floor n 10))))
    (loop for index below n collect (mod index distinct))))

(defun generic-half-lists (n)
  "Return a cons of the two N/2-element fixnum lists for the concatenation
benches: the car holds 0 to HALF-1 and the cdr holds HALF to 2*HALF-1, for
HALF = floor(N/2), so the concatenation rebuilds the N-element range."
  (let ((half (max 1 (floor n 2))))
    (cons (generic-ranged-list 0 half)
          (generic-ranged-list half half))))

(defun generic-ranged-dict (start count)
  "Return a COUNT-pair persistent dict with fixnum keys START to
START+COUNT-1, each mapped to its triple."
  (loop with result = (dict)
        for key from start below (+ start count)
        do (setf result (dict-set result key (* key 3)))
        finally (return result)))

(defun generic-ranged-hash-set (start count)
  "Return a persistent set of the COUNT fixnums from START to START+COUNT-1,
built by looped SET-ADD inserts from the empty set."
  (loop with result = (hash-set)
        for key from start below (+ start count)
        do (setf result (set-add key result))
        finally (return result)))

(defun generic-ranged-ordered-dict (start count)
  "Return a COUNT-pair ordered dict with fixnum keys START to START+COUNT-1,
each mapped to its triple, inserted in ascending key order."
  (loop with result = (ordered-dict)
        for key from start below (+ start count)
        do (setf result (dict-set result key (* key 3)))
        finally (return result)))

(defun generic-forced-lazy (n)
  "Return a fully forced lazy sequence of the fixnums 0 to N-1: RANGE builds
the deferred nodes and one SEQ-LENGTH pass forces and memoizes every node, so
timed calls walk value-state nodes only."
  (let ((lazy (range :end n)))
    (seq-length lazy)
    lazy))

;;; Shared note text. Every comparison bench pairs the caveat with its own
;;; specifics through SEQ-NOTE.

(alexandria:define-constant +seq-caveat+
  "Sophie: CLOS generic dispatch + reconstruction policy + structural
equality defaults; CL: direct call, type-specific."
  :test #'equal
  :documentation "Shared semantics caveat carried by every seq comparison
bench.")

(defun seq-note (specific)
  "Return the note for one seq comparison bench: the shared semantics caveat
followed by the bench's SPECIFIC text."
  (concatenate 'string +seq-caveat+ " " specific))

;;; CL baselines. Each builds its input inside :SETUP, outside the timed
;;; region, and measures the plain CL form on the same source type and data as
;;; the Sophie bench it pairs with.

(define-bench cl-elt
  (:category :seq-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (generic-ranged-vector 0 n) (floor n 2)))
  (:call (context) (elt (car context) (cdr context)))
  (:note "CL ELT at position N/2 of an N-element fixnum vector: a direct,
type-specific constant-time access."))

(define-bench cl-car
  (:category :seq-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (generic-ranged-list 0 n))
  (:call (context) (car context))
  (:note "CL CAR on an N-element list: a direct, type-specific constant-time
access."))

(define-bench cl-length
  (:category :seq-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (generic-ranged-list 0 n))
  (:call (context) (length context))
  (:note "CL LENGTH on an N-element list: a direct, type-specific O(N)
count."))

(define-bench cl-map
  (:category :seq-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (generic-ranged-list 0 n))
  (:call (context) (map 'list #'1+ context))
  (:note "CL MAP 'LIST of #'1+ over an N-element list, allocating a fresh
N-element result list."))

(define-bench cl-remove-if-not
  (:category :seq-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (generic-ranged-list 0 n))
  (:call (context) (remove-if-not #'evenp context))
  (:note "CL REMOVE-IF-NOT of #'EVENP over an N-element list, allocating a
fresh result list of about N/2 elements."))

(define-bench cl-reduce
  (:category :seq-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (generic-ranged-list 0 n))
  (:call (context) (reduce #'+ context))
  (:note "CL REDUCE of #'+ over an N-element fixnum list with no initial
value."))

(define-bench cl-find
  (:category :seq-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (generic-ranged-list 0 n) (floor n 2)))
  (:call (context) (find (cdr context) (car context)))
  (:note "CL FIND of the middle fixnum in an N-element list under the default
EQL test, scanning from the front to the hit at position N/2."))

(define-bench cl-position
  (:category :seq-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (generic-ranged-list 0 n) (floor n 2)))
  (:call (context) (position (cdr context) (car context)))
  (:note "CL POSITION of the middle fixnum in an N-element list under the
default EQL test, scanning from the front to the hit at position N/2."))

(define-bench cl-count
  (:category :seq-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (generic-ranged-list 0 n) (floor n 2)))
  (:call (context) (count (cdr context) (car context)))
  (:note "CL COUNT of the middle fixnum over an N-element list under the
default EQL test; the item occurs exactly once, so the call scans the full
list."))

(define-bench cl-substitute
  (:category :seq-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (generic-ranged-list 0 n) (floor n 2)))
  (:call (context) (substitute 0 (cdr context) (car context)))
  (:note "CL SUBSTITUTE replacing the middle fixnum with 0 over an N-element
list under the default EQL test, allocating a fresh result list."))

(define-bench cl-remove
  (:category :seq-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (generic-ranged-list 0 n) (floor n 2)))
  (:call (context) (remove (cdr context) (car context)))
  (:note "CL REMOVE of the middle fixnum from an N-element list under the
default EQL test, allocating a fresh result list."))

(define-bench cl-remove-duplicates-list
  (:category :seq-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (generic-duplicated-elements n))
  (:call (context) (remove-duplicates context))
  (:note "CL REMOVE-DUPLICATES on an N-element list with N/10 distinct fixnums
under the default EQL test. The list algorithm tests each element against the
retained remainder, quadratic overall. The size-10000 point is the dominant
runtime cost of the seq matrix (tens of seconds per host) and is retained
deliberately to expose the quadratic CL baseline at scale."))

(define-bench cl-sort
  (:category :seq-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (generic-shuffled-vector n))
  (:call (context) (sort context #'<))
  (:note "CL SORT of an N-element fixnum vector with #'<, destructive on its
argument. SETUP builds one fresh shuffled copy per rep; call 1 sorts shuffled
data and calls 2..K re-sort the already-sorted vector, CL's best case, so the
baseline understates CL's average sort cost at equal N."))

(define-bench cl-sort-copy
  (:category :seq-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (generic-shuffled-vector n))
  (:call (context) (sort (copy-seq context) #'<))
  (:note "CL SORT on a fresh copy of the N-element deterministically shuffled
fixnum vector on every timed call: COPY-SEQ plus destructive SORT produces a
fresh sorted vector without changing the setup input, matching SEQ-SORT's
fresh result and unsorted input distribution each invocation."))

(define-bench cl-stable-sort-copy
  (:category :seq-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (generic-shuffled-vector n))
  (:call (context) (stable-sort (copy-seq context) #'<))
  (:note "CL STABLE-SORT on a fresh copy of the N-element deterministically
shuffled fixnum vector on every timed call: COPY-SEQ plus destructive
STABLE-SORT produces a fresh stable sorted vector without changing the setup
input, matching SEQ-STABLE-SORT's fresh result and unsorted input distribution
with the same stability guarantee."))

(define-bench cl-subseq
  (:category :seq-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (generic-ranged-vector 0 n) n))
  (:call (context) (subseq (car context) 2 (- (cdr context) 2)))
  (:note "CL SUBSEQ of an N-element fixnum vector from position 2 to N-2,
allocating a fresh result vector."))

(define-bench cl-concatenate
  (:category :seq-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (generic-half-lists n))
  (:call (context) (concatenate 'list (car context) (cdr context)))
  (:note "CL CONCATENATE of two lists of about N/2 fixnums into one fresh
N-element list."))

(define-bench cl-reverse
  (:category :seq-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (generic-ranged-list 0 n))
  (:call (context) (reverse context))
  (:note "CL REVERSE of an N-element list, allocating a fresh result
list."))

(define-bench cl-every
  (:category :seq-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (generic-ranged-list 0 n))
  (:call (context) (every #'integerp context))
  (:note "CL EVERY of #'INTEGERP over an N-element all-fixnum list; the
predicate holds everywhere, so the call scans the full list."))

(define-bench cl-find-keyword-full
  (:category :seq-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (generic-ranged-list 0 n) n))
  (:call (context)
    (find 5 (car context) :test #'eql :key #'identity
          :start 1 :end (- (cdr context) 1)))
  (:note "CL FIND with the full keyword option set (:TEST #'EQL, :KEY
#'IDENTITY, :START 1, :END N-1) over an N-element list, hitting the fixnum 5;
the keyword-processing counterpart of CL-FIND."))

;;; Sophie benches, dispatch tier: pure dispatch overhead over minimal work,
;;; against the direct CL form.

(define-bench seq-ref-vector
  (:category :seq)
  (:baseline cl-elt)
  (:tier :dispatch)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (generic-ranged-vector 0 n) (floor n 2)))
  (:call (context) (seq-ref (car context) (cdr context)))
  (:note (seq-note
           "SEQ-REF at position N/2 of an N-element vector against the
baseline's direct ELT: one CLOS generic dispatch plus index normalization and
the found/absent second value, constant work per call.")))

(define-bench seq-first-list
  (:category :seq)
  (:baseline cl-car)
  (:tier :dispatch)
  (:sizes (10 100 1000 10000))
  (:setup (n) (generic-ranged-list 0 n))
  (:call (context) (seq-first context))
  (:note (seq-note
           "SEQ-FIRST on an N-element list against the baseline's direct CAR:
one CLOS generic dispatch over constant work.")))

(define-bench seq-length-list
  (:category :seq)
  (:baseline cl-length)
  (:tier :dispatch)
  (:sizes (10 100 1000 10000))
  (:setup (n) (generic-ranged-list 0 n))
  (:call (context) (seq-length context))
  (:note (seq-note
           "SEQ-LENGTH on an N-element list against the baseline's direct
LENGTH: one CLOS generic dispatch over the same O(N) count; the list method
uses the cycle-safe CL:LIST-LENGTH rather than LENGTH.")))

(define-bench seq-find-keyword-full
  (:category :seq)
  (:baseline cl-find-keyword-full)
  (:tier :dispatch)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (generic-ranged-list 0 n) n))
  (:call (context)
    (seq-find 5 (car context) :test #'eql :key #'identity
              :start 1 :end (- (cdr context) 1)))
  (:note (seq-note
           "SEQ-FIND with the full keyword option set against the same-shape
CL FIND: keyword processing in the generic dispatch has a distinct cost, so
the tier is :DISPATCH; the shared measured work is the same scan to the
fixnum 5.")))

;;; Sophie SEQABLEP gateway benches: the dispatch test every seq operation
;;; pays before any traversal, one CLOS generic call per timed call. No CL
;;; equivalent exists, so the numbers are absolute; the size is 1 because the
;;; call is constant work.

(define-bench seqablep-gateway
  (:category :seq)
  (:tier :dispatch)
  (:sizes (1))
  (:setup (n) (generic-ranged-list 0 n))
  (:call (context) (seqablep context))
  (:note "SEQABLEP on a list: the dispatch gateway every seq op pays, absolute
with no CL baseline; one CLOS generic dispatch returning T."))

(define-bench seqablep-gateway-vector
  (:category :seq)
  (:tier :dispatch)
  (:sizes (1))
  (:setup (n) (generic-ranged-vector 0 n))
  (:call (context) (seqablep context))
  (:note "SEQABLEP on a vector: the dispatch gateway every seq op pays,
absolute with no CL baseline; one CLOS generic dispatch returning T."))

(define-bench seqablep-gateway-dict
  (:category :seq)
  (:tier :dispatch)
  (:sizes (1))
  (:setup (n) (generic-ranged-dict 0 n))
  (:call (context) (seqablep context))
  (:note "SEQABLEP on a persistent dict: the dispatch gateway every seq op
pays, absolute with no CL baseline; one CLOS generic dispatch returning T
through the dict method."))

(define-bench seqablep-gateway-hash-set
  (:category :seq)
  (:tier :dispatch)
  (:sizes (1))
  (:setup (n) (generic-ranged-hash-set 0 n))
  (:call (context) (seqablep context))
  (:note "SEQABLEP on a persistent hash-set: the dispatch gateway every seq op
pays, absolute with no CL baseline; one CLOS generic dispatch returning T
through the hash-set method."))

(define-bench seqablep-gateway-lazy-seq
  (:category :seq)
  (:tier :dispatch)
  (:sizes (1))
  (:setup (n) (generic-forced-lazy n))
  (:call (context) (seqablep context))
  (:note "SEQABLEP on a lazy sequence: the dispatch gateway every seq op pays,
absolute with no CL baseline; one CLOS generic dispatch returning T through
the lazy-seq method."))

;;; Sophie benches, same-op tier: representative seq operations on lists (and
;;; vectors where the CL op is vector-shaped) against the matching CL form on
;;; the same data.

(define-bench seq-map-list
  (:category :seq)
  (:baseline cl-map)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (generic-ranged-list 0 n))
  (:call (context) (seq-map #'1+ context))
  (:note (seq-note
           "SEQ-MAP of #'1+ over an N-element list against the baseline's CL
MAP 'LIST: the generic dispatch, view-based traversal, and list reconstruction
produce the same fresh N-element result list shape.")))

(define-bench seq-filter-list
  (:category :seq)
  (:baseline cl-remove-if-not)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (generic-ranged-list 0 n))
  (:call (context) (seq-filter #'evenp context))
  (:note (seq-note
           "SEQ-FILTER of #'EVENP over an N-element list against CL
REMOVE-IF-NOT, the same-op shape: both allocate a fresh result list of about
N/2 elements.")))

(define-bench seq-reduce-list
  (:category :seq)
  (:baseline cl-reduce)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (generic-ranged-list 0 n))
  (:call (context) (seq-reduce #'+ context))
  (:note (seq-note
           "SEQ-REDUCE of #'+ over an N-element list against CL REDUCE: the
generic layer materializes the elements into a list first and then reduces it,
so the measured work is the traversal plus a list-backed reduction.")))

(define-bench seq-find-list
  (:category :seq)
  (:baseline cl-find)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (generic-ranged-list 0 n) (floor n 2)))
  (:call (context) (seq-find (cdr context) (car context)))
  (:note (seq-note
           "SEQ-FIND of the middle fixnum in an N-element list under the
default structural SL:EQUALS test against the baseline's EQL scan to the same
hit at position N/2.")))

(define-bench seq-position-list
  (:category :seq)
  (:baseline cl-position)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (generic-ranged-list 0 n) (floor n 2)))
  (:call (context) (seq-position (cdr context) (car context)))
  (:note (seq-note
           "SEQ-POSITION of the middle fixnum in an N-element list under the
default structural SL:EQUALS test against the baseline's EQL scan to the same
hit at position N/2.")))

(define-bench seq-count-list
  (:category :seq)
  (:baseline cl-count)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (generic-ranged-list 0 n) (floor n 2)))
  (:call (context) (seq-count (cdr context) (car context)))
  (:note (seq-note
           "SEQ-COUNT of the middle fixnum over an N-element list under the
default structural SL:EQUALS test; the item occurs exactly once, so both sides
scan the full list, as the baseline does under EQL.")))

(define-bench seq-substitute-list
  (:category :seq)
  (:baseline cl-substitute)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (generic-ranged-list 0 n) (floor n 2)))
  (:call (context) (seq-substitute 0 (cdr context) (car context)))
  (:note (seq-note
           "SEQ-SUBSTITUTE replacing the middle fixnum with 0 over an
N-element list under the default structural SL:EQUALS test, allocating a
fresh result list like the baseline's EQL SUBSTITUTE.")))

(define-bench seq-remove-list
  (:category :seq)
  (:baseline cl-remove)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (generic-ranged-list 0 n) (floor n 2)))
  (:call (context) (seq-remove (cdr context) (car context)))
  (:note (seq-note
           "SEQ-REMOVE of the middle fixnum from an N-element list under the
default structural SL:EQUALS test, allocating a fresh result list like the
baseline's EQL REMOVE.")))

(define-bench seq-remove-duplicates-list
  (:category :seq)
  (:baseline cl-remove-duplicates-list)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (generic-duplicated-elements n))
  (:call (context) (seq-remove-duplicates context))
  (:note (seq-note
           "SEQ-REMOVE-DUPLICATES on an N-element list with N/10 distinct
fixnums under the default structural SL:EQUALS test; the baseline deduplicates
the same input under EQL, quadratic overall. The size-10000 point is the
dominant runtime cost of the seq matrix (tens of seconds per host) and is
retained deliberately to expose the quadratic CL baseline at scale.")))

(define-bench seq-sort
  (:category :seq)
  (:baseline cl-sort)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (generic-shuffled-vector n))
  (:call (context) (seq-sort context))
  (:note (seq-note
           "SEQ-SORT of an N-element fixnum vector: Sophie returns a sorted
copy (non-destructive) under the default structural compare test #'SL:LT
through CLOS, so every timed call sorts the same shuffled input afresh. CL
SORT is destructive on its argument; the baseline sorts an already-sorted
vector from call 2 on, CL's best case, disclosed there.")))

(define-bench seq-stable-sort
  (:category :seq)
  (:baseline cl-sort)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (generic-shuffled-vector n))
  (:call (context) (seq-stable-sort context))
  (:note (seq-note
           "SEQ-STABLE-SORT of an N-element fixnum vector: the stability-
guaranteed sorted copy, sharing SEQ-SORT's bottom-up merge sort, paired with
the same CL SORT baseline, which is not required to be stable and, being
destructive, sorts an already-sorted vector from call 2 on, CL's best case,
disclosed there.")))

(define-bench seq-sort-copy-control
  (:category :seq)
  (:baseline cl-sort-copy)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (generic-shuffled-vector n))
  (:call (context) (seq-sort context))
  (:note (seq-note
           "SEQ-SORT on the same deterministically shuffled N-element fixnum
vector as CL-SORT-COPY: each invocation returns a fresh sorted vector from an
unsorted input. The CL control includes COPY-SEQ and SORT in the timed call;
Sophie uses its default structural comparison through CLOS.")))

(define-bench seq-stable-sort-copy-control
  (:category :seq)
  (:baseline cl-stable-sort-copy)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (generic-shuffled-vector n))
  (:call (context) (seq-stable-sort context))
  (:note (seq-note
           "SEQ-STABLE-SORT on the same deterministically shuffled N-element
fixnum vector as CL-STABLE-SORT-COPY: each invocation returns a fresh stable
sorted vector from an unsorted input. The CL control includes COPY-SEQ and
STABLE-SORT in the timed call; Sophie compares through CLOS.")))

(define-bench seq-subseq-vector
  (:category :seq)
  (:baseline cl-subseq)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (generic-ranged-vector 0 n) n))
  (:call (context) (seq-subseq (car context) 2 (- (cdr context) 2)))
  (:note (seq-note
           "SEQ-SUBSEQ of an N-element vector from position 2 to N-2 against
the baseline's CL SUBSEQ: the generic dispatch and vector reconstruction
allocate the same fresh result vector shape.")))

(define-bench seq-concatenate
  (:category :seq)
  (:baseline cl-concatenate)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (generic-half-lists n))
  (:call (context) (seq-concatenate (car context) (cdr context)))
  (:note (seq-note
           "SEQ-CONCATENATE of two lists of about N/2 fixnums against the
baseline's CL CONCATENATE 'LIST: the generic dispatch and list reconstruction
allocate the same fresh N-element result list.")))

(define-bench seq-reverse-list
  (:category :seq)
  (:baseline cl-reverse)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (generic-ranged-list 0 n))
  (:call (context) (seq-reverse context))
  (:note (seq-note
           "SEQ-REVERSE of an N-element list against the baseline's CL
REVERSE: the generic layer materializes the elements and reconstructs the
reversed list, allocating the same fresh result shape.")))

(define-bench seq-every-list
  (:category :seq)
  (:baseline cl-every)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (generic-ranged-list 0 n))
  (:call (context) (seq-every #'integerp context))
  (:note (seq-note
           "SEQ-EVERY of #'INTEGERP over an N-element all-fixnum list against
the baseline's CL EVERY; the predicate holds everywhere, so both sides scan
the full list.")))

;;; Sophie dispatch-over-container benches: the generic layer over Sophie
;;; containers. No CL equivalent exists, so the numbers are absolute and every
;;; note says so.

(define-bench seq-map-over-lazy
  (:category :seq)
  (:sizes (10 100 1000 10000))
  (:setup (n) (generic-forced-lazy n))
  (:call (context) (seq-map #'1+ context))
  (:note "SEQ-MAP of #'1+ over a pre-forced N-element lazy sequence; no CL
equivalent exists, so the numbers are absolute. SEQ-MAP over a lazy source
returns a lazy result: the timed call constructs the deferred result node
without forcing it, so the measured work is the dispatch and lazy-node
construction, not the full mapping, and the number is expected to be flat in
N."))

(define-bench seq-filter-over-dict-keys
  (:category :seq)
  (:sizes (10 100 1000 10000))
  (:setup (n) (generic-ranged-dict 0 n))
  (:call (context) (seq-filter #'evenp (dict-keys context)))
  (:note "SEQ-FILTER of #'EVENP over the lazy key sequence of an N-pair
persistent dict; no CL equivalent exists, so the numbers are absolute.
DICT-KEYS is lazy and SEQ-FILTER over a lazy source returns a lazy result, so
the timed call constructs the deferred result without forcing it; the
measured work is the dispatch and lazy-node construction, not the full
filter, and the number is expected to be flat in N."))

(define-bench seq-length-on-dict
  (:category :seq)
  (:sizes (10 100 1000 10000))
  (:setup (n) (generic-ranged-dict 0 n))
  (:call (context) (seq-length context))
  (:note "SEQ-LENGTH on an N-pair persistent dict; no CL equivalent exists, so
the numbers are absolute. The method dispatches to DICT-SIZE, an O(1) count
read, so the number is the dispatch plus a constant-time count."))

(define-bench seq-length-on-set
  (:category :seq)
  (:sizes (10 100 1000 10000))
  (:setup (n) (generic-ranged-hash-set 0 n))
  (:call (context) (seq-length context))
  (:note "SEQ-LENGTH on an N-element persistent hash-set; no CL equivalent
exists, so the numbers are absolute. The method dispatches to the set's
O(1) count, so the number is the dispatch plus a constant-time count."))

(define-bench seq-reduce-over-ordered-dict
  (:category :seq)
  (:sizes (10 100 1000 10000))
  (:setup (n) (generic-ranged-ordered-dict 0 n))
  (:call (context)
    (seq-reduce #'+ context :key #'entry-key :initial-value 0))
  (:note "SEQ-REDUCE of #'+ over an N-pair ordered dict with :KEY
#'ENTRY-KEY and :INITIAL-VALUE 0; the generic lambda list is (FUNCTION SOURCE
&KEY ...), and the traversal yields SL:MAP-ENTRY objects, so the key extracts
each entry's fixnum key before the addition. No CL equivalent exists, so the
numbers are absolute."))

(define-bench seq-ref-on-lazy
  (:category :seq)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (generic-forced-lazy n) (floor n 2)))
  (:call (context) (seq-ref (car context) (cdr context)))
  (:note "SEQ-REF at position N/2 of a pre-forced N-element lazy sequence; the
positional fallback walks the memoized lazy nodes one by one to the index. No
CL equivalent exists, so the numbers are absolute."))

;;; Round B traversal matrix. Each source is rebuilt in SETUP; lazy cold pools
;;; are single-use. The -b suffix distinguishes these round-B measurements
;;; from the committed baseline names; only *_CONSTRUCT benches omit consumption.

(defun traversal-list (n)
  (loop for i below n collect i))

(defun traversal-vector (n)
  (coerce (traversal-list n) 'vector))

(defun traversal-sum-pieces (outer &optional (limit nil))
  "Force each selected outer cell and every element of its piece."
  (loop with cursor = outer
        with total = 0
        with count = 0
        until (or (and limit (>= count limit)) (seq-emptyp cursor))
        do (incf total (realize-seq (seq-first cursor)))
           (incf count)
           (setf cursor (seq-rest cursor))
        finally (return total)))

(defun traversal-inner-list (x)
  (list x (1+ x)))

(defun traversal-inner-vector (x)
  (vector x (1+ x)))

(defun traversal-inner-lazy (x)
  (range :start x :end (+ x 2)))

(defun traversal-empty-inner (x)
  (declare (ignore x))
  nil)

(defun traversal-run-mapcat (function source)
  "Realize all output cells of a MAPCAT result."
  (realize-seq (seq-mapcat function source)))

(defun traversal-run-split-at (n source)
  "Consume both pieces of the split-at result."
  (traversal-sum-pieces (seq-split-at (floor n 2) source)))

(defun traversal-run-split-with (n source)
  "Consume both pieces of the split-with result."
  (traversal-sum-pieces (seq-split-with (lambda (x) (< x (floor n 2))) source)))

;;; Same-work CL controls are registered ahead of their Sophie comparisons.
(define-bench cl-member-first-b
  (:category :seq-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (traversal-list n))
  (:call (source) (member 0 source))
  (:note "CL MEMBER first fixnum; returns original list tail, not a deferred view."))

(define-bench cl-member-late-b
  (:category :seq-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (traversal-list n) (1- n)))
  (:call (context) (member (cdr context) (car context)))
  (:note "CL MEMBER last fixnum on a list; returns original list tail."))

(define-bench cl-member-missing-b
  (:category :seq-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (traversal-list n) n))
  (:call (context) (member (cdr context) (car context)))
  (:note "CL MEMBER absent fixnum on a list; scans all N cells."))

(define-bench seq-member-first-search-b
  (:category :seq-traversal)
  (:baseline cl-member-first-b)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (traversal-list n))
  (:call (source) (seq-member 0 source))
  (:note (seq-note "Search only: first match on list, deferred returned tail NOT consumed;
Sophie structural equality and view allocation differ from CL MEMBER.")))

(define-bench seq-member-late-search-b
  (:category :seq-traversal)
  (:baseline cl-member-late-b)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (traversal-list n) (1- n)))
  (:call (context) (seq-member (cdr context) (car context)))
  (:note (seq-note "Search only: last match on list; returned tail NOT consumed; Sophie
structural equality and view allocation differ from CL MEMBER.")))

(define-bench seq-member-missing-search-b
  (:category :seq-traversal)
  (:baseline cl-member-missing-b)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (traversal-list n) n))
  (:call (context) (seq-member (cdr context) (car context)))
  (:note (seq-note "Search only: missing match on list; full scan, NIL returned; Sophie
structural equality differs from CL MEMBER.")))

(define-bench seq-member-first-tail-realize-b
  (:category :seq-traversal)
  (:sizes (10 100 1000 10000))
  (:setup (n) (traversal-list n))
  (:call (source) (realize-seq (seq-member 0 source)))
  (:note "Search AND consume returned tail: first match, traverses N returned
elements; absolute because CL MEMBER returns existing tail."))

(define-bench seq-member-late-tail-realize-b
  (:category :seq-traversal)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (traversal-list n) (1- n)))
  (:call (context) (realize-seq (seq-member (cdr context) (car context))))
  (:note "Search AND consume returned tail: last match, one tail element; absolute."))

(define-bench seq-member-warm-lazy-missing-b
  (:category :seq-traversal)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (pre-forced-range n) n))
  (:call (context) (seq-member (cdr context) (car context)))
  (:note "WARM lazy source: missing search traverses memoized N cells; absolute."))

(define-bench seq-member-cold-lazy-missing-b
  (:category :seq-traversal)
  (:sizes (10 100 1000 10000))
  (:cold-pool-size 4)
  (:setup (n) (fresh-pool 4 (lambda () (cons (range :end n) n))))
  (:call (context) (seq-member (cdr context) (car context)))
  (:note "COLD lazy source: missing search forces each cell once; four fresh inputs
per batch; absolute."))

(define-bench cl-mapcan-fixed-list-b
  (:category :seq-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (traversal-list n))
  (:call (source) (mapcan #'traversal-inner-list source))
  (:note "CL MAPCAN producing 2N list cells from N list elements; destructive
concatenation only of freshly allocated callback lists."))

(define-bench seq-mapcat-list-fixed-realize-b
  (:category :seq-traversal)
  (:baseline cl-mapcan-fixed-list-b)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (traversal-list n))
  (:call (source) (traversal-run-mapcat #'traversal-inner-list source))
  (:note (seq-note "N list callbacks each produce a fresh two-element list; full 2N-element
result consumption; CL MAPCAN omits Sophie's reconstruction and traversal of
result.")))

(define-bench seq-mapcat-list-empty-realize-b
  (:category :seq-traversal)
  (:sizes (10 100 1000 10000))
  (:setup (n) (traversal-list n))
  (:call (source) (traversal-run-mapcat #'traversal-empty-inner source))
  (:note "N callbacks produce empty lists; consumes empty result and tests source
exhaustion; absolute."))

(define-bench seq-mapcat-vector-fixed-realize-b
  (:category :seq-traversal)
  (:sizes (10 100 1000 10000))
  (:setup (n) (traversal-vector n))
  (:call (source) (traversal-run-mapcat #'traversal-inner-vector source))
  (:note "N callbacks produce two-element vectors; full 2N-element result consumption;
absolute."))

(define-bench seq-mapcat-warm-lazy-inner-realize-b
  (:category :seq-traversal)
  (:sizes (10 100 1000 10000))
  (:setup (n) (pre-forced-range n))
  (:call (source) (traversal-run-mapcat #'traversal-inner-lazy source))
  (:note "WARM lazy outer; N cold two-element lazy inner ranges per call, fully
realized (2N results); absolute."))

(define-bench seq-mapcat-cold-lazy-inner-realize-b
  (:category :seq-traversal)
  (:sizes (10 100 1000 10000))
  (:cold-pool-size 4)
  (:setup (n) (fresh-pool 4 (lambda () (range :end n))))
  (:call (source) (traversal-run-mapcat #'traversal-inner-lazy source))
  (:note "COLD lazy outer and N cold two-element lazy inners; full 2N realization;
four fresh inputs per batch; absolute."))

(define-bench seq-mapcat-warm-lazy-construct-b
  (:category :seq-traversal)
  (:sizes (10 100 1000 10000))
  (:setup (n) (pre-forced-range n))
  (:call (source) (seq-mapcat #'traversal-inner-lazy source))
  (:note "CONSTRUCTION ONLY over warm lazy outer: no callback and no inner or output
cell forced; absolute."))

;;; Pattern length 2 in ordinary search, 4 in bounded/from-end cases.
(define-bench cl-search-late-b
  (:category :seq-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (list (- n 2) (1- n)) (traversal-vector n)))
  (:call (context) (search (car context) (cdr context)))
  (:note "CL SEARCH two-element late pattern in N-element vector."))

(define-bench seq-search-early-b
  (:category :seq-traversal)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons '(0 1) (traversal-vector n)))
  (:call (context) (seq-search (car context) (cdr context)))
  (:note "Two-element early match on vector; absolute (no separate early CL control)."))

(define-bench seq-search-late-b
  (:category :seq-traversal)
  (:baseline cl-search-late-b)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (list (- n 2) (1- n)) (traversal-vector n)))
  (:call (context) (seq-search (car context) (cdr context)))
  (:note (seq-note "Two-element late match on vector; Sophie structural test and view traversal
versus direct CL SEARCH.")))

(define-bench seq-search-missing-b
  (:category :seq-traversal)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons '(999999 999998) (traversal-list n)))
  (:call (context) (seq-search (car context) (cdr context)))
  (:note "Two-element missing pattern on list; full scan; absolute."))

(define-bench seq-search-bounded-from-end-b
  (:category :seq-traversal)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (list (floor n 2) (1+ (floor n 2))
                           (+ 2 (floor n 2)) (+ 3 (floor n 2)))
                     (traversal-vector n)))
  (:call (context)
    (seq-search (car context) (cdr context) :start2 1 :end2 (1- (length
    (cdr context))) :from-end t))
  (:note "Four-element match in bounded vector region; :FROM-END scans full selected
region; absolute."))

(define-bench cl-mismatch-early-b
  (:category :seq-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (traversal-list n) (cons -1 (cdr (traversal-list n)))))
  (:call (context) (mismatch (car context) (cdr context)))
  (:note "CL First-element mismatch on equal-length lists."))

(define-bench seq-mismatch-early-b
  (:category :seq-traversal)
  (:baseline cl-mismatch-early-b)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (traversal-list n) (cons -1 (cdr (traversal-list n)))))
  (:call (context) (seq-mismatch (car context) (cdr context)))
  (:note (seq-note "First-element mismatch on equal-length lists; compared with direct CL call.")))

(define-bench seq-mismatch-late-b
  (:category :seq-traversal)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (traversal-vector n) (concatenate 'vector (traversal-vector (1- n))
    (vector -1))))
  (:call (context) (seq-mismatch (car context) (cdr context)))
  (:note "Last-element mismatch on equal-length vectors; absolute."))

(define-bench cl-mismatch-equal-b
  (:category :seq-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (traversal-list n) (traversal-list n)))
  (:call (context) (mismatch (car context) (cdr context)))
  (:note "CL No mismatch on distinct equal lists."))

(define-bench seq-mismatch-equal-b
  (:category :seq-traversal)
  (:baseline cl-mismatch-equal-b)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (traversal-list n) (traversal-list n)))
  (:call (context) (seq-mismatch (car context) (cdr context)))
  (:note (seq-note "No mismatch on equal-length equal lists; scans all N elements; compared with
direct CL call.")))

(define-bench seq-mismatch-unequal-b
  (:category :seq-traversal)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (traversal-vector n) (traversal-vector (1- n))))
  (:call (context) (seq-mismatch (car context) (cdr context)))
  (:note "Unequal lengths, equal prefix, vector sources; absolute."))

(define-bench seq-mismatch-bounded-from-end-b
  (:category :seq-traversal)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (traversal-list n) (traversal-list n)))
  (:call (context)
    (seq-mismatch (car context) (cdr context)
                  :start1 1 :start2 1 :end1 (1- (length (car context)))
                  :end2 (1- (length (cdr context))) :from-end t))
  (:note "No mismatch, bounded matching list regions, reverse alignment; absolute."))

(define-bench cl-map-lockstep-two-equal-b
  (:category :seq-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (traversal-list n) (traversal-list n)))
  (:call (context) (map 'list #'+ (car context) (cdr context)))
  (:note "CL Two equal lists and N binary callbacks."))

(define-bench seq-map-lockstep-two-equal-b
  (:category :seq-traversal)
  (:baseline cl-map-lockstep-two-equal-b)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (traversal-list n) (traversal-list n)))
  (:call (context) (seq-map #'+ (car context) (cdr context)))
  (:note (seq-note "Two equal lists, eager N-element result, N binary callbacks; compared with
direct CL call.")))

(define-bench seq-map-lockstep-two-short-first-b
  (:category :seq-traversal)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (traversal-list (floor n 2)) (traversal-vector n)))
  (:call (context) (realize-seq (seq-map #'+ (car context) (cdr context))))
  (:note "Mixed list/vector, shortest first (N/2), full mixed lazy result consumption;
absolute."))

(define-bench seq-map-lockstep-two-short-last-b
  (:category :seq-traversal)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (traversal-vector n) (traversal-list (floor n 2))))
  (:call (context) (realize-seq (seq-map #'+ (car context) (cdr context))))
  (:note "Mixed vector/list, shortest last (N/2), full mixed lazy result consumption;
absolute."))

(define-bench seq-map-lockstep-three-short-middle-b
  (:category :seq-traversal)
  (:sizes (10 100 1000 10000))
  (:setup (n) (list (traversal-list n) (traversal-vector (floor n 2)) (traversal-list n)))
  (:call (context) (realize-seq (seq-map #'+ (first context) (second context) (third context))))
  (:note "Three mixed sources, shortest middle (N/2); full lazy result consumption;
absolute."))

(define-bench seq-map-lockstep-three-warm-lazy-b
  (:category :seq-traversal)
  (:sizes (10 100 1000 10000))
  (:setup (n) (list (traversal-list n) (traversal-vector n) (pre-forced-range n)))
  (:call (context) (realize-seq (seq-map #'+ (first context) (second context) (third context))))
  (:note "Three equal mixed sources including WARM lazy last; full N-element result
consumption; absolute."))

(define-bench seq-map-lockstep-three-cold-lazy-b
  (:category :seq-traversal)
  (:sizes (10 100 1000 10000))
  (:cold-pool-size 4)
  (:setup (n) (fresh-pool 4 (lambda () (list (traversal-list n) (traversal-vector n)
    (range :end n)))))
  (:call (context) (realize-seq (seq-map #'+ (first context) (second context) (third context))))
  (:note "Three equal mixed sources including COLD lazy last; full N-element result
consumption; four fresh inputs per batch; absolute."))

(define-bench seq-split-at-list-construct-b
  (:category :seq-traversal)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (floor n 2) (traversal-list n)))
  (:call (context) (seq-split-at (car context) (cdr context)))
  (:note "List split-at EAGER call and both pieces built at construction; outer is
eager list, not deferred; absolute."))

(define-bench seq-split-at-warm-lazy-construct-b
  (:category :seq-traversal)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons n (pre-forced-range n)))
  (:call (context) (seq-split-at (floor (car context) 2) (cdr context)))
  (:note "CONSTRUCTION ONLY of deferred pair over WARM lazy source; no piece forced;
absolute."))

(define-bench seq-split-at-warm-lazy-partial-b
  (:category :seq-traversal)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons n (pre-forced-range n)))
  (:call (context)
    (realize-seq (seq-first (seq-split-at (floor (car context) 2) (cdr context)))))
  (:note "PARTIAL outer (first piece only), first piece fully consumed; WARM lazy
source; absolute."))

(define-bench seq-split-at-warm-lazy-full-b
  (:category :seq-traversal)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons n (pre-forced-range n)))
  (:call (context) (traversal-run-split-at (car context) (cdr context)))
  (:note "FULL outer and both pieces consumed; WARM lazy source; absolute."))

(define-bench seq-split-with-warm-lazy-construct-b
  (:category :seq-traversal)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons n (pre-forced-range n)))
  (:call (context)
    (seq-split-with (lambda (x) (< x (floor (car context) 2))) (cdr context)))
  (:note "CONSTRUCTION ONLY of deferred split-with pair on WARM lazy source; predicate
not called; absolute."))

(define-bench seq-split-with-warm-lazy-full-b
  (:category :seq-traversal)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons n (pre-forced-range n)))
  (:call (context) (traversal-run-split-with (car context) (cdr context)))
  (:note "FULL outer and both pieces consumed on WARM lazy source, ~N/2 predicate
calls; absolute."))

(define-bench seq-split-delimiter-full-b
  (:category :seq-traversal)
  (:sizes (10 100 1000 10000))
  (:setup (n) (traversal-vector n))
  (:call (source) (traversal-sum-pieces (seq-split source :delimiter '(3 4))))
  (:note "FULL outer and vector pieces; two-element delimiter occurs once; absolute."))

(define-bench seq-split-predicate-full-b
  (:category :seq-traversal)
  (:sizes (10 100 1000 10000))
  (:setup (n) (traversal-list n))
  (:call (source) (traversal-sum-pieces (seq-split source :predicate (lambda (x) (zerop
    (mod x 5))))))
  (:note "FULL outer and list pieces, every fifth element a delimiter (including index
0); absolute."))

(define-bench seq-partition-overlap-full-b
  (:category :seq-traversal)
  (:sizes (10 100 1000 10000))
  (:setup (n) (traversal-vector n))
  (:call (source) (traversal-sum-pieces (seq-partition 4 source :step 2)))
  (:note "FULL outer and vector pieces; overlapping width 4 step 2, trailing
incomplete piece dropped; absolute."))

(define-bench seq-partition-gap-full-b
  (:category :seq-traversal)
  (:sizes (10 100 1000 10000))
  (:setup (n) (traversal-list n))
  (:call (source) (traversal-sum-pieces (seq-partition 3 source :step 5)))
  (:note "FULL outer and list pieces; gapped width 3 step 5; absolute."))

(define-bench seq-partition-padded-full-b
  (:category :seq-traversal)
  (:sizes (10 100 1000 10000))
  (:setup (n) (traversal-vector n))
  (:call (source) (traversal-sum-pieces (seq-partition 4 source :step 3 :pad '(0 0 0))))
  (:note "FULL outer and vector pieces; width 4 step 3, final short piece padded from
a three-element zero sequence; absolute."))

(define-bench seq-partition-by-construct-b
  (:category :seq-traversal)
  (:sizes (10 100 1000 10000))
  (:setup (n) (traversal-list n))
  (:call (source) (seq-partition-by (lambda (x) (floor x 5)) source))
  (:note "CONSTRUCTION ONLY, deferred grouping by five-element runs; no key callback
or piece forced; absolute."))

(define-bench seq-partition-by-partial-b
  (:category :seq-traversal)
  (:sizes (10 100 1000 10000))
  (:setup (n) (traversal-list n))
  (:call (source)
    (realize-seq (seq-first (seq-partition-by (lambda (x) (floor x 5)) source))))
  (:note "PARTIAL outer, only first five-element group and its piece consumed;
absolute."))

(define-bench seq-partition-by-full-b
  (:category :seq-traversal)
  (:sizes (10 100 1000 10000))
  (:setup (n) (traversal-list n))
  (:call (source)
    (traversal-sum-pieces (seq-partition-by (lambda (x) (floor x 5)) source)))
  (:note "FULL outer and all pieces, N grouping-key callbacks; absolute."))

(define-bench seq-filter-dict-keys-realize-b
  (:category :seq-traversal)
  (:sizes (10 100 1000 10000))
  (:setup (n) (generic-ranged-dict 0 n))
  (:call (source) (realize-seq (seq-filter #'evenp (dict-keys source))))
  (:note "REALIZES filter over dict-sourced key view: traverses all N dict keys and N
predicate calls, consumes N/2 returned cells; unlike
seq-filter-over-dict-keys construction-only; absolute."))

(defun traversal-work-check ()
  "Untimed consumption/callback assertions; no instrumentation in timed runs."
  (let ((calls 0))
    (assert (= 8 (realize-seq (seq-mapcat (lambda (x)
                                           (incf calls)
                                           (list x (1+ x)))
                                         '(0 1 2 3)))))
    (assert (= calls 4))
    (setf calls 0)
    (seq-mapcat (lambda (x) (incf calls) (list x)) (range :end 4))
    (assert (zerop calls))
    (setf calls 0)
    (assert (= 4 (realize-seq (seq-map (lambda (x y) (incf calls) (+ x y))
                                         '(0 1 2 3) #(0 1 2 3 4)))))
    (assert (= calls 4))
    (setf calls 0)
    (assert (= 4 (traversal-sum-pieces
                  (seq-partition-by (lambda (x) (incf calls) (floor x 2))
                                    '(0 1 2 3)))))
    (assert (= calls 4))
    (setf calls 0)
    (assert (= 4 (traversal-sum-pieces
                  (seq-split-with (lambda (x) (incf calls) (< x 2))
                                  '(0 1 2 3)))))
    (assert (= calls 3))
    (assert (= 8 (traversal-sum-pieces
                  (seq-split #(0 1 2 3 4 5 6 7 8 9) :delimiter '(3 4)))))
    (assert (= 16 (traversal-sum-pieces
                   (seq-partition 4 #(0 1 2 3 4 5 6 7 8 9) :step 2))))
    (assert (= 16 (traversal-sum-pieces
                   (seq-partition 4 #(0 1 2 3 4 5 6 7 8 9)
                                  :step 3 :pad '(0 0 0)))))
    (assert (= 2 (realize-seq
                  (seq-filter #'evenp (dict-keys (generic-ranged-dict 0 4))))))
    (with-work-counters
      (reset-work-counters)
      (assert (= 3 (realize-seq (seq-member 1 '(0 1 2 3)))))
      (assert (plusp (equals-call-count))))
    t))

(define-bench seq-split-delimiter-construct-b
  (:category :seq-traversal)
  (:sizes (10 100 1000 10000))
  (:setup (n) (traversal-vector n))
  (:call (source) (seq-split source :delimiter '(3 4)))
  (:note "CONSTRUCTION ONLY of deferred split on vector; no delimiter scan, outer cell
or piece forced; absolute."))

(define-bench seq-split-delimiter-partial-b
  (:category :seq-traversal)
  (:sizes (10 100 1000 10000))
  (:setup (n) (traversal-vector n))
  (:call (source) (realize-seq (seq-first (seq-split source :delimiter '(3 4)))))
  (:note "PARTIAL outer, first vector piece consumed through two-element delimiter (3
4); no suffix consumed; absolute."))

(define-bench seq-partition-overlap-construct-b
  (:category :seq-traversal)
  (:sizes (10 100 1000 10000))
  (:setup (n) (traversal-vector n))
  (:call (source) (seq-partition 4 source :step 2))
  (:note "CONSTRUCTION ONLY, deferred width-4 overlapping partitions on vector; no
piece forced; absolute."))

(define-bench seq-partition-overlap-partial-b
  (:category :seq-traversal)
  (:sizes (10 100 1000 10000))
  (:setup (n) (traversal-vector n))
  (:call (source) (realize-seq (seq-first (seq-partition 4 source :step 2))))
  (:note "PARTIAL outer: first four-element vector piece consumed, no subsequent
piece; absolute."))
