;;;; Dict benchmarks: the Sophie dictionary surface against plain CL hash
;;;; tables.
;;;;
;;;; Matrix B covers the full dict protocol. The CL baselines come first
;;;; (category :DICT-BASELINE) so every Sophie bench (category :DICT) can
;;;; reference its baseline by registration order. Every comparison bench
;;;; carries a :TIER fairness label and a note with the shared semantics
;;;; caveat: Sophie dicts are persistent, use structural equality, and go
;;;; through CLOS generic dispatch, while the baselines mutate hash tables
;;;; under :TEST #'EQUAL through direct calls. :TEST #'EQUAL is kept
;;;; uniformly, even for fixnum keys where ANSI's default EQL test would be
;;;; faster, so every baseline pays the same honest test.
;;;;
;;;; Sizing follows the suite rules: (10 100 1000 10000) by default, with
;;;; 100000 added only to the cheap linear construction and iteration benches;
;;;; ECL caps sizes at 10000 through the harness host seam. No reader feature
;;;; conditionals appear in this file; host differences live in
;;;; benchmarks/host.lisp.

(in-package #:sophie-lisp.benchmarks)

;;; Input builders. Every builder runs inside :SETUP, outside the timed
;;; region; persistent inputs are rebuilt fresh per rep by the harness.

(defun ranged-dict (start count)
  "Return a COUNT-pair persistent dict with fixnum keys START to
START+COUNT-1, each mapped to its triple."
  (loop with result = (dict)
        for key from start below (+ start count)
        do (setf result (dict-set result key (* key 3)))
        finally (return result)))

(defun ranged-table (start count)
  "Return a COUNT-entry hash table with fixnum keys START to START+COUNT-1,
each mapped to its triple, under :TEST #'EQUAL."
  (loop with table = (make-hash-table :test #'equal)
        for key from start below (+ start count)
        do (setf (gethash key table) (* key 3))
        finally (return table)))

(defun string-key (index)
  "Return the string key for bench position INDEX, of the form key-000001."
  (format nil "key-~6,'0d" index))

(defun string-dict (n)
  "Return an N-pair persistent dict keyed by STRING-KEY strings, each key
mapped to its position's triple."
  (loop with result = (dict)
        for index below n
        do (setf result (dict-set result (string-key index) (* index 3)))
        finally (return result)))

(defun frequency-elements (n)
  "Return an N-element list with N/10 distinct fixnum elements for the
frequency benches, cycling (MOD I DISTINCT) over the element positions."
  (let ((distinct (max 1 (floor n 10))))
    (loop for index below n collect (mod index distinct))))

(defun nested-dict (n)
  "Return an N-key dict of ten-pair sub-dicts for the nested-path benches.
Outer keys are 0 to N-1; each sub-dict maps inner keys 0 to 9 to their
septuples, so the fixed path (0 5) names a present entry in the first
sub-dict."
  (loop with outer = (dict)
        for outer-key below n
        do (setf outer
                 (dict-set outer outer-key
                           (loop with inner = (dict)
                                 for inner-key below 10
                                 do (setf inner
                                          (dict-set inner inner-key
                                                    (* inner-key 7)))
                                 finally (return inner))))
        finally (return outer)))

;;; Collision-key crafting for the shared-prefix bench. The trie consumes
;;; hash bits in five-bit chunks from bit zero, so keys sharing the low
;;; chunk descend the same first edge, and keys agreeing on each further
;;; chunk descend together one level more; the greedy sub-bucketing below
;;; maximizes that shared descent for the bench size. Full 64-bit hash
;;; collisions, which SL:EQUALS-confirmed collision leaves would require,
;;; are not crafted; the bench note records that limit.

(defparameter *shared-prefix-key-cache* (make-hash-table :test #'eql)
  "Crafted shared-prefix key vectors keyed by bench size. The candidate scan
is too costly to repeat in every bench setup, so the first use for a size
builds and caches the vector for the rest of the session.")

(defun largest-sub-bucket (pairs width)
  "Return the largest group of (HASH . KEY) PAIRS whose hashes agree on the
WIDTH low bits, or NIL when PAIRS is empty."
  (let ((groups (make-hash-table :test #'eql))
        (best nil))
    (dolist (pair pairs)
      (push pair (gethash (ldb (byte width 0) (car pair)) groups)))
    (maphash (lambda (chunk group)
               (declare (ignore chunk))
               (when (> (length group) (length best))
                 (setf best group)))
             groups)
    best))

(defun craft-shared-prefix-keys (n)
  "Scan fixnum candidates for hash codes sharing one low five-bit chunk, then
greedily narrow to the largest sub-bucket agreeing on each deeper chunk while
it still holds N keys, and return N of those keys as a vector."
  ;; The scan budget grows with N so the greedy usually reaches a second
  ;; shared chunk, bounded above so the one-time scan stays cheap enough to
  ;; run inside a bench setup; the largest sizes may keep only the first
  ;; chunk, which the bench note reports as the achieved depth.
  (let ((target (ldb (byte 5 0) (hash-code 1)))
        (bucket '()))
    (loop for candidate from 1
          until (>= candidate (min (max (* 2048 n) 20480) 4194304))
          do (let ((hash (hash-code candidate)))
               (when (= target (ldb (byte 5 0) hash))
                 (push (cons hash candidate) bucket))))
    (unless (>= (length bucket) n)
      (error "BENCH shared-prefix scan found ~d keys but needs ~d."
             (length bucket) n))
    (loop with selected = bucket
          for width from 10 by 5 to 60
          for narrower = (largest-sub-bucket selected width)
          while (and narrower (>= (length narrower) n))
          do (setf selected narrower)
          finally (return (map 'vector #'cdr (subseq selected 0 n))))))

(defun shared-prefix-keys (n)
  "Return a vector of N fixnum keys whose SL:HASH-CODE values share the low
five-bit trie chunk, and deeper chunks where the candidate pool allows."
  (or (gethash n *shared-prefix-key-cache*)
      (setf (gethash n *shared-prefix-key-cache*)
            (craft-shared-prefix-keys n))))

(defun crafted-dict (n)
  "Return a cons of the N-key shared-prefix dict and its probe key, the first
crafted key, for the collision bench."
  (let ((keys (shared-prefix-keys n)))
    (cons (loop with result = (dict)
                for key across keys
                do (setf result (dict-set result key (* key 3)))
                finally (return result))
          (svref keys 0))))

;;; Shared note text. Every comparison bench pairs the caveat with its own
;;; specifics through COMPARISON-NOTE.

(alexandria:define-constant +dict-caveat+
  "Sophie: persistent, structural equality, CLOS generic; CL: mutable, :TEST
#'EQUAL, direct call."
  :test #'equal
  :documentation "Shared semantics caveat carried by every dict comparison
bench.")

(defun comparison-note (specific)
  "Return the note for one dict comparison bench: the shared semantics
caveat followed by the bench's SPECIFIC text."
  (concatenate 'string +dict-caveat+ " " specific))

;;; CL baselines. Each builds its hash table inside :SETUP, outside the timed
;;; region, and measures the plain CL form in :CALL.

(define-bench ht-make-n
  (:category :dict-baseline)
  (:sizes (10 100 1000 10000 100000))
  (:setup (n)
    (cons (loop for key below n collect key)
          (loop for key below n collect (* key 3))))
  (:call (context)
    (loop with table = (make-hash-table :test #'equal)
          for key in (car context)
          for value in (cdr context)
          do (setf (gethash key table) value)
          finally (return table)))
  (:note "Mutable table built by N SETF GETHASH insertions from prebuilt key
and value lists. :TEST #'EQUAL is kept uniformly, even for fixnum keys where
ANSI's default EQL test would be faster, so every baseline pays the same
honest test."))

(define-bench ht-ref-hit
  (:category :dict-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (ranged-table 0 n) (floor n 2)))
  (:call (context) (gethash (cdr context) (car context)))
  (:note "GETHASH hit on an N-entry :TEST #'EQUAL table with fixnum keys."))

(define-bench ht-ref-miss
  (:category :dict-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (ranged-table 0 n) n))
  (:call (context) (gethash (cdr context) (car context)))
  (:note "GETHASH miss on an N-entry :TEST #'EQUAL table with fixnum keys;
the probe key is one past the last inserted key."))

(define-bench ht-setf
  (:category :dict-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (ranged-table 0 n) (floor n 2)))
  (:call (context) (setf (gethash (cdr context) (car context)) 0))
  (:note "In-place SETF GETHASH on a present key; every timed call rewrites
the same entry, which is the mutable semantics being measured."))

(define-bench ht-remhash
  (:category :dict-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (ranged-table 0 n) (floor n 2)))
  (:call (context) (remhash (cdr context) (car context)))
  (:note "In-place REMHASH of a present key; after the first timed call the
key is absent, so calls 2..K measure the absent-key path. CL removal is O(1)
amortized, which is the mutable-semantics advantage the DICT-WITHOUT
comparison is read against."))

(define-bench ht-count
  (:category :dict-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (ranged-table 0 n))
  (:call (context) (hash-table-count context))
  (:note "HASH-TABLE-COUNT on an N-entry table."))

(define-bench ht-iterate
  (:category :dict-baseline)
  (:sizes (10 100 1000 10000 100000))
  (:setup (n) (ranged-table 0 n))
  (:call (context)
    (loop for key being the hash-key of context
          sum (gethash key context)))
  (:note "Full iteration over an N-entry table summing the values; iteration
order is the table's own and irrelevant to the sum."))

(define-bench ht-copy-setf
  (:category :dict-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (ranged-table 0 n) (floor n 2)))
  (:call (context)
    (let ((copy (alexandria:copy-hash-table (car context))))
      (setf (gethash (cdr context) copy) 0)
      copy))
  (:note "The T3 baseline for one persistent update: copy the whole table,
then mutate the copy. COPY-HASH-TABLE is alexandria, not ANSI."))

(define-bench ht-merge
  (:category :dict-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n)
    (let ((overlap (max 1 (floor n 10))))
      (cons (ranged-table 0 n)
            (ranged-table (- n overlap) n))))
  (:call (context)
    (let ((result (alexandria:copy-hash-table (car context))))
      (loop for key being the hash-key of (cdr context)
            do (setf (gethash key result) (gethash key (cdr context))))
      result))
  (:note "Manual loop merging one table into an alexandria copy of another;
the two N-entry tables overlap in N/10 keys."))

(define-bench ht-frequencies
  (:category :dict-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (frequency-elements n))
  (:call (context)
    (loop with table = (make-hash-table :test #'equal)
          for element in context
          do (incf (gethash element table 0))
          finally (return table)))
  (:note "Manual loop counting occurrences of an N-element list with N/10
distinct elements into a fresh :TEST #'EQUAL table."))

;;; Sophie benches. Ops returning new structures start every timed call from
;;; the same prebuilt input and discard the result, measuring one persistent
;;; update from the same base.

(define-bench dict-make-n
  (:category :dict)
  (:baseline ht-make-n)
  (:tier :same-op)
  (:sizes (10 100 1000 10000 100000))
  (:setup (n)
    (cons (loop for key below n collect key)
          (loop for key below n collect (* key 3))))
  (:call (context)
    (loop with result = (dict)
          for key in (car context)
          for value in (cdr context)
          do (setf result (dict-set result key value))
          finally (return result)))
  (:note (comparison-note
           "Construction semantics differ: the persistent trie is built by N
path-copying DICT-SET inserts while the baseline mutates one table in
place.")))

(define-bench dict-ref-hit-fixnum
  (:category :dict)
  (:baseline ht-ref-hit)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (ranged-dict 0 n) (floor n 2)))
  (:call (context) (dict-ref (car context) (cdr context)))
  (:note (comparison-note "Hit lookup on a persistent trie of fixnum keys.")))

(define-bench dict-ref-miss-fixnum
  (:category :dict)
  (:baseline ht-ref-miss)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (ranged-dict 0 n) n))
  (:call (context) (dict-ref (car context) (cdr context)))
  (:note (comparison-note "Miss lookup on a persistent trie of fixnum keys;
the probe key is one past the last inserted key.")))

(define-bench dict-ref-hit-string
  (:category :dict)
  (:baseline ht-ref-hit)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (string-dict n) (string-key (floor n 2))))
  (:call (context) (dict-ref (car context) (cdr context)))
  (:note (comparison-note
           "String keys pay a full structural hash per lookup with no
cross-invocation memoization, likely the dominant lookup asymmetry. The
baseline hashes a fixnum key, so the string/fixnum contrast is measured
against DICT-REF-HIT-FIXNUM within the Sophie pair.")))

(define-bench dict-ref-miss-string
  (:category :dict)
  (:baseline ht-ref-miss)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (string-dict n) (string-key n)))
  (:call (context) (dict-ref (car context) (cdr context)))
  (:note (comparison-note
           "Miss lookup on string keys; the probe key is one past the last
inserted key and pays the same structural hash as a hit.")))

(define-bench dict-set
  (:category :dict)
  (:baseline ht-copy-setf)
  (:tier :persistent-vs-copy)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (ranged-dict 0 n) (floor n 2)))
  (:call (context) (dict-set (car context) (cdr context) 0))
  (:note (comparison-note
           "One persistent update from the same base each call: O(log N) trie
path copy against the baseline's O(N) full-table copy plus mutation.")))

(define-bench dict-set-new-key
  (:category :dict)
  (:baseline ht-copy-setf)
  (:tier :persistent-vs-copy)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (ranged-dict 0 n) n))
  (:call (context) (dict-set (car context) (cdr context) 0))
  (:note (comparison-note
           "Trie growth path: inserting a fresh key grows the trie and may
split branches, still O(log N), against the baseline's copy plus insert.")))

(define-bench dict-without
  (:category :dict)
  (:baseline ht-remhash)
  (:tier :persistent-vs-copy)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (ranged-dict 0 n) (floor n 2)))
  (:call (context) (dict-without (car context) (cdr context)))
  (:note (comparison-note
           "One persistent removal from the same base each call: O(log N)
path copy against in-place REMHASH; the baseline's calls after the first
measure the absent-key path (see HT-REMHASH).")))

(define-bench dict-size
  (:category :dict)
  (:baseline ht-count)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (ranged-dict 0 n))
  (:call (context) (dict-size context))
  (:note (comparison-note
           "Entry count of a persistent dict against HASH-TABLE-COUNT.")))

(define-bench dict-member
  (:category :dict)
  (:baseline ht-ref-hit)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (ranged-dict 0 n) (floor n 2)))
  (:call (context) (dict-member (car context) (cdr context)))
  (:note (comparison-note
           "Membership returns presence and value like GETHASH's two values,
so the hit lookup is the nearest baseline shape.")))

(define-bench dict-update
  (:category :dict)
  (:baseline ht-setf)
  (:tier :persistent-vs-copy)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (ranged-dict 0 n) (floor n 2)))
  (:call (context) (dict-update (car context) (cdr context) #'1+))
  (:note (comparison-note
           "Read, apply, and rebuild: DICT-UPDATE returns a new dict through
an O(log N) path copy while the baseline mutates in place.")))

(define-bench dict-update-in
  (:category :dict)
  (:sizes (10 100 1000 10000))
  (:ecl-cap 1000)
  (:setup (n) (nested-dict n))
  (:call (context) (dict-update-in context '(0 5) #'1+))
  (:note "Sophie-only nested update along the fixed path (0 5) into an N-key
dict of ten-pair sub-dicts; no ANSI counterpart exists, so no baseline. The
ECL cap bounds the N=10000 setup cost there."))

(define-bench dict-set-in
  (:category :dict)
  (:sizes (10 100 1000 10000))
  (:ecl-cap 1000)
  (:setup (n) (nested-dict n))
  (:call (context) (dict-set-in context '(0 5) 0))
  (:note "Sophie-only nested set along the fixed path (0 5) into an N-key dict
of ten-pair sub-dicts; no ANSI counterpart exists, so no baseline. The ECL
cap bounds the N=10000 setup cost there."))

(define-bench dict-ref-in
  (:category :dict)
  (:sizes (10 100 1000 10000))
  (:ecl-cap 1000)
  (:setup (n) (nested-dict n))
  (:call (context) (dict-ref-in context '(0 5)))
  (:note "Sophie-only nested lookup along the fixed path (0 5) into an N-key
dict of ten-pair sub-dicts; no ANSI counterpart exists, so no baseline. The
ECL cap bounds the N=10000 setup cost there."))

(define-bench dict-keys
  (:category :dict)
  (:baseline ht-iterate)
  (:tier :same-op)
  (:sizes (10 100 1000 10000 100000))
  (:setup (n) (ranged-dict 0 n))
  (:call (context) (seq-into 'list (dict-keys context)))
  (:note (comparison-note
           "Full realization of the lazy key seq into a list via SEQ-INTO;
realization, not lazy-seq construction, is the measured work, matching the
baseline's full-table iteration. The Sophie side conses N fresh cells
realizing the seq while the baseline sums without consing, so per-element
work differs.")))

(define-bench dict-vals
  (:category :dict)
  (:baseline ht-iterate)
  (:tier :same-op)
  (:sizes (10 100 1000 10000 100000))
  (:setup (n) (ranged-dict 0 n))
  (:call (context) (seq-into 'list (dict-vals context)))
  (:note (comparison-note
           "Full realization of the lazy value seq into a list via SEQ-INTO;
realization, not lazy-seq construction, is the measured work, matching the
baseline's full-table iteration. The Sophie side conses N fresh cells
realizing the seq while the baseline sums without consing, so per-element
work differs.")))

(define-bench dict-keys-map
  (:category :dict)
  (:sizes (10 100 1000 10000))
  (:setup (n) (ranged-dict 0 n))
  (:call (context) (dict-keys-map #'1+ context))
  (:note "Full rebuild mapping #'1+ over the keys of an N-pair dict; no ANSI
counterpart bench exists, so no baseline."))

(define-bench dict-values-map
  (:category :dict)
  (:sizes (10 100 1000 10000))
  (:setup (n) (ranged-dict 0 n))
  (:call (context) (dict-values-map #'1+ context))
  (:note "Full rebuild mapping #'1+ over the values of an N-pair dict; no
ANSI counterpart bench exists, so no baseline."))

(define-bench dict-frequencies
  (:category :dict)
  (:baseline ht-frequencies)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (frequency-elements n))
  (:call (context) (dict-frequencies context))
  (:note (comparison-note
           "Occurrence counting over the same N-element list with N/10
distinct elements.")))

(define-bench dict-group-by
  (:category :dict)
  (:sizes (10 100 1000 10000))
  (:setup (n) (loop for element below n collect element))
  (:call (context) (dict-group-by (lambda (element) (mod element 10)) context))
  (:note "N elements grouped by (MOD X 10) into ten list-valued groups; no
ANSI counterpart bench exists, so no baseline."))

(define-bench dict-count-by
  (:category :dict)
  (:baseline ht-frequencies)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (loop for element below n collect element))
  (:call (context) (dict-count-by (lambda (element) (mod element 10)) context))
  (:note (comparison-note
           "Counting by (MOD X 10) with ten distinct keys has the baseline's
loop shape, though the baseline counts element identity over N/10 distinct
elements.")))

(define-bench dict-reduce-kv
  (:category :dict)
  (:baseline ht-iterate)
  (:tier :same-op)
  (:sizes (10 100 1000 10000 100000))
  (:setup (n) (ranged-dict 0 n))
  (:call (context)
    (dict-reduce-kv (lambda (accumulator key value)
                      (declare (ignore key))
                      (+ accumulator value))
                    0
                    context))
  (:note (comparison-note
           "Left fold summing the values of an N-pair dict against the
baseline's full-table summation loop.")))

(define-bench dict-select-keys
  (:category :dict)
  (:sizes (10 100 1000 10000))
  (:setup (n)
    (cons (ranged-dict 0 n)
          (loop for key below (floor n 2) collect key)))
  (:call (context) (dict-select-keys (car context) (cdr context)))
  (:note "Persistent rebuild restricted to N/2 present keys of an N-pair
dict; no ANSI counterpart bench exists, so no baseline."))

(define-bench dict-remove-keys
  (:category :dict)
  (:sizes (10 100 1000 10000))
  (:setup (n)
    (cons (ranged-dict 0 n)
          (loop for key below (floor n 2) collect key)))
  (:call (context) (dict-remove-keys (car context) (cdr context)))
  (:note "Persistent rebuild dropping N/2 present keys of an N-pair dict; no
ANSI counterpart bench exists, so no baseline."))

(define-bench dict-zipmap
  (:category :dict)
  (:baseline ht-make-n)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n)
    (cons (loop for key below n collect key)
          (loop for key below n collect (* key 3))))
  (:call (context) (dict-zipmap (car context) (cdr context)))
  (:note (comparison-note
           "Pairing two prebuilt N-element lists, the same input shape the
baseline builds its table from.")))

(define-bench dict-merge
  (:category :dict)
  (:baseline ht-merge)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n)
    (let ((overlap (max 1 (floor n 10))))
      (cons (ranged-dict 0 n)
            (ranged-dict (- n overlap) n))))
  (:call (context) (dict-merge (car context) (cdr context)))
  (:note (comparison-note
           "Merging two N-pair dicts overlapping in N/10 keys under default
:LAST-WINS collisions.")))

(define-bench dict-merge*
  (:category :dict)
  (:baseline ht-merge)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n)
    (let ((overlap (max 1 (floor n 10))))
      (list (ranged-dict 0 n)
            (ranged-dict (- n overlap) n)
            (ranged-dict (* 2 n) n))))
  (:call (context)
    (dict-merge* (first context) (second context) (third context)))
  (:note (comparison-note
           "Three-way merge of N-pair dicts; the baseline covers the two-way
shape only.")))

(define-bench dict-merge-with
  (:category :dict)
  (:baseline ht-merge)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n)
    (let ((overlap (max 1 (floor n 10))))
      (cons (ranged-dict 0 n)
            (ranged-dict (- n overlap) n))))
  (:call (context) (dict-merge-with #'+ (car context) (cdr context)))
  (:note (comparison-note
           "Merging with #'+ combining the values of the N/10 overlapping
keys.")))

(define-bench dict-transform
  (:category :dict)
  (:sizes (10 100 1000 10000))
  (:setup (n) (ranged-dict 0 n))
  (:call (context)
    (dict-transform (lambda (key value) (values key (1+ value))) context))
  (:note "Full rebuild producing a new key and value per entry; no ANSI
counterpart bench exists, so no baseline."))

(define-bench dict-collect
  (:category :dict)
  (:baseline ht-make-n)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n)
    (loop for key below n collect (map-entry key (* key 3))))
  (:call (context) (dict-collect (dict) context))
  (:note (comparison-note
           "Building an N-pair dict from prebuilt SL:MAP-ENTRY objects; the
empty dict contributes only its type, the same construction shape as the
baseline's prebuilt key and value lists.")))

(define-bench alist-dict
  (:category :dict)
  (:sizes (10 100 1000 10000))
  (:setup (n) (loop for key below n collect (cons key (* key 3))))
  (:call (context) (alist-dict context))
  (:note "Persistent dict from an N-entry alist; no ANSI counterpart bench
exists, so no baseline."))

(define-bench plist-dict
  (:category :dict)
  (:sizes (10 100 1000 10000))
  (:setup (n) (loop for key below n nconc (list key (* key 3))))
  (:call (context) (plist-dict context))
  (:note "Persistent dict from an N-entry plist; no ANSI counterpart bench
exists, so no baseline."))

(define-bench dict-alist
  (:category :dict)
  (:baseline ht-iterate)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (ranged-dict 0 n))
  (:call (context) (dict-alist context))
  (:note (comparison-note
           "Traversing an N-pair dict into a fresh alist; the baseline sums
instead of consing, so per-element work differs.")))

(define-bench dict-plist
  (:category :dict)
  (:baseline ht-iterate)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (ranged-dict 0 n))
  (:call (context) (dict-plist context))
  (:note (comparison-note
           "Traversing an N-pair dict into a fresh plist; the baseline sums
instead of consing, so per-element work differs.")))

(define-bench plist-dict-view-ref
  (:category :dict)
  (:sizes (10 100 1000 10000))
  (:setup (n)
    (cons (loop for key below n nconc (list key (* key 3)))
          (floor n 2)))
  (:call (context) (dict-ref (plist-dict-view (car context)) (cdr context)))
  (:note "Absolute Sophie-only observation (no baseline): each timed call
builds a read-only view over a live N-pair plist (O(N) plist analysis) and
then linear-scans it under EQ. GETF times lookup alone, and GETHASH times a
lookup on a prebuilt hash table; neither includes comparable view setup."))

(define-bench read-after-update-original
  (:category :dict)
  (:sizes (10 100 1000 10000))
  (:setup (n) (cons (ranged-dict 0 n) (floor n 2)))
  (:call (context) (dict-ref (car context) (cdr context)))
  (:note "Read-after-update pair, original: DICT-REF on the original N-pair
dict. Structural sharing must not degrade reads on the updated version
measured by READ-AFTER-UPDATE-UPDATED; the pair is Sophie-internal, so no
baseline."))

(define-bench read-after-update-updated
  (:category :dict)
  (:sizes (10 100 1000 10000))
  (:setup (n)
    (let ((base (ranged-dict 0 n)))
      (cons (dict-set base (floor n 2) 0) (floor n 2))))
  (:call (context) (dict-ref (car context) (cdr context)))
  (:note "Read-after-update pair, updated: DICT-REF on a version updated
once by DICT-SET outside the timed region. Structural sharing must not
degrade reads relative to READ-AFTER-UPDATE-ORIGINAL; the pair is
Sophie-internal, so no baseline."))

(define-bench dict-ref-collision
  (:category :dict)
  (:baseline dict-ref-hit-fixnum)
  (:sizes (10 100 1000 10000))
  (:ecl-cap 100)
  (:setup (n) (crafted-dict n))
  (:call (context) (dict-ref (car context) (cdr context)))
  (:note "Hit lookup on a dict whose keys were crafted to share low hash
chunks, forcing deeper trie descent than the sequential-key dict of the
DICT-REF-HIT-FIXNUM baseline at the same size. Achieved depth per size:
through n=1000 the crafted keys share the low 10 bits (two trie chunks) of
their hash codes, while n=10000 shares only the first five-bit chunk
because the scan budget limits the greedy. Validation result: EQUALS
dispatches per ref are equal (one) for the crafted and sequential dicts,
since the keys diverge at chunk three and every leaf is unique, so the
bench's timing signal is only the extra shared trie levels (one to two),
which is weak. Full 64-bit hash collisions, which SL:EQUALS-confirmed
collision leaves would require, were not crafted. The comparison is
Sophie-internal, so no tier label applies. The ECL cap bounds the one-time
candidate scan, which ECL's slower SL:HASH-CODE makes costly at the larger
sizes."))

(define-bench dict-test
  (:category :dict)
  (:sizes (1))
  (:setup (n) (declare (ignore n)) (dict))
  (:call (context) (dict-test context))
  (:note "Trivial accessor returning the dict's equality designator; benched
at one size for coverage only."))
