# Chapter 6: Sequence Operations

## 6.1 Concepts

### 6.1.1 Type-Preserving Returns

**Ordered-dictionary reconstruction.** `SL:ORDERED-DICT` is a concrete,
ordered, entry-only type (Chapter 9, Section 9.1.18), governed by the dedicated
matrix below, not by the limited ordinary `SL:DICT`/hash-table roster. This
matrix forms part of each named operation's contract. Bounds, counts, source
indices, callback inputs, and recurrence steps refer to the logical input or
emitted stream **before** dictionary reconstruction. Reconstruction accepts only
`SL:MAP-ENTRY` objects and signals `TYPE-ERROR` for an actual emitted non-entry.
It must not widen, infer a type from contents, retry callbacks for another
container, or fall back after refusal. Empty reconstructed results are
`SL:ORDERED-DICT` objects, not `NIL`.

Reconstruction visits the emitted entries in their specified output order.
The first equivalent key fixes position, while the last association supplies
both the resident key object and value, even for an `EQ`-identical value.
Consequently, emission count and resident unique-key count may differ. This
qualification applies to every count-of-result-elements statement in the
entries below when reconstructing an ordered dictionary. Retention-only
operations select already unique entries and therefore do not introduce new
key collisions. Reordering establishes the result's stored order; future novel
key insertion appends to that order.

Callback timing and return representation are independent. For eager ordered
reconstruction, callback production and reconstruction occur during the call;
an implementation may produce all callback results before accumulating them.
No general guarantee suppresses callbacks after the first output element that
will later be refused. Callback count/order and short-circuit rules in each
entry still apply, and callbacks are not repeated solely for reconstruction.
A callback condition propagates at its invocation; a Collector condition
propagates at reconstruction, without returning a partial result. This does
not weaken Chapter 9's separate immediate collision cutoff for `DICT-TRANSFORM`.

| Ordered policy row | Operations | Result, traversal, callbacks, and cardinality |
|---|---|---|
| Mapping | `SL:SEQ-MAP`, `SL:SEQ-MAP-INDEXED` | Eager ordered result for one ordered source; multi-MAP follows the multi-source row. Only emitted entry values are accepted. MAP-INDEXED uses original source indices and calls once per source element, regardless of duplicate output keys. |
| Keeping | `SL:SEQ-KEEP` | Eager ordered result. NIL callback results are omitted; every emitted non-NIL result must be an entry. An entry whose value is NIL is retained. All omitted results produce a typed empty dictionary. |
| Substitution | `SL:SEQ-SUBSTITUTE`, `SL:SEQ-SUBSTITUTE-IF` | Eager ordered reconstruction of the substituted stream in normal output order, including unchanged outside-region entries. Invalid replacement objects are rejected only if emitted; COUNT 0 and no-match cases do not validate an unused replacement. FROM-END changes match selection, not output order. Collisions with unchanged earlier or later entries obey encounter-order last-wins. |
| Flattening | `SL:SEQ-MAPCAT` | Eager ordered result from flattened callback seqables. NIL is an empty callback sequence; a list containing NIL emits a non-entry and signals TYPE-ERROR. A MAP-ENTRY alone is not seqable and signals TYPE-ERROR when reached. Cross-group duplicates collapse; an infinite callback sequence can prevent return and later callback calls. |
| Running reduction | `SL:SEQ-REDUCTIONS` | Eager ordered reconstruction of emitted accumulator states. The initial state and every later emitted state must be entries. Empty input without an initial value yields an ordered empty; supplied NIL is an emitted invalid initial state even on empty input. Duplicate state keys reduce resident size, not the number of recurrence steps or callback calls. |
| Selection | `SL:SEQ-FILTER`, `SL:SEQ-REMOVE`, `SL:SEQ-REMOVE-IF`, `SL:SEQ-TAKE`, `SL:SEQ-DROP`, `SL:SEQ-TAKE-WHILE`, `SL:SEQ-DROP-WHILE`, `SL:SEQ-SUBSEQ`, `SL:SEQ-TAKE-NTH`, `SL:SEQ-REMOVE-DUPLICATES`, `SL:SEQ-DEDUPE`, `SL:SEQ-TRIM-LEFT` | Eager ordered result with retained entries in source order. Bounds and COUNT/FROM-END rules remain those of each entry; FILTER omits outside-region elements while REMOVE retains them. Tests, predicates, and keys operate on entries or their specified projections, not implicit dictionary keys. Trimming requires its non-string predicate. |
| Reordering and end selection | `SL:SEQ-REVERSE`, `SL:SEQ-SORT`, `SL:SEQ-STABLE-SORT`, `SL:SEQ-TAKE-LAST`, `SL:SEQ-TRIM-RIGHT`, `SL:SEQ-TRIM` | Eager ordered result in the operation's output order, including typed empties. Stable sorting retains tie order; sorting still requires an applicable ordering test/key, and trimming requires a predicate. Stored order supplies no dictionary comparator. Sorting's key may be re-invoked across comparisons as specified below. |
| Multi-source | `SL:SEQ-CONCATENATE`, `SL:SEQ-INTERLEAVE`; secondary cross-reference: multi-source `SL:SEQ-MAP` (primary row: Mapping) | All sources of the same concrete ordered class yield an eager strict ordered result. Heterogeneous sources retain the lazy result representation, except when all
sources are built-in dictionaries, in which case the promotion rules above
apply. When every source has a concrete/eager reconstruction path, traversal and MAP callbacks nevertheless complete at call time; when any source takes a lazy path, traversal and callbacks are deferred. CONCATENATE is serial; INTERLEAVE and MAP use complete lockstep rounds and stop at the shortest source. Duplicate encounters do not affect traversal rounds. Zero-source INTERLEAVE returns NIL, with no inferred ordered type. |
| Nested pieces | `SL:SEQ-SPLIT`, `SL:SEQ-SPLIT-AT`, `SL:SEQ-SPLIT-WITH`, `SL:SEQ-PARTITION`, `SL:SEQ-PARTITION-BY` | Lazy outer sequence, with each piece reconstructed as an ordered dictionary only when the outer position exposing it is forced. No call-time source traversal, predicate calls, or Collector creation/accumulation/finalization. The outer container is never built by an ordered Collector. Split empty pieces are typed ordered empties; PARTITION adds no empty chunk. Successful forcing memoizes the same piece under EQ; failed forcing remains retryable under Chapter 4 without fallback. |
| Lazy views | `SL:SEQ-DROP-LAST`, `SL:SEQ-TREE-SEQ` | Always lazy for ordered input; no ordered reconstruction. DROP-LAST retains force-time lookahead even for n=0. TREE-SEQ retains its force-time branch/children callbacks and emits arbitrary nodes. |
| Suffix query | `SL:SEQ-MEMBER` | Search and its test/key calls occur at call time through a match or exhaustion; the result is a lazy suffix view or NIL, never an ordered dictionary. |
| Scalar queries and reduction | `SL:SEQ-LAST`, `SL:SEQ-FIND`, `SL:SEQ-FIND-IF`, `SL:SEQ-POSITION`, `SL:SEQ-POSITION-IF`, `SL:SEQ-COUNT`, `SL:SEQ-COUNT-IF`, `SL:SEQ-SEARCH`, `SL:SEQ-MISMATCH`, `SL:SEQ-EVERY`, `SL:SEQ-SOME`, `SL:SEQ-NOTEVERY`, `SL:SEQ-NOTANY`, `SL:SEQ-MIN`, `SL:SEQ-MAX`, `SL:SEQ-REDUCE` | Existing eager query rules, short-circuiting, defaults, conditions, and scalar or source-entry results. Positions are absolute stored-order indices, not keys. REDUCE and predicate-returning queries may return any object; no entry-only result restriction or uniqueness reconstruction applies. LAST/MIN/MAX and unseeded REDUCE retain their empty-input errors. |
| Explicit construction | `SL:SEQ-INTO`, `SL:SEQ-JOIN` | Target determines result. An ordered target eagerly accepts entries only, including actual emitted separators, and applies uniqueness across the complete joined stream. Unsupported ordered Collector options signal PROGRAM-ERROR. Explicit list or LAZY-SEQ conversion before mapping permits arbitrary mapped elements. LAZY-SEQ target keeps its deferred exception. |

For ordered nested results, the independent prefix/suffix forcing rules below
apply exactly as for a source with a reconstruction Collector: prefix forcing
does not reconstruct the suffix; suffix forcing continues the shared traversal.
For SPLIT-WITH the first false element is retained for the suffix and no later
predicate is called. Successful traversal and callbacks are shared, not restarted
on repeated observations. SPLIT retains its final piece and all empty pieces.
PARTITION-BY classifies adjacent source entries, not reconstructed chunk keys.

For ordered PARTITION, n and step measure the buffered source window before
uniqueness reconstruction, with the existing overlap/gap rules. Only actually
used padding elements are checked for entry type, at the affected chunk's force
time. Unused invalid padding elements are not rejected as elements (the PAD
argument's classification is still validated at call time). A padding key that
matches a buffered key replaces that association at its first position, so a
fully padded n-element window may have fewer than n resident keys. There is no
widening, extra padding to restore unique-key cardinality, or additional empty
chunk. A bad used padding element signals TYPE-ERROR with the ordinary retry
and no-fallback rules.

A **transforming operation** is eager on a concrete input — a list, vector, or
string — and produces a result of the same concrete type. On a lazy sequence
input, the same operation is lazy and produces a lazy sequence. On a hash table or
`SL:DICT` input, an operation in the built-in dictionary-preserving roster
specified below eagerly reconstructs the same built-in dictionary type, retaining
the selected associations; an operation in the built-in dictionary promotion
roster reconstructs an `SL:ORDERED-DICT` as specified below; and every other
operation retains its existing lazy behavior. In the latter case, the lazy
sequence's input elements are `SL:MAP-ENTRY` objects; an element-preserving
operation retains those entries, while an element-transforming operation such as
`SL:SEQ-MAP` yields whatever the callback returns. On an `SL:HASH-SET`
input, element-dropping operations (such as `SL:SEQ-FILTER` and
`SL:SEQ-REMOVE`) are eager and produce a hash set; element-changing operations
(such as `SL:SEQ-MAP`) are lazy and produce a lazy sequence (Chapter 9). Type
preservation requires eagerness for the operations to which it applies: the
operation materializes its result to reconstruct it in the input type. A
user-defined sequence type with a Collector (Chapter 4) is eager and calls its
Collector at call time, except where an operation entry specifies a different
timing. A user-defined sequence type without a Collector is lazy: the result is
a lazy sequence, deferred to force time. Splitting and partitioning operations
(Section 6.2.4) reconstruct pieces at force time even when a user-defined
Collector is present. `SL:SEQ-DROP-LAST` is also lazy for a user-defined sequence
type, regardless of whether it has a Collector; no Collector is invoked for
that lazy result. An operation determines whether a user
type has a Collector without signaling an error.

A user-defined sequence type that is a subclass of `SL:LAZY-SEQ` with a Collector
is not conforming: `SL:LAZY-SEQ` is sealed for construction, and direct
subclassing has unspecified consequences (Chapter 4).

**Vector element-type preservation roster.** For a vector source, the following
operations preserve the source's actual `ARRAY-ELEMENT-TYPE` when they select or
rearrange existing elements: `SL:SEQ-FILTER`, `SL:SEQ-REMOVE`,
`SL:SEQ-REMOVE-IF`, `SL:SEQ-TAKE`, `SL:SEQ-DROP`, `SL:SEQ-TAKE-WHILE`,
`SL:SEQ-DROP-WHILE`, `SL:SEQ-SUBSEQ`, `SL:SEQ-TAKE-NTH`, `SL:SEQ-TAKE-LAST`,
`SL:SEQ-DROP-LAST`, `SL:SEQ-REMOVE-DUPLICATES`, `SL:SEQ-DEDUPE`,
`SL:SEQ-TRIM-LEFT`, `SL:SEQ-TRIM-RIGHT`, `SL:SEQ-TRIM`, `SL:SEQ-REVERSE`,
`SL:SEQ-SORT`, and `SL:SEQ-STABLE-SORT`. For `SL:SEQ-SPLIT`,
`SL:SEQ-SPLIT-AT`, `SL:SEQ-SPLIT-WITH`, `SL:SEQ-PARTITION`, and
`SL:SEQ-PARTITION-BY`, this rule applies to each inner piece, not to a nested
outer container. Reconstruction passes the source's actual element type to the vector
Collector, while source traversal honors the active length; active length is
traversal state, not a Collector option. An empty result in this roster has the
same actual vector element type as its source. `SL:SEQ-PARTITION` checks each
actual padding element against that type; only a chunk containing an
incompatible padding element widens to a general vector, while every other
chunk remains specialized.

**Built-in dictionary-preserving roster.** For a built-in `hash-table` or
`SL:DICT` source, the following operations eagerly reconstruct a dictionary of
the same built-in type: `SL:SEQ-FILTER`, `SL:SEQ-REMOVE`, `SL:SEQ-REMOVE-IF`,
`SL:SEQ-TAKE`, `SL:SEQ-DROP`, `SL:SEQ-TAKE-WHILE`, `SL:SEQ-DROP-WHILE`,
`SL:SEQ-SUBSEQ`, `SL:SEQ-TAKE-NTH`, `SL:SEQ-TAKE-LAST`,
`SL:SEQ-REMOVE-DUPLICATES`, `SL:SEQ-DEDUPE`, `SL:SEQ-TRIM-LEFT`,
`SL:SEQ-TRIM-RIGHT`, and `SL:SEQ-TRIM`. The result preserves the source's
built-in dictionary type, hash-table test when applicable, and every retained
key/value association. Selection uses one coherent traversal view and any
predicate, test, or key callbacks run at call time; the resulting dictionary
has no promised order. This rule applies only to the built-in types and creates
no additional obligation for user-defined dicts. `SL:SEQ-DROP-LAST` is not in
this roster and retains its separate lazy dictionary behavior.

**Built-in dictionary promotion roster.** For a built-in `hash-table` or
`SL:DICT` source, `SL:SEQ-SORT`, `SL:SEQ-STABLE-SORT`, `SL:SEQ-REVERSE`,
`SL:SEQ-MAP`, `SL:SEQ-MAP-INDEXED`, `SL:SEQ-KEEP`, `SL:SEQ-MAPCAT`,
`SL:SEQ-SUBSTITUTE`, `SL:SEQ-SUBSTITUTE-IF`, `SL:SEQ-REDUCTIONS`,
`SL:SEQ-CONCATENATE`, `SL:SEQ-INTERLEAVE`, multi-source `SL:SEQ-MAP`,
`SL:SEQ-SPLIT`, `SL:SEQ-SPLIT-AT`, `SL:SEQ-SPLIT-WITH`,
`SL:SEQ-PARTITION`, and `SL:SEQ-PARTITION-BY` reconstruct an
`SL:ORDERED-DICT`. Key matching uses `SL:EQUALS`, not the source hash-table
test: keys distinct under that test but equivalent under `SL:EQUALS` coalesce.
For `SL:SEQ-SPLIT`, `SL:SEQ-SPLIT-AT`, `SL:SEQ-SPLIT-WITH`,
`SL:SEQ-PARTITION`, and `SL:SEQ-PARTITION-BY`, the outer result remains a lazy
sequence and each piece is reconstructed as an `SL:ORDERED-DICT` when forced.
`SL:SEQ-DROP-LAST`, `SL:SEQ-TREE-SEQ`, and `SL:SEQ-MEMBER` are lazy. This
roster does not apply to user-defined dicts or to `SL:PLIST-DICT-VIEW`, which
follow the Collector and protocol rules of Chapter 4.

For promoted operations that emit entries and then reconstruct them, collisions
may alter cardinality: the emitted stream has the operation's specified
semantics, and reconstruction then coalesces keys under `SL:EQUALS`. Promoted
mapping operations — `SL:SEQ-MAP`, `SL:SEQ-MAP-INDEXED`, `SL:SEQ-KEEP`,
`SL:SEQ-MAPCAT`, `SL:SEQ-SUBSTITUTE`, `SL:SEQ-SUBSTITUTE-IF`, and
`SL:SEQ-REDUCTIONS` — require every element emitted for reconstruction to be an `SL:MAP-ENTRY`; an
actual non-entry signals `TYPE-ERROR`, without fallback to a lazy result. For
`SL:SEQ-MAPCAT`, the callback returns a seqable whose flattened elements are
emitted for reconstruction; the entry requirement applies to those emitted
elements, not to the callback's return value.

**Normalize-then-reorder.** For `SL:SEQ-SORT`, `SL:SEQ-STABLE-SORT`, and
`SL:SEQ-REVERSE` in the promotion roster, the source is first normalized by one
call-time traversal into an `SL:ORDERED-DICT`: the first equivalent-key position
is retained and the last association supplies the resident key and value. The
operation reorders those unique resident entries and reconstructs a new
`SL:ORDERED-DICT`. `SL:SEQ-SORT` uses its ordering comparator;
`SL:SEQ-STABLE-SORT` retains tie order from the normalized stored order; and
`SL:SEQ-REVERSE` reverses that order. Thus the resident result of sorting is
sorted. For an unordered source, normalized traversal order is unspecified, so
reverse order and stable-sort tie order are likewise unspecified. A sort
comparator receives `SL:MAP-ENTRY` objects from the normalized dictionary, with
each key appearing exactly once. Normalization does not invoke sort `:KEY` or
`:TEST` callbacks, although it may invoke key hashing or equality behavior.

The vector roster is limited to selecting or rearranging source elements. For
vector inputs, element-changing operations, including `SL:SEQ-MAP`, `SL:SEQ-MAP-INDEXED`,
`SL:SEQ-KEEP`, `SL:SEQ-SUBSTITUTE`, `SL:SEQ-SUBSTITUTE-IF`,
`SL:SEQ-MAPCAT`, and `SL:SEQ-REDUCTIONS`, retain general-vector behavior and
do not infer a type from callback results. Multi-source operations follow the
multi-source result rules above, and explicit target construction is governed
by its target designator. String-specific behavior follows the rules above.

**Side-effect timing.** On a concrete input, a transforming operation runs its
callback at call time, and any condition the callback signals propagates to
the caller of the operation. On a lazy sequence, hash table, or `SL:DICT`
input, the callback runs at force time, and conditions propagate to the caller
that forces the result, except as specified for the built-in dictionary rosters
below. On an `SL:HASH-SET` input, element-dropping operations run their callback
at call time; element-changing operations run at force time. For a built-in
`hash-table` or `SL:DICT` input to the dictionary-preserving roster, selection
callbacks — predicates, tests, and keys — run at call time within the
operation's one traversal.

Except for the deferred nested operations specified below, for a single-source
operation in the promotion roster, traversal and callbacks run at call time.
For `SL:SEQ-CONCATENATE`, `SL:SEQ-INTERLEAVE`, and
multi-source `SL:SEQ-MAP`, promotion occurs only when every source is a built-in
dictionary — a `hash-table`, `SL:DICT`, or `SL:ORDERED-DICT` — and then
traversal and callbacks run at call time. If any source is not a built-in
dictionary but all sources have eager paths, callbacks run at call time although
the result is a lazy sequence; if any source is lazy, callbacks are deferred.
For promoted nested operations, the outer sequence is lazy and piece
reconstruction and its callbacks occur when that piece is forced. For
normalize-then-reorder operations, normalization runs at call time and any
sort or reverse callbacks run afterward at call time. `SL:ORDERED-DICT` follows
its dedicated matrix, and user-defined dicts follow the Collector and
operation-specific timing rules above.
`SL:SEQ-DROP-LAST` has no user callback: its eager string/vector branch
traverses and reconstructs at call time, while every other branch performs its
lookahead traversal at force time.

The operations `SL:SEQ-SPLIT`, `SL:SEQ-PARTITION`, and `SL:SEQ-PARTITION-BY`
defer traversal and callbacks to force time on every input; their return-type and
nesting rules are specified in their entries. `SL:SEQ-DROP-LAST` is eager only
for string and vector inputs. On every other input, including lists,
user-defined collections, dictionaries, hash tables, hash sets, and lazy
sequences, it returns a lazy sequence and retains its bounded lookahead behavior.

**Transforming operations — return types.** The return type of a transforming
operation depends on the input type:

| Input type | Return type |
|---|---|
| `list` | `list` |
| `vector` | `vector` (actual source element type for the vector-preserving roster; otherwise element type `T`) |
| `string` | `string` when every result element is a character; otherwise `vector` (element type `T`) |
| `hash-table` | same `hash-table` type for the built-in dictionary-preserving roster; `SL:ORDERED-DICT` for the promotion roster; lazy outer with `SL:ORDERED-DICT` inner pieces for nested promotion; lazy sequence for non-roster operations |
| `SL:ORDERED-DICT` | strict same ordered type for reconstruction; lazy outer/ordered inner nested pieces; explicit lazy views and scalar/target results follow the ordered policy matrix above |
| `SL:DICT` | `SL:DICT` for the built-in dictionary-preserving roster; `SL:ORDERED-DICT` for the promotion roster; lazy outer with `SL:ORDERED-DICT` inner pieces for nested promotion; lazy sequence for non-roster operations |
| `SL:HASH-SET` | hash set for element-dropping operations; lazy sequence for element-changing, forcing, multi-source, and nested-result operations (Chapter 9) |
| lazy sequence | lazy sequence |
| user sequence type with a Collector | the user type, via the Collector (Chapter 4) |
| user sequence type without a Collector | lazy sequence |

A `string` input widens to a general `vector` when any result element is not a
character. A vector-preserving operation retains the source's actual element
type because it selects or rearranges existing elements. Only
`SL:SEQ-PARTITION` may widen such a vector result, and only for a chunk whose
actual padding element does not fit that source type. Element-changing
operations continue to use a general vector even when the callback values
happen to fit a specialized source.

**Multi-source operations.** When every source of a sequence-producing
multi-source operation is the same concrete type (`list`, `vector`, or
`string`), the result is that type. When sources have different concrete
types, the result is a lazy sequence. When every source is a built-in
dictionary — `hash-table`, `SL:DICT`, or `SL:ORDERED-DICT` —
`SL:SEQ-CONCATENATE`, `SL:SEQ-INTERLEAVE`, and multi-source `SL:SEQ-MAP`
promote to `SL:ORDERED-DICT`; if the sources include built-in dictionaries but
not all are built-in dictionaries, the result is a lazy sequence. A vector result from a multi-source or
element-changing operation has element type `T`; no source element type is
inferred. When all sources are the same user-defined type with a Collector, the
result is that user type. When sources include different user-defined types, or
a user-defined type without a Collector, the result is a lazy sequence.

**Forcing operations — return types.** The forcing operations `SL:SEQ-SORT`,
`SL:SEQ-STABLE-SORT`, `SL:SEQ-REVERSE`, `SL:SEQ-TAKE-LAST`,
`SL:SEQ-TRIM-RIGHT`, and `SL:SEQ-TRIM` return the same type as their input for
`list`, `vector`, `string`, and lazy sequence. For a vector input in the
vector-preserving roster, the result uses its actual `ARRAY-ELEMENT-TYPE`.
A `hash-table`, `SL:DICT`, or
`SL:HASH-SET` input produces a lazy sequence unless the operation is in one of
the built-in dictionary rosters. For a preservation-roster operation, a
built-in dict input eagerly returns its same built-in dictionary type, including
for `SL:SEQ-TAKE-LAST`; hash-table test and retained associations are preserved
and result order is unspecified. For `SL:SEQ-SORT`, `SL:SEQ-STABLE-SORT`, and
`SL:SEQ-REVERSE`, a `hash-table` or `SL:DICT` input is promoted to
`SL:ORDERED-DICT` under the normalize-then-reorder rule. `SL:HASH-SET` retains
its lazy behavior for those operations. User-defined sequence types follow the
Collector rule: a type with a Collector is preserved; a type without one returns
a lazy sequence. A lazy sequence is the
default fallback when no concrete type is determined. The forcing operations
`SL:SEQ-MIN` and `SL:SEQ-MAX` return a value, not a sequence. `SL:SEQ-REDUCE`
returns a value. `SL:SEQ-INTO` and `SL:SEQ-JOIN` are construction operations
that return the target type named by their designator; they are not
type-preserving (Chapter 4). In this chapter, scalar queries are forcing in
that they are eager, but they are not members of the Section 6.2.5 forcing group.

**`SL:SEQ-DROP-LAST`.** On a string or vector input, `SL:SEQ-DROP-LAST` eagerly
traverses the active sequence length and returns a fresh mutable result of the
same type, containing all but the final *n* elements. This eager rule applies
when *n* is zero as well: the operation returns a fresh copy rather than reusing
the source. A vector result uses the source's actual `ARRAY-ELEMENT-TYPE`,
including for empty results and active fill-pointer vectors. On every other input
type — including lists, user-defined collections with or without a Collector,
hash tables, `SL:DICT`, `SL:HASH-SET`, and lazy sequences — the operation remains
lazy, performs no finiteness pre-scan, and retains the bounded lookahead rules of
its entry.

**Nested results.** For a `hash-table`, `SL:DICT`, or `SL:ORDERED-DICT`, each
of the five split/partition operators returns a lazy outer sequence with
`SL:ORDERED-DICT` inner pieces, including typed empty split pieces, as specified
in the applicable policy. `SL:SEQ-SPLIT` and `SL:SEQ-PARTITION` return a lazy
sequence as the outer container. For `list`, `vector`, and `string` inputs, each
non-empty piece preserves the input type. For a vector input, each piece uses
the source's actual element type when all its elements fit; for
`SL:SEQ-PARTITION`, only a chunk with incompatible actual padding widens to a
general vector. For `SL:HASH-SET`, the outer container and each piece are lazy
sequences (Chapter 9): a piece of a set is not a set.
For `SL:SEQ-SPLIT`, `SL:SEQ-SPLIT-AT`, and `SL:SEQ-SPLIT-WITH`, an empty piece
uses the same reconstruction representation as a non-empty piece: an empty
string remains a string, an empty vector retains the source's actual
`ARRAY-ELEMENT-TYPE`, an empty built-in-dictionary piece is an empty
`SL:ORDERED-DICT`, and an empty list or lazy-sequence piece is `NIL`.
`SL:SEQ-PARTITION` never emits an empty chunk, so this rule does not add one.
An empty piece in a lazy-sequence fallback is `NIL`, the empty lazy sequence
(Chapter 4), not an `SL:LAZY-SEQ` node. For `hash-table`, `SL:DICT`, and
`SL:ORDERED-DICT` inputs, the outer pair and its pieces for
`SL:SEQ-SPLIT-AT` and `SL:SEQ-SPLIT-WITH` are lazy outer results with
`SL:ORDERED-DICT` pieces. For a lazy-seq input, the outer pair is a lazy
sequence and its pieces are lazy sequences. For a user-defined input, the outer
pair is always a lazy sequence. When the source has a reconstruction Collector,
each piece uses that Collector to preserve the source type, including an empty
piece; without a Collector, each piece is a lazy sequence. The operation neither
queries nor probes whether the source Collector can contain pieces as elements,
and does not invoke that Collector to construct the outer pair.
The final piece of `SL:SEQ-SPLIT` is type-preserving, except for
`SL:HASH-SET`, where it is a lazy sequence; for `hash-table` and `SL:DICT`, it
is an `SL:ORDERED-DICT`. `SL:SEQ-SPLIT-AT` and `SL:SEQ-SPLIT-WITH` return a pair
— a two-element sequence whose elements are the prefix and suffix, with piece
types as specified above. The outer pair is a `list` for a `list` input and a
general `vector` for a `vector` input, including strings. For `SL:HASH-SET`, the
pair and its pieces are lazy sequences. `SL:SEQ-TREE-SEQ` always returns a lazy
sequence.

For `SL:SEQ-SPLIT-AT` and `SL:SEQ-SPLIT-WITH` on a `hash-table`, `SL:DICT`,
`SL:ORDERED-DICT`, or a user-defined source with a reconstruction Collector, the
call returns the lazy outer pair without source traversal, predicate invocation,
or Collector invocation. Each piece is materialized and reconstructed only when
the outer position exposing that piece
is forced. Forcing the first outer node reconstructs the prefix, not the suffix;
forcing the second outer node reconstructs the suffix. Under Chapter 4's node
forcing rules, observing the first node with `SL:SEQ-FIRST`, `SL:SEQ-EMPTYP`,
or `SL:SEQ-REST` forces that node. Obtaining its rest does not force the second
node; observing that rest does. Successful observations reuse the same piece
object under `EQ` and do not repeat its reconstruction. Traversal and callbacks
are shared between the pieces, not restarted for each observation. Conditions
from a piece's Collector propagate to the forcing caller without fallback; failed
forcing remains retryable under Chapter 4 and the callback rules below.

A padding element introduced by `SL:SEQ-PARTITION` that is not a character widens
a string chunk to a general `vector` under the widening rules above. For a vector
chunk, padding is checked against the source's actual element type and only an
incompatible padded chunk widens to a general vector.

**Reconstruction mechanism.** Type-preserving reconstruction is an
operation-level mechanism. The operation inspects each input type, determines
the result type under the return-type rules of this chapter, collects the
transformed elements, and reconstructs the result as the Collector protocol
(Chapter 4) specifies. The obligations of reconstruction are observable: the
result must be one the applicable Collector for the result type produces —
the same result type and element type, the same freshness, the same
accumulated order, and the same refusal and error behavior. Every
applicable Collector method, including user-defined and extension methods,
must take effect as Chapter 4 specifies. Subject to these obligations, the
internal means of reconstruction are unconstrained: an implementation may
invoke the Collector protocol or construct the result directly, provided the
outcome is indistinguishable to conforming programs from the result of
invoking the Collector protocol. Each source's class is considered for a
multi-source operation. When a result widens from a string to a general
vector, reconstruction dispatches on the widened type's Collector rather
than on the string source. String-to-vector widening is governed by the
designator-path Collector for the widened class, such as the vector
Collector with `:ELEMENT-TYPE T`; this is an exception to normal
reconstruction-path dispatch. Vector-preserving reconstruction instead
supplies the source's actual `ARRAY-ELEMENT-TYPE`; partition reconstruction
may choose the general vector Collector only for a chunk whose padding is
incompatible.
Instance-based reconstruction dispatch uses ordinary CLOS dispatch on the actual
source object. A method specialized on the source class is the usual route and
gives subclass inheritance; if the source object is itself a class object, an
applicable non-default primary method with an `EQL` specializer on that object
also counts. The intended operation path does not alter dispatch or filter
applicable methods.
`SL:SEQ-INTO` is not type-preserving: its purpose is to change types via a
designator, and it uses the `EQL`-on-class-object dispatch path (Chapter 4).

**Widening.** Strings widen to a general vector when a result is not character.
A vector-preserving operation retains the source's actual element type because
its selected and rearranged elements already come from that source. For a
vector-preserving vector result, the sole widening exception is
`SL:SEQ-PARTITION`: an actual padding element that does
not fit the source type widens only its padded chunk to a general vector. This
is compatibility checking against an existing source type, not inference of a
new specialized type. Lists and general vectors accommodate any element.
Element-changing operations and multi-source results remain general vectors or
lazy sequences under their existing rules. When no concrete type accommodates
the result, the operation returns a lazy sequence. A refusal
signaled by a Collector during reconstruction propagates at reconstruction time
— call time for eager reconstruction, force time for deferred reconstruction; the operation does not
fall back to returning a lazy sequence.

An empty result from an immutable target type (`SL:DICT`, `SL:HASH-SET`) may reuse
a standard empty object. An empty result from a mutable target type is freshly
allocated.

A per-element callback — a predicate, key, or function the operation invokes
with one element — runs exactly once for each element the operation's entry
requires that callback to examine (or per tuple for multi-source operations)
in each successful traversal of that element. A
pairwise-comparison callback — a `:TEST` argument invoked with two keyed
values, as in the sorting, searching, mismatch, duplicate-removal, and
adjacency operations — has no once-per-element guarantee. The `:KEY` function in
`SL:SEQ-SORT` and `SL:SEQ-STABLE-SORT` may be re-invoked on the same element
across comparisons; it is not cached. A callback
invocation that signals does not count toward this rule; the element position
remains retryable under Chapter 4's forcing rules for a lazy operation, and a retry re-invokes the
callback. Widening is determined after all callbacks have run; the callback is
not re-run for the widened type.

**Data-dependent return types.** The return type of a type-preserving
operation may depend on the data: `(SL:SEQ-MAP #'CHAR-CODE "abc")` returns a
`vector` of integers, widened from `string`, while
`(SL:SEQ-MAP #'CHAR-UPCASE "abc")` returns a `string`. For the vector-preserving
roster, the source's actual element type is selected before reconstruction;
callback-result data does not select a specialized type.

**Transforming roster.** The following operations are transforming — eager and
type-preserving on concrete input, lazy on lazy sequence input, and, on a
`hash-table` or `SL:DICT` input, governed by the built-in dictionary-preserving
and promotion rosters. The preservation roster eagerly returns the same
built-in dictionary type; the promotion roster returns `SL:ORDERED-DICT` or a
lazy outer sequence with `SL:ORDERED-DICT` pieces as applicable; operations in
neither roster remain lazy. On `SL:HASH-SET` input, element-dropping members of
this roster produce a hash set; element-changing members produce a lazy sequence
(Chapter 9): `SL:SEQ-MAP`, `SL:SEQ-FILTER`, `SL:SEQ-REMOVE`,
`SL:SEQ-REMOVE-IF`, `SL:SEQ-SUBSTITUTE`, `SL:SEQ-SUBSTITUTE-IF`,
`SL:SEQ-TAKE`, `SL:SEQ-DROP`, `SL:SEQ-TAKE-WHILE`, `SL:SEQ-DROP-WHILE`,
`SL:SEQ-SUBSEQ`, `SL:SEQ-KEEP`, `SL:SEQ-MAPCAT`, `SL:SEQ-TAKE-NTH`,
`SL:SEQ-INTERLEAVE`, `SL:SEQ-MAP-INDEXED`, `SL:SEQ-CONCATENATE`,
`SL:SEQ-REMOVE-DUPLICATES`, `SL:SEQ-DEDUPE`, `SL:SEQ-REDUCTIONS`, and
`SL:SEQ-TRIM-LEFT`. `SL:SEQ-MEMBER` is not a transforming operation: it always
returns a lazy sequence or `NIL`, regardless of input type.

The following operations are transforming with special return-type rules:
`SL:SEQ-SPLIT` and `SL:SEQ-PARTITION` (outer lazy sequence, pieces preserve
input type except that built-in dictionary pieces are `SL:ORDERED-DICT` and
`SL:HASH-SET` pieces are lazy sequences), `SL:SEQ-PARTITION-BY` (outer lazy
sequence, with the same piece rules), `SL:SEQ-SPLIT-AT` and
`SL:SEQ-SPLIT-WITH` (pair, with outer-pair widening for `string`; built-in
dictionary sources have a lazy outer pair with `SL:ORDERED-DICT` pieces;
user-defined sources have a lazy outer pair and Collector-preserved pieces when
a Collector is present; `SL:HASH-SET` has a lazy pair and lazy pieces),
`SL:SEQ-TREE-SEQ` (always a lazy sequence), and `SL:SEQ-DROP-LAST` (eager
string/vector result using its source type, lazy otherwise).

**Forcing roster.** The following forcing operations are type-preserving:
`SL:SEQ-SORT`, `SL:SEQ-STABLE-SORT`, `SL:SEQ-REVERSE`, `SL:SEQ-TAKE-LAST`,
`SL:SEQ-TRIM-RIGHT`, and `SL:SEQ-TRIM`. The following forcing operations
return a value, not a sequence: `SL:SEQ-LAST`, `SL:SEQ-COUNT`,
`SL:SEQ-COUNT-IF`, `SL:SEQ-MIN`, `SL:SEQ-MAX`, and `SL:SEQ-REDUCE`. The
construction operations `SL:SEQ-INTO` and `SL:SEQ-JOIN` return the target type
named by their designator.

### 6.1.2 Selected Region, Termination, and Non-Destructiveness

The **selected region** of a source for an operation is the elements selected by its
`:START`, `:END`, and `:FROM-END` arguments together with its traversal direction. When
no bounds are supplied, the selected region is the entire source.

No operation in this chapter modifies a sequence argument. The consequences of
caller-side modification while a Sophie operation may still traverse a source are
specified in Chapter 4.

**Termination.** No eagerness rule guarantees termination on an unbounded source.
Termination follows from each operation's dictionary entry. An operation that requires
the end of a source cannot terminate on an unbounded source (Chapter 5).

`SL:SEQ-LAST`, `SL:SEQ-COUNT`, `SL:SEQ-COUNT-IF`, `SL:SEQ-REDUCE`, `SL:SEQ-INTO`,
`SL:SEQ-JOIN`, `SL:SEQ-TAKE-LAST`, `SL:SEQ-MIN`, `SL:SEQ-MAX`, `SL:SEQ-REVERSE`,
`SL:SEQ-REMOVE-DUPLICATES`,
`SL:SEQ-SORT`, `SL:SEQ-STABLE-SORT`, and right or combined trimming require the complete
finite selected region; for `SL:SEQ-INTO` and `SL:SEQ-JOIN` this applies to a concrete target, the `LAZY-SEQ` target being the exception specified in Chapter 4. Front-traversing queries such as `SL:SEQ-FIND`,
`SL:SEQ-POSITION`, `SL:SEQ-EVERY`, `SL:SEQ-SOME`, `SL:SEQ-NOTEVERY`, `SL:SEQ-NOTANY`,
`SL:SEQ-SEARCH`, `SL:SEQ-MISMATCH`, and `SL:SEQ-MEMBER` stop when their answer is
determined. A search with `:FROM-END` true, a last-match operation, or an operation
whose answer requires the end may require the complete selected region. `SL:SEQ-SEARCH`
forces its pattern region completely and may traverse an unbounded subject without
finding a match. `SL:SEQ-MISMATCH` may continue without end when its sources never
establish a mismatch. A count or reduction requires the complete finite selected region.

**Freshness and empty results.** When an operation constructs or reconstructs a mutable
Common Lisp container — a nonempty list, vector, string, or hash table — the result's
top-level container is newly allocated and is not EQ to any input container from which
it was derived. Elements and immutable substructure may be shared. The empty list is
NIL and has no freshness guarantee. For immutable or persistent result types, including
SL:LAZY-SEQ, result identity is unspecified; an implementation may return any
observationally equivalent value, including an input for a no-op.

An empty vector result is a zero-length vector whose applicable
`ARRAY-ELEMENT-TYPE` follows the result rule (the source's actual type for a
vector-preserving result, and `T` for a general-vector result), an empty string
result is `""`, and an empty list result is `NIL`.

Operations concerned with keyed results or entry projection are specified in Chapter 9;
Chapter 6 operations may produce or consume `SL:MAP-ENTRY` objects (Chapter 4) as
ordinary elements.

### 6.1.3 Keyword Policy and Defaults

An operation accepts only the keywords in its Syntax. This policy is not an invitation
to accept additional keywords. Operation-specific keywords declared by an entry's Syntax
are outside the general policies below. An unrecognized keyword signals an error of type
`PROGRAM-ERROR`.

Where present, `:KEY` defaults to `#'IDENTITY`. Passing `:KEY NIL` is equivalent to
omitting `:KEY`; `NIL` is not a malformed function designator in this position. For
equality operations, `:TEST` defaults to `#'SL:EQUALS`. For sorting operations, `:TEST`
is an ordering predicate and defaults to `#'SL:LT`, as specified by the comparison
protocol in Chapter 7. These regimes apply to every operation in this chapter that
accepts `:TEST`, except where its entry explicitly overrides the default.

`:START` defaults to zero and `:END` defaults to the end of the source. `:FROM-END`
defaults to `NIL` and has the meaning specified by the operation. `:COUNT` defaults to
`NIL`, meaning unlimited. A count is a non-negative integer or `NIL`. For
trimming operations, the omitted predicate on a string defaults to the
implementation's character whitespace classification.

**Bounds.** A `:START` equal to the length of a finite source selects an empty region. A
`:START` greater than the length signals an error of type `TYPE-ERROR`. An `:END`
greater than the length of a finite source is treated as the length. An `:END` less than
`:START` signals an error of type `TYPE-ERROR`. The same rules govern regions designated
by `:START1` and `:END1`, and by `:START2` and `:END2`.

Bounds validation has two layers. Syntactic validation of non-integer bounds, a negative
`:START`, or an `:END` less than `:START` occurs at call time before source traversal.
Source-dependent validation of a `:START` beyond the length of a finite source
occurs only when the source is traversed: at force time for a lazy operation on a lazy
sequence, hash table, `SL:DICT`, or `SL:HASH-SET` input, and during eager traversal
otherwise. An unbounded source never triggers a source-dependent bounds error.

Bounds are interpreted against the source in its normal traversal order. Index-returning
operations return absolute source indices. `:FROM-END` means search from the end for
search operations, reverses reduction argument order for `SL:SEQ-REDUCE`, and selects
last occurrences for removal, substitution, and duplicate-removal where the entry
specifies. A supplied `:COUNT` limits the operation named by the entry.

Malformed function designators, predicates, tests, keys, counts, and bounds signal an
error at call time before source traversal. For a lazy operation, a non-seqable
primary source signals an error of type `TYPE-ERROR` at call time via dispatch;
a non-primary source signals an error of type `TYPE-ERROR` when traversal first
reaches it. For an eager operation, a non-seqable source signals an error of type
`TYPE-ERROR` at call time when traversal first reaches it. The trivially-empty
permission below is an exception for a result that is empty at construction.
Conditions signaled by a user callback or a Collector are not intercepted by the
operation.

A `:TEST` function used by an equality-based operation must be an equivalence relation:
reflexive, symmetric, and transitive. Undefined consequences follow if it is not.

**Size and step arguments.** `SL:SEQ-TAKE-NTH` and `SL:SEQ-PARTITION` require a positive
integer; a negative or non-integer argument signals an error of type `TYPE-ERROR`, and
zero signals an error of type `PROGRAM-ERROR`. `SL:SEQ-SPLIT-AT`, `SL:SEQ-DROP-LAST`,
and `SL:SEQ-TAKE-LAST` require a non-negative integer; a negative or non-integer
argument signals an error of type `TYPE-ERROR`, and zero is valid.

Size and step argument validation occurs at call time for all operations, including
always-lazy operations.

`SL:SEQ-MAP`, `SL:SEQ-SORT`, `SL:SEQ-STABLE-SORT`, `SL:SEQ-REVERSE`,
`SL:SEQ-CONCATENATE`, the four predicate operations `SL:SEQ-EVERY`, `SL:SEQ-SOME`,
`SL:SEQ-NOTEVERY`, and `SL:SEQ-NOTANY`, and `SL:SEQ-SUBSEQ` do not accept
`:START`, `:END`, `:FROM-END`, or `:COUNT`. `SL:SEQ-MAP` accepts no keywords.
`SL:SEQ-SORT` and `SL:SEQ-STABLE-SORT` accept only `:TEST` and `:KEY`.

### 6.1.4 Multi-Source Lockstep Traversal

The lockstep operations — `SL:SEQ-MAP`, `SL:SEQ-MISMATCH`, `SL:SEQ-EVERY`,
`SL:SEQ-SOME`, `SL:SEQ-NOTEVERY`, `SL:SEQ-NOTANY`, and `SL:SEQ-INTERLEAVE` —
traverse in lockstep. At each step, the next node of each source
is forced from left to right before the predicate or function is invoked. Traversal
stops as soon as any source is exhausted; remaining sources are not read at that step.
Invocation occurs after all sources for the current step have been forced, and only when
no source was exhausted. Other multi-source operations (`SL:SEQ-SEARCH`, `SL:SEQ-CONCATENATE`,
`SL:SEQ-JOIN`, and `SL:SEQ-SPLIT`) traverse serially as specified in their
entries and Section 6.1.5. The same rule applies to multi-source operations in
other chapters, including `SL:DICT-ZIPMAP` in Chapter 9.

`SL:SEQ-MISMATCH` must distinguish simultaneous exhaustion from one source being a
proper prefix of the other. When one source exhausts, it forces the other source's
corresponding node to make that determination. The exhausted source's end is detected
first; the other source's node is then forced. This exception is limited to the
exhaustion check and does not permit reading beyond the single node needed.

### 6.1.5 Dispatch, Traversal Views, and Extensibility

Every operation labeled "Generic Function" is a CLOS generic function that dispatches on
its primary sequence argument, the subject. The standardized methods specified in each
entry's Dictionary Conventions are required; whether an implementation realizes them as
distinct specialized methods or as a single method specialized on `T` is an
implementation detail.

There is no `SL:SEQ` traversal facade. Each operation must establish and retain one
coherent traversal view for each source. Direct primitive calls on an unordered
collection establish independent views, as specified in Chapter 4; an operation must not
combine incompatible views. The sequence of seq protocol primitive calls used by an
operation is unspecified, as it is for `SL:DOSEQ` in Chapter 4. For an unordered
source, the elements an operation selects, and any index it returns, are relative to
the operation's retained traversal view; two calls on the same unordered source may
observe different views and return different results.

**Traversal timing.** On a lazy sequence input, lazy operations compose without
materializing intermediate collections: forcing `(SL:SEQ-TAKE n (SL:SEQ-MAP f source))`
forces only the nodes needed for the first *n* results. A lazy operation on a lazy
sequence, hash table, `SL:DICT`, or `SL:HASH-SET` input defers traversal to force
time, except that a member of either built-in dictionary roster traverses and
reconstructs a built-in hash table or `SL:DICT` at the time specified for that
roster: call time for single-source promotion and preservation, and piece force
time for nested promotion. The operation-specific and multi-source timing rules in Section 6.1.1 govern
the timing of traversal for all operations. Subject to those rules, a lazy
operation on a concrete input or eager `SL:HASH-SET` input, and every eager
operation — including forcing, query, and construction operations and the query
part of a combined operation such as `SL:SEQ-MEMBER` — traverses each source
that traversal reaches during the call. The
rules of Section 6.1.1 determine the timing for user-defined sequence types.

A multi-source operation traverses each source at most once per operation, in argument
order, and only when traversal first reaches it. A serial operation such as
`SL:SEQ-CONCATENATE` reaches sources one at a time as each preceding source is
exhausted; when the first source is unbounded, later sources are never reached. A
lockstep operation reaches all sources at the first step, from left to right.

Conditions signaled during traversal or by callbacks propagate to the caller of an eager
operation, and from the eager part of a combined operation to the caller of that
operation. Conditions from the lazy part of a lazy operation propagate to the caller
that forces the result.

**Trivially empty results.** For a lazy or eager operation whose result is trivially
empty at construction time, such as `(SL:SEQ-TAKE 0 source)`, the specification does
not require source validation. The operation may return an empty result without traversing the
source. When the result is not trivially empty, normal validation applies. This
short-circuit permission takes precedence over an operation's source-validation promise, but not over
argument validation: malformed function designators, predicates, tests, keys, counts,
and bounds are still validated at call time.

**Non-standard dispatch.** `SL:SEQ-INTO` and `SL:SEQ-JOIN` take a target designator as
their first argument and dispatch on their source argument. `SL:SEQ-SEARCH` takes a
pattern as its first source and dispatches on its sequence argument, the subject; the
pattern is forced completely before the search begins. `SL:SEQ-INTERLEAVE` takes `&REST`
sources with no required argument; whether it is a generic function dispatching
on a required first source or a function with an `&REST` surface is an
implementation detail. An invocation with no sources returns an empty result
without traversal.

**Extensibility.** The `SL:SEQ-*` operation generic functions are closed to user methods
(Chapter 1). A user-defined type participates by defining the mandatory seq primitives
`SL:SEQABLEP`, `SL:SEQ-EMPTYP`, `SL:SEQ-FIRST`, and `SL:SEQ-REST` (Chapter 4),
optionally `SL:SEQ-REF` and `SL:SEQ-LENGTH`, and, if it requires type-preserving
reconstruction, an applicable non-default primary reconstruction-path
`SL:MAKE-COLLECTOR-FOR` method for the source object (usually specialized on
its class; when the source is itself a class object, an applicable non-default
primary method with an `EQL` specializer also counts) (Chapter 4).

**Element classification.** The element-dropping, element-changing, and ordering classifications, including their hash-set consequences, are defined in Section 6.1.1.

## 6.2 Dictionary

Notes and examples for this chapter appear in Appendix D.

**Dictionary Conventions:** Each entry incorporates the dedicated ordered-dictionary matrix in Section 6.1.1 for ordered sources or targets, including its entry-type errors, uniqueness cardinality, and timing exceptions. Unless an entry says otherwise, every generic function in this chapter dispatches on its primary sequence parameter. Standardized methods specialize on `list` and `vector` (the latter including strings); a `T` method supplies traversal for any other seqable source and signals `TYPE-ERROR` when the source is not seqable. All other required parameters are unspecialized. The standardized methods are closed; user-defined seqable types participate through the Chapter 4 seq protocol, not by adding `SL:SEQ-*` methods.

### 6.2.1 Queries and Scalar Results
The query operations in this section inspect seqable sources and return values rather than type-preserving collections, except that `SL:SEQ-MEMBER` returns a lazy sequence when it finds a match. A query is eager: traversal that the operation requires takes place during the call, including traversal of a lazy sequence. A query forces only as much of each source as its answer requires and may stop as soon as that answer is determined, as described in Section 6.1.2.

### SL:SEQ-LAST _Generic Function_

**Name:** `SL:SEQ-LAST`, Generic Function

**Syntax:**
`(SL:SEQ-LAST` *source* `)` → *element*

**Arguments and Values:**
- *source* — a seqable object.
- *element* — the last element of *source*.

**Description:**
`SL:SEQ-LAST` is a scalar query under Section 6.1.1, including its ordered-dictionary policy matrix.

`SL:SEQ-LAST` returns the last element encountered in *source*; it cannot
terminate on an unbounded source.

**Exceptional Situations:** `SL:SEQ-LAST` signals an error of type `SIMPLE-ERROR` if *source* is empty.

**See Also:** Section 6.1.2; `SL:SEQ-FIRST` (Chapter 4).


### SL:SEQ-FIND, SL:SEQ-FIND-IF _Generic Functions_

**Name:** `SL:SEQ-FIND`, `SL:SEQ-FIND-IF`, Generic Functions

**Syntax:**
`(SL:SEQ-FIND` *item source* `&key` *test key start end from-end* `)` → *element*
`(SL:SEQ-FIND-IF` *predicate source* `&key` *key start end from-end* `)` → *element*

**Arguments and Values:**
- *item* — the object to compare with source elements.
- *predicate* — a usable function designator.
- *source* — a seqable object.
- *test* — a usable function designator, defaulting to `#'SL:EQUALS`.
- *key* — a usable function designator, defaulting to `#'IDENTITY`; `NIL` is equivalent to omission.
- *start*, *end*, and *from-end* — bounds and direction described in Section 6.1.3.
- *element* — the first matching source element in the selected direction, or `NIL`.
For `SL:SEQ-FIND`, *test* is called as `(funcall test item keyed-source-element)` — *item* is the first argument. For `SL:SEQ-FIND-IF`, *predicate* is called with the keyed source element.

**Description:**
`SL:SEQ-FIND` and `SL:SEQ-FIND-IF` are scalar queries under Section 6.1.1, including its ordered-dictionary policy matrix.

Element selection and keyword semantics are as for `CL:FIND` and `CL:FIND-IF`, except for the Sophie-specific source, return-type, forcing, and error rules stated here.

Without `:FROM-END`, they stop at the first match; with `:FROM-END T`, they force as much as needed to determine the last match, which may be the complete selected region of a lazy source. They return the matching source element or `NIL`.

**Exceptional Situations:** None beyond the general rules in Sections 6.1.3 and 6.1.5.

**See Also:** Section 6.1.2; `SL:SEQ-POSITION`; `SL:SEQ-MEMBER`.


### SL:SEQ-POSITION, SL:SEQ-POSITION-IF _Generic Functions_

**Name:** `SL:SEQ-POSITION`, `SL:SEQ-POSITION-IF`, Generic Functions

**Syntax:**
`(SL:SEQ-POSITION` *item source* `&key` *test key start end from-end* `)` → *index-or-NIL*
`(SL:SEQ-POSITION-IF` *predicate source* `&key` *key start end from-end* `)` → *index-or-NIL*

**Arguments and Values:**
- *item*, *predicate*, *test*, and *key* — as described for `SL:SEQ-FIND`.
- *source* — a seqable object.
- *start*, *end*, and *from-end* — bounds and direction described in Section 6.1.3.
- *index-or-NIL* — an absolute source index, or `NIL` when no match exists.

**Description:**
`SL:SEQ-POSITION` and `SL:SEQ-POSITION-IF` are scalar queries under Section 6.1.1, including its ordered-dictionary policy matrix.

Element selection and keyword semantics are as for `CL:POSITION` and `CL:POSITION-IF`, except for the Sophie-specific source, return-type, forcing, and error rules stated here.

Without `:FROM-END`, they stop at the first match; with `:FROM-END T`, they force as much as needed to determine the last match, which may be the complete selected region of a lazy source. They return an absolute source index, including the `:START` offset, or `NIL`.

**Exceptional Situations:** None beyond the general rules in Sections 6.1.3 and 6.1.5.

**See Also:** Section 6.1.2; `SL:SEQ-FIND`; `SL:SEQ-MEMBER`.


### SL:SEQ-MEMBER _Generic Function_

**Name:** `SL:SEQ-MEMBER`, Generic Function

**Syntax:**
`(SL:SEQ-MEMBER` *item source* `&key` *test key* `)` → *lazy-seq-or-NIL*

**Arguments and Values:**
- *item* — the object to compare with source elements.
- *source* — a seqable object.
- *test* — a usable function designator, defaulting to `#'SL:EQUALS`.
- *key* — a usable function designator, defaulting to `#'IDENTITY`; `NIL` is equivalent to omission.
- *lazy-seq-or-NIL* — a lazy sequence beginning at the first match, or `NIL`.
The *key* function is applied to each source element reached, and *test* is called as `(funcall test item keyed-source-element)`.

**Description:**
`SL:SEQ-MEMBER` is a query whose result is always a lazy sequence or `NIL`, regardless of source type. It forces *source* through the first match or exhaustion at call time; the returned tail is forced only when that lazy sequence is consumed.

**Exceptional Situations:** None beyond the general rules in Sections 6.1.3 and 6.1.5.

**See Also:** Section 6.1.2; `SL:SEQ-FIND`; `SL:SEQ-POSITION`.


### SL:SEQ-COUNT, SL:SEQ-COUNT-IF _Generic Functions_

**Name:** `SL:SEQ-COUNT`, `SL:SEQ-COUNT-IF`, Generic Functions

**Syntax:**
`(SL:SEQ-COUNT` *item source* `&key` *test key start end from-end* `)` → *count*
`(SL:SEQ-COUNT-IF` *predicate source* `&key` *key start end from-end* `)` → *count*

**Arguments and Values:**
- *item*, *predicate*, *test*, and *key* — as described for `SL:SEQ-FIND`.
- *source* — a seqable object.
- *start*, *end*, and *from-end* — bounds and direction described in Section 6.1.3.
- *count* — a non-negative integer equal to the number of matches.

**Description:**
`SL:SEQ-COUNT` and `SL:SEQ-COUNT-IF` are scalar queries under Section 6.1.1, including its ordered-dictionary policy matrix.

`SL:SEQ-COUNT` and `SL:SEQ-COUNT-IF` count, respectively, equality matches and predicate matches; traversal direction does not change the count.

**Exceptional Situations:** None beyond the general rules in Sections 6.1.3 and 6.1.5.

**See Also:** Section 6.1.2; `SL:SEQ-REDUCE`.


### SL:SEQ-SEARCH _Generic Function_

**Name:** `SL:SEQ-SEARCH`, Generic Function

**Syntax:**
`(SL:SEQ-SEARCH` *pattern source* `&key` *test key start1 end1 start2 end2 from-end* `)` → *index-or-NIL*

**Arguments and Values:**
- *pattern* — a seqable object whose selected region is searched for as a whole.
- *source* — the seqable subject in which the pattern is sought.
- *test* — a usable function designator, defaulting to `#'SL:EQUALS`.
- *key* — a usable function designator, defaulting to `#'IDENTITY`; `NIL` is equivalent to omission.
- *start1* and *end1* — bounds for the pattern region.
- *start2* and *end2* — bounds for the subject region.
- *from-end* — whether the rightmost matching occurrence is selected.
- *index-or-NIL* — the absolute subject index of a match, or `NIL`.
The bounds and direction have the meanings specified in Section 6.1.3.

**Description:**
`SL:SEQ-SEARCH` is a scalar query under Section 6.1.1, including its ordered-dictionary policy matrix.

Subject matching and keyword semantics are as for `CL:SEARCH`, except for the Sophie-specific source, return-type, forcing, and error rules stated here.

The complete selected region of *pattern* is forced at call time before searching begins. The generic function dispatches on *source*, the subject, not on *pattern*. Subject traversal then stops when the answer is determined; the result is an absolute subject index, including the `:START2` offset, or `NIL`.

**Method Signatures:**
- `((pattern T) (source list))` → an absolute subject index or `NIL`.
- `((pattern T) (source vector))` → an absolute subject index or `NIL`.
- `((pattern T) (source T))` → traversal over a seqable subject; signals an error of type `TYPE-ERROR` when the subject is not seqable.

**Exceptional Situations:** An unbounded pattern region does not terminate because the pattern is forced completely before the search begins.

**See Also:** Section 6.1.2; `SL:SEQ-MISMATCH`.


### SL:SEQ-MISMATCH _Generic Function_

**Name:** `SL:SEQ-MISMATCH`, Generic Function

**Syntax:**
`(SL:SEQ-MISMATCH` *source1 source2* `&key` *test key start1 end1 start2 end2 from-end* `)` → *index-or-NIL*

**Arguments and Values:**
- *source1* and *source2* — seqable objects traversed in lockstep.
- *test* — a usable function designator, defaulting to `#'SL:EQUALS`.
- *key* — a usable function designator, defaulting to `#'IDENTITY`; `NIL` is equivalent to omission.
- *start1*, *end1*, *start2*, and *end2* — source bounds.
- *from-end* — whether comparison proceeds from the ends to select the rightmost mismatch.
- *index-or-NIL* — the absolute index in *source1* of the first mismatch, or `NIL` when both selected regions exhaust simultaneously.
Bounds and direction are interpreted as specified in Section 6.1.3.

**Description:**
`SL:SEQ-MISMATCH` is a scalar lockstep query under Section 6.1.1 and Section 6.1.4.

Comparison and keyword semantics are as for `CL:MISMATCH`, except for the Sophie-specific source, return-type, forcing, and error rules stated here.

The operation forces the selected regions in lockstep at call time, from *source1* then *source2*, as specified in Section 6.1.4. If one source exhausts, it forces the other's corresponding node to distinguish simultaneous exhaustion from a proper prefix. With `:FROM-END T`, it uses the CLHS alignment rule and forces as much of both regions as establishing the rightmost mismatch requires. The result is `NIL` for simultaneous exhaustion or the absolute *source1* index of the mismatch or proper-prefix continuation. With `:FROM-END` true, the returned index follows `CL:MISMATCH` semantics: one plus the mismatching position in the forward direction.

**Exceptional Situations:** None beyond the general rules in Sections 6.1.3 and 6.1.5.

**See Also:** Section 6.1.2; `SL:SEQ-SEARCH`.


### SL:SEQ-EVERY, SL:SEQ-SOME, SL:SEQ-NOTEVERY, SL:SEQ-NOTANY _Generic Functions_

**Name:** `SL:SEQ-EVERY`, `SL:SEQ-SOME`, `SL:SEQ-NOTEVERY`, `SL:SEQ-NOTANY`, Generic Functions

**Syntax:**
`(SL:SEQ-EVERY` *predicate source* `&rest` *more-sources* `)` → *generalized-boolean*
`(SL:SEQ-SOME` *predicate source* `&rest` *more-sources* `)` → *value-or-NIL*
`(SL:SEQ-NOTEVERY` *predicate source* `&rest` *more-sources* `)` → *generalized-boolean*
`(SL:SEQ-NOTANY` *predicate source* `&rest` *more-sources* `)` → *generalized-boolean*

**Arguments and Values:**
- *predicate* — a usable function designator.
- *source* and *more-sources* — one or more seqable objects.
- *generalized-boolean* — `T` or `NIL`.
- *value-or-NIL* — the first non-`NIL` value returned by *predicate*, or `NIL`.

**Description:**
`SL:SEQ-EVERY`, `SL:SEQ-SOME`, `SL:SEQ-NOTEVERY`, and `SL:SEQ-NOTANY` are scalar lockstep queries under Section 6.1.1 and Section 6.1.4. They short-circuit on the predicate result that determines the answer or when a source is exhausted: `EVERY` returns `NIL` at the first false result and `T` on exhaustion; `SOME` returns the first non-`NIL` predicate value and `NIL` on exhaustion; `NOTEVERY` returns `T` at the first false result and `NIL` on exhaustion; and `NOTANY` returns `NIL` at the first true result and `T` on exhaustion.

**Exceptional Situations:** None beyond the general rules in Sections 6.1.3 and 6.1.5.

**See Also:** Section 6.1.4.


### SL:SEQ-MIN _Generic Function_

**Name:** `SL:SEQ-MIN`, Generic Function

**Syntax:**
`(SL:SEQ-MIN` *source* `&key` *key default* `)` → *result*

**Arguments and Values:**
- *source* — a seqable object.
- *key* — a usable function designator, defaulting to `#'IDENTITY`; `NIL` is equivalent to omission.
- *default* — a value returned when the selected source is empty, if supplied.
- *result* — either the source element whose keyed value is least under `SL:COMPARE`, or the supplied *default* value when the selected source is empty.

**Description:**
`SL:SEQ-MIN` is a scalar query under Section 6.1.1, including its ordered-dictionary policy matrix.

`SL:SEQ-MIN` applies *key* and returns the source element with the least keyed value under `SL:COMPARE`, or the supplied *default* for an empty source. Equivalent keyed values may select any one of their elements.

**Exceptional Situations:** `SL:SEQ-MIN` signals an error of type `SIMPLE-ERROR` if the source is empty without a supplied *default*, or if `SL:COMPARE` reports an incomparable pair of keys.

**See Also:** Section 6.1.2; `SL:SEQ-MAX`; Chapter 7.


### SL:SEQ-MAX _Generic Function_

**Name:** `SL:SEQ-MAX`, Generic Function

**Syntax:**
`(SL:SEQ-MAX` *source* `&key` *key default* `)` → *result*

**Arguments and Values:**
- *source*, *key*, and *default* — as described for `SL:SEQ-MIN`.
- *result* — either the source element whose keyed value is greatest under `SL:COMPARE`, or the supplied *default* value when the selected source is empty.

**Description:**
`SL:SEQ-MAX` is a scalar query under Section 6.1.1, including its ordered-dictionary policy matrix.

`SL:SEQ-MAX` applies *key* and returns the source element with the greatest keyed value under `SL:COMPARE`, or the supplied *default* for an empty source. Equivalent keyed values may select any one of their elements.

**Exceptional Situations:** `SL:SEQ-MAX` signals an error of type `SIMPLE-ERROR` if the source is empty without a supplied *default*, or if `SL:COMPARE` reports an incomparable pair of keys.

**See Also:** Section 6.1.2; `SL:SEQ-MIN`; Chapter 7.


### SL:SEQ-REDUCE _Generic Function_

**Name:** `SL:SEQ-REDUCE`, Generic Function

**Syntax:**
`(SL:SEQ-REDUCE` *function source* `&key` *key start end from-end initial-value* `)` → *value*

**Arguments and Values:**
- *function* — a usable function designator that combines an accumulator and an element.
- *source* — a seqable object.
- *key* — a usable function designator, defaulting to `#'IDENTITY`; `NIL` is equivalent to omission.
- *start*, *end*, and *from-end* — the selected region and direction described in Section 6.1.3.
- *initial-value* — an optional starting accumulator. Its presence is determined by whether the keyword is supplied; a supplied `NIL` is an initial accumulator, not an omission.
- *value* — the final accumulator value.

**Description:**
`SL:SEQ-REDUCE` is a scalar query under Section 6.1.1, including its ordered-dictionary policy matrix.

Reduction semantics are as for `CL:REDUCE`, except that *key* is applied to each source element and the presence of `:INITIAL-VALUE` is determined by keyword supply, so a supplied `NIL` is an initial accumulator.

The operation forces the complete finite selected region at call time, including a lazy source. An empty selected region returns the supplied initial value, or signals an error when none was supplied; a one-element region without an initial value returns its keyed element without calling *function*. `:FROM-END` changes traversal direction and reduction argument order as specified here. The operation does not terminate on an unbounded selected region.

**Exceptional Situations:** `SL:SEQ-REDUCE` signals an error of type `SIMPLE-ERROR` for an empty selected region when no *initial-value* is supplied.

**See Also:** Section 6.1.2; `SL:SEQ-REDUCTIONS`.


### 6.2.2 Transforming Operations

### SL:SEQ-MAP _Generic Function_

**Name:** `SL:SEQ-MAP`, Generic Function

**Syntax:** `SL:SEQ-MAP function sequence &rest more-sequences → result`

**Arguments and Values:** *function* is a usable function designator. It is
called with one element from each source. *sequence* and every member of *more-sequences* are seqable objects. There
must be at least one source. The result is a sequence containing the values returned by *function*.

**Description:**
`SL:SEQ-MAP` is an element-changing transforming operation under Section 6.1.1, including its ordered-dictionary policy matrix.

Maps the sources in lockstep. At each position, the function
receives one element from each source, in source argument order. Traversal stops as soon as any source is exhausted, and
no function call is made for an incomplete tuple. Result elements occur in the order of the tuples that produced them.

A hash table, `SL:DICT`, or `SL:ORDERED-DICT` contributes `SL:MAP-ENTRY` objects as source elements. A callback result need not itself be seqable. For ordered reconstruction it must be an entry; for other result representations the applicable result policy governs acceptance.

**Exceptional Situations:** Signals an error of type `PROGRAM-ERROR` if no source is supplied.

**See Also:** Section 6.1.1; `SL:SEQ-MAP-INDEXED`; `SL:SEQ-MAPCAT`.


### SL:SEQ-MAP-INDEXED _Generic Function_

**Name:** `SL:SEQ-MAP-INDEXED`, Generic Function

**Syntax:** `SL:SEQ-MAP-INDEXED function seq → result`

**Arguments and Values:** *function* is a usable function designator. It is
called with two arguments: a zero-based integer index and an element. *seq* is a seqable object. The result is a sequence
of the values returned by *function*.

**Description:**
`SL:SEQ-MAP-INDEXED` is an element-changing transforming operation under Section 6.1.1, including its ordered-dictionary policy matrix.

Calls *function* once for each source element, passing the
source position and then the element. The first element has index zero, and the index increases by one for each element
traversed. The index is not affected by any operation composed outside
`SL:SEQ-MAP-INDEXED`.

For a hash table, `SL:DICT`, or `SL:ORDERED-DICT`, the element passed to *function* is an
`SL:MAP-ENTRY`. The result contains callback values, not source elements.

**Exceptional Situations:** None beyond the general rules in Sections 6.1.3 and 6.1.5.

**See Also:** Section 6.1.1; `SL:SEQ-MAP`.


### SL:SEQ-FILTER _Generic Function_

**Name:** `SL:SEQ-FILTER`, Generic Function

**Syntax:** `SL:SEQ-FILTER predicate sequence &key from-end start end key count → result`

**Arguments and Values:** *predicate* is a usable one-argument function
designator. *sequence* is seqable. *key* is a usable function designator or
`NIL`, with the default specified in Section 6.1.3. *start*, *end*, and *count*
have the bounds and count meanings specified there. *from-end* is a generalized boolean.

**Description:**
`SL:SEQ-FILTER` is an element-dropping transforming operation under Section 6.1.1, including its ordered-dictionary policy matrix. For a vector source, it reconstructs the result with the source's actual `ARRAY-ELEMENT-TYPE`, including when the selected result is empty.

For a built-in `hash-table` or `SL:DICT` source, this operation uses the
built-in dictionary-preserving roster: it establishes one traversal view and
traverses at call time, applying its predicate and key according to the callback rules,
and returns the same built-in dictionary type with the retained associations. A
hash-table result preserves the source test; dictionary result order is
unspecified. This rule does not add an obligation for user-defined dicts.

Selects the region designated by *start* and *end*; elements outside that region are omitted regardless of whether they match. Within the region it retains each element for which
`(funcall predicate (funcall key element))` is true. Retained elements are the
original elements, in source order. Without *count*, all matching elements are retained. A non-`NIL` *count* limits the
number of retained matches, not the number of rejected elements.

With `:FROM-END NIL`, traversal stops after *count* matches have been retained when *count* is non-`NIL`. With
`:FROM-END T`, the operation retains the last *count* matching elements in the selected region and emits those retained
elements in their original source order. It must traverse far enough to identify those last matches. When *count* is
`NIL`, `:FROM-END` does not change the returned result; it may change the direction in which elements are traversed and therefore the order of callback side effects. When *count* is positive and the source is unbounded, `:FROM-END T` does not terminate unless the selected region is bounded. When
*count* is zero, the result is empty and no source element is traversed.

**Exceptional Situations:** None beyond the general rules in Sections 6.1.3 and 6.1.5.

**See Also:** Section 6.1.1; `SL:SEQ-REMOVE`; `SL:SEQ-KEEP`.


### SL:SEQ-KEEP _Generic Function_

**Name:** `SL:SEQ-KEEP`, Generic Function

**Syntax:** `SL:SEQ-KEEP function seq → result`

**Arguments and Values:** *function* is a usable one-argument function
designator. *seq* is seqable. The result contains the non-`NIL` values returned by *function*.

**Description:**
`SL:SEQ-KEEP` is an element-changing transforming operation under Section 6.1.1, including its ordered-dictionary policy matrix.

Applies *function* to each source element and emits each
non-`NIL` returned value. A `NIL` return value is omitted; the source element that produced it is not emitted. Result
values retain source order.

If *function* returns a value that is not compatible with a concrete string, reconstruction widens the result as
specified in Section 6.1.1. The operation does not test the original element; it tests the callback's returned value.

**Exceptional Situations:** None beyond the general rules in Sections 6.1.3 and 6.1.5.

**See Also:** Section 6.1.1; `SL:SEQ-FILTER`; `SL:SEQ-REMOVE`.


### SL:SEQ-REMOVE, SL:SEQ-REMOVE-IF _Generic Functions_

**Name:** `SL:SEQ-REMOVE`, `SL:SEQ-REMOVE-IF`, Generic Functions

**Syntax:** `SL:SEQ-REMOVE item sequence &key test key start end from-end count → result`

`SL:SEQ-REMOVE-IF predicate sequence &key key start end from-end count → result`

**Arguments and Values:** For `SL:SEQ-REMOVE`, *item* is the value to match and
*test* is a two-argument equality predicate. For `SL:SEQ-REMOVE-IF`, *predicate* is a usable one-argument function
designator. *sequence* is seqable. *key*, *start*, *end*, *from-end*, and *count* have the meanings and defaults
specified in Section 6.1.3. The result contains the elements not removed.

**Description:**
Element removal and keyword semantics are as for `CL:REMOVE` and `CL:REMOVE-IF`, except for the Sophie-specific source, return-type, forcing, and error rules stated here.

`SL:SEQ-REMOVE` and `SL:SEQ-REMOVE-IF` are element-dropping transforming operations under Section 6.1.1, including its ordered-dictionary policy matrix. For a vector source, each reconstructs the result with the source's actual `ARRAY-ELEMENT-TYPE`, including when the selected result is empty.

For a built-in `hash-table` or `SL:DICT` source, this operation uses the
built-in dictionary-preserving roster: it establishes one traversal view and
traverses at call time, applying its predicate, test, and key according to the
callback rules, and returns the same built-in dictionary type with the retained
associations. A hash-table result preserves the source test; dictionary result
order is unspecified. This rule does not add an obligation for user-defined
dicts.

With `:FROM-END T` and a positive `:COUNT`, the operation must traverse the complete finite selected region before producing results; it does not terminate on an unbounded source. With `:COUNT 0`, no matching callback is invoked; the result is a copy of the source with the selected region unchanged. `:START` and `:END` bound the search region, not the result; the result includes elements outside the selected region. For mutable result types it is freshly allocated, for immutable result types identity is unspecified, and the source is traversed as required for reconstruction.

**Exceptional Situations:** None beyond the general rules in Sections 6.1.3 and 6.1.5.

**See Also:** Section 6.1.1; `SL:SEQ-FILTER`; `SL:SEQ-KEEP`.


### SL:SEQ-SUBSTITUTE, SL:SEQ-SUBSTITUTE-IF _Generic Functions_

**Name:** `SL:SEQ-SUBSTITUTE`, `SL:SEQ-SUBSTITUTE-IF`, Generic Functions

**Syntax:** `SL:SEQ-SUBSTITUTE newitem olditem sequence &key test key start end from-end count → result`

`SL:SEQ-SUBSTITUTE-IF newitem predicate sequence &key key start end from-end count → result`

**Arguments and Values:** *newitem* is the value supplied for each selected
match. In `SL:SEQ-SUBSTITUTE`, *olditem* is matched using *test* after *key* is applied. In
`SL:SEQ-SUBSTITUTE-IF`, *predicate* receives the keyed value. *sequence* is seqable. The other
arguments have the meanings and defaults in Section 6.1.3.

**Description:**
Element substitution and keyword semantics are as for `CL:SUBSTITUTE` and `CL:SUBSTITUTE-IF`, except for the Sophie-specific source, return-type, forcing, and error rules stated here.

`SL:SEQ-SUBSTITUTE` and `SL:SEQ-SUBSTITUTE-IF` are element-changing transforming operations under Section 6.1.1, including its ordered-dictionary policy matrix.

With `:FROM-END T` and a positive `:COUNT`, the operation must traverse the complete finite selected region before producing results; it does not terminate on an unbounded source. With `:COUNT 0`, no matching callback is invoked; the result is a copy of the source with the selected region unchanged. `:START` and `:END` bound the search region, not the result; the result includes elements outside the selected region. For mutable result types it is freshly allocated, for immutable result types identity is unspecified, and the source is traversed as required for reconstruction.

**Exceptional Situations:** None beyond the general rules in Sections 6.1.3 and 6.1.5.

**See Also:** Section 6.1.1; `SL:SEQ-REMOVE`.


### SL:SEQ-MAPCAT _Generic Function_

**Name:** `SL:SEQ-MAPCAT`, Generic Function

**Syntax:** `SL:SEQ-MAPCAT function seq → result`

**Arguments and Values:** *function* is a usable one-argument function
designator. *seq* is seqable. Each callback invocation returns a seqable object. The result contains the elements of all
callback results, concatenated in source order.

**Description:**
`SL:SEQ-MAPCAT` is an element-changing transforming operation under Section 6.1.1, including its ordered-dictionary policy matrix.

Applies *function* to each source element. The sequence
returned by each invocation is traversed completely before the callback is applied to the next source element. Its
elements are emitted in their own order, and the groups are emitted in source order. The operation does not splice or
modify any callback result.

A callback result may be empty. An unbounded callback result prevents traversal from reaching later source elements. A
callback result that is itself lazy is forced only as its elements are needed.

**Exceptional Situations:** A callback result that is not seqable signals an error of type `TYPE-ERROR` when traversal first reaches it.

**See Also:** Section 6.1.1; `SL:SEQ-MAP`; `SL:SEQ-CONCATENATE`.


### SL:SEQ-TAKE, SL:SEQ-DROP _Generic Functions_

**Name:** `SL:SEQ-TAKE`, `SL:SEQ-DROP`, Generic Functions

**Syntax:** `SL:SEQ-TAKE n sequence → result`; `SL:SEQ-DROP n sequence → result`

**Arguments and Values:** *n* is a non-negative integer. *sequence* is
seqable. `SL:SEQ-TAKE` returns the first at most *n* elements. `SL:SEQ-DROP` skips the first *n* elements and returns
the remainder.

**Description:**
`SL:SEQ-TAKE` and `SL:SEQ-DROP` are element-dropping transforming operations under Section 6.1.1, including its ordered-dictionary policy matrix. For a vector source, each reconstructs the result with the source's actual `ARRAY-ELEMENT-TYPE`, including an empty result.

For a built-in `hash-table` or `SL:DICT` source, these operations use the
built-in dictionary-preserving roster: each establishes one traversal view and
traverses at call time, returning the same built-in dictionary type with the
retained associations. A hash-table result preserves the source test;
dictionary result order is unspecified. This rule does not add an obligation for
user-defined dicts.

`SL:SEQ-TAKE` emits no more than *n* source elements and does
not force elements after the retained prefix. It terminates on an unbounded source for every finite *n*. With *n* equal
to zero, it returns an empty result without reading a source element.

`SL:SEQ-DROP` consumes and discards up to the first *n* source elements, then
emits the remainder in source order. It forces every node it skips. It terminates after skipping a finite *n* on an
unbounded source, although consuming an unbounded remainder requires a subsequent consumer that can terminate.

**Exceptional Situations:** Signals an error of type `TYPE-ERROR` if *n* is negative or not an integer.

**See Also:** Section 6.1.1; `SL:SEQ-TAKE-WHILE`.


### SL:SEQ-TAKE-WHILE, SL:SEQ-DROP-WHILE _Generic Functions_

**Name:** `SL:SEQ-TAKE-WHILE`, `SL:SEQ-DROP-WHILE`, Generic Functions

**Syntax:** `SL:SEQ-TAKE-WHILE predicate sequence → result`; `SL:SEQ-DROP-WHILE predicate sequence → result`

**Arguments and Values:** *predicate* is a usable one-argument function
designator. *sequence* is seqable.

**Description:**
`SL:SEQ-TAKE-WHILE` and `SL:SEQ-DROP-WHILE` are element-dropping transforming operations under Section 6.1.1, including its ordered-dictionary policy matrix. For a vector source, each reconstructs the result with the source's actual `ARRAY-ELEMENT-TYPE`, including an empty result.

For a built-in `hash-table` or `SL:DICT` source, these operations use the
built-in dictionary-preserving roster: each establishes one traversal view and
traverses at call time, applying the predicate according to the callback rules,
and returns the same built-in dictionary type with the retained associations. A
hash-table result preserves the source test; dictionary result order is
unspecified. This rule does not add an obligation for user-defined dicts.

`SL:SEQ-TAKE-WHILE` emits the initial source elements for which
*predicate* returns true, stopping before the first false result. The false element and all following elements are
omitted. An empty source, or a source whose first predicate result is false, produces an empty result.

`SL:SEQ-DROP-WHILE` consumes the initial run for which *predicate* returns true
and emits the remainder beginning with the first false element. It does not apply the predicate to elements after that
first false element. Both operations preserve the normal traversal order.

Neither operation terminates on an unbounded source if it must establish a false result or the end of an all-true
source. `SL:SEQ-TAKE-WHILE` and
`SL:SEQ-DROP-WHILE` stop once their respective first nonmatching boundary is
known.

**Exceptional Situations:** None beyond the general rules in Sections 6.1.3 and 6.1.5.

**See Also:** Section 6.1.1; `SL:SEQ-TAKE`; `SL:SEQ-DROP`.


### SL:SEQ-SUBSEQ _Generic Function_

**Name:** `SL:SEQ-SUBSEQ`, Generic Function

**Syntax:** `SL:SEQ-SUBSEQ sequence start &optional end → result`

**Arguments and Values:** *sequence* is seqable. *start* is a non-negative
integer and is required. *end* is optional; when omitted or `NIL`, it denotes the end of the source. When supplied
and non-`NIL`, *end* is a non-negative integer. The selected region is the half-open interval
`[start,end)` in normal source order.

**Description:**
`SL:SEQ-SUBSEQ` is an element-dropping transforming operation under Section 6.1.1, including its ordered-dictionary policy matrix. For a vector source, it reconstructs the result with the source's actual `ARRAY-ELEMENT-TYPE`, including an empty result.

For a built-in `hash-table` or `SL:DICT` source, this operation uses the
built-in dictionary-preserving roster: it establishes one traversal view and
traverses at call time, returning the same built-in dictionary type with the
retained associations. A hash-table result preserves the source test;
dictionary result order is unspecified. This rule does not add an obligation for
user-defined dicts.

Returns the elements at positions *start* through one less
than *end*, preserving source order. If *end* is `NIL`, it returns the suffix beginning at *start*.

Bounds have the meanings specified in Section 6.1.3.

A finite explicit *end* allows a lazy result to stop after the requested region on an unbounded source. An omitted *end*
may return an unbounded suffix and therefore does not by itself terminate a subsequent full consumer.

**Exceptional Situations:** None beyond the general rules in Sections 6.1.3 and 6.1.5.

**See Also:** Section 6.1.1; `SL:SEQ-TAKE`; `SL:SEQ-DROP`.


### SL:SEQ-TAKE-NTH _Generic Function_

**Name:** `SL:SEQ-TAKE-NTH`, Generic Function

**Syntax:** `SL:SEQ-TAKE-NTH n seq → result`

**Arguments and Values:** *n* is a positive integer. *seq* is seqable. The
result contains source elements at zero-based positions 0, *n*, 2*n*, and so on.

**Description:**
`SL:SEQ-TAKE-NTH` is an element-dropping transforming operation under Section 6.1.1, including its ordered-dictionary policy matrix. For a vector source, it reconstructs the result with the source's actual `ARRAY-ELEMENT-TYPE`, including an empty result.

For a built-in `hash-table` or `SL:DICT` source, this operation uses the
built-in dictionary-preserving roster: it establishes one traversal view and
traverses at call time, returning the same built-in dictionary type with the
retained associations. A hash-table result preserves the source test;
dictionary result order is unspecified. This rule does not add an obligation for
user-defined dicts.

Emits the first source element, then skips *n* - 1 elements
before each subsequent emitted element. It preserves the source traversal order. Skipped elements are not emitted, but
they must be traversed to reach a later selected element. The operation works on an unbounded source; a bounded consumer
can obtain any finite prefix of its result.

**Exceptional Situations:** None beyond the general rules in Sections 6.1.3 and 6.1.5.

**See Also:** Section 6.1.1.


### SL:SEQ-REMOVE-DUPLICATES _Generic Function_

**Name:** `SL:SEQ-REMOVE-DUPLICATES`, Generic Function

**Syntax:** `SL:SEQ-REMOVE-DUPLICATES sequence &key test key start end from-end → result`

**Arguments and Values:** *sequence* is seqable. *test* is a two-argument
equality predicate and *key* is a function designator or `NIL`, with defaults specified in Section 6.1.3. *start*,
*end*, and *from-end* designate the selected region. The result contains one representative of each distinct keyed value
in that region, with retained source elements in source order.

**Description:**
`SL:SEQ-REMOVE-DUPLICATES` is an element-dropping transforming operation under Section 6.1.1, including its ordered-dictionary policy matrix. For a vector source, it reconstructs the result with the source's actual `ARRAY-ELEMENT-TYPE`, including an empty result. Unlike ordinary filtering, it must establish the complete finite selected region before the first result node can be produced.

For a built-in `hash-table` or `SL:DICT` source, this operation uses the
built-in dictionary-preserving roster: it establishes one traversal view and
traverses at call time, applying its test and key according to the callback
rules, and returns the same built-in dictionary type with the retained
associations. A hash-table result preserves the source test; dictionary result
order is unspecified. This rule does not add an obligation for user-defined
dicts.

In the default mode, the first source occurrence of each
keyed value is retained; for an unordered input, "first" means first in the traversal view established for the operation. A later element is omitted when `(funcall test retained-keyed-value later-keyed-value)` is true for a keyed value already retained. The source is not modified.

With `:FROM-END T`, the last source occurrence of each distinct keyed value is retained — for an unordered input, last in the operation's traversal view. Retained elements are still
emitted in normal source order. Regardless of mode, the operation must establish the
complete finite selected region before the first result node can be produced. It
does not terminate on an unbounded selected region. In default mode, the retained
representatives are then emitted in source order. Test and key callbacks are not
applied again solely because a result is reconstructed or widened.

**Exceptional Situations:** None beyond the general rules in Sections 6.1.3 and 6.1.5.

**See Also:** Section 6.1.1; `SL:SEQ-DEDUPE`.


### SL:SEQ-DEDUPE _Generic Function_

**Name:** `SL:SEQ-DEDUPE`, Generic Function

**Syntax:** `SL:SEQ-DEDUPE seq &key test → result`

**Arguments and Values:** *seq* is seqable. *test* is a two-argument predicate;
when omitted it has the equality default specified in Section 6.1.3. The result contains the first element of each run
of adjacent elements.

**Description:**
`SL:SEQ-DEDUPE` is an element-dropping transforming operation under Section 6.1.1, including its ordered-dictionary policy matrix. For a vector source, it reconstructs the result with the source's actual `ARRAY-ELEMENT-TYPE`, including an empty result.

For a built-in `hash-table` or `SL:DICT` source, this operation uses the
built-in dictionary-preserving roster: it establishes one traversal view and
traverses at call time, applying its test according to the callback rules, and
returns the same built-in dictionary type with the retained associations. A
hash-table result preserves the source test; dictionary result order is
unspecified. This rule does not add an obligation for user-defined dicts.

The first source element is emitted. Each subsequent element
is compared with the immediately preceding source element by `(funcall test preceding-element current-element)`, whether or not that predecessor was emitted. If the predicate is true, the current element
is omitted; otherwise it is emitted. Only adjacent duplicates
are collapsed. Nonadjacent equal elements are retained.

The operation keeps only one element of each adjacent run and requires local state. Producing a finite result prefix
terminates when traversal reaches enough distinct runs to satisfy that prefix. An infinite run of adjacent equivalent
elements does not terminate when a consumer requests a result beyond the first element of the run. For an unordered
`SL:HASH-SET`, adjacency is determined by the traversal view established for that operation; the result is nevertheless a
hash set under Section 6.1.1.

**Exceptional Situations:** None beyond the general rules in Sections 6.1.3 and 6.1.5.

**See Also:** Section 6.1.1; `SL:SEQ-REMOVE-DUPLICATES`.


### SL:SEQ-TRIM-LEFT _Generic Function_

**Name:** `SL:SEQ-TRIM-LEFT`, Generic Function

**Syntax:** `SL:SEQ-TRIM-LEFT sequence &key predicate → result`

**Arguments and Values:** *sequence* is seqable. *predicate* — a usable one-argument function designator. When omitted for a
string, the default is specified in Section 6.1.3. For a non-string input, *predicate* is required.
An explicitly supplied `NIL` is invalid.

**Description:**
`SL:SEQ-TRIM-LEFT` is an element-dropping transforming operation under Section 6.1.1, including its ordered-dictionary policy matrix. For a vector source, it reconstructs the result with the source's actual `ARRAY-ELEMENT-TYPE`, including an empty result.

For a built-in `hash-table` or `SL:DICT` source, this operation uses the
built-in dictionary-preserving roster: it establishes one traversal view and
traverses at call time, applying its predicate according to the callback rules,
and returns the same built-in dictionary type with the retained associations. A
hash-table result preserves the source test; dictionary result order is
unspecified. This rule does not add an obligation for user-defined dicts.

Removes the leading run of elements selected by *predicate*.
It emits the first element that is not selected and all following elements without applying
the test again. If every element is selected, the result is empty. The operation preserves the remaining elements and
their source order.

When *predicate* is a function designator, an element is selected when the
function returns a true value for that element.

**Exceptional Situations:** Signals an error of type `PROGRAM-ERROR` when *predicate* is omitted for a non-string input or when an explicitly supplied *predicate* is `NIL`.

**See Also:** Section 6.1.1; `SL:SEQ-TRIM-RIGHT`; `SL:SEQ-TRIM`.


### SL:SEQ-REDUCTIONS _Generic Function_

**Name:** `SL:SEQ-REDUCTIONS`, Generic Function

**Syntax:** `SL:SEQ-REDUCTIONS function seq &key initial-value → result`

**Arguments and Values:** *function* is a usable two-argument function
designator. It receives an accumulator followed by a source element and returns the next accumulator. *seq* is seqable.
*initial-value* is optional; its presence is determined by whether the keyword is supplied, so a supplied
`NIL` is an initial accumulator. The result is a sequence of intermediate
accumulator values.

**Description:**
`SL:SEQ-REDUCTIONS` is an element-changing transforming operation under Section 6.1.1, including its ordered-dictionary policy matrix.

Returns the running accumulator states, not only the final
state. If *initial-value* is supplied, it is the first result element, and the first source element is combined with it.
Each later result is produced by calling *function* with the preceding accumulator and the next source element. If
*initial-value* is omitted, the first source element is the first result element and reduction begins with the second
source element.

The callback is invoked once for each reduction step. Before reconstruction,
an empty source emits no states when no initial value is supplied, and emits
only *initial-value* when it is supplied. A supplied initial value makes the
emitted stream one element longer than the source; omission gives the same
emission count as source length. Ordered reconstruction can collapse duplicate
state keys and refuses any emitted non-entry, including a supplied NIL initial
value. It does not change the recurrence or callback count. The result on an
unbounded lazy source is unbounded, and a finite prefix can be obtained by a bounded consumer.

**Exceptional Situations:** None beyond the general rules in Sections 6.1.3 and 6.1.5.

**See Also:** Section 6.1.1; `SL:SEQ-REDUCE`.


### 6.2.3 Multi-Source Operations

### SL:SEQ-CONCATENATE _Generic Function_

**Name:** `SL:SEQ-CONCATENATE`, Generic Function

**Syntax:** `(SL:SEQ-CONCATENATE sequence &rest more-sources) → result`

**Arguments and Values:**

- *sequence* — a seqable object; the first source.
- *more-sources* — zero or more seqable objects. Each source is traversed in its
  normal traversal order.
- *result* — a sequence containing the elements of the sources in source
  order.

`SL:SEQ-CONCATENATE` is a multi-source transforming operation under Section 6.1.1, including its ordered-dictionary policy matrix. It traverses sources serially, exhausting each source before beginning the next; serial activation is specified in Section 6.1.5.

An unbounded first source prevents a later source from being traversed. Full
consumption of the result therefore does not terminate, and does not reach any
later source, when its first source is unbounded and cannot be exhausted. A
later source is reached only after every preceding source has been exhausted.

**Exceptional Situations:** None beyond the general rules in Sections 6.1.3 and 6.1.5.


### SL:SEQ-INTERLEAVE _Generic Function_

**Name:** `SL:SEQ-INTERLEAVE`, Generic Function

**Syntax:** `(SL:SEQ-INTERLEAVE &rest sources) → result`

**Arguments and Values:**

- *sources* — zero or more seqable objects.
- *result* — a sequence containing one element from each source per
  traversal round, in source order.

`SL:SEQ-INTERLEAVE` is a multi-source transforming operation under Section 6.1.1, including its ordered-dictionary policy matrix. It traverses sources in lockstep and does not produce a partial final round.

With no sources, the operation returns NIL — the empty lazy sequence (Chapter 4) — without traversal.

**Method Signatures:**

No standardized method signature is specified. Whether `SL:SEQ-INTERLEAVE`
is a generic function dispatching on a required first source or an ordinary
function with an `&REST` surface is an implementation detail under Section
6.1.5. A non-seqable source signals an error of type `TYPE-ERROR` when
traversal first reaches it.

**Exceptional Situations:** None beyond the general rules in Sections 6.1.3 and 6.1.5.

**See Also:** Section 6.1.1; Section 6.1.4; Section 6.1.5;
`SL:SEQ-CONCATENATE`; Chapter 4; Chapter 5; Chapter 9.


### 6.2.4 Splitting and Partitioning

### SL:SEQ-SPLIT _Generic Function_

**Name:** `SL:SEQ-SPLIT`, Generic Function

**Syntax:**

`(SL:SEQ-SPLIT` *sequence* `&key` *delimiter* *predicate* *test* `)` → *lazy-seq*

**Arguments and Values:**

- *sequence* — a seqable object.
- *delimiter* — a delimiter object. A seqable delimiter is used as a sequence;
  any other delimiter is treated as a sequence containing that one object.
- *predicate* — a one-argument function designator.
- *test* — a two-argument comparison function designator. It defaults to
  `#'SL:EQUALS` and applies only to delimiter matching.
- *lazy-seq* — a lazy sequence of pieces.

Exactly one of *delimiter* and *predicate* must be supplied. A `NIL` delimiter
is recognized as the empty sequence before scalar wrapping. Each emitted piece
is a sequence of the input type, except that a `hash-table`, `SL:DICT`, or
`SL:ORDERED-DICT` source yields an `SL:ORDERED-DICT` piece; for a vector input,
each inner piece uses the
source's actual `ARRAY-ELEMENT-TYPE`, including an empty piece. The outer result
is always a `lazy-seq`. For an `SL:HASH-SET` input, each piece is also a `lazy-seq`, as specified in Section
6.1.1.

**Description:**

Splits *sequence* at each selected boundary. On the delimiter path, the
sequence is scanned from left to right and the first delimiter occurrence at
each position is selected. Selected occurrences are non-overlapping and are
omitted from the pieces. On the predicate path, an element for which
*predicate* returns true is omitted and ends the current piece. Empty pieces, including pieces between adjacent delimiters or after a trailing
delimiter, are retained, and the final piece is emitted. An empty piece uses the
same reconstruction representation as a non-empty piece: strings remain strings,
vectors retain the source's actual `ARRAY-ELEMENT-TYPE`; a built-in-dictionary
piece is an `SL:ORDERED-DICT`; and list or lazy-sequence pieces are `NIL`; user-defined inputs follow their Collector contract.

The operation does not traverse *sequence* at call time; traversal, predicate calls, and delimiter matching occur when the corresponding result is forced. A seqable delimiter is forced on the first force to determine its length and contents; an unbounded delimiter does not terminate that determination.

On the delimiter path, *test* is called as `(funcall test delimiter-element source-element)` and defaults to `SL:EQUALS`; a scalar delimiter is a one-element sequence. A zero-length delimiter is invalid.

**Exceptional Situations:** Signals `PROGRAM-ERROR` when both or neither of *delimiter* and *predicate* are supplied, or when *test* is supplied on the predicate path. Signals `SIMPLE-ERROR` when the delimiter sequence is empty. A scalar `NIL` delimiter is known empty at call time and signals immediately; a seqable delimiter that is empty signals when the first result is forced.

**See Also:** Section 6.1.1; `SL:SEQ-SPLIT-AT`; `SL:SEQ-SPLIT-WITH`.


### SL:SEQ-SPLIT-AT _Generic Function_

**Name:** `SL:SEQ-SPLIT-AT`, Generic Function

**Syntax:**

`(SL:SEQ-SPLIT-AT` *n* *seq* `)` → *pair*

**Arguments and Values:**

- *n* — a non-negative integer.
- *seq* — a seqable object.
- *pair* — a pair whose first element is the prefix and whose second element is
  the suffix.

The prefix contains the first *n* elements of *seq*. The suffix contains every
remaining element. The pair and its pieces have the types prescribed by the
nested-results rules of Section 6.1.1: on a `list` or `vector` input the outer
pair is that input type when it can hold the pieces; on a vector input, each
piece uses the source's actual `ARRAY-ELEMENT-TYPE`, including an empty piece; on
a `string` input the outer pair is a `vector`, and both non-empty pieces are
strings; the empty-piece representation follows Section 6.1.1; on an
`SL:HASH-SET` input the pair and pieces are lazy sequences.

**Description:**
Returns the pair formed by cutting *seq* immediately before element *n*. If *n* is zero, the prefix is empty and the suffix is the complete sequence. If *n* is greater than the number of elements, the prefix is the complete sequence and the suffix is empty. Each empty piece uses the same reconstruction representation as its non-empty counterpart: strings remain strings, vectors retain the source's actual `ARRAY-ELEMENT-TYPE`, a built-in-dictionary piece is an `SL:ORDERED-DICT`, and list or lazy-sequence pieces are `NIL`; user-defined inputs follow their Collector contract.

The pair and its pieces share one traversal. The operation invokes no user
predicate. For a `hash-table`, `SL:DICT`, `SL:ORDERED-DICT`, or a user-defined source with a reconstruction Collector, the outer
pair is lazy and each piece is reconstructed on demand as specified in Section
6.1.1. Forcing the prefix position traverses at most the first *n* elements,
stopping earlier on exhaustion; for *n* zero it reads no source element.
It does not traverse the suffix to reconstruct the prefix. Forcing the suffix
position continues the shared traversal to exhaustion to reconstruct the suffix;
an unbounded suffix therefore prevents that force from terminating. Collector
creation, accumulation, and finalization occur at the corresponding piece's
force time, including for empty pieces, without an outer Collector eligibility
check or fallback.

**Exceptional Situations:** None beyond the general rules in Sections 6.1.3 and 6.1.5.

**See Also:** Section 6.1.1; `SL:SEQ-SPLIT`; `SL:SEQ-SPLIT-WITH`.


### SL:SEQ-SPLIT-WITH _Generic Function_

**Name:** `SL:SEQ-SPLIT-WITH`, Generic Function

**Syntax:**

`(SL:SEQ-SPLIT-WITH` *predicate* *seq* `)` → *pair*

**Arguments and Values:**

- *predicate* — a one-argument function designator.
- *seq* — a seqable object.
- *pair* — a pair whose first element is the prefix and whose second element is
  the suffix.

The prefix is the longest initial run of elements for which *predicate* returns
true. The suffix begins with the first element for which *predicate* returns
false and contains all remaining elements. The pair and its pieces have the
nested-result types specified in Section 6.1.1. In particular, a `vector` input
uses the source's actual `ARRAY-ELEMENT-TYPE` for each piece, including an empty
piece; a `string`
input produces a widened vector for the outer pair and both non-empty pieces are
strings; the empty-piece representation follows Section 6.1.1; an
`SL:HASH-SET` input produces a lazy-sequence pair and lazy-sequence pieces.

**Description:**

Scans *seq* from its beginning and splits before the first element that does not
satisfy *predicate*. If every element satisfies the predicate, the suffix is
empty. If the first element does not satisfy it, the prefix is empty. Each empty
piece uses the same reconstruction representation as its non-empty counterpart:
strings remain strings, vectors retain the source's actual
`ARRAY-ELEMENT-TYPE`; a built-in-dictionary piece is an `SL:ORDERED-DICT`; and
list or lazy-sequence pieces are `NIL`; user-defined
inputs follow their Collector contract.

The two pieces must share one traversal, and the predicate is called exactly
once per element examined by that traversal, subject to the successful-traversal
and retry rules of Section 6.1.1. The predicate is not called after its first
false result.

For a `hash-table`, `SL:DICT`, `SL:ORDERED-DICT`, or a user-defined source with a reconstruction Collector, the outer pair is
lazy and each piece is reconstructed on demand as specified in Section 6.1.1.
Forcing the prefix position traverses through the first false predicate result
or source exhaustion, retaining the false element for the suffix; it does not
traverse beyond that boundary. Forcing the suffix position continues the same
traversal to exhaustion, including the retained boundary element, without
repeating successful predicate calls. An unbounded all-true prefix prevents
prefix reconstruction from terminating; an unbounded suffix prevents suffix
reconstruction from terminating. Collector creation, accumulation, and
finalization occur at the corresponding piece's force time, including for empty
pieces, without an outer Collector eligibility check or fallback.

**Exceptional Situations:** None beyond the general rules in Sections 6.1.3 and 6.1.5.

**See Also:** Section 6.1.1; `SL:SEQ-SPLIT`; `SL:SEQ-SPLIT-AT`.


### SL:SEQ-PARTITION _Generic Function_

**Name:** `SL:SEQ-PARTITION`, Generic Function

**Syntax:**

`(SL:SEQ-PARTITION` *n* *seq* `&key` *step* *pad* `)` → *lazy-seq*

**Arguments and Values:**

- *n* — a positive integer giving the size of each chunk.
- *seq* — a seqable object.
- *step* — a positive integer giving the advance between successive chunk
  starts. It defaults to *n*.
- *pad* — `NIL`, `T`, or a seqable object. It defaults to absent, which has the
  same effect as `NIL`.
- *lazy-seq* — a lazy sequence of chunks.

Each complete chunk buffers *n* elements before reconstruction; for an ordered
dictionary, duplicate padding keys may reduce the resident count. Chunk types
follow Section 6.1.1.
For a vector input, each chunk is reconstructed with the source's actual
`ARRAY-ELEMENT-TYPE`; only incompatible actual padding widens that chunk to a
general vector. The outer result is always a `lazy-seq`. For an `SL:HASH-SET` input, each chunk
is also a `lazy-seq`, as specified in Section 6.1.1.

**Description:**

Returns chunks whose starts are separated by *step* source positions. A
*step* less than *n* produces overlapping chunks. A *step* greater than *n*
skips the elements between chunks. Traversal stops when there is no source
element at the next chunk start.

When the final chunk has fewer than *n* elements, absent *pad* or `:PAD NIL`
drops that chunk. `:PAD T` emits the short chunk as-is. A seqable *pad* value
supplies successive padding elements until the chunk has *n* elements or the
pad sequence is exhausted; the resulting short chunk is emitted even if the
padding sequence also exhausts. Padding elements are not taken from the source. After the final chunk is dropped, emitted, or padded, the operation terminates; no chunk begins at a later position.

Chunks are formed by buffering rather than positional indexing. An empty chunk is not emitted. A padding element that is not a character widens a string chunk to a general
`vector` under the widening rules of Section 6.1.1.

**Exceptional Situations:** An invalid `:PAD` classification signals an error of type `TYPE-ERROR` at call time.

**See Also:** Section 6.1.1; `SL:SEQ-PARTITION-BY`; `SL:SEQ-DROP-LAST`.


### SL:SEQ-PARTITION-BY _Generic Function_

**Name:** `SL:SEQ-PARTITION-BY`, Generic Function

**Syntax:**

`(SL:SEQ-PARTITION-BY` *key-function* *seq* `&key` *test* `)` → *lazy-seq*

**Arguments and Values:**

- *key-function* — a one-argument function designator.
- *seq* — a seqable object.
- *test* — a two-argument equality predicate, defaulting to
  `#'SL:EQUALS` (Section 6.1.3).
- *lazy-seq* — a lazy sequence of chunks.

Each chunk is a maximal sequence of adjacent input elements, reconstructed in
the input type except that a `hash-table`, `SL:DICT`, or `SL:ORDERED-DICT`
source yields an `SL:ORDERED-DICT` chunk. For a vector input, each chunk uses the source's actual
`ARRAY-ELEMENT-TYPE`. The outer result is always a `lazy-seq`. For an `SL:HASH-SET`
input, each chunk is a `lazy-seq`, as specified in Section 6.1.1.

**Description:**

Returns maximal adjacent runs for which applying *key-function* produces equal values
under *test*. The first element begins the first chunk. For every later element,
its key is compared with the key of the preceding element; a different key
ends the current chunk and begins the next one. Elements are never reordered,
and equal keys in non-adjacent runs do not cause those runs to be combined.

**Exceptional Situations:** None beyond the general rules in Sections 6.1.3 and 6.1.5.

**See Also:** Section 6.1.1; `SL:SEQ-PARTITION`; `SL:DICT-GROUP-BY` in Chapter 9.


### SL:SEQ-TREE-SEQ _Generic Function_

**Name:** `SL:SEQ-TREE-SEQ`, Generic Function

**Syntax:**

`(SL:SEQ-TREE-SEQ` *branch-fn* *children-fn* *tree* `)` → *lazy-seq*

**Arguments and Values:**

- *branch-fn* — a one-argument predicate that identifies branch nodes.
- *children-fn* — a one-argument function designator that returns the children
  of a branch node as a seqable object.
- *tree* — the root node; it may be any object.
- *lazy-seq* — a lazy sequence of nodes.

**Description:**

Walks *tree* in depth-first, pre-order traversal. The root is emitted first.
The input relation defined by *branch-fn* and *children-fn* must be an acyclic
tree. Behavior on cyclic or shared-substructure inputs is unspecified.
For each node, `branch-fn` is called to determine whether it is a branch. If it
returns true, `children-fn` is called and its returned seqable is traversed in
order; each child and its descendants are then visited before the next sibling.
If `branch-fn` returns false, the node is a leaf and `children-fn` is not called.
Every branch and leaf node is emitted exactly once in the traversal.

The operation always returns a `lazy-seq`; neither callback is called at
call time. Branch tests, child production, and child traversal occur at force
time, allowing finite prefixes of suitable unbounded trees.

**Method Signatures:**

The standardized generic function has one method specializing on `T`; it does
not dispatch on *tree*, because the root may be any object. The method is closed.
Seqability is required of the objects *children-fn* returns, not of the root, and
a non-seqable children object signals an error of type `TYPE-ERROR` as specified
in Exceptional Situations.

**Exceptional Situations:** Signals an error of type `TYPE-ERROR` when *children-fn* returns a non-seqable object for a branch.

**See Also:** Section 6.1.1; Chapter 4's lazy-sequence protocol.


### SL:SEQ-DROP-LAST _Generic Function_

**Name:** `SL:SEQ-DROP-LAST`, Generic Function

**Syntax:**

`(SL:SEQ-DROP-LAST` *n* *seq* `)` → *result*

**Arguments and Values:**

- *n* — a non-negative integer.
- *seq* — a seqable object.
- *result* — for a string or vector *seq*, a fresh result of the same type
  containing all but the final *n* active elements; otherwise, a lazy sequence
  containing all but the final *n* elements of *seq*.

**Description:**

For a string or vector *seq*, returns an eager, fresh result containing all but
its final *n* active elements. The result is a string for a string input. For a
vector input, the result is reconstructed with the source's actual
`ARRAY-ELEMENT-TYPE`, including when it is empty; the active length excludes
inactive capacity beyond a fill pointer. When *n* is zero, the operation still
returns a newly allocated mutable copy. When *n* is at least the active length,
the result is an empty string or vector with the applicable source type.

For every other input type, returns a lazy sequence containing all but the final
*n* elements of *seq*. This includes lists, user-defined collections whether or
not they have a Collector, hash tables, `SL:DICT`, `SL:HASH-SET`, and lazy
sequences. This branch maintains an *n*-element lookahead buffer: an input
element is emitted only after *n* later positions have been read. When the
source ends, the buffered elements are silently discarded. It does not scan the
source in advance to determine finiteness. The result is created without
traversing *seq*; source traversal and buffering occur when the result is
forced. Bounded lookahead permits finite result prefixes from unbounded sources.
For *n* zero, the lazy result has the source's elements and order; when *n*
exceeds the source length, the result is empty.

**Exceptional Situations:** None beyond the general rules in Sections 6.1.3 and 6.1.5.

**See Also:** Section 6.1.1; `SL:SEQ-TAKE-LAST`.


### 6.2.5 Forcing Operations

The operations in this group force the complete selected region at call time unless an entry says otherwise; their return classifications are specified in Section 6.1.1.


### SL:SEQ-REVERSE _Generic Function_

**Name:** `SL:SEQ-REVERSE`, Generic Function

**Syntax:** `(SL:SEQ-REVERSE` *sequence* `)` → *result*

**Arguments and Values:**

- *sequence* — a seqable object whose selected region is finite.
- *result* — a sequence containing the selected elements in reverse
  order.

**Description:**

`SL:SEQ-REVERSE` is a forcing operation under Section 6.1.1, including its ordered-dictionary policy matrix.

Returns the elements in reverse order. It cannot produce a result for an
unbounded selected region. For a vector source, the result uses the source's
actual `ARRAY-ELEMENT-TYPE`, including when the result is empty. The operation accepts no keyword arguments.

**Exceptional Situations:** None beyond the general rules in Sections 6.1.3 and 6.1.5.

**See Also:** Section 6.1.1.


### SL:SEQ-SORT, SL:SEQ-STABLE-SORT _Generic Functions_

**Name:** `SL:SEQ-SORT`, `SL:SEQ-STABLE-SORT`, Generic Functions

**Syntax:**

`(SL:SEQ-SORT` *sequence* `&key` *test* *key* `)` → *result*  
`(SL:SEQ-STABLE-SORT` *sequence* `&key` *test* *key* `)` → *result*

**Arguments and Values:**

- *sequence* — a seqable object whose selected region is finite.
- *test* — a two-argument ordering predicate. It defaults to `#'SL:LT`.
- *key* — a one-argument function designator. It defaults to `#'IDENTITY`;
  supplying `NIL` has the same effect as omitting the keyword, as specified in
  Section 6.1.3.
- *result* — a sequence containing the selected elements in sorted order.

Only `:TEST` and `:KEY` are accepted. In particular, these operations do not
accept `:START`, `:END`, or `:FROM-END`.

**Description:**

`SL:SEQ-SORT` and `SL:SEQ-STABLE-SORT` are forcing operations under Section 6.1.1, including its ordered-dictionary policy matrix.

Sorting and keyword semantics are as for `CL:SORT` and `CL:STABLE-SORT`, except for the Sophie-specific source, return-type, forcing, and error rules stated here.

Each operation forces the complete selected region at call time, including a lazy source. The `:KEY` function is not cached and may be re-invoked on the same element across comparisons. The default ordering is `SL:LT` as specified in Chapter 7. For a vector source, each operation reconstructs the result with the source's actual `ARRAY-ELEMENT-TYPE`, including when the result is empty; callback results do not infer a replacement element type.

**Exceptional Situations:** Under the default `SL:LT` ordering, an incomparable pair of keys signals an error of type `SIMPLE-ERROR`; a supplied test that is not a total ordering has unspecified consequences.

**See Also:** Section 6.1.1; Chapter 7.


### SL:SEQ-TAKE-LAST _Generic Function_

**Name:** `SL:SEQ-TAKE-LAST`, Generic Function

**Syntax:** `(SL:SEQ-TAKE-LAST` *n* *sequence* `)` → *result*

**Arguments and Values:**

- *n* — a non-negative integer.
- *sequence* — a seqable object whose selected region is finite. For a built-in
  `hash-table` or `SL:DICT`, the operation returns a same-type dictionary under
  the built-in dictionary-preserving roster.
- *result* — a sequence containing the last *n* elements of the selected
  region, or the same built-in dictionary type for a built-in dictionary input.

**Description:**

`SL:SEQ-TAKE-LAST` is a forcing operation under Section 6.1.1, including its ordered-dictionary policy matrix. For a built-in
`hash-table` or `SL:DICT` source, it uses the built-in dictionary-preserving
roster: it establishes one traversal view, traverses at call time, and returns
the same built-in dictionary type with the retained associations. A hash-table
result preserves the source test; dictionary result order is unspecified. This
rule does not add an obligation for user-defined dicts.

Returns the last *n* elements of the selected region. It must reach the end to
determine which elements are last and therefore does not terminate on an
unbounded source. When *n* is zero, the result is the empty sequence of the
applicable return representation. For a vector source, the result uses the
source's actual `ARRAY-ELEMENT-TYPE`, including when it is empty.

**Exceptional Situations:** None beyond the general rules in Sections 6.1.3 and 6.1.5.

**See Also:** Section 6.1.1; `SL:SEQ-DROP-LAST`.


### SL:SEQ-TRIM-RIGHT _Generic Function_

**Name:** `SL:SEQ-TRIM-RIGHT`, Generic Function

**Syntax:** `(SL:SEQ-TRIM-RIGHT` *sequence* `&key` *predicate* `)` → *result*

**Arguments and Values:**

- *sequence* — a seqable object whose selected region is finite.
- *predicate* — a usable one-argument function designator. When *predicate* is omitted for a string, the default is specified in Section 6.1.3. For a non-string input, *predicate* is required. An explicitly supplied `NIL` is invalid.
- *result* — a sequence with the trailing run identified by *predicate*
  removed.

**Description:**

`SL:SEQ-TRIM-RIGHT` is a forcing operation under Section 6.1.1, including its ordered-dictionary policy matrix. For a vector source, it reconstructs the result with the source's actual `ARRAY-ELEMENT-TYPE`, including an empty result.

For a built-in `hash-table` or `SL:DICT` source, this operation uses the
built-in dictionary-preserving roster: it establishes one traversal view and
traverses at call time, applying its predicate according to the callback rules,
and returns the same built-in dictionary type with the retained associations. A
hash-table result preserves the source test; dictionary result order is
unspecified. This rule does not add an obligation for user-defined dicts.

Removes the trailing run of elements identified by *predicate* and returns the
retained elements. Trimming is right-end-only: leading elements are retained
even when they satisfy *predicate*.

A function-designator *predicate* selects an element when it returns a true value for that element.

**Exceptional Situations:** Signals an error of type `PROGRAM-ERROR` when a non-string source omits *predicate*.

**See Also:** Section 6.1.1; `SL:SEQ-TRIM-LEFT`; `SL:SEQ-TRIM`.


### SL:SEQ-TRIM _Generic Function_

**Name:** `SL:SEQ-TRIM`, Generic Function

**Syntax:** `(SL:SEQ-TRIM` *sequence* `&key` *predicate* `)` → *result*

**Arguments and Values:**

- *sequence* — a seqable object whose selected region is finite.
- *predicate* — a usable one-argument function designator. When *predicate* is omitted for a string, the default is specified in Section 6.1.3. For a non-string input, *predicate* is required. An explicitly supplied `NIL` is invalid.
- *result* — a sequence with both end runs identified by *predicate*
  removed.

**Description:**

`SL:SEQ-TRIM` is a forcing operation under Section 6.1.1, including its ordered-dictionary policy matrix. For a vector source, it reconstructs the result with the source's actual `ARRAY-ELEMENT-TYPE`, including an empty result.

For a built-in `hash-table` or `SL:DICT` source, this operation uses the
built-in dictionary-preserving roster: it establishes one traversal view and
traverses at call time, applying its predicate according to the callback rules,
and returns the same built-in dictionary type with the retained associations. A
hash-table result preserves the source test; dictionary result order is
unspecified. This rule does not add an obligation for user-defined dicts.

Removes the leading and trailing runs of elements identified by *predicate* and
returns the retained elements. The two runs are the maximal runs at the
respective ends; elements in the interior are retained, including elements that
satisfy *predicate*.

A function-designator *predicate* selects an element when it returns a true value for that element.

**Exceptional Situations:** Signals an error of type `PROGRAM-ERROR` when a non-string source omits *predicate*.

**See Also:** Section 6.1.1; `SL:SEQ-TRIM-LEFT`; `SL:SEQ-TRIM-RIGHT`.


### 6.2.6 Construction


### SL:SEQ-INTO _Generic Function_

**Name:** `SL:SEQ-INTO`, Generic Function

**Syntax:**

`(SL:SEQ-INTO` *target-designator source* `)` → *result*

**Arguments and Values:**

- *target-designator* — a symbol or a proper list whose first element is a
  target symbol and whose remaining elements are an even-length keyword and
  value option list, as specified by the Collector protocol in Chapter 4.
- *source* — a seqable object.
- *result* — a collection of the target type named by
  *target-designator*, or a lazy sequence for the `LAZY-SEQ` target.

**Description:**

`SL:SEQ-INTO` is eager. For every target other than `LAZY-SEQ`, it resolves
*target-designator*, creates a Collector, traverses *source* completely,
accumulates every source element in traversal order, and finalizes the Collector. Target
resolution and Collector creation take place at call time, and all source
traversal, source forcing, accumulation, and finalization for a concrete target
also take place at call time. The operation does not return until the complete
finite selected region has been traversed and the result has been finalized.
Consequently, it does not terminate on an unbounded source.

The target designator, rather than the representation or type of *source*,
determines the return type. For a mutable Common Lisp target (list, vector, string,
or hash table), the result is newly allocated and is not EQ to any input container
from which it was derived. An empty list result is `NIL`, an immutable singleton,
and is exempt from this requirement. For immutable or persistent target types, including
`LAZY-SEQ`, result identity is unspecified. An immutable empty target may use its
standard empty object as specified by the Collector protocol; mutable empty targets
are freshly allocated.

A target symbol whose name is `LAZY-SEQ` is recognized before any
package-sensitive class lookup, regardless of the package of the symbol. This
special target does not invoke the Collector protocol and wraps *source* in a
lazy sequence without forcing it. The wrapper is the exception to the
otherwise complete-traversal requirement; its deferred traversal occurs when
its elements are demanded.

Target resolution follows the implementation-defined strategy in Chapter 4. A symbol
designator that resolves to a class names that class as the target; a symbol that
does not resolve signals `TYPE-ERROR`. The symbol `NIL` is looked up as a target
name like any other symbol.

`SL:SEQ-INTO` dispatches on *source*, not on *target-designator*. Its
standardized methods select behavior from the source argument while using the
target designator only as construction data, as specified in Section 6.1.5.

**Method Signatures:**

- `((target-designator T) (source list))` → the constructed target collection.
- `((target-designator T) (source vector))` → the constructed target collection.
- `((target-designator T) (source T))` → traversal over a seqable source; signals
  an error of type `TYPE-ERROR` when *source* is not seqable.

**Exceptional Situations:**

Malformed target designators or malformed option lists signal an error of type `PROGRAM-ERROR`; a `LAZY-SEQ` target with options also signals `PROGRAM-ERROR`. An unresolved target or unsupported Collector target signals `TYPE-ERROR`. An invalid option value signals `TYPE-ERROR` when `SL:MAKE-COLLECTOR-FOR` creates the Collector; unsupported but well-formed embedded Collector options signal `PROGRAM-ERROR` for supported targets.

**See Also:** Section 6.1.1; Chapter 4; `SL:SEQ-JOIN`.


### SL:SEQ-JOIN _Generic Function_

**Name:** `SL:SEQ-JOIN`, Generic Function

**Syntax:**

`(SL:SEQ-JOIN` *target-designator seqs* `&key` *separator* `)` → *result*

**Arguments and Values:**

- *target-designator* — a target designator with the same resolution rules as
  `SL:SEQ-INTO`.
- *seqs* — a seqable object whose elements are seqable pieces.
- *separator* — an optional seqable object. When supplied, its elements are
  inserted between every pair of adjacent non-empty pieces; when omitted, no
  separator elements are inserted.
- *result* — a collection of the target type, or a lazy sequence for a
  `LAZY-SEQ` target.

**Description:**

`SL:SEQ-JOIN` is eager for a concrete target. It creates one Collector for the
resolved target, traverses *seqs* serially, and traverses each piece serially
in the order encountered. It accumulates each piece's elements, inserting the
separator's elements once between every pair of adjacent non-empty pieces. The
separator is forced once and its resulting sequence is reused for each insertion.
No separator is inserted before the first piece or after the last piece. An empty
*seqs* produces an empty target collection. An empty piece is skipped: it
contributes no elements and does not count as adjacent for separator insertion. An empty result for an immutable target type may reuse a
standard empty object.

The complete finite selected region of *seqs*, every piece reached in that
region, and the separator used between pieces must be traversed before a
concrete result is returned. Thus the operation does not terminate on an
unbounded source, an unbounded piece, or an unbounded separator that must be
consumed. Traversal is serial: the operation does not traverse pieces in
parallel or interleave independent piece views.

The target designator determines the return type. For a mutable Common Lisp
target (list, vector, string, or hash table), the result is newly allocated and
not EQ to any input container from which it was derived. An empty list result is
`NIL`, an immutable singleton, and is exempt from this requirement. For immutable
or persistent target types, result identity is unspecified. The operation is not
type-preserving. The `LAZY-SEQ` target does not invoke the Collector protocol
(Chapter 4): it returns a lazy sequence representing the serial joined traversal
without forcing *seqs*, a piece, or *separator* at call time. Embedded
target-designator options are not permitted for a `LAZY-SEQ` target, and its
deferred result is the sole exception to the complete traversal requirement.

`SL:SEQ-JOIN` dispatches on *seqs*, its primary source argument, not on
*target-designator*. Its source dispatch is governed by Section 6.1.5.

**Method Signatures:**

- `((target-designator T) (seqs list))` → the constructed target collection.
- `((target-designator T) (seqs vector))` → the constructed target collection.
- `((target-designator T) (seqs T))` → traversal over a seqable *seqs*; signals
  an error of type `TYPE-ERROR` when *seqs* is not seqable.

**Exceptional Situations:**

The target-designator and target-resolution errors are those specified for `SL:SEQ-INTO`: malformed designators or embedded options, or options supplied for a `LAZY-SEQ` target, signal `PROGRAM-ERROR`; an unresolved or unsupported target signals `TYPE-ERROR`; an invalid option value signals `TYPE-ERROR` when the Collector is created; and unsupported but well-formed embedded Collector options signal `PROGRAM-ERROR` for supported targets.
**See Also:** Section 6.1.1; Chapter 4; `SL:SEQ-INTO`.

