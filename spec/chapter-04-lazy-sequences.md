# Chapter 4: Lazy Sequences, Collections, and the Collector Protocol

## 4.1 Concepts

### 4.1.1 Collections and Seqability

A **collection** is an object whose contents may be traversed as a sequence of
elements. A **concrete collection** is one whose contents are present rather than
deferred — a list, vector, string, hash table, `SL:DICT`, `SL:ORDERED-DICT`, or `SL:HASH-SET` — as
distinct from a lazy sequence.

A **seqable** object is a collection that participates in the seq protocol.
`SL:SEQABLEP` determines whether an object is seqable.

The standardized seqable types are:

| Type | Elements |
|------|----------|
| `list` | The successive cars of the list. |
| `vector` | The elements in increasing index order, within the active length. |
| `string` | The characters in increasing index order, within the active length. |
| `hash-table` | `SL:MAP-ENTRY` objects representing the table entries. |
| `SL:ORDERED-DICT` | `SL:MAP-ENTRY` objects in stored order (Chapter 9). |
| `SL:LAZY-SEQ` | The elements produced by forcing successive nodes. |

`NIL` is both the empty list and the empty lazy sequence. A vector or string
with a fill pointer is traversed only through its active length. The seqable
types defined in Chapter 9 participate as specified there. User-defined types
participate through the seq protocol.

A list traversal may proceed incrementally without first establishing that the
whole list is proper. A dotted list signals an error of type `TYPE-ERROR` when
traversal reaches its dotted tail. A circular list is an unbounded sequence;
traversal continues around the cycle.

A **view** is a lazy sequence over a concrete source whose forcing reads that
source. Each independently created view has its own traversal state; successive
nodes within that view continue the same traversal. Memoization within a view
ensures that repeated observation of the same node returns the same element.

Hash-table traversal order is unspecified. A lazy-sequence view of a hash table
nevertheless has a stable order: `SL:SEQ-REST` on that view continues the same
view, and repeated traversal of that view observes the same order. Direct calls
to `SL:SEQ-FIRST` and `SL:SEQ-REST` on the hash table establish independent
views. Two separately created views of the same unmodified hash table may have
different orders. No order is canonical for the hash table.

### 4.1.2 The Seq Protocol

The seq protocol consists of `SL:SEQABLEP`, `SL:SEQ-EMPTYP`, `SL:SEQ-FIRST`,
`SL:SEQ-REST`, `SL:SEQ-REF`, and `SL:SEQ-LENGTH`.

Methods specialized on vector also apply to strings, as specified by ANSI Common Lisp.
Dictionary entries that list a vector method cover strings unless a separate string
method is present.

A user-defined seqable type must have applicable methods, directly or by
inheritance, on `SL:SEQABLEP`, `SL:SEQ-EMPTYP`, `SL:SEQ-FIRST`, and `SL:SEQ-REST`.
Its `SL:SEQABLEP` method must return true. It may define `SL:SEQ-REF` for direct
indexed access; otherwise the traversal method applies. It may define
`SL:SEQ-LENGTH` when the length is available more directly than by traversal. A
dict type must have an applicable `SL:SEQ-LENGTH` method as required by Chapter 9.

A **proper sequence** is a finite or unbounded sequence whose traversal reaches
each element through successive `SL:SEQ-REST` calls without encountering a
non-seqable tail. A dotted list is seqable but is not a proper sequence, as
specified below. The methods for a seqable type must obey these requirements for
proper sequences:

1. If `SL:SEQ-EMPTYP` returns true, `SL:SEQ-FIRST` and `SL:SEQ-REST` return
   `NIL` without signaling an error.
2. If `SL:SEQ-EMPTYP` returns false, `SL:SEQ-FIRST` returns the first element
   and `SL:SEQ-REST` returns a seqable object representing the remaining
   traversal.
3. For a finite proper sequence, repeated application of `SL:SEQ-REST`
   eventually reaches an empty sequence.
4. Within one lazy-sequence traversal view, decomposition into
   `SL:SEQ-FIRST` followed by `SL:SEQ-REST` produces each element exactly once
   and in that view's order.
5. `SL:SEQ-REF` at its effective non-negative position, after negative-index
   normalization, denotes the element reached after that many applications of
   `SL:SEQ-REST` within one traversal view.
6. Calls that observe an unmodified ordered source are stable. Calls that
   observe an unordered source are stable within one view; separate views may
   differ.

A dotted list is seqable but is not a proper sequence. Traversal may consume its
conses incrementally; when `SL:SEQ-REST` reaches the dotted tail, it signals an
error of type `TYPE-ERROR` instead of returning a seqable rest. The proper-
sequence requirements above therefore do not require traversal of a dotted list
to reach an empty sequence.

Direct calls to `SL:SEQ-FIRST`, `SL:SEQ-REST`, and `SL:SEQ-REF` on an unordered
collection each establish an independent view, so their results do not jointly
decompose one traversal. Coherent complete traversal of an unordered collection
is obtained by using `SL:DOSEQ` or `(SL:SEQ-INTO 'LAZY-SEQ` *source* `)`; each
establishes a single view over all elements. One view is self-consistent;
separate views may differ.

Violating these requirements has undefined consequences. `SL:SEQ-FIRST` may return
`NIL` both for an empty sequence and for a sequence whose first element is `NIL`;
callers use `SL:SEQ-EMPTYP` for that distinction.

`SL:SEQ-REST` returns the tail of a proper list, equivalent to its `CDR`. It
returns a lazy-sequence view for a vector, string, hash table, dict type, or lazy
sequence. It returns `NIL` for an empty source. Chapter 6
specifies when higher-level operations reconstruct a result in a concrete
source type.

`SL:SEQ-LENGTH` returns a non-negative integer for a finite sequence. It returns
`NIL` when unboundedness is known; otherwise it may traverse the sequence and
may not terminate. The traversal method supplies this behavior for an ordinary
user-defined seqable type that does not define a more specific method.

`(SETF SL:SEQ-REF)` is a separate write protocol. Methods are standardized for
lists, vectors, and strings. A user-defined mutable type may define a method,
but such a method is not required for seqability.

### 4.1.3 Lazy Sequences and Forcing

A **lazy sequence** is `NIL` or an `SL:LAZY-SEQ` node. `NIL` is the empty lazy
sequence. A node is either unresolved or resolved. A resolved node is empty
when its thunk resolved to `NIL`, or nonempty when its element and rest are
fixed.

Forcing an unresolved node invokes or resolves its deferred computation. A
successful force resolves transitively through returned wrapper nodes until it
reaches `NIL` or a node with a fixed element and rest. If the thunk returns an
`SL:LAZY-SEQ` node that has already resolved to empty, the original node resolves
to empty without further forcing. Resolution to `NIL` makes the original node
empty. Resolution to a nonempty node fixes the original node's element and rest.

A successful force is memoized per node. Every later observation of that node
uses the same element and rest, including the same objects under `EQ`, without
repeating its deferred computation. A force of one node does not force its
tail. Consequently, a finite prefix may be consumed without forcing the
remainder, including when the remainder is unbounded. Conditions signaled by
forcing a lazy-sequence node during any seq-protocol call propagate to the
caller of that call.

An already-forced node remains stable regardless of later modification of an
object from which its values were obtained. Memoization is associated with the
node, not with the source collection or with another view.

Recursive forcing of the same node while that node is currently being forced
signals an error of type `PROGRAM-ERROR`. A node whose fixed rest is itself is
valid and denotes an unbounded sequence.

`SL:LAZY-SEQ` is a sealed abstraction. A conforming program must construct
nodes only with `SL:LAZY-SEQ`, `SL:MAKE-LAZY-SEQ`, `SL:LAZY-CONS`, or an
operation specified to return a lazy sequence. It must not subclass
`SL:LAZY-SEQ` or call `MAKE-INSTANCE` to construct one.

### 4.1.4 Lazy Sequence Construction and Failure

`SL:LAZY-SEQ` defers lexical forms. `SL:MAKE-LAZY-SEQ` defers a zero-argument
function. `SL:LAZY-CONS` constructs a node whose element and rest are already
fixed. Each constructor returns an `SL:LAZY-SEQ` node, even when a deferred
computation resolves to `NIL`.

A deferred computation must return exactly one value. That value must be
`NIL` or an `SL:LAZY-SEQ` node. Returning zero values, multiple values, or one
non-`NIL` value that is not a node signals an error of type `TYPE-ERROR` at
force time.

A successful resolution is memoized per node. If forcing signals a condition that
escapes, returns an invalid result, or fails during transitive resolution, the
failed resolution caches nothing and may be retried. If a signaled condition is
resumed and the computation returns a valid result normally, forcing succeeds
and memoizes that result. Recursive forcing of the same node signals an error of
type `PROGRAM-ERROR`; if that condition is handled and a valid result is then
returned, the result is memoized, otherwise nothing is cached. A failure during
transitive resolution leaves the outer node unresolved and retryable.

Macro expansions of `SL:LAZY-SEQ` obey the generated-variable requirements of
Chapter 8.

### 4.1.5 Keyed Traversal

An `SL:MAP-ENTRY` is an immutable record containing a key and a value.
`SL:ENTRY-KEY` and `SL:ENTRY-VALUE` read its fields. An entry is not itself
seqable, and no SETF accessors are defined for its fields. `SL:MAP-ENTRY` is a
sealed abstraction: subclassing and `MAKE-INSTANCE` are prohibited.

Each element produced by hash-table traversal is an `SL:MAP-ENTRY` representing
a table entry. Entry identity is unspecified. The entries in one lazy-sequence
view collectively represent the table entries present for that traversal.

The keyed collection types in Chapter 9 also use `SL:MAP-ENTRY` where specified
there. Equality and comparison of entries are defined in Chapter 7.

### 4.1.6 The Collector Protocol

A **Collector** is mutable construction state governed by
`SL:MAKE-COLLECTOR-FOR`, `SL:COLLECTOR-ACCUMULATE`, and
`SL:COLLECTOR-RESULT`. A construction operation obtains a Collector,
accumulates source elements in traversal order, and finalizes it.

`SL:MAKE-COLLECTOR-FOR` serves two operation paths, but both calls use ordinary
CLOS dispatch on the actual argument. On the designator path, *target* is the
class object resolved from the target designator, so an `EQL` specializer on
that class object participates through normal method precedence. On the
reconstruction path, *target* is the seqable source instance, so class
specialization and inheritance use ordinary CLOS dispatch on that instance.
The same actual object therefore has the same applicable methods and normal
`EQL` precedence regardless of which operation path supplied it; a class object
that is also a seqable source is not forced through an intended path or filtered
to remove an applicable method. An extension whose object serves both roles must
satisfy both contracts: its designator-path result must be an instance of the
registered target class, and its reconstruction-path result must preserve the
source's concrete type. The operation path determines the caller's result
contract, not a different dispatch mechanism.

`SL:SEQ-INTO` uses the designator path, and type-preserving operations use the
reconstruction path. On the reconstruction path used by the type-preserving
operations of Chapter 6, the argument is a seqable source instance. A method on
a class applies to its subclasses unless overridden. When a type-preserving
operation widens its result as specified in Chapter 6, reconstruction uses the
Collector of the widened type, not the source type. For the vector-preserving
roster in Chapter 6, reconstruction of a vector source supplies the source's
actual `ARRAY-ELEMENT-TYPE` to the vector Collector. Source traversal still
honors the vector's active length; active length is traversal state, not a
Collector option. The default `:ELEMENT-TYPE T` remains the behavior of an
explicit `vector` target and of operations whose results are element-changing
or multi-source. A partition chunk whose actual padding is incompatible uses
the general vector Collector; this widening is local to that chunk. Where
this chapter or Chapter 6 says reconstruction supplies an option to,
dispatches on, or invokes a Collector, the requirement is the observable
result that Collector or option selects, not a mandated internal call
sequence.

A target designator used by `SL:SEQ-INTO` is either a symbol naming a class, a
symbol naming a target, or a proper list. For a list designator, the `CAR` is the
target symbol and the `CDR` is an even-length keyword and value option list;
target resolution applies to the `CAR`. Any symbol whose name is `LAZY-SEQ`,
regardless of its package, is recognized before ordinary target resolution. That
target accepts no options, wraps the source without forcing, and does not invoke
the Collector protocol. Supplying options with a `LAZY-SEQ` target signals an
error of type `PROGRAM-ERROR`.

Every other target symbol is resolved to a class object by an
implementation-defined lookup strategy. If the symbol cannot be resolved to a
class, an error of type `TYPE-ERROR` is signaled. The resolved class object and
options are passed to `SL:MAKE-COLLECTOR-FOR`. An unsupported resolved class
signals an error of type `TYPE-ERROR` through that generic function.

This chapter standardizes Collectors for these target classes:

| Target | Default options | Accepted elements | Result |
|--------|-----------------|-------------------|--------|
| `list` | None. | Any object. | A list in accumulation order. |
| `vector` | `:ELEMENT-TYPE T` | Objects of the element type. | A vector. |
| `string` | `:ELEMENT-TYPE CHARACTER` | Characters of the element type. | A string. |
| `hash-table` | `:TEST EQUAL` | `SL:MAP-ENTRY` objects. | A hash table. |
| `SL:ORDERED-DICT` | None; fixed `SL:EQUALS`. | `SL:MAP-ENTRY` objects only. | An ordered dictionary under Chapter 9's first-position/last-association-wins rule. |

An option value that is not valid for the selected target signals an error of
type `TYPE-ERROR` when the Collector is created. For a string target,
`:ELEMENT-TYPE` must designate a subtype of `CHARACTER`. For a hash-table
target, `:TEST` must be a designator for one of the standard hash-table test
functions `EQ`, `EQL`, `EQUAL`, or `EQUALP`.

For a hash-table Collector, accumulation stores the entry's key and value. If
several accumulated entries have equivalent keys under the table test, the
last value is retained. Additional standardized targets, including the types in
Chapter 9, are defined in later chapters.

`SL:COLLECTOR-RESULT` computes and caches the result once. Repeated calls on
the same Collector return the same object under `EQ`. Accumulation after
finalization has undefined consequences.

A Collector that refuses an element must signal an error and must not silently
drop or truncate it. The refused element contributes nothing. Accumulation may
continue after a refusal; each later accumulation is governed by the same
contract, and later successful accumulations are included in the result.
Elements successfully accumulated before the refusal remain accumulated.
Finalization after a refusal is defined, returns the result of all successful
accumulations, and remains idempotent.

A conforming extension that introduces a Collector result target crosses the
extension boundary only through non-enumerated specializers. It must use its own
class for Collector state, define an `SL:MAKE-COLLECTOR-FOR` method with an
`EQL` specializer on its result class object for the designator path, and define
`SL:COLLECTOR-ACCUMULATE` and `SL:COLLECTOR-RESULT` methods for its Collector
class. A user-defined seqable type that participates in type-preserving
reconstruction must have an applicable non-default primary
`SL:MAKE-COLLECTOR-FOR` method for the source object, directly or by inheritance,
accepting the keywords its Collector supports. A method specialized on the source
class is the usual route. Designator-target status is a separate, additional
obligation that the type may also discharge by defining an `EQL`-specialized
method for its class object.

A type participates in type-preserving reconstruction when ordinary CLOS dispatch
on the actual source instance has an applicable non-default primary
`SL:MAKE-COLLECTOR-FOR` method. A class-specialized method remains the ordinary
source-based opt-in and applies through normal CLOS inheritance and precedence.
If the source instance is itself a class object and an `EQL`-specialized method
is applicable to that object, that method also counts; participation lookup must
not filter out an applicable `EQL` method or otherwise select a different method
set for this dual-role case. `:BEFORE`, `:AFTER`, and `:AROUND` methods do not
constitute participation. An extension Collector's result must be an instance of the
registered target class on the designator path, or preserve the source's concrete type on
the reconstruction path. For mutable Common Lisp results (list, vector, string,
hash-table), the reconstruction result must be freshly allocated and not EQ to any
input. An empty list result is `NIL`, an immutable singleton, and is exempt from
this requirement. For immutable or persistent result types, result identity is
unspecified. The result must represent the accumulated elements in accumulation
order, subject to the standardized keyed target's uniqueness and traversal
rules: an ordered dictionary retains first key positions and latest key/value
associations, and an unordered dictionary promises no traversal order. Duplicate
keys in these targets are successful accumulation, not refusal. This specific
keyed reconstruction rule does not authorize arbitrary Collectors to discard
accepted elements. These protocol requirements are subject to the enumerated-method closure
of Chapter 1.

### 4.1.7 Iteration and Source Modification

`SL:DOSEQ` traverses a seqable source in the manner of `DOLIST`. Its source form
is evaluated exactly once. On each iteration it binds an element pattern and,
in the indexed form, a zero-based index variable. Patterns use the complete
destructuring rules specified in Chapter 8.

The indexed binding syntax and its selection rules are specified in the `SL:DOSEQ`
entry below.

The map-entry pattern rules are specified in the `SL:DOSEQ` entry below.

`SL:DOSEQ` establishes an implicit block named `NIL`. `RETURN` exits the
iteration and supplies its values. Normal completion returns `NIL`.

Modifying a source while it is being traversed by a Sophie operation has
undefined consequences for that operation. This precondition includes both
structural modification and replacement of elements. It lasts while the
operation may still read the source, including through an unforced lazy result.
The source-modification rule applies to external program mutation, not to the
internal resolution and memoization performed by the lazy-seq protocol itself.
Already-forced lazy-sequence nodes remain stable.

## 4.2 Dictionary

### 4.2.1 Lazy Sequence Protocol

**Dictionary Conventions:**

Seq protocol methods other than `SL:SEQABLEP` require seqable sources; the `T`
method supplies traversal and signals `TYPE-ERROR` for non-seqable sources.
`SL:SEQABLEP` accepts any object and returns false for nonparticipants without
signaling. The Chapter 4 seq protocol generics (`SL:SEQ-FIRST`, `SL:SEQ-REST`,
`SL:SEQ-EMPTYP`, `SL:SEQ-REF`, `SL:SEQ-LENGTH`, `SL:SEQABLEP`) are open to
user-defined seqable types. The Chapter 6 `SL:SEQ-*` operation generics are
closed; user-defined types participate through the Chapter 4 seq protocol, not
by adding Chapter 6 methods.

Lazy-node forcing, memoization, and retry semantics are specified in
Sections 4.1.3 and 4.1.4. The sealed abstractions `SL:LAZY-SEQ` and
`SL:MAP-ENTRY` prohibit subclassing and `MAKE-INSTANCE`; see Sections 4.1.3
and 4.1.5.

Collector refusal, finalization, and caching semantics are specified in
Section 4.1.6. An unsupported target on either the designator path or the
reconstruction path signals `TYPE-ERROR`. A non-Collector object passed to
`SL:COLLECTOR-ACCUMULATE` or `SL:COLLECTOR-RESULT` signals `TYPE-ERROR`.

Notes and examples for this chapter appear in Appendix D.

### SL:LAZY-SEQ _Type_

**Name:** `SL:LAZY-SEQ`, Type

**Syntax:**

`SL:LAZY-SEQ`

**Arguments and Values:**

A value of this type is an unresolved or resolved lazy-sequence node.

**Description:**

Names the class of lazy-sequence nodes. `NIL` is the empty lazy sequence but is
not of type `SL:LAZY-SEQ`. A node is unresolved or resolved; a resolved node is
empty or nonempty as specified in Section 4.1.3.

### SL:LAZY-SEQ _Macro_

**Name:** `SL:LAZY-SEQ`, Macro

**Syntax:**

`(SL:LAZY-SEQ` *form* `)` → *lazy-sequence*

**Arguments and Values:**

- *form* — a form evaluated only when the node is forced.
- *lazy-sequence* — an `SL:LAZY-SEQ` node.

**Description:**

Returns a node that, when forced, evaluates *form* in its lexical environment.
The values and failure behavior of *form* are the thunk contract of
`SL:MAKE-LAZY-SEQ`.

**Exceptional Situations:**

Signals an error of type `PROGRAM-ERROR` at macroexpansion time if other than
exactly one *form* is supplied.

Conditions from evaluating *form*, including the forcing validation conditions
specified for `SL:MAKE-LAZY-SEQ`, are signaled at force time.

### SL:MAKE-LAZY-SEQ _Function_

**Name:** `SL:MAKE-LAZY-SEQ`, Function

**Syntax:**

`(SL:MAKE-LAZY-SEQ` *thunk* `)` → *lazy-sequence*

**Arguments and Values:**

- *thunk* — a zero-argument function. The *thunk* is a function object; symbols are not accepted as designators.
- *lazy-sequence* — an unresolved `SL:LAZY-SEQ` node.

**Description:**

Returns a node that invokes *thunk* when forced. The thunk must return exactly
one value, either `NIL` or an `SL:LAZY-SEQ` node. Returned nodes are resolved
transitively.

**Exceptional Situations:**

Signals an error of type `TYPE-ERROR` at call time if *thunk* is not a function.

Signals an error of type `TYPE-ERROR` at force time if *thunk* returns zero
values, multiple values, or one value other than `NIL` or an `SL:LAZY-SEQ`
node. Signals an error of type `PROGRAM-ERROR` if forcing recursively attempts
to force the same currently-forcing node.

### SL:LAZY-CONS _Function_

**Name:** `SL:LAZY-CONS`, Function

**Syntax:**

`(SL:LAZY-CONS` *element rest* `)` → *lazy-sequence*

**Arguments and Values:**

- *element* — any object.
- *rest* — `NIL` or an `SL:LAZY-SEQ` node.
- *lazy-sequence* — a node with fixed contents.

**Description:**

Returns a node whose first element is *element* and whose rest is *rest*.
Neither argument is deferred by this function.

**Exceptional Situations:**

Signals an error of type `TYPE-ERROR` if *rest* is neither `NIL` nor an
`SL:LAZY-SEQ` node.

### SL:LAZY-SEQ-P _Function_

**Name:** `SL:LAZY-SEQ-P`, Function

**Syntax:**

`(SL:LAZY-SEQ-P` *object* `)` → *generalized-boolean*

**Arguments and Values:**

- *object* — any object.
- *generalized-boolean* — true or false.

**Description:**

Returns true if *object* is `NIL` or an `SL:LAZY-SEQ` node; otherwise returns
false. It does not force *object*.

**Exceptional Situations:**

None.

### 4.2.2 Seq Protocol

**Ordered dictionary method signatures.** The following standardized dispatch
cases supplement the individual entries; their arguments, defaults, and error
contracts apply unchanged. Chapter 9 defines the type and persistence rules.

| Generic function | Method signature and result |
|---|---|
| `SL:SEQABLEP` | `((object SL:ORDERED-DICT))` → true, without traversal |
| `SL:SEQ-EMPTYP` | `((source SL:ORDERED-DICT))` → true exactly when its size is zero |
| `SL:SEQ-FIRST` | `((source SL:ORDERED-DICT))` → first stored-order entry, or NIL |
| `SL:SEQ-REST` | `((source SL:ORDERED-DICT))` → lazy view after the first entry, or NIL when empty; no reconstruction |
| `SL:SEQ-REF` | `((source SL:ORDERED-DICT) index &optional default)` → positional entry and presence, not keyed lookup; traversal fallback may supply this behavior |
| `SL:SEQ-LENGTH` | `((source SL:ORDERED-DICT))` → non-traversing unique-key count equal to `SL:DICT-SIZE` |

There is no ordered positional writer; the no-writer `(SETF SL:SEQ-REF)`
contract signals `SIMPLE-ERROR`. The keyed writers are specified in Chapters
8 and 9. Separate ordered traversals are consistent in order, unlike separate
traversals of an unordered dictionary.

### SL:SEQABLEP _Generic Function_

**Name:** `SL:SEQABLEP`, Generic Function

**Syntax:**

`(SL:SEQABLEP` *object* `)` → *generalized-boolean*

**Arguments and Values:**

- *object* — any object.
- *generalized-boolean* — true or false.

**Description:**

Returns true if *object* participates in the seq protocol; otherwise returns
false. An `SL:MAP-ENTRY` is not seqable.

**Method Signatures:**

- `((object list))` → true.
- `((object vector))` → true; this includes strings.
- `((object hash-table))` → true.
- `((object SL:LAZY-SEQ))` → true.
- `((object SL:MAP-ENTRY))` → false.

Chapter 9 defines the methods for its seqable types.

**Exceptional Situations:**

None.

### SL:SEQ-EMPTYP _Generic Function_

**Name:** `SL:SEQ-EMPTYP`, Generic Function

**Syntax:**

`(SL:SEQ-EMPTYP` *source* `)` → *generalized-boolean*

**Arguments and Values:**

- *source* — a seqable object.
- *generalized-boolean* — true if *source* is empty; otherwise false.

**Description:**

Determines whether *source* has an element. On an unresolved lazy-sequence node,
it forces that node sufficiently to determine emptiness.

**Method Signatures:**

- `((source list))` → whether the list is empty.
- `((source vector))` → whether the active length is zero.
- `((source hash-table))` → whether the table has no entries.
- `((source SL:LAZY-SEQ))` → whether the node resolves to empty.

Chapter 9 defines the methods for its seqable types.

### SL:SEQ-FIRST _Generic Function_

**Name:** `SL:SEQ-FIRST`, Generic Function

**Syntax:**

`(SL:SEQ-FIRST` *source* `)` → *element*

**Arguments and Values:**

- *source* — a seqable object.
- *element* — its first element, or `NIL` when empty.

**Description:**

Returns the first element of *source*. For a hash table, the element is an
`SL:MAP-ENTRY`. For a lazy-sequence node, the node is forced sufficiently to
obtain its first element.

**Method Signatures:**

- `((source list))` → the first list element or `NIL`.
- `((source vector))` → the element at index zero or `NIL`.
- `((source hash-table))` → an entry or `NIL`.
- `((source SL:LAZY-SEQ))` → the first element or `NIL`.

Chapter 9 defines the methods for its seqable types.

### SL:SEQ-REST _Generic Function_

**Name:** `SL:SEQ-REST`, Generic Function

**Syntax:**

`(SL:SEQ-REST` *source* `)` → *rest*

**Arguments and Values:**

- *source* — a seqable object.
- *rest* — a seqable object or `NIL`.

**Description:**

Returns the traversal after the first element, or `NIL` when *source* is empty.
For a proper list it returns the list tail. For a vector, string, hash table, or
lazy-sequence node it returns a lazy-sequence view.

**Method Signatures:**

- `((source list))` → the list tail or `NIL`.
- `((source vector))` → a lazy-sequence view or `NIL`.
- `((source hash-table))` → a lazy-sequence view or `NIL`.
- `((source SL:LAZY-SEQ))` → the rest or `NIL`.

Chapter 9 defines the methods for its seqable types.

**Exceptional Situations:**

Signals an error of type `TYPE-ERROR` when the next list tail is dotted.

### SL:SEQ-REF _Generic Function_

**Name:** `SL:SEQ-REF`, Generic Function

**Syntax:**

`(SL:SEQ-REF` *source index* `&OPTIONAL` *default* `)` → *element*, *present-p*

**Arguments and Values:**

- *source* — a seqable object.
- *index* — an integer.
- *default* — any object.
- *element* — the indexed element, or *default*.
- *present-p* — true when the indexed element exists; otherwise false.

**Description:**

Returns the element at zero-based *index* and true. For a non-negative *index*,
the position is counted from the start. For a negative *index*, the effective
position is *L* + *index*, where *L* is the finite length of *source*; thus
`-1` selects the last element and `-*L*` the first. An effective position below
zero is out of range. If the position is out of range and *default* was
supplied, returns *default* and false. An omitted *default* is
distinguishable from a supplied *default* of `NIL`. A method specialized on a
user-defined seqable type must accept a default-supplied-p flag (or equivalent)
to distinguish these cases.

Negative indexing requires a finite source. Its length determination follows
`SL:SEQ-LENGTH` semantics: if `SL:SEQ-LENGTH` returns `NIL`, signaling known
unboundedness, `SIMPLE-ERROR` is signaled even when *default* was supplied; if
unboundedness cannot be established, length determination may not terminate.
A non-negative lookup has no length prerequisite. Negative lookup may force an
entire finite lazy sequence and propagates traversal errors. Error reporting
uses the requested *index*, not its effective position.

The traversal method advances with `SL:SEQ-REST` and observes with
`SL:SEQ-FIRST`. More specific methods may provide direct access.

**Method Signatures:**

- `((source list) index &OPTIONAL default)` → indexed list element and presence.
- `((source vector) index &OPTIONAL default)` → indexed active element and presence.
- `((source hash-table) index &OPTIONAL default)` → indexed element and presence.
- `((source SL:LAZY-SEQ) index &OPTIONAL default)` → indexed element and presence.

Additional standardized behavior for seqable types is defined in Chapter 9.

**Exceptional Situations:**

Signals an error of type `TYPE-ERROR` if *index* is not an integer, or if its
effective position is out of range and *default* was not supplied. Empty
sequences have no valid indices. For a negative *index*, an effective position
below zero is out of range. For a negative index, `SIMPLE-ERROR` is signaled if
`SL:SEQ-LENGTH` returns `NIL`; if unboundedness cannot be established, length
determination may not terminate. For the standardized list method, traversal
that reaches a dotted tail signals an error of type `TYPE-ERROR`. Detection by
a user-supplied traversal method might signal an error of type `TYPE-ERROR`.

### (SETF SL:SEQ-REF) _Generic Function_

**Name:** `(SETF SL:SEQ-REF)`, Generic Function

**Syntax:**

`(SETF (SL:SEQ-REF` *source index* `&OPTIONAL` *default* `)` *new-value* `)`
→ *new-value*

**Arguments and Values:**

- *new-value* — any object acceptable to the concrete source.
- *source* — a mutable seqable object.
- *index* — an integer.
- *default* — any object; ignored by the writer.

**Description:**

Replaces the element at *index* in a mutable concrete source and returns
*new-value*. For a non-negative *index*, the position is counted from the
start. For a negative *index*, the effective position is *L* + *index*, where
*L* is the finite length of the source; `-1` selects the last element and
`-*L*` the first. An effective position below zero is out of range. For list,
vector, and string sources, standard access and update behavior follows CLHS
after this normalization; vector and string indices use the active length. The
*default* argument is ignored. `NIL` is an empty list; lazy sequences and
sources without a writer are not writable.

**Method Signatures:**

Standardized methods apply to list, vector, and string. The `SL:LAZY-SEQ` and
`T` methods signal `SIMPLE-ERROR` unless an extension writer applies.

**Extensibility:**

A user-defined mutable seqable type may define a writer method; it is not
required for seqability.

**Exceptional Situations:**

Standard writable sources signal `TYPE-ERROR` for a noninteger or out-of-range
index, or an unacceptable new value; an out-of-range write signals
`TYPE-ERROR` even when a *default* was supplied. The `SL:LAZY-SEQ` and
no-writer methods signal `SIMPLE-ERROR` before index validation; the lazy
method does so regardless of index validity.

### SL:SEQ-LENGTH _Generic Function_

**Name:** `SL:SEQ-LENGTH`, Generic Function

**Syntax:**

`(SL:SEQ-LENGTH` *source* `)` → *length*

**Arguments and Values:**

- *source* — a seqable object.
- *length* — a non-negative integer, or `NIL`.

**Description:**

Returns the number of elements in a finite *source*. Returns `NIL` when
unboundedness is known; otherwise it may traverse the source and may not
terminate.

**Method Signatures:**

- `((source list))` → the list length, or `NIL` when unboundedness is known.
- `((source vector))` → the active length.
- `((source hash-table))` → the number of entries.
- `((source SL:LAZY-SEQ))` → its finite length or `NIL` when known unbounded.

Chapter 9 defines required non-traversing methods for its dict types.

**Exceptional Situations:**

Signals an error of type `TYPE-ERROR` if traversal reaches a dotted list tail.

### SL:DOSEQ _Macro_

**Name:** `SL:DOSEQ`, Macro

**Syntax:**

`(SL:DOSEQ (` *pattern source* `)` {declaration}* {*form*} `)` → *result*

`(SL:DOSEQ ((` *pattern index* `)` *source* `)` {declaration}* {*form*} `)` → *result*

**Arguments and Values:**

- *pattern* — a symbol or destructuring pattern. A dotted pair such as
  `(key . value)` destructures a cons entry, such as an alist element. A
  hash-table or dict element is an `SL:MAP-ENTRY` object; bind it to a symbol and
  use `SL:ENTRY-KEY` and `SL:ENTRY-VALUE`, or destructure it directly with the
  `(:ENTRY k v)` pattern defined in Chapter 8.
- *index* — a symbol bound to the zero-based traversal index.
- *source* — a form evaluated once to produce a seqable object.
- *declaration* — a leading declaration form interpreted as specified in Chapter 8.
- *form* — a body form.
- *result* — values returned by `RETURN`, or `NIL` on normal completion.

The indexed syntax is selected only when the outer binding form is a proper
two-element list whose first element is a proper two-element list whose second
element is a symbol. A dotted pair in the pattern position is a destructuring
pattern. A proper list of three or more elements in the pattern position is a
destructuring pattern. Any binding form that does not match the indexed syntax
is a destructuring pattern; its first component is the element pattern.
Consequently, a proper two-element list in the pattern position whose second
element is a symbol is captured by the indexed syntax. To destructure an
element that is itself a two-element list, use a dotted or nested pattern, or
bind the whole element and destructure it in the body with `SL:BIND`.

**Description:**

Evaluates *source* once and traverses it in element order using the seq protocol,
evaluating the body once for each element after binding *pattern*. The number
and sequence of primitive seq-protocol calls is unspecified. A symbol pattern
binds the whole element. A non-symbol pattern is destructured as specified in
Chapter 8. Hash-table and dict elements are `SL:MAP-ENTRY` objects, so their
natural patterns bind the entry to a symbol and project with `SL:ENTRY-KEY` and
`SL:ENTRY-VALUE`, or destructure it directly with the `(:ENTRY k v)` map-entry
pattern defined in Chapter 8. A `(key . value)` dotted pattern applies to cons
entries such as alist elements, not to `SL:MAP-ENTRY` objects. With the indexed
syntax, the index starts at zero and increases by one per element.

The body begins with any leading declarations and is then an implicit `TAGBODY`
within an implicit `(BLOCK NIL ...)`. Declarations have the scope specified in
Chapter 8: declarations naming the element or index apply to each corresponding
binding as it is established, while free declarations do not govern the source
expression or destructuring defaults. Tags, `GO`, and `RETURN` retain their
existing meanings. Element and index bindings contain values, not SETF-able
source places.

**Exceptional Situations:**

Signals an error of type `TYPE-ERROR` if the value of *source* is not seqable.
Signals an error of type `PROGRAM-ERROR` for malformed syntax or an invalid
pattern. Destructuring might signal an error of a type specified in Chapter 8.

Conditions signaled during traversal, including conditions signaled by forcing
lazy-sequence nodes, propagate to the `SL:DOSEQ` caller.

### 4.2.3 Map Entry Protocol

### SL:MAP-ENTRY _Type_

**Name:** `SL:MAP-ENTRY`, Type

**Syntax:**

`SL:MAP-ENTRY`

**Arguments and Values:**

A value of this type is an immutable keyed entry.

**Description:**

Names the class of immutable map entries. An entry contains a key and value, is
not seqable, and has no SETF accessors. Entry identity is unspecified. Under
`*PRINT-READABLY*` true, printing an `SL:MAP-ENTRY` signals
`PRINT-NOT-READABLE`. Equality and comparison are defined in Chapter 7.

**Exceptional Situations:**

Printing with `*PRINT-READABLY*` true signals an error of type
`PRINT-NOT-READABLE`.

### SL:MAP-ENTRY _Function_

**Name:** `SL:MAP-ENTRY`, Function

**Syntax:**

`(SL:MAP-ENTRY` *key value* `)` → *map-entry*

**Arguments and Values:**

- *key* — any object.
- *value* — any object.
- *map-entry* — an `SL:MAP-ENTRY` object.

**Description:**

Returns an immutable entry containing *key* and *value*.

**Exceptional Situations:**

None.

### SL:ENTRY-KEY _Function_

**Name:** `SL:ENTRY-KEY`, Function

**Syntax:**

`(SL:ENTRY-KEY` *map-entry* `)` → *key*

**Arguments and Values:**

- *map-entry* — an `SL:MAP-ENTRY` object.
- *key* — its key.

**Description:**

Returns the key of *map-entry*. No SETF accessor is defined.

**Exceptional Situations:**

Signals an error of type `TYPE-ERROR` if *map-entry* is not an `SL:MAP-ENTRY`.

### SL:ENTRY-VALUE _Function_

**Name:** `SL:ENTRY-VALUE`, Function

**Syntax:**

`(SL:ENTRY-VALUE` *map-entry* `)` → *value*

**Arguments and Values:**

- *map-entry* — an `SL:MAP-ENTRY` object.
- *value* — its value.

**Description:**

Returns the value of *map-entry*. No SETF accessor is defined.

**Exceptional Situations:**

Signals an error of type `TYPE-ERROR` if *map-entry* is not an `SL:MAP-ENTRY`.

### 4.2.4 Collector Protocol

### SL:MAKE-COLLECTOR-FOR _Generic Function_

**Name:** `SL:MAKE-COLLECTOR-FOR`, Generic Function

**Syntax:**

`(SL:MAKE-COLLECTOR-FOR` *target* `&REST` *options* `&KEY` `)` → *collector*

**Arguments and Values:**

- *target* — a class object on the designator path, or a seqable source object on
  the reconstruction path.
- *options* — keyword and value pairs accepted by the selected method.
- *collector* — fresh mutable Collector state.

**Description:**

Creates fresh Collector state. Both operation paths invoke ordinary CLOS dispatch on
*target*, the actual argument. On the designator path, *target* is the resolved
class object, so an `EQL` specializer on that object is applicable through normal
method precedence. On the reconstruction path, *target* is the seqable source
instance, so class specialization and inheritance apply through ordinary CLOS
dispatch. If a class object is also a seqable source, the same applicable methods
and normal `EQL` precedence apply when that object is passed; no intended-path
override or method filtering is performed. An extension supporting both roles
must satisfy both the designator-path result contract and the
reconstruction-path source-type contract. An unsupported target signals an error
of type `TYPE-ERROR`.

**Method Signatures:**

Designator-path methods:

- `((target (EQL (FIND-CLASS 'list))) &KEY)`.
- `((target (EQL (FIND-CLASS 'vector))) &KEY (element-type T))`.
- `((target (EQL (FIND-CLASS 'string))) &KEY (element-type 'character))`.
- `((target (EQL (FIND-CLASS 'hash-table))) &KEY (test 'EQUAL))`.
- `((target (EQL (FIND-CLASS 'SL:ORDERED-DICT))) &REST options &KEY)`.
- `((target SL:ORDERED-DICT) &REST options &KEY)` — the corresponding
  reconstruction-path method, using no prototype contents.

Both ordered methods are required non-default primary methods and return fresh
mutable Collector state. They accept no options; even a `:TEST` option signals
`PROGRAM-ERROR`. This does not change the separate batch `SL:DICT-COLLECT`
method, which ignores its supplied test (Chapter 9).

Standardized reconstruction-path methods have the same keyword signatures as
their corresponding designator-path methods and use ordinary CLOS dispatch on
the seqable source object. A class-specialized method is their usual shape:
`((target` *source-class* `) &KEY` ...`)`; if the source object is itself a
class object, an applicable primary method with an `EQL` specializer on that
object also participates.

Additional standardized methods are defined in later chapters.

**Exceptional Situations:**

Signals an error of type `TYPE-ERROR` for an unsupported target or when an
option value is not valid for the selected target. For an unsupported target
with a well-formed option list, this `TYPE-ERROR` takes precedence over option
validation; option-acceptance and option-value errors are signaled only for
supported targets. A string target requires its `:ELEMENT-TYPE` to designate a
subtype of `CHARACTER`. A hash-table target requires its `:TEST` to be a
designator for one of the standard hash-table test functions `EQ`, `EQL`,
`EQUAL`, or `EQUALP`.
Signals an error of type `PROGRAM-ERROR` if *options* is not a proper keyword
and value list or contains an option not accepted by a standardized method.

### SL:COLLECTOR-ACCUMULATE _Generic Function_

**Name:** `SL:COLLECTOR-ACCUMULATE`, Generic Function

**Syntax:**

`(SL:COLLECTOR-ACCUMULATE` *collector element* `)` → *collector*

**Arguments and Values:**

- *collector* — Collector state.
- *element* — an object to accumulate.

**Description:**

Adds *element* to *collector* and returns the same Collector object. Standardized
Collectors accept any object for a list target, an object of the selected
element type for a vector target, a character of the selected element type for
a string target, and an `SL:MAP-ENTRY` for a hash-table target.

**Method Signatures:**

Standardized Collector methods provide the following applicable behavior:

- A list Collector accepts any object.
- A vector Collector accepts an object of the selected element type.
- A string Collector accepts a character of the selected element type.
- A hash-table Collector accepts an `SL:MAP-ENTRY` and stores its key and value.
- An ordered-dictionary Collector accepts every `SL:MAP-ENTRY`, including
  duplicate keys, and returns the same Collector. A non-entry signals
  `TYPE-ERROR` before contributing anything. Successful accumulations follow
  Chapter 9's first-position/last-association-wins policy. Refusal recovery,
  retained prior successes, and finalization caching follow Section 4.1.6.

**Exceptional Situations:**

Signals an error of type `TYPE-ERROR` if *collector* is not a Collector, when a
vector or string element is incompatible with its element type, when a
hash-table Collector receives a non-`SL:MAP-ENTRY`, or when an ordered-dictionary
Collector receives a non-`SL:MAP-ENTRY`.

### SL:COLLECTOR-RESULT _Generic Function_

**Name:** `SL:COLLECTOR-RESULT`, Generic Function

**Syntax:**

`(SL:COLLECTOR-RESULT` *collector* `)` → *result*

**Arguments and Values:**

- *collector* — Collector state.
- *result* — its finalized collection.

**Description:**

Finalizes *collector* and returns its result. Standardized result types include
list, vector, string, hash table, and `SL:ORDERED-DICT` according to the target.
An ordered result contains exactly the successfully accumulated associations
under the uniqueness policy, including a typed empty result. Successful
finalization caches the same object under `EQ`. A failed finalization or
non-local exit does not cache a result or consume the successful accumulations;
finalization remains retryable. Accumulation after finalization has undefined
consequences.

**Method Signatures:**

Standardized Collector methods return a list, vector, string, hash table, or
`SL:ORDERED-DICT` according to the target.

**Exceptional Situations:**

Signals an error of type `TYPE-ERROR` if *collector* is not a Collector.
Accumulation after finalization has undefined consequences.
