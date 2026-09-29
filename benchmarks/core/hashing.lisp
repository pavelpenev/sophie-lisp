;;;; Hashing and equality benchmarks: the Sophie structural hash, equality,
;;;; and comparison surface against plain CL hashing and equality.
;;;;
;;;; Matrix A covers SL:HASH-CODE, SL:EQUALS, SL:COMPARE, and SL:LT. The CL
;;;; baselines come first (category :HASHING-BASELINE) so every Sophie bench
;;;; (category :HASHING) can reference its baseline by registration order.
;;;; Every comparison bench carries a :TIER fairness label and a note with
;;;; the shared semantics caveat: Sophie hashing is structural,
;;;; EQUALS-consistent, and CLOS generic, bounded at depth 16 with
;;;; per-invocation memoization of shared substructure, while the CL
;;;; baselines are direct calls.
;;;;
;;;; Sizing follows the suite rules: (10 100 1000 10000) for sized shapes and
;;;; (1) for fixed ones; the tree/DAG memoization pair uses the full
;;;; binary-tree node counts (15 63 255 1023). NaN is excluded by design:
;;;; SL:HASH-CODE signals TYPE-ERROR on a NaN, so no bench hashes one. No
;;;; reader feature conditionals appear in this file; host differences live
;;;; in benchmarks/host.lisp.

(in-package #:sophie-lisp.benchmarks)

;;; Input builders. Every builder runs inside :SETUP, outside the timed
;;; region; persistent inputs are rebuilt fresh per rep by the harness.

(defun hash-string (n)
  "Return a fresh N-character string cycling the lowercase letters, so
every position carries content both hash functions must observe."
  (coerce (loop for index below n
                collect (code-char (+ 97 (mod index 26))))
          'string))

(defun hash-vector (n)
  "Return a fresh N-element vector of fixnums, each element its triple."
  (coerce (loop for index below n collect (* index 3)) 'vector))

(defun hash-list (n)
  "Return a fresh N-element list of fixnums 0 to N-1."
  (loop for index below n collect index))

(defun hash-list-differ-first (n)
  "Return a fresh N-element fixnum list whose first element differs from
HASH-LIST's list of the same size; every other position agrees."
  (cons -1 (loop for index from 1 below n collect index)))

(defun hash-list-differ-last (n)
  "Return a fresh N-element fixnum list that differs from HASH-LIST's list
of the same size only in its last element."
  (loop for index below n
        collect (if (= index (1- n)) -1 index)))

(defun hash-deep-conses (n)
  "Return N-deep car-nested conses: each level wraps the previous structure
as its car, so the nesting depth equals the cons count."
  (let ((result 0))
    (loop for index below n
          do (setf result (cons result index)))
    result))

(defun hash-ranged-dict (n)
  "Return a fresh N-pair persistent dict with fixnum keys 0 to N-1, each
mapped to its triple."
  (loop with result = (dict)
        for key below n
        do (setf result (dict-set result key (* key 3)))
        finally (return result)))

(defun hash-nested-dict (n)
  "Return an N-key dict whose values are distinct ten-pair sub-dicts, each
built fresh so no sub-dict is shared with another."
  (loop with outer = (dict)
        for outer-key below n
        do (setf outer (dict-set outer outer-key (hash-ranged-dict 10)))
        finally (return outer)))

(defun hash-tree-depth (n)
  "Return the depth of the full binary tree holding N cons nodes, or signal
an error when N is not of the form 2^d-1."
  (let ((depth (1- (integer-length (1+ n)))))
    (unless (= n (1- (expt 2 depth)))
      (error "BENCH tree size ~d is not 2^d-1." n))
    depth))

(defun hash-binary-tree (depth)
  "Return a fresh full binary tree of 2^DEPTH-1 fresh cons nodes with no
shared substructure; the leaves are fixnums."
  (if (zerop depth)
      0
      (cons (hash-binary-tree (1- depth))
            (hash-binary-tree (1- depth)))))

(defun hash-shared-dag (depth)
  "Return a shared-substructure binary tree with the same 2^DEPTH-1 node
references as HASH-BINARY-TREE, but every right child is the very same
object as its left sibling, so the DAG holds only DEPTH unique conses."
  (if (zerop depth)
      0
      (let ((left (hash-shared-dag (1- depth))))
        (cons left left))))

(defclass hashing-identity-node ()
  ((payload :initarg :payload :initform nil))
  (:documentation
   "Trivial one-slot class whose instances take the identity-hash path; the
slot exists only so instances are more than bare class wrappers."))

;;; Shared note text. Every comparison bench pairs the caveat with its own
;;; specifics through HASHING-NOTE.

(alexandria:define-constant +hashing-caveat+
  "Sophie: structural, EQUALS-consistent, CLOS generic, depth-16
per-invocation memoization; CL: direct call."
  :test #'equal
  :documentation "Shared semantics caveat carried by every hashing
comparison bench.")

(defun hashing-note (specific)
  "Return the note for one hashing comparison bench: the shared semantics
caveat followed by the bench's SPECIFIC text."
  (concatenate 'string +hashing-caveat+ " " specific))

;;; CL baselines. Each builds its input inside :SETUP, outside the timed
;;; region, and measures the plain CL form in :CALL.

(define-bench sxhash-fixnum
  (:category :hashing-baseline)
  (:sizes (1))
  (:setup (n) (+ n 12345))
  (:call (context) (sxhash context))
  (:note "SXHASH on a fixnum; the CL hash baseline for the fixed shapes."))

(define-bench sxhash-string
  (:category :hashing-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (hash-string n))
  (:call (context) (sxhash context))
  (:note "SXHASH on an N-character string with varied content."))

(define-bench sxhash-cons
  (:category :hashing-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (hash-deep-conses n))
  (:call (context) (sxhash context))
  (:note "SXHASH on N-deep car-nested conses; SXHASH is a direct call; traversal depth is host-dependent."))

(define-bench sxhash-vector
  (:category :hashing-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (hash-vector n))
  (:call (context) (sxhash context))
  (:note "SXHASH on a vector of N fixnums."))

(define-bench equal-cons
  (:category :hashing-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (hash-list n) (hash-list n)))
  (:call (context) (equal (car context) (cdr context)))
  (:note "EQUAL on two EQUAL but distinct N-element lists of fixnums; EQUAL
has no memoization, so every call re-traverses fully."))

(define-bench equalp-vector
  (:category :hashing-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (hash-vector n) (hash-vector n)))
  (:call (context) (equalp (car context) (cdr context)))
  (:note "EQUALP on two EQUALP-equal but distinct N-element fixnum
vectors."))

(define-bench num-lt
  (:category :hashing-baseline)
  (:sizes (1))
  (:setup (n) (cons (+ n 1) (+ n 2)))
  (:call (context) (< (car context) (cdr context)))
  (:note "< on two fixnums; the CL ordering baseline."))

;;; Sophie benches. The hash benches measure one SL:HASH-CODE call on a
;;; prebuilt input; the equals benches measure one SL:EQUALS call on a
;;; prebuilt pair.

(define-bench hash-code-fixnum
  (:category :hashing)
  (:baseline sxhash-fixnum)
  (:tier :same-op)
  (:sizes (1))
  (:setup (n) (+ n 12345))
  (:call (context) (hash-code context))
  (:note (hashing-note
           "SL:HASH-CODE on a fixnum through the generic number method; the
depth-16 bound and memoization never engage on flat data.")))

(define-bench hash-code-string
  (:category :hashing)
  (:baseline sxhash-string)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (hash-string n))
  (:call (context) (hash-code context))
  (:note (hashing-note
           "SL:HASH-CODE hashes strings as rank-one arrays element-wise,
observing at most the 64-element prefix, so sizes above 64 are
prefix-bounded while SXHASH sampling is implementation-dependent.")))

(define-bench hash-code-cons-shallow
  (:category :hashing)
  (:baseline sxhash-cons)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (hash-list n))
  (:call (context) (hash-code context))
  (:note (hashing-note
           "SL:HASH-CODE on an N-element flat list; the depth-16 bound
observes only the first 16 spine elements, and the SXHASH-CONS baseline
hashes N-deep nested conses rather than a flat list, so the shapes differ
and the ratio is read with care.")))

(define-bench hash-code-cons-deep
  (:category :hashing)
  (:baseline sxhash-cons)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (hash-deep-conses n))
  (:call (context) (hash-code context))
  (:note (hashing-note
           "SL:HASH-CODE on N-deep car-nested conses; the depth-16 bound
truncates past 16 levels; SXHASH traversal depth is
implementation-dependent, so the ratio is not a pure dispatch cost.")))

(define-bench hash-code-vector
  (:category :hashing)
  (:baseline sxhash-vector)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (hash-vector n))
  (:call (context) (hash-code context))
  (:note (hashing-note
           "SL:HASH-CODE hashes at most the 64-element prefix of the vector,
so sizes above 64 are prefix-bounded; SXHASH sampling is
implementation-dependent.")))

(define-bench hash-code-bignum
  (:category :hashing)
  (:sizes (10 100 1000 10000))
  (:setup (n) (+ (expt 2 200) n))
  (:call (context) (hash-code context))
  (:note "SL:HASH-CODE on a 201-bit bignum through the limb-wise integer
hash; no ANSI counterpart bench exists, so no baseline."))

(define-bench hash-code-rational
  (:category :hashing)
  (:sizes (10 100 1000 10000))
  (:setup (n) (/ (+ n 1) (+ n 7)))
  (:call (context) (hash-code context))
  (:note "SL:HASH-CODE on a reduced rational through the exact
numerator/denominator hash; no ANSI counterpart bench exists, so no
baseline."))

(define-bench hash-code-float
  (:category :hashing)
  (:sizes (10 100 1000 10000))
  (:setup (n) (+ (coerce n 'double-float) 0.5d0))
  (:call (context) (hash-code context))
  (:note "SL:HASH-CODE on a double float through the exact RATIONAL
canonicalization; no ANSI counterpart bench exists, so no baseline. NaN is
excluded by design: SL:HASH-CODE signals TYPE-ERROR there, so no bench
hashes one."))

(define-bench equals-cons-equal
  (:category :hashing)
  (:baseline equal-cons)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (hash-list n) (hash-list n)))
  (:call (context) (equals (car context) (cdr context)))
  (:note (hashing-note
           "SL:EQUALS on two structurally equal N-element lists; like the
EQUAL baseline it re-traverses fully on every call, with no
cross-invocation memoization.")))

(define-bench equals-cons-differ-first
  (:category :hashing)
  (:baseline equal-cons)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (hash-list n) (hash-list-differ-first n)))
  (:call (context) (equals (car context) (cdr context)))
  (:note (hashing-note
           "SL:EQUALS on N-element lists whose first elements differ; EQUALS
exits at the first element, while the EQUAL baseline compares two equal
lists through their full length.")))

(define-bench equals-cons-differ-last
  (:category :hashing)
  (:baseline equal-cons)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (hash-list n) (hash-list-differ-last n)))
  (:call (context) (equals (car context) (cdr context)))
  (:note (hashing-note
           "SL:EQUALS on N-element lists differing only in the last
element; both sides traverse nearly the whole list before exiting.")))

(define-bench equals-vector
  (:category :hashing)
  (:baseline equalp-vector)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (hash-vector n) (hash-vector n)))
  (:call (context) (equals (car context) (cdr context)))
  (:note (hashing-note
           "SL:EQUALS on two structurally equal N-element fixnum vectors
against the EQUALP baseline.")))

(define-bench compare-numbers
  (:category :hashing)
  (:baseline num-lt)
  (:tier :same-op)
  (:sizes (1))
  (:setup (n) (cons (+ n 1) (+ n 2)))
  (:call (context) (compare (car context) (cdr context)))
  (:note (hashing-note
           "SL:COMPARE on two fixnums returns :LESS through generic
dispatch against the baseline's direct <.")))

(define-bench lt-numbers
  (:category :hashing)
  (:baseline num-lt)
  (:tier :same-op)
  (:sizes (1))
  (:setup (n) (cons (+ n 1) (+ n 2)))
  (:call (context) (lt (car context) (cdr context)))
  (:note (hashing-note
           "SL:LT on two fixnums goes through SL:COMPARE, adding a keyword
comparison and a membership check over the baseline's direct <.")))

(define-bench hash-code-dict
  (:category :hashing)
  (:sizes (10 100 1000 10000))
  (:setup (n) (hash-ranged-dict n))
  (:call (context) (hash-code context))
  (:note "SL:HASH-CODE on an N-pair fixnum-keyed dict through the
unordered trie fold; no ANSI counterpart bench exists, so no baseline."))

(define-bench equals-dict
  (:category :hashing)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (hash-ranged-dict n) (hash-ranged-dict n)))
  (:call (context) (equals (car context) (cdr context)))
  (:note "SL:EQUALS on two structurally equal N-pair dicts through the
bijection check; no ANSI counterpart bench exists, so no baseline."))

(define-bench hash-code-dict-in-dict
  (:category :hashing)
  (:sizes (10 100 1000))
  (:setup (n) (hash-nested-dict n))
  (:call (context) (hash-code context))
  (:note "SL:HASH-CODE on a dict whose N values are distinct ten-pair
sub-dicts; the sub-dicts are separate objects, so per-invocation
memoization does not collapse them. The size list stops at 1000, a
deliberate deviation from the suite default: each size builds N fresh
ten-pair sub-dicts, so the setup cost grows quadratically with the largest
size. No ANSI counterpart bench exists, so no baseline."))

(define-bench hash-code-tree
  (:category :hashing)
  (:sizes (15 63 255 1023))
  (:setup (n) (hash-binary-tree (hash-tree-depth n)))
  (:call (context) (hash-code context))
  (:note "SL:HASH-CODE on a fresh full binary tree of N cons nodes built
per rep with no shared substructure; every node is hashed once within the
invocation. Sophie-internal, so no baseline."))

(define-bench hash-code-dag
  (:category :hashing)
  (:sizes (15 63 255 1023))
  (:setup (n) (hash-shared-dag (hash-tree-depth n)))
  (:call (context) (hash-code context))
  (:note "SL:HASH-CODE on a shared-substructure binary tree with the same N
node references but every right child reusing its left sibling's object;
memoization is per-invocation, so the DAG hashes each unique object once
and the unique-object count grows only with the depth. Read against
HASH-CODE-TREE; Sophie-internal, so no baseline."))

(define-bench hash-code-identity-first-call
  (:category :hashing)
  (:sizes (1))
  (:cold-pool-size 64)
  (:setup (n)
    (declare (ignore n))
    (loop repeat 64
          collect (make-instance 'hashing-identity-node
                                 :payload (gensym "bench-node-"))))
  (:call (context) (hash-code context))
  (:note "COLD: first-ever SL:HASH-CODE on a fresh instance of the trivial
one-slot HASHING-IDENTITY-NODE class; the identity path assigns a token
under the bordeaux-threads lock and enters the trivial-garbage weak table.
The pool holds 64 fresh instances and K caps at the pool size. No ANSI
counterpart bench exists, so no baseline."))

(define-bench hash-code-identity-repeat
  (:category :hashing)
  (:sizes (1))
  (:setup (n)
    (declare (ignore n))
    (let ((node (make-instance 'hashing-identity-node
                                :payload (gensym "bench-node-"))))
      (hash-code node)
      node))
  (:call (context) (hash-code context))
  (:note "SL:HASH-CODE on one instance whose identity token was assigned
outside the timed region; every timed call takes the repeat path, lock
plus weak-table lookup. No ANSI counterpart bench exists, so no
baseline."))

(define-bench hash-code-flat-overhead
  (:category :hashing)
  (:sizes (10))
  (:setup (n) (hash-vector n))
  (:call (context) (hash-code context))
  (:note "SL:HASH-CODE on a ten-element flat vector; the array hash method
always enters CALL-WITH-STRUCTURAL-HASH, which creates the memo table on
first component access, so the bench measures the per-invocation
memoization context setup on flat data: the marker check, memo-table
creation, and bookkeeping, where memoization provides no payoff because
the data has no shared substructure. The single size (10) is a deliberate
deviation from the suite default: flat-overhead is a fixed-shape
measurement, so further sizes add nothing. No ANSI counterpart bench
exists, so no baseline."))
