;;;; Lazy sequence benchmarks: first-forcing cost versus memoized
;;;; re-traversal of Sophie lazy seqs against plain CL list and vector
;;;; traversal.
;;;;
;;;; Matrix E covers the lazy core: RANGE, REPEATEDLY, ITERATE, CYCLE,
;;;; LAZY-CONS/LAZY-SEQ chains, DOSEQ, and SEQ-INTO. The CL baselines come
;;;; first (category :LAZY-BASELINE) so every Sophie bench (category :LAZY)
;;;; can reference its baseline by registration order.
;;;;
;;;; COLD versus WARM is the point of this file. Forcing a lazy-seq node
;;;; memoizes its element and rest persistently at the node, so a COLD bench
;;;; (first-forcing cost) consumes a fresh unrealized seq per timed call from
;;;; a pool, while a WARM bench (re-traversal cost) uses a seq pre-forced in
;;;; :SETUP. The two regimes are never mixed in one bench, and every note
;;;; labels which one it measures.
;;;;
;;;; Realization approach, shared by every bench that consumes a seq: a
;;;; SEQ-FIRST/SEQ-REST traversal counting elements until SEQ-EMPTYP, which
;;;; forces every cell exactly once (SEQ-EMPTYP forces the next cell;
;;;; SEQ-FIRST and SEQ-REST read the memoized element and rest). The one
;;;; exception is SEQ-INTO-LIST-FROM-LAZY, whose measured operation is
;;;; SEQ-INTO itself.
;;;;
;;;; Sizing follows the suite rules: (10 100 1000 10000) for sized shapes,
;;;; (1) for fixed ones, and (1000 10000 100000) for the deep-chain bench
;;;; with :ECL-CAP 10000. No reader feature conditionals appear in this
;;;; file; host differences live in benchmarks/host.lisp.

(in-package #:sophie-lisp.benchmarks)

;;; Input builders. Every builder runs inside :SETUP, outside the timed
;;; region; cold pools are rebuilt fresh per rep by the harness.

(defun realize-seq (seq)
  "Fully realize SEQ and return its element count: a SEQ-FIRST/SEQ-REST
traversal counting elements until SEQ-EMPTYP, where SEQ-EMPTYP forces the
next cell exactly once and SEQ-FIRST and SEQ-REST read the memoized
element and rest."
  (loop with current = seq
        with total = 0
        until (seq-emptyp current)
        do (seq-first current)
           (incf total)
           (setf current (seq-rest current))
        finally (return total)))

(defun realize-seq-prefix (seq limit)
  "Realize at most the first LIMIT cells of SEQ and return the number of
elements realized: the same SEQ-FIRST/SEQ-REST traversal, bounded so the
cell after the LIMIT-th is never forced."
  (loop with current = seq
        with total = 0
        while (< total limit)
        until (seq-emptyp current)
        do (seq-first current)
           (incf total)
           (setf current (seq-rest current))
        finally (return total)))

(defun lazy-chain (n)
  "Return a fresh N-cell lazy chain whose root is an unresolved node and
whose forcing of cell I runs one thunk allocating cell I as a LAZY-CONS
with the unresolved node for cell I+1 as its rest. Construction and each
single force are O(1), so no deep recursion occurs anywhere."
  (if (zerop n)
      nil
      (lazy-seq (lazy-cons n (lazy-chain (1- n))))))

(defun fresh-pool (pool-size builder)
  "Return a list of POOL-SIZE fresh inputs, each the result of one BUILDER
call; every entry is unrealized until the timed call forces it."
  (loop repeat pool-size collect (funcall builder)))

(defun pre-forced-range (n)
  "Return a (RANGE :END N) seq fully forced in advance, so timed calls see
only memoized cells."
  (let ((seq (range :end n)))
    (realize-seq seq)
    seq))

(defun lazy-ranged-dict (n)
  "Return a fresh N-pair persistent dict with fixnum keys 0 to N-1, each
mapped to its triple."
  (loop with result = (dict)
        for key below n
        do (setf result (dict-set result key (* key 3)))
        finally (return result)))

;;; Shared note text. Every bench that realizes or re-traverses a seq
;;; carries the same realization-approach text through LAZY-NOTE, prefixed
;;; with its COLD or WARM regime label.

(alexandria:define-constant +lazy-realization+
  "Realization: SEQ-FIRST/SEQ-REST traversal counting elements until
SEQ-EMPTYP; SEQ-EMPTYP forces the next cell exactly once and SEQ-FIRST and
SEQ-REST read the memoized element and rest."
  :test #'equal
  :documentation "Shared realization-approach text carried by every lazy
bench note.")

(defun lazy-note (label specific)
  "Return the note for one lazy bench: the COLD or WARM LABEL, the shared
realization text, and the bench's SPECIFIC caveat."
  (concatenate 'string label " " +lazy-realization+ " " specific))

;;; CL baselines. Each builds its input inside :SETUP, outside the timed
;;; region, and measures the plain CL form in :CALL.

(define-bench cl-list-realize
  (:category :lazy-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (loop for index below n collect index))
  (:call (context)
    (loop with total = 0
          for tail = context then (cdr tail)
          until (null tail)
          do (car tail)
             (incf total)
          finally (return total)))
  (:note "CL baseline: counting traversal of an N-element list built in
setup, reading each element; the eager re-traversal reference for the WARM
lazy benches."))

(define-bench cl-vector-realize
  (:category :lazy-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (coerce (loop for index below n collect index) 'vector))
  (:call (context)
    (loop with total = 0
          for index below (length context)
          do (aref context index)
             (incf total)
          finally (return total)))
  (:note "CL baseline: counting traversal of an N-element vector built in
setup, reading each element; the vector re-traversal reference. No Sophie
bench currently references it, so its numbers are absolute."))

(define-bench cl-loop-iota
  (:category :lazy-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) n)
  (:call (context) (loop for index below context collect index))
  (:note "CL baseline: eager LOOP construction of N elements; the eager
equivalent the COLD range bench is measured against."))

;;; Sophie benches. The COLD benches draw a fresh unrealized seq per timed
;;; call from a pool; the WARM benches re-traverse a seq pre-forced in
;;; :SETUP, so no timed call forces a cell.

(define-bench range-cold
  (:category :lazy)
  (:baseline cl-loop-iota)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:cold-pool-size 32)
  (:setup (n) (fresh-pool 32 (lambda () (range :end n))))
  (:call (context) (realize-seq context))
  (:note (lazy-note "COLD"
           "First forcing of a fresh (RANGE :END N) seq against the
baseline's eager LOOP construction of N elements; each forced cell runs one
thunk and allocates one resolved node plus one unresolved successor, so
both sides allocate O(N) nodes per call. The pool holds 32 fresh seqs and
K caps at the pool size.")))

(define-bench range-warm
  (:category :lazy)
  (:baseline cl-list-realize)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (pre-forced-range n))
  (:call (context) (realize-seq context))
  (:note (lazy-note "WARM"
           "Re-traversal of a pre-forced (RANGE :END N) seq: every cell is
already memoized, so each timed call takes only memo-hit paths against the
baseline's list re-traversal, and no cell is forced inside the timed
region. Read against RANGE-COLD for the memoization payoff.")))

(define-bench repeatedly-cold
  (:category :lazy)
  (:sizes (10 100 1000 10000))
  (:cold-pool-size 32)
  (:setup (n)
    (fresh-pool 32 (lambda () (repeatedly (lambda () 42) :count n))))
  (:call (context) (realize-seq context))
  (:note (lazy-note "COLD"
           "First forcing of a fresh (REPEATEDLY ... :COUNT N) seq: every
forced cell runs the zero-argument callback through the retained
designator, so the per-element callback cost is part of the measurement.
No plain-CL eager equivalent among the baselines pays a per-element
callback, so no baseline. The pool holds 32 fresh seqs and K caps at the
pool size.")))

(define-bench iterate-take-cold
  (:category :lazy)
  (:sizes (10 100 1000 10000))
  (:cold-pool-size 32)
  (:setup (n) (fresh-pool 32 (lambda () (cons n (iterate #'1+ 0)))))
  (:call (context) (realize-seq-prefix (cdr context) (car context)))
  (:note (lazy-note "COLD"
           "Bounded consumption of an infinite source: the timed call
realizes exactly the first N cells of a fresh (ITERATE #'1+ 0) seq and
never forces past the N-th cell; the pool entry carries the limit together
with the seq. Each forced cell after the first runs the successor callback
once, so N-1 callbacks run over the N realized cells; the first cell yields
the initial value without a callback. No plain-CL counterpart bench
exists, so no baseline. The pool holds 32 fresh seqs and K caps at the
pool size.")))

(define-bench cycle-take-cold
  (:category :lazy)
  (:sizes (10 100 1000 10000))
  (:cold-pool-size 32)
  (:setup (n)
    (let ((source (loop for index below (max 1 (floor n 10))
                        collect index)))
      (fresh-pool 32 (lambda () (cons n (cycle source))))))
  (:call (context) (realize-seq-prefix (cdr context) (car context)))
  (:note (lazy-note "COLD"
           "Bounded consumption of an infinite replay: the timed call
realizes the first N cells of a fresh (CYCLE SOURCE) seq over an
N/10-element list, entering the replay path once the captured prefix is
exhausted, and never forces past the N-th cell; the pool entry carries the
limit together with the seq. The 32 pool entries share one immutable
source list, but each cycle keeps its own view and prefix state. No
plain-CL counterpart bench exists, so no baseline. K caps at the pool
size.")))

(define-bench lazy-cons-chain-cold
  (:category :lazy)
  (:sizes (10 100 1000 10000))
  (:cold-pool-size 32)
  (:setup (n) (fresh-pool 32 (lambda () (lazy-chain n))))
  (:call (context) (realize-seq context))
  (:note (lazy-note "COLD"
           "Raw node forcing: full realization of a fresh N-cell
LAZY-CHAIN, where each cell's force is one thunk call allocating the
resolved cell and its unresolved successor, with no source arithmetic or
callback, so the bench measures the lazy-node forcing floor. No plain-CL
counterpart bench exists, so no baseline. The pool holds 32 fresh chains
and K caps at the pool size.")))

(define-bench deep-chain-realize
  (:category :lazy)
  (:sizes (1000 10000 100000))
  (:ecl-cap 10000)
  (:cold-pool-size 4)
  (:setup (n) (fresh-pool 4 (lambda () (lazy-chain n))))
  (:call (context) (realize-seq context))
  (:note (lazy-note "COLD"
           "The deep-chain bench: full realization of a fresh N-cell
LAZY-CHAIN at sizes far beyond the suite default. Deep chains are
expensive to realize per call, so the pool holds only 4 fresh chains and
K caps at 4; whether the adaptive floor is reachable at that cap is size-
and host-dependent: at sizes where the 4-call batch stays under the
floor, K stays 4 with FLOOR-REACHED false, and once a single realization
exceeds the floor, K is 1 with FLOOR-REACHED true; the record's
FLOOR-REACHED field carries the actual value per size. Stack safety: the
implementation realizes through explicit loops (LAZY-STEP's pending list
and this file's LOOP traversal), so a 100000-cell chain forces without
deep recursion. The size list (1000 10000 100000) is a deliberate
deviation from the suite default, with ECL capped at 10000 through
:ECL-CAP. No plain-CL counterpart bench exists, so no baseline.")))

(define-bench forcing-overhead
  (:category :lazy)
  (:sizes (1))
  (:cold-pool-size 32)
  (:setup (n)
    (declare (ignore n))
    (fresh-pool 32 (lambda () (lazy-seq (lazy-cons 42 nil)))))
  (:call (context) (seq-first context))
  (:note "COLD: one-node forcing of a fresh single-cell
(LAZY-SEQ (LAZY-CONS 42 NIL)) seq; the timed SEQ-FIRST runs the thunk,
resolves the cell, and writes the memoized element and rest, measuring
the one-node forcing plus memoization-write floor. The pool holds 32
fresh cells and K caps at the pool size. Read against MEMO-HIT, the WARM
pair, whose ratio isolates the forcing cost."))

(define-bench memo-hit
  (:category :lazy)
  (:sizes (1))
  (:setup (n)
    (declare (ignore n))
    (let ((cell (lazy-seq (lazy-cons 42 nil))))
      (seq-first cell)
      cell))
  (:call (context) (seq-first context))
  (:note "WARM: SEQ-FIRST on a single cell pre-forced outside the timed
region; every timed call takes the memo-hit path (state :VALUE, no thunk).
Read against FORCING-OVERHEAD, the COLD pair: the ratio isolates the
forcing plus memoization-write cost."))

(define-bench lazy-over-dict
  (:category :lazy)
  (:sizes (10 100 1000 10000))
  (:setup (n)
    (let ((keys (dict-keys (lazy-ranged-dict n))))
      (realize-seq keys)
      keys))
  (:call (context) (realize-seq context))
  (:note (lazy-note "WARM"
           "Re-traversal of the pre-forced lazy key seq of an N-pair dict,
a lazy seq over a dict source: every cell is memoized before timing, so
the timed calls measure generic dispatch over memo-hit cells only. No
plain-CL counterpart bench exists, so no baseline.")))

(define-bench doseq-list
  (:category :lazy)
  (:sizes (10 100 1000 10000))
  (:setup (n) (loop for index below n collect index))
  (:call (context)
    (let ((total 0))
      (doseq (_ context)
        (incf total))
      total))
  (:note "DOSEQ iteration over an N-element list with a counter increment
per element: macro runtime, generic over seqables. CL has no generic
equivalent (DOLIST is list-only), so the numbers are absolute with no
baseline."))

(define-bench doseq-vector
  (:category :lazy)
  (:sizes (10 100 1000 10000))
  (:setup (n) (coerce (loop for index below n collect index) 'vector))
  (:call (context)
    (let ((total 0))
      (doseq (_ context)
        (incf total))
      total))
  (:note "DOSEQ iteration over an N-element vector with a counter
increment per element: macro runtime, generic over seqables. CL has no
generic equivalent, so the numbers are absolute with no baseline."))

(define-bench doseq-lazy
  (:category :lazy)
  (:sizes (10 100 1000 10000))
  (:setup (n) (pre-forced-range n))
  (:call (context)
    (let ((total 0))
      (doseq (_ context)
        (incf total))
      total))
  (:note "WARM: DOSEQ iteration over a pre-forced (RANGE :END N) lazy seq
with a counter increment per element; the seq was fully realized in setup
by this file's shared SEQ-FIRST/SEQ-REST counting traversal, so every
timed step takes memo-hit paths. Macro runtime, generic over seqables; CL
has no generic equivalent, so the numbers are absolute with no baseline."))

(define-bench seq-into-list-from-lazy
  (:category :lazy)
  (:sizes (10 100 1000 10000))
  (:setup (n) (pre-forced-range n))
  (:call (context) (seq-into 'list context))
  (:note "WARM: SEQ-INTO 'LIST conversion of a pre-forced (RANGE :END N)
lazy seq per call, measuring the conversion cost over memoized cells; the
seq was fully realized in setup by this file's shared SEQ-FIRST/SEQ-REST
counting traversal. This bench's realization op is SEQ-INTO itself, the
one deliberate exception to that traversal. No plain-CL counterpart bench
exists, so no baseline."))
