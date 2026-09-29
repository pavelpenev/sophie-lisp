# Chapter 9: Dictionaries and the Dict Protocol

## 9.1 Concepts

### 9.1.1 Protocol Overview

A **dict** is an object that indexes values by key. The dict protocol is the keyed counterpart of
the seq protocol (Chapter 4): where a seq answers "what is at position *i*", a dict answers "what
is associated with *k*". The primitive generic functions `SL:DICT-REF`, `SL:DICT-TEST`, and
`SL:DICT-SIZE` are the required extension protocol for user-defined dict types; `SL:DICT-SET`,
`SL:DICT-WITHOUT`, and `SL:DICT-COLLECT` are optional extensions. Every dict is seqable: its
elements are `SL:MAP-ENTRY` objects (Chapter 4), so every traversal operation of Chapters 4 and 6
operates on a dict without modification.

The protocol specifies behavior, not performance. `SL:DICTP` means that an object participates in the full dict
protocol: it supports `SL:DICT-REF`, `SL:DICT-TEST`, `SL:DICT-SIZE`, and seqability. The lookup cost
is a property of the concrete type, not of the protocol. The concrete type `SL:DICT` carries the
performance guarantees of [Section 9.1.2](#912-the-sldict-persistent-map-type); other conforming types
carry whatever their documentation states.

### 9.1.2 The SL:DICT Persistent Map Type

`SL:DICT` is a persistent, immutable map with an implementation-dependent representation. Lookup,
non-destructive add, and non-destructive remove have O(1) expected complexity. `SL:DICT` is immutable: dict-producing operations produce dicts and do not mutate their input. A persistent structure
is never modified in place: every update returns a dict that shares structure with the
original, and the original remains valid and unchanged; absent-key `SL:DICT-WITHOUT` may return
the input dict unchanged when the key is absent. Because updates share structure, a sequence of updates
costs proportionally to the change, not to the whole contents, and holding on to older versions is cheap.

| Property | Value |
|----------|-------|
| Lookup (`SL:DICT-REF`) | O(1) expected |
| Non-destructive add (`SL:DICT-SET`) | O(1) expected, shares structure |
| Non-destructive remove (`SL:DICT-WITHOUT`) | O(1) expected, shares structure |
| Entry traversal | `(SL:SEQ-INTO 'LAZY-SEQ dict)` → a lazy-seq of `SL:MAP-ENTRY` objects |
| Keys/values | `SL:DICT-KEYS`/`SL:DICT-VALS` derive via `SL:SEQ-MAP` over the entries |
| Size (`SL:DICT-SIZE`) | O(1) expected |
| Key equality | `SL:EQUALS` (returned by `SL:DICT-TEST`) |
| Key hashing | `SL:HASH-CODE` |
| Coercion to a hash table | `(SL:SEQ-INTO 'hash-table dict)` — an O(n) copy |
| Mutation | None; `SL:DICT` is immutable. Use a hash table for mutation. |

The O(1) bounds are expected bounds under `SL:HASH-CODE`; degradation under adversarial hashing is
a performance concern, never a correctness one (Chapter 7).

`SL:DICT` is seqable: `(SL:SEQ-INTO 'LAZY-SEQ dict)` yields a lazy-seq of `SL:MAP-ENTRY`
objects, exactly as hash-table traversal does (Chapter 4). Traversal order is unspecified and may
differ between separate traversal calls on the same unmodified dict; traversal within a single
lazy-seq view is stable across forcings of that view, and repeated forcing of that view returns the
same memoized `SL:MAP-ENTRY` objects. Because `SL:DICT` is structurally immutable — no operation
modifies the dict itself — the modification-during-traversal hazard of Chapter 4 cannot arise for a
resident `SL:DICT`. This immutability is structural only: it does not extend to objects resident in
the dict. The consequences are undefined when an object used as a key while it is resident is
mutated in a way that changes its equality or hash behavior ([Section
9.1.6](#916-dict-consistency-laws)).

Equality and comparison on a circular key or value may not terminate, as specified in
Chapter 7. A finite decisive prefix returns normally, and any result returned by
those operations remains subject to the Chapter 7 protocol laws; a dict operation
that invokes a nonterminating call consequently may not terminate. `SL:HASH-CODE`
remains bounded and cycle-safe for finite structural keys and values and must not
recurse forever on a finite cycle. These rules do not make the dict consistency
laws undefined for an operation whose protocol calls return.

Key matching in an `SL:DICT` uses `SL:EQUALS` with `SL:HASH-CODE`. Any object acceptable to those
two functions is acceptable as a key.

### 9.1.3 Concrete Dict Types

The built-in dict types are:

| Type | `SL:DICTP` | Lookup | Mutable | Use case |
|------|---------|--------|---------|----------|
| `SL:ORDERED-DICT` | Yes | O(1) expected | No | Persistent keyed collection with stored order (Section 9.1.18) |
| `SL:DICT` | Yes | O(1) expected | No | Default dict result, functional pipelines |
| `hash-table` | Yes | O(1) expected | Yes, via `(SETF SL:DICT-REF)` | CL interop, mutation |
| `plist-dict-view` | Yes | O(n) | No | Read-only dict-protocol view of a plist |

Alists, plists, and sets are not dicts in raw form. An alist is a seq of conses; a plist is a seq;
neither supports keyed lookup through the dict protocol. Conversion between these shapes and dicts
is by the explicit auxiliary functions `SL:ALIST-DICT`, `SL:PLIST-DICT`, `SL:DICT-ALIST`, and
`SL:DICT-PLIST` ([Section 9.1.8](#918-construction-and-conversion)); there is no implicit
conversion ([Section 9.1.9](#919-no-shape-sniffing)).

A `SL:PLIST-DICT-VIEW` participates in the dict protocol but has no collector. Dict-producing
transformations on it fall back to `SL:DICT`.

A hash table's write surface within the dict protocol is `(SETF SL:DICT-REF)`, which is equivalent
to `(SETF GETHASH)` and mutates the table. It also supports the non-destructive
`SL:DICT-SET` and `SL:DICT-WITHOUT` operations. Each makes a shallow copy of the
container, preserves the table's standard `EQ`, `EQL`, `EQUAL`, or `EQUALP` test,
and leaves the source unchanged; resident key and value objects are not copied.
The copy is O(n) in the table's entry count. A `SL:PLIST-DICT-VIEW` remains
read-only and declines both functional update operations.

### 9.1.4 The Extension Protocol

A user-defined dict type participates by defining methods on the primitive generics:

| Primitive | Role | Required |
|-----------|------|----------|
| `SL:DICT-REF` | Keyed lookup: `dict-ref dict key &optional default` → `(values value present-p)` | Yes |
| `(SETF SL:DICT-REF)` | Stores a value on a mutable dict | Optional (mutable-dict operation) |
| `SL:DICT-TEST` | Returns the dict's equality-test designator | Yes |
| `SL:DICT-SIZE` | Count of unique keys | Yes |
| `SL:DICT-WITHOUT` | New dict without a key | Optional |
| `SL:DICT-SET` | New dict with a key set | Optional |
| `SL:DICT-COLLECT` | Constructs a dict of the source's type from a seq of `SL:MAP-ENTRY` objects | Optional (for type preservation) |

A type that defines the primitive methods must also define `SL:DICTP` returning T for its
instances, and must satisfy the seqability law of [Section 9.1.5](#915-dict-implies-seqable).
`SL:DICTP` without the primitives, or the primitives without `SL:DICTP`, is non-conforming. This
mirrors the seq protocol's conformance obligation for `SL:SEQABLEP` (Chapter 4).

**Lookup.** `SL:DICT-REF` returns two values: the value associated with the
key, and a generalized boolean that is true when the key was present. An
absent key returns `(values default NIL)`, where *default* is the supplied
optional argument or `NIL`. Key matching is governed by the dict's
`SL:DICT-TEST`.

**Test.** `SL:DICT-TEST` returns the equality-test designator identifying
the test used for key matching. For a hash table it returns the symbol naming the table's test
(`EQ`, `EQL`, `EQUAL`, or `EQUALP`). Hash-table tests are restricted to `EQ`, `EQL`, `EQUAL`, and
`EQUALP`. For hash tables using tests other than `EQ`, `EQL`, `EQUAL`, or `EQUALP`, behavior with
respect to the Sophie dict protocol is unspecified. For `SL:DICT` it returns the function
`#'SL:EQUALS`. A user type returns whatever designator its documentation
specifies. Test sameness between two dicts is determined by `EQ` on the
returned designators
([Section 9.1.12](#9112-type-preservation-for-dict-operations)). A conforming
type's `SL:DICT-TEST` must return the same `EQ`-identical designator on
repeated calls for the same dict. No universal canonicalization of test designators is required; the
`EQ`-on-designator test-sameness rule presupposes stability.

Key tests must be equivalence relations: reflexive, symmetric, and transitive. The consequences are
undefined if a key test violates this requirement.

Calling any dict primitive on an object that does not satisfy `SL:DICTP` signals an error of type
`TYPE-ERROR`.

**Validation ordering.** When multiple arguments are simultaneously invalid, the condition signaled is
unspecified unless an entry states otherwise. No callback is invoked after a detectable structural error.

**Size.** `SL:DICT-SIZE` returns the number of unique keys in the dict. It
must terminate for every conforming dict; all dicts are finite
([Section 9.1.6](#916-dict-consistency-laws)).

**Optional operations.** A user-defined dict type may decline `SL:DICT-SET` or
`SL:DICT-WITHOUT` by having no primary method more specific than `T`; a specialized declining method
that signals `PROGRAM-ERROR` is also permitted and does not constitute participation in the optional
operation. Calling the operation on such a dict signals `PROGRAM-ERROR`. The standardized
`hash-table` type supports both operations by shallow, non-destructive copying. A type that does
support them must obey the algebraic laws below.

**`SL:DICT-SET`/`SL:DICT-WITHOUT` algebraic laws.** For a type that supports them,
`SL:DICT-SET` and `SL:DICT-WITHOUT` obey all of the following:

1. **Closure.** The result is a `SL:DICTP` object.
2. **Persistence.** The original dict is unchanged. For mutable hash-table results, the result is
   newly allocated and not `EQ` to the input. For persistent dict types, result identity is
   unspecified; an implementation may return the input when the result is observationally equal.
   Structural sharing is permitted. A user type *should* share structure with the input where possible,
   but structural sharing is a recommendation, not a requirement: the normative obligations for user
   types are persistence and closure. For `SL:DICT` the result shares structure and updates run in O(1)
   expected time ([Section 9.1.2](#912-the-sldict-persistent-map-type)). For a `hash-table`, the
   result is a fresh shallow copy: copying the container is O(n), while resident keys and values
   retain their object identity and are not recursively copied.
3. **Lookup effects.** After `(SL:DICT-SET d k v)`,
   `(SL:DICT-REF result k)` returns `v` with present-p true; after
   `(SL:DICT-WITHOUT d k)`, `(SL:DICT-REF result k)` returns present-p false.
4. **Test preservation.** The result's `SL:DICT-TEST` is the same — `EQ` on
   the designator — as the input's.
5. **Size deltas.** `SL:DICT-SET` of a new key increments `SL:DICT-SIZE` by
   one; of an existing key leaves it unchanged. `SL:DICT-WITHOUT` of a
   present key decrements it by one.
6. **Unaffected keys.** Keys other than the operated-on key are unchanged by
   either operation.
7. **Absent-key removal is a no-op.** `(SL:DICT-WITHOUT d k)` where `k` is
   absent returns a dict equal to `d`, where two dicts are *equal* when they
   have the same key/value associations under their test and the same
   `SL:DICT-TEST` designator (`EQ` on the designator).

**Mutation.** `(SETF SL:DICT-REF)` is an optional SETF generic function, not a
`DEFINE-SETF-EXPANDER`. On a mutable dict type it sets the value associated with a key; its default
argument is ignored during storage. On `SL:DICT` it signals an error of type `SIMPLE-ERROR`: an
immutable dict is not a writable backing collection, and the persistent update is `SL:DICT-SET`. On
a `SL:DICTP` type that defines no `(SETF SL:DICT-REF)` method, the call signals `PROGRAM-ERROR` via
the default `T` method. On an object that is not a `SL:DICTP` object, it signals `TYPE-ERROR`. The
condition type therefore depends on whether the type is wrong (`TYPE-ERROR`), the operation is
declined (`PROGRAM-ERROR`), or the object is inherently immutable (`SIMPLE-ERROR`).

The specified behavior for instances of the standardized built-in classes in this chapter takes
precedence over methods that would otherwise be selected because of a host implementation's class
hierarchy. An implementation must ensure that method selection preserves all such behavior specified
in this chapter. More-specific methods on conforming user-defined subclasses take precedence through
normal CLOS dispatch.

### 9.1.5 Dict Implies Seqable

Every dict is seqable. Traversing a dict yields `SL:MAP-ENTRY` objects, one for each resident
association, and `(SL:SEQ-INTO 'LAZY-SEQ dict)` returns a lazy-seq over those entries. This is a
mandatory conformance law rather than an optional capability.

Each direct traversal obtains one coherent view of the dict. `SL:SEQ-FIRST`, `SL:SEQ-REST`, and
`SL:SEQ-REF` on the same dict are consistent within a single traversal.

A user-defined dict type must have applicable methods, directly or by inheritance, on
`SL:SEQABLEP`, `SL:SEQ-EMPTYP`,
`SL:SEQ-FIRST`, `SL:SEQ-REST`, and `SL:SEQ-LENGTH`. `SL:SEQABLEP` returns true. `SL:SEQ-LENGTH`
must be non-traversing and must return `SL:DICT-SIZE` for the same object. The other methods
provide entry traversal consistent with Section 9.1.6.

A user-defined dict type must also **support** `SL:SEQ-REF`. Supporting it does not require
defining a specialized method: the traversal method specialized on `T` in Chapter 4 may supply the
required behavior. Thus the applicable-method obligation for the five methods above and the support
obligation for `SL:SEQ-REF` are distinct.

`SL:DICTP` without seqability is non-conforming. The converse does not hold: a seqable whose
elements happen to be `SL:MAP-ENTRY` objects is not thereby a dict; dictness additionally requires
the keyed-lookup protocol.

The standardized seq behavior for this chapter's built-in types is:

| Type | `SL:SEQABLEP` | `SL:SEQ-EMPTYP` | `SL:SEQ-FIRST` | `SL:SEQ-REST` | `SL:SEQ-REF` | `SL:SEQ-LENGTH` |
|---|---|---|---|---|---|---|
| `SL:DICT` | true | true exactly when `SL:DICT-SIZE` is zero | first entry in an unspecified traversal, or `NIL` when empty | remaining entries in that traversal as a seqable | positional entry lookup by traversal under Chapter 4 positional addressing; traversal order is unspecified, with no cross-call stability guarantee | non-traversing; equals `SL:DICT-SIZE` |
| `SL:ORDERED-DICT` | true | true exactly when `SL:DICT-SIZE` is zero | first stored-order entry, or `NIL` when empty | remaining entries in stored order as a seqable | positional entry lookup in stored order under Chapter 4 positional addressing; `-1` selects the last stored-order entry; the Chapter 4 traversal method may supply it | non-traversing; equals `SL:DICT-SIZE` |
| `SL:HASH-SET` | true | true exactly when `SL:SET-SIZE` is zero | first element in an unspecified traversal, or `NIL` when empty | remaining elements in that traversal as a seqable | zero-based element lookup by traversal; the Chapter 4 traversal method may supply it | non-traversing; equals `SL:SET-SIZE` |

For `SL:DICT` and `SL:HASH-SET`, separate traversals need not have the same order.
For unordered dicts (`hash-table` and `SL:DICT`), negative `SL:SEQ-REF` indices
use Chapter 4 positional addressing within one traversal view; the traversal order
is unspecified and there is no cross-call stability guarantee. For
`SL:ORDERED-DICT`, every traversal has stored order. Within one lazy-seq view,
memoization makes the observed traversal stable. All six behaviors are
standardized methods or standardized supported behavior for the purposes of
Chapter 4.

### 9.1.6 Dict Consistency Laws

The dict protocol has consistency laws, mirroring the seq protocol's laws (Chapter 4). Every
conforming dict obeys laws 1–5 while resident keys retain their equality and hash behavior. Law 6
governs mutation of resident keys when that behavior changes:

1. **Lookup/traversal agreement.** Every `SL:MAP-ENTRY` produced by
   traversing the dict has a key that `SL:DICT-REF` finds (present-p true)
   and a value that is `SL:EQUALS` to the value `SL:DICT-REF` returns for
   that key. Conversely, every key for which `SL:DICT-REF` returns
   present-p true appears in the traversal: every resident association has
   exactly one traversal entry, and any successful lookup has a traversal
   key equivalent to the queried key under `SL:DICT-TEST`. Traversal and
   lookup agree on the key set. This law is scoped to the complete
   traversal of a single lazy-seq view of the dict — for example, the
   lazy-seq returned by `(SL:SEQ-INTO 'LAZY-SEQ dict)`: within one such
   view, the entries produced are exactly the dict's stable entry set.
   Separate traversals of an unordered dict are not guaranteed to share
   order, and direct traversal calls on the dict itself fall under the same
   boundary: the law quantifies over the dict's stable entry set, not over
   any ordering shared between distinct traversals.
2. **Size agreement.** `SL:DICT-SIZE` equals the number of unique keys in
   the traversal.
3. **Test agreement.** `SL:DICT-TEST` returns the equality-test designator
   identifying the test used by
   `SL:DICT-REF` for key matching.
4. **Key uniqueness.** No two entries in the traversal share a key under
   `SL:DICT-TEST`.
5. **Finiteness.** All dicts are finite. `SL:DICT-SIZE` returns a
   non-negative integer; for `(SL:DICT-KEYS dict)`, where *dict* is a
   conforming dict, fully forcing the lazy-seq terminates after exactly
   `SL:DICT-SIZE` elements. (`SL:DICT-KEYS` itself accepts any seqable of
   entries, including an infinite one; this termination guarantee is scoped
   to dict subjects.) An
   infinite key space is a different abstraction, not a dict.
6. **Mutation of resident keys.** The consequences are undefined if an object used as a key while it
   is resident in a dict is mutated in a way that changes its equality or hash behavior. The dict may
   fail to find the key, find the wrong entry, or corrupt its internal structure. This mirrors the
   mutation-during-traversal rule of Chapter 4.

**Mutation during traversal.** The consequences are undefined if a source is mutated while a dict
operation is consuming it. This applies to every dict operation that traverses a source — including
mutation performed inside a `SL:DICT-TRANSFORM` callback and mutation of any dict being traversed by
`SL:DICT-MERGE` — and mirrors the mutation-during-traversal discipline of Chapter 4.

### 9.1.7 The Dict-Collector Protocol

User-defined dict types participate in type preservation ([Section
9.1.12](#9112-type-preservation-for-dict-operations)) via the dict-collector protocol, parallel to
the seq Collector (Chapter 4). Both protocols use instance-based dispatch on the source object's
class with standard CLOS method precedence, so a method on a parent class applies to subclasses
unless overridden. An applicable collector must preserve all required type invariants of its class,
including when the method is inherited. Both use method presence as the opt-in: a dict type that provides a
non-default primary `SL:DICT-COLLECT` method — one whose specializer is more specific than `T` — applicable to
its instances is *eligible* for type preservation by `SL:DICT-MERGE` and `SL:DICT-TRANSFORM`,
subject to the type- and test-sameness rules of [Section
9.1.12](#9112-type-preservation-for-dict-operations); one that does not falls back to `SL:DICT`.
Only a primary method confers participation: `:before`, `:after`, and `:around` methods do not
count toward it. Participation is determined internally by checking whether a non-default primary
`SL:DICT-COLLECT` method applicable to the source instance's class exists (by any
implementation-defined mechanism); the default `T` method is excluded from the participation test.
No separate user-facing predicate exists.

`SL:DICT-COLLECT` constructs a dict of the source's type from a seq of `SL:MAP-ENTRY`
objects. *source* is a prototype dict instance used for dispatch, test propagation, and construction or
configuration state needed to preserve invariants; the content comes entirely from *entries* (a
seqable yielding `SL:MAP-ENTRY` objects). A collector may use that state, but *entries* must supply
all contents of the result. Standardized callers propagate the source dict's `SL:DICT-TEST` as the `:test` argument. When `:test`
is omitted, it defaults to `EQL`. In the standardized
callers, `SL:DICT-COLLECT` receives the source selected according to the type-preservation rules in
Section 9.1.12. For `SL:DICT`
the result always uses `SL:EQUALS` regardless of *test*: the `SL:DICT` method ignores the *test*
argument, because `SL:DICT` has no configurable test. The default *test* (`EQL`) is meaningful
only for `hash-table` results and user dict types that accept a test.

`SL:DICT-COLLECT` on an unbounded entries seqable does not terminate. It forces all of *entries* at
call time.

The default `T` method signals an error of type `TYPE-ERROR`. A type whose class has no
non-default primary `SL:DICT-COLLECT` method applicable to it — neither defined nor inherited —
does not participate in dict type preservation and falls back to `SL:DICT` in `SL:DICT-MERGE` and
`SL:DICT-TRANSFORM`.

**Conformance obligation.** A `SL:DICT-COLLECT` method must:

- accept every `SL:MAP-ENTRY` object in *entries*;
- produce a dict whose `SL:DICT-TEST` is correct — for `SL:DICT`, always
  `SL:EQUALS`; for `hash-table` and user types that accept a test, the
  supplied *test*;
- return a dict that does not mutate any input. For mutable hash-table results, the
  result is newly allocated and not `EQ` to any input. For persistent dict types,
  result identity is unspecified.

*Exception for fixed-test user collectors.* Like `SL:DICT` itself — which ignores *test* and
always uses `SL:EQUALS` — a user dict type whose test is fixed by its construction may ignore an
incompatible supplied *test* or signal an error of type `PROGRAM-ERROR`, rather than adopt it. The
"produce a dict whose test is the supplied *test*" obligation above applies to types whose test is
configurable. Standardized callers (`SL:DICT-MERGE`, `SL:DICT-TRANSFORM`) pass the source's actual
`SL:DICT-TEST` as *test*, so a fixed-test type receives its own test in the type-preserving path;
the exception matters only when a caller supplies a test that does not match the type's fixed
test. Compatibility between a supplied *test* and a type's fixed test is determined by `EQ` on the
supplied and fixed test designators: the designators match when they are `EQ`, and do not match
otherwise.

If *entries* contains multiple `SL:MAP-ENTRY` objects whose keys are equal under the result dict's
test, the last one wins, matching the protocol-wide duplicate-key policy ([Section
9.1.10](#9110-duplicate-key-policy)). In standardized methods, a non-`SL:MAP-ENTRY` element signals
an error of type `TYPE-ERROR` immediately upon encountering it. A conforming
user method must likewise signal an error of type `TYPE-ERROR` upon encountering
a non-`SL:MAP-ENTRY` element.

Built-in `SL:DICT-COLLECT` methods exist for `SL:DICT`, `SL:ORDERED-DICT`, and `hash-table`.

**Collector bridge for the `'dict` target.** The `'dict` target of
`SL:SEQ-INTO` reaches this protocol through an adapter Collector: its
`SL:MAKE-COLLECTOR-FOR` method for `SL:DICT` returns Collector state whose
`SL:COLLECTOR-ACCUMULATE` stores `SL:MAP-ENTRY` objects in a vector and
whose `SL:COLLECTOR-RESULT` invokes `SL:DICT-COLLECT` with an empty
`SL:DICT` prototype and the accumulated entry sequence
(Chapter 4).
The batch operation and the incremental Collector lifecycle are therefore
distinct: `SL:DICT-COLLECT` itself is a batch operation, while the `'dict`
target accumulates incrementally and finalizes with one `SL:DICT-COLLECT`
call.

### 9.1.8 Construction and Conversion

| Form | What |
|------|------|
| `(SL:DICT :a 1 :b 2)` | Element constructor: alternating key/value arguments |
| `(SL:SEQ-INTO 'dict entry-seq)` | Universal converter, via the Collector protocol |
| `(SL:ALIST-DICT alist)` | Auxiliary: convert an alist to an `SL:DICT` |
| `(SL:PLIST-DICT plist)` | Auxiliary: convert a plist to an `SL:DICT` |
| `(SL:PLIST-DICT-VIEW plist)` | Adapter: read-only dict-protocol view of a plist |
| `(SL:DICT-ALIST dict)` | Auxiliary: convert a dict to an alist |
| `(SL:DICT-PLIST dict)` | Auxiliary: convert a dict to a plist |

`SL:DICT`, used as a function, is the element constructor, as `CL:VECTOR` and `CL:LIST` are for
their types. It takes alternating key and value arguments and returns an `SL:DICT`. It has no test
parameter: `SL:DICT` uses `SL:EQUALS` and `SL:HASH-CODE` for key comparison, always.

`SL:SEQ-INTO` with the `'dict` designator forces the source and constructs an `SL:DICT` from
its `SL:MAP-ENTRY` elements through the Collector protocol (Chapter 4; the `'dict` target does not
bypass the Collector the way `'LAZY-SEQ` does). It converts any seqable of `SL:MAP-ENTRY` objects
— including another dict or a hash table — into an `SL:DICT`.

The auxiliary conversions are library-level conveniences, not protocol primitives. `SL:ALIST-DICT`
and `SL:PLIST-DICT` convert an alist or plist into an `SL:DICT`; `SL:DICT-ALIST` and
`SL:DICT-PLIST` convert any dict into an alist or plist. All four resolve duplicate keys by the
last-wins policy of [Section 9.1.10](#9110-duplicate-key-policy). The order of the alist or plist
produced from a dict follows the dict's traversal order (stored order for `SL:ORDERED-DICT`, unspecified for `SL:DICT`).

`SL:PLIST-DICT-VIEW` aliases its backing plist; it does not copy it. The consequences are undefined
if the backing plist is mutated while the view exists.

An odd number of arguments to `SL:DICT` signals an error of type `PROGRAM-ERROR`. Non-list or
improper alist inputs, or alist elements that are not conses, signal an error of type `TYPE-ERROR`.
An odd or improper plist signals an error of type `PROGRAM-ERROR`. For `(SL:SEQ-INTO 'hash-table dict)`,
the target hash table's test governs key
acceptance, and a key unacceptable to that test signals an error of type `TYPE-ERROR`. See Chapter 4
for `SL:SEQ-INTO`.

### 9.1.9 No Shape-Sniffing

`SL:SEQ-INTO` with the `'dict` target and the `SL:DICT` constructor never inspect the shapes of
list elements to guess intent. A list is a seq, not a dict: converting a list of conses with
`(SL:SEQ-INTO 'dict alist)` treats each cons as an ordinary element and signals `TYPE-ERROR`,
because a cons is not an `SL:MAP-ENTRY`. To convert an alist or plist to a dict, use the explicit
auxiliary functions `SL:ALIST-DICT` and `SL:PLIST-DICT`. The canonical entry type disambiguates
the reverse direction the same way Chapter 4 disambiguates hash-table traversal from alist
traversal: a dict or hash table yields `SL:MAP-ENTRY` objects, while an alist yields `(key .
value)` conses, so the two are never confused by shape.

### 9.1.10 Duplicate-Key Policy

Conforming dicts never have duplicate keys: keys are unique by construction. Entry seqs derived
from alists or plists may carry duplicates; conversion to a dict resolves them. The policy is
stated once here, at the protocol level. Last-wins is the *default* policy: it applies when
`:collision` is omitted or `:last-wins`. `SL:DICT-MERGE` and `SL:DICT-TRANSFORM` may specify
`:collision :error` instead, per [Section
9.1.14](#9114-the-sldict-merge-and-sldict-transform-collision-semantics). Otherwise the policy applies to
every construction context:

| Context | Policy |
|---------|--------|
| Construction: `SL:DICT` constructor (`(SL:DICT :a 1 :a 2)`) | Last-wins |
| Construction: `SL:SEQ-INTO` with the `'dict` target | Last-wins |
| Construction: `SL:DICT-COLLECT` | Last-wins |
| Construction: `SL:DICT-MERGE` | Last-wins by default (rightmost input wins); `:collision :error` available |
| Construction: `SL:DICT-TRANSFORM` | `:collision :last-wins` (default); `:collision :error` available |
| Construction: `SL:DICT-ZIPMAP` | Last-wins (later keys overwrite earlier) |
| Construction: `SL:ALIST-DICT`, `SL:PLIST-DICT` | Last-wins |
| Construction: `#d()` literal (Chapter 3) | Last-wins |
| `SL:DICT-SIZE` | Unique key count |

When last-wins resolves keys that are equal under the dict's test but not `EQ` — for example,
separately allocated but `EQUAL` strings — last-wins retains both the key and the value from the
last association. The key object from the earlier association is discarded.

Lookup is unambiguous in every context: because every conforming dict has unique keys by
construction, `SL:DICT-REF` finds exactly one entry for a present key. There is no first-match
versus last-match distinction for lookup on a dict.

### 9.1.11 Sets

A **hash-set** is a persistent, unordered collection of unique elements with an implementation-dependent
representation. The type is `SL:HASH-SET`; the predicate is `SL:HASH-SET-P`. A hash-set is immutable:
set operations produce results and do not mutate their inputs. Lookup has O(1) expected complexity.

**Seqability.** A hash-set is seqable: `SL:SEQABLEP` is true, and its
traversal yields the set elements directly, without wrapping them in
`SL:MAP-ENTRY` objects; stored elements may themselves be `SL:MAP-ENTRY`
objects. A set has no values. It supports the seq protocol primitives
`SL:SEQ-EMPTYP`,
`SL:SEQ-FIRST`, `SL:SEQ-REST`, `SL:SEQ-REF`, and a non-traversing
`SL:SEQ-LENGTH` equal to `SL:SET-SIZE`. Traversal order is unspecified and may
differ between separate traversal calls on the same unmodified hash-set;
traversal within a single lazy-seq view is stable across forcings of that
view, as for `SL:DICT` and hash-table. The consequences are undefined if a resident element of a
hash-set is mutated so that its `SL:EQUALS` or `SL:HASH-CODE` behavior changes.

**Collector.** A hash-set has a collector that deduplicates on accumulation.
`SL:SEQ-INTO` with the target designator `hash-set` works on any seq
(deduplicating). Accumulating an already-present element is successful
accumulation whose state does not change — not a refusal (Chapter 4).

**Not `SL:DICTP`.** A hash-set has no values; `SL:DICT-REF` does not apply. A
hash-set is not an `SL:DICTP` object. This transposes against the rule of
Section 9.1.5: a seqable type whose traversal yields elements is not thereby a
dict, and a hash-set's elements are stored directly without wrapping in
`SL:MAP-ENTRY` objects; stored elements may themselves be `SL:MAP-ENTRY`
objects. A dict viewed
as a seq is a seq of `SL:MAP-ENTRY` objects; `SL:SEQ-INTO` with target
`hash-set` on a dict therefore yields a set of entries (not keys). For a set
of keys, use `(SL:SEQ-INTO 'hash-set (SL:DICT-KEYS d))`. This follows the seq
law (Section 9.1.5) and the no-shape-sniffing principle (Section 9.1.9).

Equality, comparison, and hashing follow Section 9.1.16.

**Construction.** `(SL:HASH-SET &rest elements)` constructs a hash-set from
its arguments (deduplicating). `SL:SEQ-INTO` with target `hash-set`
constructs a hash-set from any seqable (deduplicating). The `#u()` reader
macro provides literal syntax (Chapter 3).

**Set operations.** The following operations accept any seqable as input.
Every sequence-producing set operation returns a hash-set regardless of input
type: the `set-` prefix requests set semantics. To preserve the input type
under element operations, use the `SL:SEQ-*` operations of Chapter 6 instead.
Explicit conversion and fixed-target operations are already allowed not to
preserve source type (Chapter 6).

| Operation | Signature | Notes |
|-----------|-----------|-------|
| `SL:SET-MEMBER` | *item sequence* → *generalized-boolean* | O(1) expected on `hash-set`, O(n) on other seqables |
| `SL:SET-ADD` | *item sequence* → *hash-set* | Deduplicates the source; future set operations are O(1) |
| `SL:SET-REMOVE` | *item sequence* → *hash-set* | Deduplicates by construction |
| `SL:SET-UNION` | *s1 s2 &rest more-sets* → *hash-set* | Set algebra produces a set |
| `SL:SET-INTERSECTION` | *s1 s2 &rest more-sets* → *hash-set* | Set algebra produces a set |
| `SL:SET-MINUS` | *s1 s2 &rest more-sets* → *hash-set* | Set subtraction |
| `SL:SET-SUBSET-P` | *s1 s2* → *generalized-boolean* | Boolean test, not type-preserving |
| `SL:SET-SIZE` | *sequence* → *non-negative-integer* | Count of distinct elements (O(1) on `hash-set`, O(n) on other seqables) |

**Any seqable can be used as input to set operations.** A list is a
non-deduplicated input; any sequence can be treated as a set input. Duplicate
elements are interpreted according to each operation's set semantics. `SL:SET-MEMBER` on a hash-set is O(1)
expected; on other seqables it delegates to traversal (O(n)). On a dict,
`SL:SET-MEMBER` checks whether any entry (`SL:MAP-ENTRY` object) matches the
item — this is incidental to dicts being seqable. For key membership, use
`SL:DICT-MEMBER` or `(SL:SET-MEMBER item (SL:DICT-KEYS d))`.

`SL:SET-SIZE` is the distinct element count, not sequence length:
`(SL:SET-SIZE '(1 1 1 1))` → `1`, while `(SL:SEQ-LENGTH '(1 1 1 1))` → `4`.

All set-producing operations use `SL:EQUALS` regardless of input types. This
determines whether values such as `1` and `1.0` coalesce (they do under
`SL:EQUALS`). Every set-producing operation returns a `SL:HASH-SET`; result
identity is unspecified. An implementation may return an input when the result is
observationally equal.

Examples in Appendix D show specific element order for illustration only; traversal order is unspecified.

**Infinite seqables.** `SL:SET-SIZE`, `SL:SET-SUBSET-P`, the set-producing
operations, and an unsuccessful `SL:SET-MEMBER` does not terminate on
unbounded inputs (Chapter 5). These operations are eager: they consume
all finite input at call time.

**Type preservation for built-in dict inputs to sequence operations.** For the
exact entry-subset roster in Chapter 6 — `SL:SEQ-FILTER`, `SL:SEQ-REMOVE`,
`SL:SEQ-REMOVE-IF`, `SL:SEQ-TAKE`, `SL:SEQ-DROP`, `SL:SEQ-TAKE-WHILE`,
`SL:SEQ-DROP-WHILE`, `SL:SEQ-SUBSEQ`, `SL:SEQ-TAKE-NTH`, `SL:SEQ-TAKE-LAST`,
`SL:SEQ-REMOVE-DUPLICATES`, `SL:SEQ-DEDUPE`, `SL:SEQ-TRIM-LEFT`,
`SL:SEQ-TRIM-RIGHT`, and `SL:SEQ-TRIM` — a built-in `SL:DICT` input produces
an `SL:DICT`, and a standard `hash-table` input produces a fresh hash table
with the same standard test. The operation uses one coherent traversal view,
retains exactly the selected key/value associations, leaves the source
unchanged, and promises no result order. Predicates, tests, and keys run at
call time according to the Chapter 6 callback rules. `SL:SEQ-DROP-LAST`,
sorting, reversal, mapping, multi-source operations, and nested-result
operations are not in this roster and retain their Chapter 6 return behavior.
A `SL:PLIST-DICT-VIEW` is not a built-in preserving input; its existing
read-only, no-Collector lazy fallback remains unchanged. User-defined dicts
have no new preservation obligation.

**Type preservation for seq operations.** A hash-set input under the Chapter 6
sequence operations follows the type-preservation principle of Chapter 6
with the added constraint that a hash-set has one defining invariant:
unique, unordered elements. The rule is: an operation returns a hash-set only
when its result is a subset of the input under the operation's selection rule,
so that uniqueness is preserved; every other transforming operation returns a
lazy-seq, because a hash-set would silently change cardinality by
deduplicating, or would impose an ordering that a set cannot faithfully
represent. Chapter 6 gives the exhaustive classification of the
transforming operations under this rule. The classification in Chapter 6 is
exhaustive for operations whose result type depends on an `SL:HASH-SET`
input.

**Type promotion for built-in dict inputs to sequence operations.** The 17 operations in Chapter 6's built-in dictionary promotion roster, when given a built-in `hash-table` or `SL:DICT`, produce an `SL:ORDERED-DICT` (Chapter 6). Promotion uses `SL:EQUALS` for key matching; the source hash-table test is not preserved. This roster is distinct from the 15-operation preservation roster above, whose operations preserve the source dict type.

### 9.1.12 Type Preservation for Dict Operations

For `SL:DICT-MERGE` and `SL:DICT-TRANSFORM`, type preservation requires all operands to have the
same dynamic class, the same `EQ`-identical `SL:DICT-TEST` designator, and that class to supply a
non-default `SL:DICT-COLLECT` method. When these conditions hold, the result preserves that class.
For non-identical user classes, the result type is implementation-defined; otherwise, when the
conditions for type preservation are not met, the result is `SL:DICT`.

`SL:DICT` always produces an `SL:DICT`. Hash tables preserve the `hash-table` type when the participating
operands have the same test and otherwise produce an `SL:DICT`. A `SL:PLIST-DICT-VIEW` has no collector
and therefore produces an `SL:DICT`. `SL:DICT-MERGE*` applies the rule at each binary fold step.

`SL:DICT-FREQUENCIES`, `SL:DICT-GROUP-BY`, and `SL:DICT-ZIPMAP` consume seqables rather than dict
prototypes and always return `SL:DICT`. `SL:DICT-VALUES-MAP`, `SL:DICT-KEYS-MAP`,
`SL:DICT-SELECT-KEYS`, and `SL:DICT-REMOVE-KEYS` consume one dict and preserve its type through
`SL:DICT-COLLECT` (with `SL:DICT` fallback where preservation is unavailable). `SL:DICT-MERGE-WITH`
uses the same result selection rule as `SL:DICT-MERGE`; `SL:DICT-COUNT-BY` always returns `SL:DICT`.

### 9.1.13 Operation Domains and Test Policy

The dict operations that produce keyed results have deliberately non-uniform
input domains and return types:

| Operation | Input domain | Returns |
|-----------|-------------|---------|
| `SL:DICT-FREQUENCIES` | any seqable of elements | `SL:DICT` |
| `SL:DICT-GROUP-BY` | any seqable of elements | `SL:DICT` (values are lists in source order) |
| `SL:DICT-ZIPMAP` | two seqables of elements | `SL:DICT` |
| `SL:DICT-MERGE` | `SL:DICTP` subjects only | type-preserving (Section 9.1.12) |
| `SL:DICT-MERGE-WITH` | two `SL:DICTP` subjects | type-preserving (Section 9.1.12) |
| `SL:DICT-TRANSFORM` | `SL:DICTP` subject only | type-preserving (Section 9.1.12) |
| `SL:DICT-VALUES-MAP` | `SL:DICTP` subject only | source-preserving through `SL:DICT-COLLECT` |
| `SL:DICT-KEYS-MAP` | `SL:DICTP` subject only | source-preserving through `SL:DICT-COLLECT` |
| `SL:DICT-SELECT-KEYS` | `SL:DICTP` subject and any finite seqable | source-preserving through `SL:DICT-COLLECT` |
| `SL:DICT-REMOVE-KEYS` | `SL:DICTP` subject and any finite seqable | source-preserving through `SL:DICT-COLLECT` |
| `SL:DICT-COUNT-BY` | function and any seqable | `SL:DICT` |
| `SL:DICT-REDUCE-KV` | function and `SL:DICTP` subject | scalar accumulator |
| `SL:DICT-REF` | `SL:DICTP` subject | *value present-p* |
| `SL:DICT-KEYS` | any seqable yielding `SL:MAP-ENTRY` objects | lazy-seq |
| `SL:DICT-VALS` | any seqable yielding `SL:MAP-ENTRY` objects | lazy-seq |

Passing an argument outside an operation's stated input domain signals an error of type `TYPE-ERROR`
unless otherwise specified in the operation's entry.

`SL:DICT-MERGE` and `SL:DICT-TRANSFORM` consume `SL:DICTP` subjects only; they do not accept an
entry seq as an alternative input domain. A caller starting with an entry seq must first convert it
with `(SL:SEQ-INTO 'dict entry-seq)`.
`SL:DICT-FREQUENCIES`, `SL:DICT-GROUP-BY`, and `SL:DICT-ZIPMAP` consume any
seqable of elements. `SL:DICT-KEYS` and `SL:DICT-VALS` consume any seqable
yielding `SL:MAP-ENTRY` objects — they need entry traversal, not
dict-specific lookup, so they work on hash tables, dicts, and any user
seqable of entries alike. `SL:DICT-REF` consumes a `SL:DICTP` subject.

**No `:test` keywords.** The operations in the table above accept no `:test`
keyword. The operations that construct or group keys — `SL:DICT-MERGE`,
`SL:DICT-TRANSFORM`, `SL:DICT-FREQUENCIES`, `SL:DICT-GROUP-BY`, and
`SL:DICT-ZIPMAP` — use the *result* dict's own `SL:DICT-TEST` for key
matching: `SL:DICT` results use `SL:EQUALS`; a type-preserved `hash-table`
result uses the table's own test. `SL:DICT-REF` uses its *subject's* test,
not a result's. `SL:DICT-KEYS` and `SL:DICT-VALS` perform no key matching at
all. The one exception to the prohibition is `SL:DICT-COLLECT`
(Section 9.1.7), which accepts a *test* keyword argument carrying the source
dict's test to the result; it is part of the collector protocol, not one of
the operations above.

The dict-protocol organizing principle is two regimes: `#'SL:EQUALS` for
equality and `#'SL:LT` / `SL:COMPARE` for ordering. The Chapter 6 operations
share the same two regimes, with `:test` defaulting to `#'SL:EQUALS` for
equality and `#'SL:LT` for ordering (Chapter 6).

Because `SL:EQUALS` considers `1` and `1.0` equal, `SL:DICT-FREQUENCIES` on
`(1 1.0 2)` counts `1` twice, and `(SL:DICT 1 :a 1.0 :b)` has one entry.
Users needing `EQL`-strict key distinction use a hash table with the `EQL`
test directly; no per-call escape hatch is provided on the `SL:DICT`
operations.

### 9.1.14 The SL:DICT-MERGE and SL:DICT-TRANSFORM Collision Semantics

`SL:DICT-MERGE` and `SL:DICT-TRANSFORM` take `SL:DICTP` inputs only, return a
dict, and never modify their inputs.

**`SL:DICT-MERGE` is binary.** Its signature is
`(SL:DICT-MERGE dict1 dict2 &key collision)`. For merging more than two dicts, use
`SL:DICT-MERGE*`, the variadic form (Section 9.2.1), which is always
`:last-wins` with no `:collision` option. The binary `SL:DICT-MERGE`
signature and `:collision` option remain as specified in its entry in
Section 9.2.1.

The default collision policy is `:last-wins` (the rightmost input wins when the relevant tests agree;
when differing tests collapse keys, the result is unspecified);
`:collision :error` signals `PROGRAM-ERROR` on the first collision detected under the selected
result dict's test. Collision detection is unconditional with respect to the source tests: it
includes distinct keys within one source that coalesce under the result test, as well as collisions
between sources. The result type and result test are selected before collision detection. If source
tests differ, the result is an `SL:DICT` with `SL:EQUALS`; under `:last-wins`, if distinct source
keys collapse under that test, the surviving value is unspecified. For unordered sources,
traversal order and thus the first detected collision are unspecified. For two
ordered dictionaries, traversal is left source then right source, each in stored
order (Section 9.1.18). No partial dictionary is returned after a collision.
An unrecognized policy signals `PROGRAM-ERROR` before any traversal begins.

`SL:DICT-TRANSFORM` is function-first. Its signature is
`(SL:DICT-TRANSFORM fn dict &key collision)`. The callback *function* takes two
arguments, the entry's key and value, and must return exactly two values, the
new key and the new value. `fn` is called once for each entry processed, in the dict's
traversal order (stored order for `SL:ORDERED-DICT`). The two-values check is made for each callback result before
that entry is accepted. Under `:collision :error`, the returned key is then checked under the
selected result dict's test; a collision signals `PROGRAM-ERROR` immediately, so no callback
runs for a later entry. The operation returns no partial dictionary, and side effects of callbacks
already run are not rolled back. The default collision policy is `:last-wins`; an unrecognized
policy signals `PROGRAM-ERROR` before any traversal begins. Under `:last-wins`, if traversal
order varies and distinct keys transform to the same key, the surviving value is unspecified.

### 9.1.15 The SL:REF Facade

`SL:REF` is a generic function facade over the two access protocols. Its
default `T` method dispatches dict-first: it tests `SL:DICTP` first and
delegates to `SL:DICT-REF` for `SL:DICTP` types; otherwise it tests
`SL:SEQABLEP` and delegates to `SL:SEQ-REF` for seqable-only types
(Chapter 4); otherwise it signals an error of type `TYPE-ERROR`. This facade
dispatch applies when no direct method is applicable. Standardized direct
methods may exist alongside it — Chapter 8 retains a direct hash-table
`SL:REF` method, for example — and such direct methods take precedence over
the default dispatch.

**Read facade.** The dict-first delegation to `SL:DICT-REF` is
suppliedness-preserving: when the caller supplies the optional *default*
argument, the delegated call receives it, and the second (present-p) value
of the delegate is returned as `SL:REF`'s second value. A supplied default
makes the call total exactly as specified in Chapter 8.

**Write facade.** `(SETF SL:REF)` delegates the same way: dict-first to
`(SETF SL:DICT-REF)` for `SL:DICTP` types, and to `(SETF SL:SEQ-REF)` for
seqable-only types. The setter accepts and ignores the optional *default*
and returns the new value as its sole value. A write on an immutable
`SL:DICT` signals `SIMPLE-ERROR` through the same path a direct
`(SETF SL:DICT-REF)` would.

**Direct methods.** The facade is not a required extension point. A user type
may define an `SL:REF` method directly, and existing `SL:REF` methods remain
legal; a user dict type that defines the dict primitives gets `SL:REF`
support through the facade without defining anything further. A direct
`SL:REF` method specializing on a user type takes precedence over the
default facade dispatch for reads. A direct `(SETF SL:REF)` method takes
precedence over the default `(SETF SL:REF)` dispatch for writes. Read and
write precedence are independent: `SL:REF` and `(SETF SL:REF)` are separate
generic functions, each with its own method precedence.

A direct `SL:REF` method on an object satisfying `SL:DICTP` must be
observationally equivalent to `SL:DICT-REF` for that object. A direct
`(SETF SL:REF)` method on an object satisfying `SL:DICTP` must be
observationally equivalent to `(SETF SL:DICT-REF)` for that object.

Chapter 8 remains the authoritative contract for `SL:REF`'s arguments,
values, and exceptional situations; this section restates the facade from
the dict protocol's side.

### 9.1.16 Equality, Comparison, and Hashing of Dicts and Hash-Sets

Chapter 7 defines the general equality, comparison, and hashing protocols. For the standardized
representations in this chapter, equality and comparison are same-representation structural
operations. `SL:COMPARE` returns `:EQUAL` exactly when the corresponding `SL:EQUALS` result is
true, and `:UNEQUAL` otherwise. There is no cross-representation coercion: objects of different
standardized representations remain unequal even when their traversed contents correspond.

Two `SL:DICT` objects are equal if and only if they have equal `SL:DICT-SIZE` counts and there is
a bijection between their associations such that corresponding keys and corresponding values are
recursively `SL:EQUALS`. Association order and the implementation's internal representation do not
participate.

Two `SL:ORDERED-DICT` objects are equal if and only if their sizes are equal
and corresponding entries in stored order have recursively `SL:EQUALS` keys
and values. Equality is order-sensitive, not a bijection ignoring order. An
ordered dictionary is unequal to an ordinary `SL:DICT`, hash table, plist view,
hash set, list (including `NIL`), vector, or lazy sequence in both argument
orders, including when both collections are empty. `SL:COMPARE` uses the
`:EQUAL`/`:UNEQUAL` rule above, never dictionary lexicographic ordering.

`SL:HASH-CODE` for an ordered dictionary hashes ordered association content
consistently with this equality, under Chapter 7's bounded cycle-safe policy.
Equal ordered contents must hash equally regardless of edit history, internal
shape, position labels, sharing, or the identity of equivalent resident keys.
Unequal orders may collide. Traversal depth, count, and mixing strategy remain
implementation-defined; no public hash-context protocol is introduced.

Two `SL:HASH-SET` objects are equal if and only if they have equal `SL:SET-SIZE` counts and there
is a bijection between their elements such that corresponding elements are `SL:EQUALS`. Element
traversal order and the implementation's internal representation do not participate.

For `SL:PLIST-DICT-VIEW`, the compared associations are the canonical first-occurrence `EQ`
associations presented by the view. Two views are equal if and only if they have equal canonical
association counts and there is a bijection between those associations such that corresponding keys
and corresponding values are recursively `SL:EQUALS`. This comparison is independent of the view's
`EQ` lookup test: `EQ`-distinct keys that are `SL:EQUALS` remain distinct canonical associations,
so their multiplicity is preserved. Raw duplicate associations after the first occurrence and the
order of the canonical associations do not participate.

`SL:HASH-CODE` on `SL:DICT`, `SL:HASH-SET`, and `SL:PLIST-DICT-VIEW` is
order-independent and consistent with the corresponding `SL:EQUALS` relation.
For a `SL:PLIST-DICT-VIEW`, only the canonical first-occurrence associations
participate; raw duplicate associations after the first occurrence and the
order of the canonical associations do not participate,
and the multiplicity of canonical associations is preserved. Hashing follows
Chapter 7's bounded, cycle-safe traversal rules; its traversal depth, element
count, and mixing strategy are implementation-defined.

### 9.1.17 Nested Dict Paths

`SL:DICT-REF-IN`, `SL:DICT-SET-IN`, and `SL:DICT-UPDATE-IN` share a nested-path protocol. *keys* must
be a finite, nonempty seqable. An empty path signals `PROGRAM-ERROR`; a non-seqable path signals
`TYPE-ERROR`; the path is fully forced from left to right before traversal or rebuilding begins. An
unbounded path does not terminate.

Traversal proceeds left to right. If a present value must serve as an intermediate and is not a
`SL:DICTP` object, the operation signals `TYPE-ERROR`; a non-dict value at the leaf is valid. An absent
intermediate is treated according to the operation: `SL:DICT-REF-IN` reports an absent path, while
`SL:DICT-SET-IN` and `SL:DICT-UPDATE-IN` construct an empty intermediate. A constructed intermediate
preserves the parent type and test when the parent has an applicable non-default `SL:DICT-COLLECT`
method; this includes a standard `hash-table`, so the new intermediate is a fresh hash table with the
parent's standard test. Otherwise it is an `SL:DICT` using `SL:EQUALS`. Existing ancestors are rebuilt
with `SL:DICT-SET` (including shallow hash-table copies), and each such ancestor must support that
operation. These operations are eager and never mutate the input containers. A callback is invoked
only after detectable path errors have been checked; if it signals, no result is returned and the
input containers remain unchanged, but arbitrary effects of the callback are not rolled back.

### 9.1.18 Ordered Dictionaries

`SL:ORDERED-DICT` is a standardized persistent, structurally immutable dict
with a stored order. It is a distinct concrete CLOS class, not a subclass of
`SL:DICT`. It satisfies the complete Dict and Seq protocols. Its logical
sequence consists of one `SL:MAP-ENTRY` per resident key, in stored order;
`SL:DICT-SIZE` and the non-traversing `SL:SEQ-LENGTH` are equal. Independent
traversals of the same version observe the same ordered associations. Within a
lazy view, repeated forcing returns the same memoized entry objects under `EQ`.
Entry identity across distinct views is unspecified.

`SL:DICTP` is the generic Dict-protocol predicate. The `SL:DICT` API is
specified in Section 9.1. No additional package, `MAKE-ORDERED-DICT` function,
or ordered reader syntax is standardized. Direct `MAKE-INSTANCE` construction
and subclassing of `SL:ORDERED-DICT` have undefined consequences, as specified
in the `SL:ORDERED-DICT` type entry and Chapter 1, Section 1.4.4.

**Construction and updates.** Key matching uses `SL:EQUALS` and `SL:HASH-CODE`.
`SL:DICT-TEST` returns the function `#'SL:EQUALS`, as for `SL:DICT`, with the
stable `EQ`-identical designator required by Section 9.1.4. There is no
configurable test. The first occurrence of a key fixes its position. Each later
equivalent key replaces both the resident key object and value at that position,
even when the new value is `EQ` to the old value. A novel key appends. Removing
a key preserves the relative order of all others; removing and subsequently
reinserting that key appends it. Absent-key removal may return the input.
Updates share immutable structure and must not alter any earlier version or
cursor. Structural immutability does not freeze contained objects. The resident-
key mutation rule of Section 9.1.6 and the method-redefinition restriction of
Chapter 7 apply. Mutable values remain observable; persistence does not authorize
stale cached value hashes.

The constructor, the ordinary incremental Collector, Chapter 6 reconstruction,
and `SL:DICT-COLLECT` all apply this first-position/last-association-wins rule
to their input encounter order. Duplicate keys are successful accumulation,
not Collector refusal. The `SL:DICT-COLLECT` method ignores the prototype's
contents and any supplied `:TEST`, including an incompatible test; the result
always uses `SL:EQUALS`. It forces its entry source at call time and signals
`TYPE-ERROR` on encountering a non-entry. The ordinary incremental Collector
for `SL:ORDERED-DICT` accepts no options, including `:TEST`; unsupported
options signal `PROGRAM-ERROR` at Collector creation. These are different
protocol surfaces, not inconsistent test policies.

**Access and reconstruction.** `SL:SEQ-REF` is positional under Chapter 4 positional addressing and yields an entry; on an ordered dictionary, `-1` selects the last stored-order entry. `SL:DICT-REF` and `SL:REF` are keyed and yield a value, including for integer keys: with `-1`, they look up key `-1`, not the last entry. Their presence/default rules are unchanged. `SL:SEQ-REST` yields a lazy
view of the remaining entries, not a reconstructed dictionary. Chapter 6's
[ordered reconstruction policy](chapter-06-sequence-operations.md#611-type-preserving-returns)
preserves the ordered type strictly: only emitted entries are accepted, with no
widening, content-based type inference, or fallback after refusal. Empty
reconstructed results remain ordered dictionaries. Reversal, sorting, and other
transformations establish the result's new stored order; a later novel
`SL:DICT-SET` appends to that order, not to historical insertion chronology.

**Derived Dict operations.** The eligibility and test-sameness rules of Section
9.1.12 apply unchanged. `SL:DICT-MERGE` of two ordered dictionaries consumes the
left entries then the right entries, each in stored order. Left positions remain;
right collisions replace associations without moving them, and novel right keys
append in right order. `SL:DICT-MERGE*` applies this rule at each left-fold step.
Mixed standardized dict classes fall back to ordinary `SL:DICT`, not to an
ordered result. `SL:DICT-TRANSFORM` visits entries in stored order and
reconstructs the emitted associations in that encounter order. Exactly two
callback values are required; `:COLLISION :ERROR` retains its immediate first-
collision cutoff, with no later callback and no partial result. `:LAST-WINS`
uses the first transformed position and latest transformed key object and value.
An unknown collision policy signals `PROGRAM-ERROR` before traversal.

`SL:DICT-UPDATE`, `SL:DICT-SET-IN`, and `SL:DICT-UPDATE-IN` rebuild through
`SL:DICT-SET`, preserving each ordered ancestor's positions and appending newly
created keys. Missing intermediates under an ordered parent are empty ordered
dictionaries with its fixed test. Existing mixed-type ancestors retain their
own supported update behavior. A present `NIL` leaf is not absence; a present
non-dict intermediate remains a `TYPE-ERROR`. Path validation and callback timing
are those of Section 9.1.17 and the operation entries.

`SL:DICT-KEYS` and `SL:DICT-VALS` remain lazy projections in stored order;
`SL:DICT-ALIST` and `SL:DICT-PLIST` remain fresh lists in that order. None uses
an ordered Collector for projected scalar values. `SL:DICT-FREQUENCIES`,
`SL:DICT-GROUP-BY`, `SL:DICT-ZIPMAP`, `SL:ALIST-DICT`, and `SL:PLIST-DICT`
retain their fixed ordinary `SL:DICT` results; group value lists retain source
encounter order. Set-producing operations retain their fixed `SL:HASH-SET`
results and consume entries, not keys. No fixed-result operation infers an
ordered result from its source or contents.

**Complexity.** As for `SL:DICT`, performance requirements belong to the concrete
type rather than the Dict protocol. Ordered keyed lookup and size have O(1)
expected container cost; traversal has O(n) container cost for n resident keys.
The implementation must document update and bulk-construction costs separately,
including order-maintenance work, hashing/equality callback costs, collision
degradation, and costs that depend on the magnitude of internal position labels.
The O(1) update guarantee for `SL:DICT` is not a guarantee for `SL:ORDERED-DICT`.
No particular tree, hash index, cached representation, or benchmark threshold is
required.

## 9.2 Dictionary

Notes and examples for this chapter appear in Appendix D.

**Dictionary Conventions.** Programs may define methods for their own types, subject to the conformance laws in Sections 9.1.4–9.1.7. Conforming programs must not override the enumerated standardized methods. Methods on subclasses remain permitted and take effect.

### 9.2.1 The Dict Protocol

### Dict Protocol _Protocol_

**Name:** Dict Protocol

Covers: `SL:ORDERED-DICT`, `SL:ORDERED-DICT-P`, `SL:DICT`, `SL:DICTP`, `SL:DICT-REF`, `SL:DICT-REF-IN`, `SL:DICT-TEST`, `SL:DICT-SIZE`, `SL:DICT-SET`,
`SL:DICT-WITHOUT`, `SL:DICT-COLLECT`, `SL:DICT-KEYS`, `SL:DICT-VALS`, `SL:DICT-FREQUENCIES`,
`SL:DICT-GROUP-BY`, `SL:DICT-ZIPMAP`, `SL:DICT-MERGE`, `SL:DICT-MERGE*`, `SL:DICT-MERGE-WITH`, `SL:DICT-MEMBER`,
`SL:DICT-UPDATE`, `SL:DICT-UPDATE-IN`, `SL:DICT-SET-IN`, `SL:DICT-TRANSFORM`, `SL:DICT-VALUES-MAP`,
`SL:DICT-KEYS-MAP`, `SL:DICT-SELECT-KEYS`, `SL:DICT-REMOVE-KEYS`, `SL:DICT-COUNT-BY`, `SL:DICT-REDUCE-KV`,
`SL:ALIST-DICT`, `SL:PLIST-DICT`, `SL:PLIST-DICT-VIEW`, `SL:DICT-ALIST`, and `SL:DICT-PLIST`.

This section covers 36 symbols in 40 dictionary entries.

**Ordered dispatch cases.** In addition to the signatures enumerated in the
individual primitive entries below, the following standardized methods apply;
the complete respective entry's arguments, defaults, and conditions apply.

| Generic function | Ordered method signature and behavior |
|---|---|
| `SL:DICTP` | `((object SL:ORDERED-DICT))` → true |
| `SL:DICT-REF` | `((dict SL:ORDERED-DICT) key &optional default)` → keyed value and presence; expected O(1) container lookup |
| `(SETF SL:DICT-REF)` | `(new-value (dict SL:ORDERED-DICT) key &optional default)` → signals `SIMPLE-ERROR`, including for absent keys; input unchanged |
| `SL:DICT-TEST` | `((dict SL:ORDERED-DICT))` → the stable function `#'SL:EQUALS` |
| `SL:DICT-SIZE` | `((dict SL:ORDERED-DICT))` → maintained unique-key count, without traversal |
| `SL:DICT-SET` | `((dict SL:ORDERED-DICT) key value)` → ordered persistent update under Section 9.1.18 |
| `SL:DICT-WITHOUT` | `((dict SL:ORDERED-DICT) key)` → ordered persistent removal under Section 9.1.18 |
| `SL:DICT-COLLECT` | `((source SL:ORDERED-DICT) entries &key (test 'EQL))` → ordered dictionary from entries only; ignores *test* |

The ordinary Collector requires applicable non-default primary methods for
both the ordered class-object and instance paths (Chapter 4). The batch
`SL:DICT-COLLECT` method is also a required non-default primary method. These
requirements confer reconstruction eligibility without probing by execution.
Derived Dict operations use their existing general methods and the ordered
semantics of Section 9.1.18; no new derived-method extension surface is added.

For dict results in this section, a dict operation returns a dict with the specified associations and does not mutate its inputs. For mutable hash-table results, the result is newly allocated and not EQ to any input. For immutable or persistent dict types, result identity is unspecified; an implementation may return any observationally equivalent value, including an input for a no-op. `Exceptional Situations` lists specified situations
and is non-exhaustive.

### SL:DICT _Type_

**Name:**

`SL:DICT`, Type

**Syntax:**

`SL:DICT`

**Arguments and Values:**

The type has no runtime arguments. A value of this type is a persistent dict.

**Description:**

`SL:DICT` names the CLOS class of the persistent dict instances produced by the `SL:DICT` constructor,
`SL:SEQ-INTO` with the `'dict` target, `SL:DICT-COLLECT`, and the dict-producing operations of this
chapter. Direct instantiation via `MAKE-INSTANCE` or subclassing of `SL:DICT` has undefined consequences.

An `SL:DICT` prints as a `#d(...)` form. Under `*PRINT-READABLY*`, printing one whose keys or values
contain unreadable objects signals `PRINT-NOT-READABLE`; exact round-tripping requires self-evaluating
keys and values (Chapter 3).

**Exceptional Situations:**

- Under `*PRINT-READABLY*`, printing an `SL:DICT` whose keys or values contain unreadable objects
  signals `PRINT-NOT-READABLE`.

**See Also:**

`SL:DICT` (Function); `SL:DICTP`; `SL:DICT-REF`; `SL:DICT-SET`; `SL:DICT-WITHOUT`; Chapter 4;
Chapter 7; Sections 9.1.2, 9.1.4–9.1.7, and 9.1.16.


### SL:DICT _Function_

**Name:**

`SL:DICT`, Function

**Syntax:**

`SL:DICT` `{key value}*` → *dict*

**Arguments and Values:**

- *key* — any object acceptable to `SL:EQUALS` and `SL:HASH-CODE`.
- *value* — any object.
- *dict* — an `SL:DICT`.

**Description:**

Constructs and returns an `SL:DICT` whose entries pair each *key* with its following *value*. The
number of arguments must be even. If the same key appears more than once, the last association
wins ([Section 9.1.10](#9110-duplicate-key-policy)); the resulting dict has one entry per unique
key.

There is no test parameter. `SL:DICT` uses `SL:EQUALS` for key matching and `SL:HASH-CODE` for
hashing, always ([Section 9.1.8](#918-construction-and-conversion)).

**Method Signatures:**

This operator is not generic; no methods are defined.

**Extensibility:**

This function is not generic.

**Exceptional Situations:**

- Signals an error of type `PROGRAM-ERROR` if the number of arguments is odd.

**See Also:**

`SL:DICT` (Type); `SL:DICT-COLLECT`; `SL:SEQ-INTO`; `SL:ALIST-DICT`; `SL:PLIST-DICT`; Sections 9.1.8–9.1.10; Chapter 4.


### SL:ORDERED-DICT _Type_

**Name:** `SL:ORDERED-DICT`, Type

**Syntax:** `SL:ORDERED-DICT`

**Arguments and Values:** A persistent ordered dictionary; no type parameters.

**Description:** Names the CLOS class constructed by `SL:ORDERED-DICT`, the
`SL:ORDERED-DICT` target of `SL:SEQ-INTO`, and ordered reconstruction specified
in Chapters 4 and 6 and Section 9.1.18. Direct `MAKE-INSTANCE` construction or
subclassing has undefined consequences, as for `SL:DICT`. This lifecycle
restriction is independent of standardized-method closure. The class is
distinct from `SL:DICT`; `SL:DICTP` is true for instances of either class.

Printing uses an unreadable diagnostic representation whose details are
implementation-dependent. No readable literal or new reader syntax is defined;
`#d(...)` continues to denote ordinary `SL:DICT`.

**Affected By:** `*PRINT-READABLY*` and standard printer controls.

**Exceptional Situations:** Printing with `*PRINT-READABLY*` true signals an
error of type `PRINT-NOT-READABLE`, including for an empty ordered dictionary.

**See Also:** [Ordered Dictionaries](#9118-ordered-dictionaries);
[Equality, Comparison, and Hashing](#9116-equality-comparison-and-hashing-of-dicts-and-hash-sets).

### SL:ORDERED-DICT _Function_

**Name:** `SL:ORDERED-DICT`, Function

**Syntax:** `SL:ORDERED-DICT` `{key value}*` → *ordered-dict*

**Arguments and Values:** *key* is any object acceptable to `SL:EQUALS` and
`SL:HASH-CODE`; *value* is any object; *ordered-dict* is an `SL:ORDERED-DICT`.

**Description:** Constructs a dictionary from alternating key/value arguments
in argument order, under Section 9.1.18's first-position/last-association-wins
rule. Zero arguments construct an empty ordered dictionary. There is no test
parameter; `:TEST`, when supplied in a key position, is an ordinary key. The
function is not generic. Result identity is unspecified; contained objects are
not copied. Argument-count validation precedes any key equality or hash calls.

**Side Effects:** Does not mutate inputs; effects of key protocol calls may occur.

**Exceptional Situations:** An odd argument count signals `PROGRAM-ERROR`.
Conditions from equality and hashing propagate.

**See Also:** [Ordered Dictionaries](#9118-ordered-dictionaries);
[SL:DICT-COLLECT](#sldict-collect-generic-function).

### SL:ORDERED-DICT-P _Function_

**Name:** `SL:ORDERED-DICT-P`, Function

**Syntax:** `SL:ORDERED-DICT-P` *object* → *generalized-boolean*

**Arguments and Values:** *object* is any object; the result is true exactly
when *object* is of type `SL:ORDERED-DICT`.

**Description:** Tests the concrete ordered type without traversing it. This
ordinary function is not generic. `SL:DICTP` remains the unchanged generic
Dict-protocol predicate; no `SL:DICT-P` predicate is introduced.

**Side Effects:** None.

**Exceptional Situations:** None.

**See Also:** [Ordered Dictionaries](#9118-ordered-dictionaries);
[SL:DICTP](#sldictp-generic-function).

### SL:DICTP _Generic Function_

**Name:**

`SL:DICTP`, Generic Function

**Syntax:**

`SL:DICTP` *object* → *generalized-boolean*

**Arguments and Values:**

- *object* — any object.
- *generalized-boolean* — true if *object* is a dict, and false otherwise.

**Description:**

Returns whether *object* is a dict: an `SL:DICT`, an `SL:ORDERED-DICT`, a hash table, or an instance of a user-defined
type that conforms to Sections 9.1.4 and 9.1.5. Alists, plists, and entry seqs are not dicts.

**Method Signatures:**

- `SL:DICTP (`*object* `SL:DICT)` — true.
- `SL:DICTP (`*object* `hash-table)` — true.
- `SL:DICTP (`*object* `SL:PLIST-DICT-VIEW)` — true.
- `SL:DICTP (`*object* `T)` — `NIL`.

**Exceptional Situations:**

None.

**See Also:**

`SL:DICT-REF`; `SL:DICT-TEST`; `SL:DICT-SIZE`; `SL:SEQABLEP`; `SL:MAP-ENTRY`; Chapter 4; Sections 9.1.4–9.1.6.


### SL:DICT-REF _Generic Function_

**Name:**

`SL:DICT-REF`, Generic Function

**Syntax:**

`SL:DICT-REF` *dict key* `&optional` *default* → *value, present-p*

**Arguments and Values:**

- *dict* — a `SL:DICTP` object.
- *key* — any object acceptable to the dict's test.
- *default* — any object, defaulting to `NIL`. Supplying it changes the
  primary value returned on absence; lookup without it already returns two
  values on every call.
- *value* — the value associated with *key*, or *default*.
- *present-p* — true if *dict* associates *key* with a value, false
  otherwise.

**Description:**

Keyed lookup on a dict. Returns the value associated with *key* as the primary value and a
*present-p* boolean as the second value, like `CL:GETHASH`. Key matching uses the dict's own test,
as returned by `SL:DICT-TEST`.

Supplying *default* changes only the primary value returned for an absent key, on the same terms as `SL:REF` (Chapter 8): an absent key returns `(values default NIL)` instead of `(values NIL NIL)`. Lookup without *default* already returns `(values NIL NIL)` on absence and is therefore total. A present key returns `(values value t)` in either form. *present-p* is returned whether or not *default* is supplied; the second value distinguishes a stored `NIL` from an absent key.

The read is the required primitive for user dict types ([Section
9.1.4](#914-the-extension-protocol)).

**Method Signatures:**

- `SL:DICT-REF (`*dict* `SL:DICT)` *key* `&optional` *default* — O(1) expected
  lookup under `SL:EQUALS`.
- `SL:DICT-REF (`*dict* `hash-table)` *key* `&optional` *default* — equivalent
  to `CL:GETHASH` with the supplied *default* (or `NIL` if no *default* is
  supplied) returned on absence, per the generic contract.
- `SL:DICT-REF (`*dict* `SL:PLIST-DICT-VIEW)` *key* `&optional` *default* — first-match `EQ` lookup.
- `SL:DICT-REF (`*dict* `T)` *key* `&optional` *default* — signals an error of
  type `TYPE-ERROR` if *dict* is not a `SL:DICTP` object; signals
  `TYPE-ERROR` if *dict* is a `SL:DICTP` object whose type defines no
  `SL:DICT-REF` method.

**Exceptional Situations:**

- Signals an error of type `TYPE-ERROR` if *dict* is not a `SL:DICTP` object.

**See Also:**

`(SETF SL:DICT-REF)`; `SL:DICT-MEMBER`; `SL:DICT-TEST`; `SL:DICT-REF-IN`; Chapter 8; Section 9.1.4.


### (SETF SL:DICT-REF) _Generic Function_

**Name:**

`(SETF SL:DICT-REF)`, Generic Function

**Syntax:**

`(SETF SL:DICT-REF)` *new-value* *dict* *key* `&optional` *default* → *new-value*

**Arguments and Values:**

- *new-value* — the object to store; it is returned as the only value.
- *dict* — a mutable `SL:DICTP` object.
- *key* — any object acceptable to the dict's test.
- *default* — any object; ignored on store.

**Description:**

Stores *new-value* as the value associated with *key* in *dict*. The *default* argument is ignored;
the store always installs *new-value*. On a hash table, the operation is equivalent to `(SETF
GETHASH)`. On `SL:DICT`, it signals `SIMPLE-ERROR` because `SL:DICT` is immutable.

**Method Signatures:**

- `(SETF SL:DICT-REF) *new-value* ((*dict* hash-table) *key* &optional *default*)` — installs the
  entry; *default* is ignored.
- `(SETF SL:DICT-REF) *new-value* ((*dict* SL:DICT) *key* &optional *default*)` — signals
  `SIMPLE-ERROR`.
- `(SETF SL:DICT-REF) *new-value* ((*dict* T) *key* &optional *default*)` — signals `TYPE-ERROR`
  if *dict* is not a `SL:DICTP` object; signals `PROGRAM-ERROR` if *dict* is a
  `SL:DICTP` object whose type defines no setter method.

**Extensibility:**

Programs may define setter methods for their own mutable dict types.

**Exceptional Situations:**

- Signals an error of type `SIMPLE-ERROR` if *dict* is an `SL:DICT`.
- Signals an error of type `TYPE-ERROR` if *dict* is not a `SL:DICTP` object.
- Signals an error of type `PROGRAM-ERROR` if *dict* is a `SL:DICTP` object whose type defines no
  `(SETF SL:DICT-REF)` method.

**See Also:**

`SL:DICT-REF`; `SL:DICT-SET`; `SL:DICT-MEMBER`; Chapter 8; Sections 9.1.3–9.1.4.


### SL:DICT-TEST _Generic Function_

**Name:**

`SL:DICT-TEST`, Generic Function

**Syntax:**

`SL:DICT-TEST` *dict* → *test*

**Arguments and Values:**

- *dict* — a `SL:DICTP` object.
- *test* — the equality-test designator identifying the test used for key
  matching in *dict*: the
  symbol `EQ`, `EQL`, `EQUAL`, or `EQUALP` for a hash table; the function
  `#'SL:EQUALS` for an `SL:DICT`; a designator documented by the type for a
  user dict.

**Description:**

Returns the equality-test designator that identifies the test governing key matching in *dict*.

**Method Signatures:**

- `SL:DICT-TEST (`*dict* `SL:DICT)` — returns the function `#'SL:EQUALS`.
- `SL:DICT-TEST (`*dict* `hash-table)` — returns the symbol naming the table's
  test (`EQ`, `EQL`, `EQUAL`, or `EQUALP`).
- `SL:DICT-TEST (`*dict* `SL:PLIST-DICT-VIEW)` — returns `#'EQ`.
- `SL:DICT-TEST (`*dict* `T)` — signals `TYPE-ERROR`.

**Exceptional Situations:**

- Signals an error of type `TYPE-ERROR` if *dict* is not a `SL:DICTP` object.

**See Also:**

`SL:DICT-REF`; `SL:DICT-COLLECT`; `SL:DICT-MERGE`; `SL:DICT-TRANSFORM`; Section 9.1.7; Section 9.1.12; Chapter 4.


### SL:DICT-SIZE _Generic Function_

**Name:**

`SL:DICT-SIZE`, Generic Function

**Syntax:**

`SL:DICT-SIZE` *dict* → *count*

**Arguments and Values:**

- *dict* — a `SL:DICTP` object.
- *count* — a non-negative integer: the number of unique keys in *dict*.

**Description:**

Returns the number of unique keys in *dict*. For an `SL:DICT` the count is maintained incrementally
and returned in O(1).

**Method Signatures:**

- `SL:DICT-SIZE (`*dict* `SL:DICT)` — the unique key count, maintained
  incrementally and returned in O(1).
- `SL:DICT-SIZE (`*dict* `hash-table)` — the table's key count.
- `SL:DICT-SIZE (`*dict* `SL:PLIST-DICT-VIEW)` — canonicalized unique-key count.
- `SL:DICT-SIZE (`*dict* `T)` — signals `TYPE-ERROR`.

**Exceptional Situations:**

- Signals an error of type `TYPE-ERROR` if *dict* is not a `SL:DICTP` object.

**See Also:**

`SL:DICT-REF`; `SL:DICT-KEYS`; `SL:DICT-VALS`; `SL:SEQ-LENGTH`; Chapter 4; Section 9.1.6.


### SL:DICT-SET _Generic Function_

**Name:**

`SL:DICT-SET`, Generic Function

**Syntax:**

`SL:DICT-SET` *dict key value* → *new-dict*

**Arguments and Values:**

- *dict* — a `SL:DICTP` object whose type supports `SL:DICT-SET`, including a
  standard `hash-table`.
- *key* — any object acceptable to the dict's test.
- *value* — any object.
- *new-dict* — a `SL:DICTP` result with *key* associated with *value*.
  The supporting method selects the result type; a type that does not support
  `SL:DICT-SET` signals `PROGRAM-ERROR` (see Exceptional Situations below).

**Description:**

Returns a dict with *key* associated with *value*. The input is never mutated. For a
standard `hash-table`, the result is a fresh shallow copy with the same hash-table test;
copying the container is O(n), and resident keys and values are shared. Setting a key that is already present
replaces its value and leaves `SL:DICT-SIZE` unchanged; setting a new key increments it. When a key is
equivalent under the dict test but not `EQ` is set, the new key object replaces the old key object.

**Method Signatures:**

- `SL:DICT-SET (`*dict* `SL:DICT)` *key* *value* — sets *key* in a
  persistent dict.
- `SL:DICT-SET (`*dict* `hash-table`) *key* *value* — returns a fresh shallow
  copy of *dict*, preserving its standard test, then associates *key* with *value*.
- `SL:DICT-SET (`*dict* `T)` *key* *value* — signals `TYPE-ERROR` if *dict* is
  not a `SL:DICTP` object; signals `PROGRAM-ERROR` if *dict* is a `SL:DICTP`
  object whose type does not support `SL:DICT-SET`.

**Exceptional Situations:**

- Signals an error of type `TYPE-ERROR` if *dict* is not a `SL:DICTP` object.
- Signals an error of type `PROGRAM-ERROR` if *dict*'s type does not support
  `SL:DICT-SET`.

**See Also:**

`SL:DICT-WITHOUT`; `SL:DICT-UPDATE`; `SL:DICT-SET-IN`; `(SETF SL:DICT-REF)`; Section 9.1.4; Chapter 4.


### SL:DICT-WITHOUT _Generic Function_

**Name:**

`SL:DICT-WITHOUT`, Generic Function

**Syntax:**

`SL:DICT-WITHOUT` *dict key* → *new-dict*

**Arguments and Values:**

- *dict* — a `SL:DICTP` object whose type supports `SL:DICT-WITHOUT`, including
  a standard `hash-table`.
- *key* — any object acceptable to the dict's test.
- *new-dict* — a `SL:DICTP` result without an association for *key*. For a standard
  `hash-table`, the result is always a fresh shallow copy, including when *key* is
  absent; it preserves the table's standard test and shares resident key and value
  objects. For persistent dict types, result identity is unspecified.

**Description:**

Returns a dict that does not associate *key* with any value. The input is never mutated. For a
standard `hash-table`, copying the container is O(n); removing an absent key is still a fresh-copy
no-op. Removing a present key decrements `SL:DICT-SIZE`; removing an absent key returns a dict equal to
*dict*.

**Method Signatures:**

- `SL:DICT-WITHOUT (`*dict* `SL:DICT)` *key* — removes *key*; absent-key
  removal may return *dict* itself.
- `SL:DICT-WITHOUT (`*dict* `hash-table`) *key* — returns a fresh shallow copy
  without *key*, preserving the table's standard test even when *key* is absent.
- `SL:DICT-WITHOUT (`*dict* `T)` *key* — signals `TYPE-ERROR` if *dict* is not
  a `SL:DICTP` object; signals `PROGRAM-ERROR` if *dict* is a `SL:DICTP` object
  whose type does not support `SL:DICT-WITHOUT`.

**Exceptional Situations:**

- Signals an error of type `TYPE-ERROR` if *dict* is not a `SL:DICTP` object.
- Signals an error of type `PROGRAM-ERROR` if *dict*'s type does not support
  `SL:DICT-WITHOUT`.

**See Also:**

`SL:DICT-SET`; `SL:DICT-REF`; `SL:DICT-ALIST`; `SL:DICT-PLIST`; Section 9.1.4; Chapter 4.


### SL:DICT-COLLECT _Generic Function_

**Name:**

`SL:DICT-COLLECT`, Generic Function

**Syntax:**

`SL:DICT-COLLECT` *source entries* `&key` *test* → *dict*

**Arguments and Values:**

- *source* — a prototype dict instance: a `SL:DICTP` object used for dispatch,
  test propagation, and construction/configuration state needed to preserve invariants.
- *entries* — a seqable whose elements are `SL:MAP-ENTRY` objects.
- *test* — an equality test designator for the result dict, defaulting to
  `EQL`. Standardized callers pass the source dict's `SL:DICT-TEST`.
- *dict* — a dict of the same type as *source*, containing *entries*.

**Description:**

Constructs a dict of the same type as *source* from *entries*. Content comes entirely from
*entries*; *source* contributes its identity for dispatch, its test, and any construction/configuration
state needed to preserve invariants. Dispatch is instance-based, on the class of *source*, with standard
CLOS method precedence: a method on a parent class applies to subclasses unless overridden ([Section
9.1.7](#917-the-dict-collector-protocol)).

The *test* argument carries the source dict's test to the result. For `SL:DICT` the result always
uses `SL:EQUALS` regardless of *test*: the `SL:DICT` method ignores the argument. For `hash-table`
and user dict types that accept a test, the result's test matches *test*. A
collector for a fixed-test user dict type — a user dict type whose test is
fixed by its construction — may ignore an incompatible supplied
*test* or signal an error of type `PROGRAM-ERROR`. Compatibility is determined by `EQ` on
the supplied and fixed test designators: the designators match when they are `EQ`, and do not match
otherwise.

Duplicate keys in *entries* resolve last-wins ([Section 9.1.10](#9110-duplicate-key-policy)).
The method must not mutate any input and must return a dict. For mutable hash-table
results, it must return a newly allocated result that is not EQ to any input. For
persistent dict types, result identity is unspecified; an implementation may
return any observationally equivalent value, including an input for a no-op
([Section 9.1.7](#917-the-dict-collector-protocol)). A fixed-test collector may
ignore an incompatible supplied *test* or signal an error of type `PROGRAM-ERROR`.

`SL:DICT-COLLECT` is a full-consumption operation: it forces all of *entries* at call time and
does not terminate on an unbounded *entries* sequence (Chapter 5).

Method presence is the opt-in to dict type preservation: `SL:DICT-MERGE` and `SL:DICT-TRANSFORM`
preserve a user dict type only when a non-default primary `SL:DICT-COLLECT` method — one whose
specializer is more specific than `T` — applicable to its instances exists; `:before`, `:after`,
and `:around` methods do not confer participation ([Section
9.1.12](#9112-type-preservation-for-dict-operations)).

**Method Signatures:**

- `SL:DICT-COLLECT (`*source* `SL:DICT)` *entries* `&key` (*test* `'EQL`) —
  returns an `SL:DICT` containing *entries*; ignores *test*.
- `SL:DICT-COLLECT (`*source* `hash-table)` *entries* `&key` (*test* `'EQL`) —
  returns a fresh hash table with test *test* containing *entries*.
- `SL:DICT-COLLECT (`*source* `T)` *entries* `&key` (*test* `'EQL`) — signals
  `TYPE-ERROR`.

Every method spells the default in its lambda list (`&key (test 'EQL)`), so that a call omitting
the keyword observes `EQL` — not `NIL` — on every method. The `SL:DICT` method ignores *test*, and
the `T` method signals before *test* matters, but both bind the default anyway, matching the
generic-level contract above.

**Exceptional Situations:**

- The default `T` method signals an error of type `TYPE-ERROR`.
- Signals an error of type `TYPE-ERROR` if an element of *entries* is not an
  `SL:MAP-ENTRY` object.
- Signals an error of type `TYPE-ERROR` if *entries* is not a seqable.
- The `hash-table` method signals an error of type `TYPE-ERROR` if *test* is
  not one of the four standard hash-table tests (`EQ`, `EQL`, `EQUAL`, or
  `EQUALP`); hash-table tests are restricted to those four, so a test
  designator naming any other test is rejected.
- A fixed-test user collector may ignore a supplied *test* that does not match its fixed test, or signal
  an error of type `PROGRAM-ERROR`.

**See Also:**

`SL:SEQ-INTO`; `SL:DICT-MERGE`; `SL:DICT-MERGE*`; `SL:DICT-TRANSFORM`; `SL:DICT-TEST`; Chapter 4; Sections 9.1.7 and 9.1.12.


### SL:DICT-KEYS _Generic Function_

**Name:**

`SL:DICT-KEYS`, Generic Function

**Syntax:**

`SL:DICT-KEYS` *collection* → *lazy-seq*

**Arguments and Values:**

- *collection* — a seqable whose elements are `SL:MAP-ENTRY` objects.
- *lazy-seq* — a lazy-seq of the keys of *collection*.

**Description:**

Returns a lazy-seq of the keys of *collection*: the lazy projection of `#'SL:ENTRY-KEY` over the
collection's entries. It is defined as

```lisp
(SL:SEQ-MAP #'SL:ENTRY-KEY (SL:SEQ-INTO 'LAZY-SEQ collection))
```

**Method Signatures:**

- `SL:DICT-KEYS (`*collection* `T)` — traverses *collection* as a seqable of
  `SL:MAP-ENTRY` objects; no per-type methods are required.

**Exceptional Situations:**

- Signals an error of type `TYPE-ERROR` if *collection* is not a seqable.
- Signals an error of type `TYPE-ERROR`, at forcing, if an element of the
  traversal is not an `SL:MAP-ENTRY` object.

**See Also:**

`SL:DICT-VALS`; `SL:DICT-REF`; `SL:ENTRY-KEY`; `SL:SEQ-MAP`; Chapter 4; Section 9.1.5.


### SL:DICT-VALS _Generic Function_

**Name:**

`SL:DICT-VALS`, Generic Function

**Syntax:**

`SL:DICT-VALS` *collection* → *lazy-seq*

**Arguments and Values:**

- *collection* — a seqable whose elements are `SL:MAP-ENTRY` objects.
- *lazy-seq* — a lazy-seq of the values of *collection*.

**Description:**

Returns a lazy-seq of the values of *collection*: the demand-driven (`SL:LAZY-SEQ`) projection of
`#'SL:ENTRY-VALUE` over the collection's entries, defined as

```lisp
(SL:SEQ-MAP #'SL:ENTRY-VALUE (SL:SEQ-INTO 'LAZY-SEQ collection))
```

It is the value counterpart of `SL:DICT-KEYS` and accepts the same domain: any seqable yielding
`SL:MAP-ENTRY` objects.

**Method Signatures:**

- `SL:DICT-VALS (`*collection* `T)` — traverses *collection* as a seqable of
  `SL:MAP-ENTRY` objects; no per-type methods are required.

**Exceptional Situations:**

- Signals an error of type `TYPE-ERROR` if *collection* is not a seqable.
- Signals an error of type `TYPE-ERROR`, at forcing, if an element of the
  traversal is not an `SL:MAP-ENTRY` object.

**See Also:**

`SL:DICT-KEYS`; `SL:DICT-REF`; `SL:ENTRY-VALUE`; `SL:SEQ-MAP`; Chapter 4; Section 9.1.5.


### SL:DICT-FREQUENCIES _Generic Function_

**Name:**

`SL:DICT-FREQUENCIES`, Generic Function

**Syntax:**

`SL:DICT-FREQUENCIES` *seq* → *dict*

**Arguments and Values:**

- *seq* — a seqable.
- *dict* — an `SL:DICT` mapping each distinct element of *seq* to the
  number of times it occurs.

**Description:**

Returns an `SL:DICT` whose keys are the distinct elements of *seq* (under `SL:EQUALS`) and
whose values are the occurrence counts. It is full-consumption: it must see all elements to count
them, so it does not terminate on an unbounded source (Chapter 5); consumption completes before
the call returns.

**Method Signatures:**

- `SL:DICT-FREQUENCIES (`*seq* `T)` — consumes any seqable; no per-type methods
  are required.

**Exceptional Situations:**

- Signals an error of type `TYPE-ERROR` if *seq* is not a seqable.

**See Also:**

`SL:DICT-GROUP-BY`; `SL:DICT`; `SL:SEQ-INTO`; Chapter 4; Chapter 5; Section 9.1.10.


### SL:DICT-GROUP-BY _Generic Function_

**Name:**

`SL:DICT-GROUP-BY`, Generic Function

**Syntax:**

`SL:DICT-GROUP-BY` *key-function seq* → *dict*

**Arguments and Values:**

- *key-function* — a function designator of one argument.
- *seq* — a seqable.
- *dict* — an `SL:DICT` mapping each key returned by *key-function* to the
  list of elements that produced it, in source order.

**Description:**

Returns an `SL:DICT` whose keys are the values returned by *key-function* applied to the elements
of *seq* and whose values are the lists of elements sharing each key, in source order. Grouping is
global: elements sharing a key are grouped regardless of position, unlike `SL:SEQ-PARTITION-BY`,
which groups only adjacent runs. It is full-consumption: global grouping requires seeing all
elements, so it does not terminate on an unbounded source (Chapter 5); consumption completes
before the call returns. The *key-function* is invoked exactly once per element, in retained traversal
order, at call time. *key-function* has been invoked for every element before the call returns. Only the
primary value returned by *key-function* is used; additional values are ignored.

**Method Signatures:**

- `SL:DICT-GROUP-BY (`*key-function* `T)` *seq* — consumes any seqable; no per-type
  methods are required.

**Exceptional Situations:**

- Signals an error of type `TYPE-ERROR` if *seq* is not a seqable or
  *key-function* is not a function designator.

**See Also:**

`SL:DICT-FREQUENCIES`; `SL:SEQ-PARTITION-BY`; `SL:DICT`; Chapter 5; Section 9.1.10.


### SL:DICT-ZIPMAP _Generic Function_

**Name:**

`SL:DICT-ZIPMAP`, Generic Function

**Syntax:**

`SL:DICT-ZIPMAP` *keys vals* → *dict*

**Arguments and Values:**

- *keys* — a seqable.
- *values* — a seqable.
- *dict* — an `SL:DICT` pairing corresponding elements of *keys* and
  *values*.

**Description:**

Returns an `SL:DICT` pairing corresponding elements of *keys* and *values*: the entry for the
i-th element of *keys* maps to the i-th element of *values*. It stops at the shorter input. The
inputs are processed by the multi-source lockstep rule of Chapter 6: at each step, the i-th
element of *keys* is forced first, then the i-th element of *values*, left to right, before the pair
is installed. Later pairs overwrite earlier ones on a repeated key: last-wins ([Section
9.1.10](#9110-duplicate-key-policy)).

The inputs are consumed as seqables of elements, not as dict prototypes; a dict
input contributes its `SL:MAP-ENTRY` objects. The result is always an `SL:DICT`
([Section 9.1.12](#9112-type-preservation-for-dict-operations)).

Construction is eager: it occurs at call time, not on demand. The operation terminates when either
input ends; it does not terminate when neither input ends — zipping two unbounded inputs never
returns (Chapter 5).

**Method Signatures:**

- `SL:DICT-ZIPMAP (`*keys* `T)` *values* — consumes any two seqables; no per-type
  methods are required.

**Exceptional Situations:**

- Signals an error of type `TYPE-ERROR` if *keys* or *values* is not a seqable.

**See Also:**

`SL:DICT`; Chapter 6; Section 9.1.10.


### SL:DICT-MERGE _Generic Function_

**Name:**

`SL:DICT-MERGE`, Generic Function

**Syntax:**

`SL:DICT-MERGE` *dict1 dict2* `&key` *collision* → *dict*

**Arguments and Values:**

- *dict1*, *dict2* — `SL:DICTP` objects.
- *collision* — a collision policy: `:last-wins` (the default) or `:error`.
- *dict* — a dict containing the entries of *dict1* and *dict2*, with the result type determined by
  Section 9.1.12.

**Description:**

Merges two dicts. Entries from *dict1* and *dict2* whose keys match under the result
dict's test are collisions. Under `:collision :error`, this includes distinct keys within either
source that coalesce under the result test and collisions between sources; the operation signals
on the first collision detected. Collision semantics follow Section 9.1.14. The result type follows
Section 9.1.12, and the operation is eager. A collision produces no partial dictionary.

The signature is binary. For merging more than two dicts, use `SL:DICT-MERGE*` ([Section
9.2.1](#921-the-dict-protocol)), the variadic form, which has no `:collision` option.

**Method Signatures:**

- `SL:DICT-MERGE (`*dict1* `T)` *dict2* `&key` (*collision* `:last-wins`) — requires both arguments
  to be `SL:DICTP` objects and signals `TYPE-ERROR` otherwise; no per-type
  methods are required, since result construction routes through
  `SL:DICT-COLLECT`.

**Exceptional Situations:**

- Signals an error of type `TYPE-ERROR` if *dict1* or *dict2* is not a `SL:DICTP`
  object.
- Collision conditions and unrecognized collision policies are specified in Section 9.1.14.

**See Also:**

`SL:DICT-MERGE*`; `SL:DICT-TRANSFORM`; `SL:DICT-COLLECT`; `SL:DICT-TEST`; Sections 9.1.12 and 9.1.14; Chapter 4.


### SL:DICT-TRANSFORM _Generic Function_

**Name:**

`SL:DICT-TRANSFORM`, Generic Function

**Syntax:**

`SL:DICT-TRANSFORM` *fn dict* `&key` *collision* → *result*

**Arguments and Values:**

- *function* — a function designator of two arguments returning exactly two values.
- *dict* — a `SL:DICTP` object.
- *collision* — a collision policy: `:last-wins` (the default) or `:error`.
- *result* — a dict whose entries are the transformed entries of *dict*.

**Description:**

Transforms each entry of *dict* by calling *function* with two arguments — the entry's key and its value
— and producing the new key and new value as exactly two values. The argument order is function-first.
The operation is eager: it consumes all finite input on a successful call. The callback is called once for each entry processed, in the source's traversal
order (stored order for `SL:ORDERED-DICT`). The two-values check and, under `:collision :error`, the returned-key collision check occur
before that entry is accepted. A detected collision signals `PROGRAM-ERROR` immediately, so no
callback runs for a later entry; no partial dictionary is returned and side effects of callbacks that
already ran are not rolled back.

Transformed entries collide when their new keys match under the result dict's test. Collision semantics
follow Section 9.1.14. The result type follows Section 9.1.12. Returning a number of values other
than two from *function* signals `PROGRAM-ERROR`.

**Method Signatures:**

- `SL:DICT-TRANSFORM (`*function* `T)` *dict* `&key` (*collision* `:last-wins`) — requires *dict* to
  be a `SL:DICTP` object and signals `TYPE-ERROR` otherwise; no per-type methods
  are required, since result construction routes through `SL:DICT-COLLECT`.

**Exceptional Situations:**

- Signals an error of type `TYPE-ERROR` if *function* is not a function designator
  or *dict* is not a `SL:DICTP` object.
- Signals an error of type `PROGRAM-ERROR` if *function* returns a number of values
  other than two.
- Collision conditions and unrecognized collision policies are specified in Section 9.1.14.

**See Also:**

`SL:DICT-MERGE`; `SL:DICT-COLLECT`; `SL:DICT-TEST`; Chapter 7; Sections 9.1.12 and 9.1.14.


### SL:DICT-VALUES-MAP _Generic Function_

**Name:** `SL:DICT-VALUES-MAP`, Generic Function

**Syntax:** `SL:DICT-VALUES-MAP` *fn dict* → *result*

**Arguments and Values:** *function* is a function designator of one argument; *dict* is a `SL:DICTP` object; *result* is a dict reconstructed from *dict*.

**Description:** Applies *function* once to each value of *dict*, retaining the original key. The primary value returned by *function* becomes the new value; the callback has arity one. Present `NIL` values are values and are preserved as entries unless *function* changes them. Keys are unchanged, so no collision arises when the result uses the source test; a fallback result test (for example, `SL:EQUALS` for a plist view) can coalesce distinct source keys. The operation is eager, non-destructive, and performs one traversal. It reconstructs through `SL:DICT-COLLECT`, preserving the source dict type when eligible and falling back to `SL:DICT` when that type cannot be preserved. Argument and function errors are detected before traversal; a callback failure produces no partial result.

**Method Signatures:** `SL:DICT-VALUES-MAP` (*function* `T`) *dict* — requires a `SL:DICTP` dict; result construction routes through `SL:DICT-COLLECT`.

**Exceptional Situations:** Signals `TYPE-ERROR` if *function* is not a function designator or *dict* is not a `SL:DICTP` object. Conditions signaled by *function* propagate.

**See Also:** `SL:DICT-KEYS-MAP`; `SL:DICT-TRANSFORM`; `SL:DICT-COLLECT`; Section 9.1.12.


### SL:DICT-KEYS-MAP _Generic Function_

**Name:** `SL:DICT-KEYS-MAP`, Generic Function

**Syntax:** `SL:DICT-KEYS-MAP` *fn dict* `&key` (*collision* `:last-wins`) → *result*

**Arguments and Values:** *function* is a function designator of one argument; *dict* is a `SL:DICTP` object; *collision* is `:last-wins` or `:error`; *result* is a reconstructed dict.

**Description:** Applies *function* once to each key of *dict*, retaining the original value. The primary value returned by *function* becomes the new key; the callback has arity one. A present `NIL` key is an ordinary key and is preserved when transformed accordingly. Under `:last-wins`, the later transformed association replaces both key and value objects. Under `:error`, the operation signals `PROGRAM-ERROR` at the first collision under the selected result test, before invoking any later callback. An unknown collision policy signals `PROGRAM-ERROR` before traversal. Ordered results retain the first transformed occurrence's position while the last association wins there. The operation is eager, non-destructive, and performs one traversal, and reconstructs through `SL:DICT-COLLECT` preserving the source dict type when eligible and otherwise returning `SL:DICT`,
as specified in Section 9.1.12. All dict types are supported.

**Method Signatures:** `SL:DICT-KEYS-MAP` (*function* `T`) *dict* `&key` (*collision* `:last-wins`) — requires a `SL:DICTP` dict; result construction routes through `SL:DICT-COLLECT`.

**Exceptional Situations:** Signals `TYPE-ERROR` if *function* is not a function designator or *dict* is not a `SL:DICTP` object. An unrecognized *collision* or a collision under `:error` signals `PROGRAM-ERROR`. Conditions from *function* propagate.

**See Also:** `SL:DICT-VALUES-MAP`; `SL:DICT-TRANSFORM`; `SL:DICT-COLLECT`; Sections 9.1.10 and 9.1.12.


### SL:DICT-SELECT-KEYS _Generic Function_

**Name:** `SL:DICT-SELECT-KEYS`, Generic Function

**Syntax:** `SL:DICT-SELECT-KEYS` *dict keys* → *result*

**Arguments and Values:** *dict* is a `SL:DICTP` object; *keys* is a finite seqable; *result* is a dict of the selected entries.

**Description:** Returns a non-destructive, eager dict containing the entries whose keys match any key in *keys*, using *dict*'s `SL:DICT-TEST`. *keys* is consumed once before dict traversal. Missing keys are ignored and duplicate requested keys have no additional effect. Entries are supplied to reconstruction in source traversal order, rather than
request order. Observable result order follows the result type's contract. The result preserves the source dict type through `SL:DICT-COLLECT` when
eligible and otherwise returns `SL:DICT`, as specified in Section 9.1.12. All
dict types are supported and the operation performs one dict traversal.

**Exceptional Situations:** Signals `TYPE-ERROR` if *dict* is not a `SL:DICTP` object or *keys* is not seqable. An unbounded *keys* input does not terminate.

**See Also:** `SL:DICT-REMOVE-KEYS`; `SL:DICT-TEST`; `SL:DICT-COLLECT`; Chapter 5.


### SL:DICT-REMOVE-KEYS _Generic Function_

**Name:** `SL:DICT-REMOVE-KEYS`, Generic Function

**Syntax:** `SL:DICT-REMOVE-KEYS` *dict keys* → *result*

**Arguments and Values:** *dict* is a `SL:DICTP` object; *keys* is a finite seqable; *result* is a dict without matching entries.

**Description:** Returns a non-destructive, eager dict omitting entries whose keys match any key in *keys*, using *dict*'s `SL:DICT-TEST`. *keys* is consumed once before dict traversal; missing keys are ignored and duplicate requested keys are harmless. Remaining entries are supplied to reconstruction in source traversal order.
Observable result order follows the result type's contract. The result preserves the source dict type through `SL:DICT-COLLECT` when
eligible and otherwise returns `SL:DICT`, as specified in Section 9.1.12. All
dict types are supported and the operation performs one dict traversal.

**Exceptional Situations:** Signals `TYPE-ERROR` if *dict* is not a `SL:DICTP` object or *keys* is not seqable. An unbounded *keys* input does not terminate.

**See Also:** `SL:DICT-SELECT-KEYS`; `SL:DICT-TEST`; `SL:DICT-COLLECT`; Chapter 5.


### SL:DICT-MERGE-WITH _Generic Function_

**Name:** `SL:DICT-MERGE-WITH`, Generic Function

**Syntax:** `SL:DICT-MERGE-WITH` *combine dict1 dict2* → *result*

**Arguments and Values:** *combine* is a function designator of two arguments; *dict1* and *dict2* are `SL:DICTP` objects; *result* is their binary merged dict.

**Description:** Performs a binary merge, selecting result class and test by the existing `SL:DICT-MERGE` rules. It traverses *dict1* once and then *dict2* once. The first occurrence installs its value unchanged. Every subsequent equivalent key calls `(FUNCALL combine old-value incoming-value)`, using the accumulated value as *old-value* and the incoming value as *incoming-value*; the primary result becomes the accumulated value. The incoming key object is retained, including after a combination, while ordered results retain the first occurrence's position. Collisions within either operand after result-test conversion also invoke *combine*. Present `NIL` values are passed to *combine*. Since the combiner need not be commutative, its result exposes the specified encounter-order fold. The operation is binary, not variadic, and supports all dict types.

**Method Signatures:** `SL:DICT-MERGE-WITH` (*combine* `T`) *dict1 dict2* — result construction follows `SL:DICT-MERGE` and `SL:DICT-COLLECT`.

**Exceptional Situations:** Signals `TYPE-ERROR` if *combine*, *dict1*, or *dict2* is invalid. Conditions from *combine* propagate.

**See Also:** `SL:DICT-MERGE`; `SL:DICT-MERGE*`; `SL:DICT-COLLECT`; Sections 9.1.12 and 9.1.14.


### SL:DICT-COUNT-BY _Generic Function_

**Name:** `SL:DICT-COUNT-BY`, Generic Function

**Syntax:** `SL:DICT-COUNT-BY` *key-function seq* → *result*

**Arguments and Values:** *key-function* is a function designator of one argument; *seq* is any seqable; *result* is an `SL:DICT` of computed keys to counts.

**Description:** Eagerly applies *key-function* once to each element of *seq* and counts its primary result. The result always uses `SL:DICT` and `SL:EQUALS`, not source preservation. The latest equivalent computed key object is retained, and result order is unspecified. An empty input produces an empty `SL:DICT`. A dict input contributes its `SL:MAP-ENTRY` entries, not its values.

**Method Signatures:** `SL:DICT-COUNT-BY` (*key-function* `T`) *seq* — consumes any seqable; no per-type methods are required.

**Exceptional Situations:** Signals `TYPE-ERROR` if *key-function* is not a function designator or *seq* is not seqable.

**See Also:** `SL:DICT-FREQUENCIES`; `SL:DICT`; `SL:EQUALS`; Chapter 5.


### SL:DICT-REDUCE-KV _Generic Function_

**Name:** `SL:DICT-REDUCE-KV`, Generic Function

**Syntax:** `SL:DICT-REDUCE-KV` *fn initial-value dict* → *result*

**Arguments and Values:** *function* is a function designator of three arguments; *initial-value* is any object; *dict* is a `SL:DICTP` object; *result* is the final scalar accumulator.

**Description:** Performs a left fold over *dict* in one retained traversal, calling `(FUNCALL fn accumulator key value)` for each entry. The primary callback result becomes the next accumulator. An empty dict returns *initial-value*, including when it is `NIL`. The result is scalar, not implicitly dict-producing, and there is no implicit early termination. All dict types are supported.

**Method Signatures:** `SL:DICT-REDUCE-KV` (*function* `T`) *initial-value dict* — traverses any `SL:DICTP` dict once.

**Exceptional Situations:** Signals `TYPE-ERROR` if *function* is not a function designator or *dict* is not a `SL:DICTP` object. Conditions from *function* propagate.

**See Also:** `SL:DICT-VALUES-MAP`; `SL:DICT-TRANSFORM`; Chapter 4.


### SL:ALIST-DICT _Function_

**Name:** `SL:ALIST-DICT`, Function

**Syntax:**

`SL:ALIST-DICT` *alist* → *dict*

**Arguments and Values:**

- *alist* — an association list: a proper list of conses.
- *dict* — an `SL:DICT`.

**Description:**

Converts *alist* to an `SL:DICT`. The key of each cons becomes an entry
key and its cdr the value, under `SL:EQUALS` key matching. Duplicate keys
resolve last-wins: the rightmost occurrence in *alist* supplies the value
(Section 9.1.10). The result has one entry per unique key.

This is the explicit conversion path for alists; no operation sniffs list
shapes to guess intent (Section 9.1.9).

**Exceptional Situations:**

- Signals an error of type `TYPE-ERROR` if *alist* is not a proper list or an
  element of *alist* is not a cons.

**See Also:**

`SL:PLIST-DICT`; `SL:DICT-ALIST`; `SL:DICT`; Sections 9.1.8–9.1.10; Chapter 4.


### SL:PLIST-DICT _Function_

**Name:** `SL:PLIST-DICT`, Function

**Syntax:**

`SL:PLIST-DICT` *plist* → *dict*

**Arguments and Values:**

- *plist* — a property list: a proper list of alternating indicators and
  values.
- *dict* — an `SL:DICT`.

**Description:**

Converts *plist* to an `SL:DICT`. Each indicator becomes an entry key
and its following value the entry value, under `SL:EQUALS` key matching.
Duplicate indicators resolve last-wins (Section 9.1.10).

This is the explicit conversion path for plists (Section 9.1.9).

**Exceptional Situations:**

- Signals an error of type `PROGRAM-ERROR` if *plist* has odd length.
- Signals an error of type `PROGRAM-ERROR` if *plist* is not a proper list.

**See Also:**

`SL:ALIST-DICT`; `SL:PLIST-DICT-VIEW`; `SL:DICT-PLIST`; `SL:DICT`; Sections 9.1.8–9.1.10; Chapter 4.


### SL:PLIST-DICT-VIEW _Type_

**Name:** `SL:PLIST-DICT-VIEW`, Type

**Syntax:**

`SL:PLIST-DICT-VIEW`

**Arguments and Values:**

The type has no runtime arguments. A value is a read-only dict-protocol adapter over a property list.

**Description:**

`SL:PLIST-DICT-VIEW` names the CLOS class of the adapter returned by the
`SL:PLIST-DICT-VIEW` function. The adapter retains its backing plist and implements the read side of
the dict protocol. Its lookup, traversal, and read-only behavior are specified by the function entry
and Sections 9.1.3, 9.1.5, 9.1.8, and 9.1.16.

**See Also:**

`SL:PLIST-DICT-VIEW` (Function); `SL:PLIST-DICT`; `SL:DICT-REF`; `SL:DICT-TEST`;
`SL:DICT-SIZE`; Chapter 4; Sections 9.1.5, 9.1.8, and 9.1.16.


### SL:PLIST-DICT-VIEW _Function_

**Name:** `SL:PLIST-DICT-VIEW`, Function

**Syntax:**

`SL:PLIST-DICT-VIEW` *plist* → *view*

**Arguments and Values:**

- *plist* — a property list: a proper list of alternating indicators and
  values.
- *view* — a `SL:PLIST-DICT-VIEW` object: a read-only dict-protocol adapter
  backed by *plist*.

**Description:**

Returns a read-only dict-protocol adapter over *plist*. The adapter
satisfies `SL:DICTP` and participates in the dict protocol without
converting the plist to an `SL:DICT`. The underlying plist is not copied;
the adapter holds a reference to it.

**Lookup** uses `EQ` for key matching, matching `CL:GETF` behavior.
`SL:DICT-REF` returns the first matching indicator's value (first-match,
not last-wins). `SL:DICT-MEMBER` tests key presence the same way.

**Traversal** — the seq protocol primitives, `SL:DICT-KEYS`, `SL:DICT-VALS`,
`SL:EQUALS`, and `SL:HASH-CODE` — presents a canonicalized view: one logical
entry per key, with the first occurrence winning. Later duplicate indicators
are hidden from traversal, `SL:DICT-SIZE`, `SL:EQUALS`, and `SL:HASH-CODE`.
This differs from the last-wins policy of `SL:PLIST-DICT`
(Section 9.1.10) — it is an explicit ruling for the view adapter, not a
general rule.

Traversal via the seq protocol yields `SL:MAP-ENTRY` objects, as for every
dict type (Section 9.1.5); `(SL:SEQ-INTO 'LAZY-SEQ view)` returns them
as a lazy sequence.

Equality, comparison, and hashing follow Section 9.1.16.

The adapter is read-only: it does not implement `SL:DICT-SET` or
`SL:DICT-WITHOUT`. Calling either on a `SL:PLIST-DICT-VIEW` signals
`PROGRAM-ERROR`, as for any dict type that declines the write-side
operations (Section 9.1.4).

`SL:DICT-TEST` returns `#'EQ`.

If the underlying plist is mutated after the adapter is created, behavior has undefined consequences.

**Exceptional Situations:**

- Signals an error of type `PROGRAM-ERROR` if *plist* has odd length.
- Signals an error of type `PROGRAM-ERROR` if *plist* is not a proper list.
- Signals an error of type `PROGRAM-ERROR` if `SL:DICT-SET`,
  `SL:DICT-WITHOUT`, or `(SETF SL:DICT-REF)` is called on a
  `SL:PLIST-DICT-VIEW`.

**See Also:**

`SL:PLIST-DICT`; `SL:DICT-REF`; `SL:DICT-TEST`; `SL:DICT-SIZE`; `SL:DICT-KEYS`; `SL:DICT-VALS`; Chapter 4; Section 9.1.5.


### SL:DICT-ALIST _Function_

**Name:** `SL:DICT-ALIST`, Function

**Syntax:**

`SL:DICT-ALIST` *dict* → *alist*

**Arguments and Values:**

- *dict* — a `SL:DICTP` object.
- *alist* — a fresh proper list of fresh conses, one per entry of *dict*.

**Description:**

Converts *dict* to an association list: one fresh `(key . value)` cons per
entry. The order of the pairs follows the dict's traversal order (stored order for `SL:ORDERED-DICT`, unspecified for `SL:DICT`)
(Section 9.1.2). The input is not mutated, and the result does not share the
container conses with it; keys and values are not copied.

**Exceptional Situations:**

- Signals an error of type `TYPE-ERROR` if *dict* is not a `SL:DICTP` object.

**See Also:**

`SL:ALIST-DICT`; `SL:DICT-PLIST`; `SL:DICT-REF`; Chapter 4; Sections 9.1.8–9.1.10.


### SL:DICT-PLIST _Function_

**Name:** `SL:DICT-PLIST`, Function

**Syntax:**

`SL:DICT-PLIST` *dict* → *plist*

**Arguments and Values:**

- *dict* — a `SL:DICTP` object.
- *plist* — a fresh proper list of alternating keys and values, one pair per
  entry of *dict*.

**Description:**

Converts *dict* to a property list: alternating entry keys and values. The
order of the pairs follows the dict's traversal order (stored order for `SL:ORDERED-DICT`, unspecified for `SL:DICT`)
(Section 9.1.2). The input is not mutated, and the result does not share the
container conses with it; keys and values are not copied.

**Exceptional Situations:**

- Signals an error of type `TYPE-ERROR` if *dict* is not a `SL:DICTP` object.

**See Also:**

`SL:PLIST-DICT`; `SL:DICT-ALIST`; `SL:DICT-REF`; Chapter 4; Sections 9.1.8–9.1.10.


### SL:DICT-MEMBER _Generic Function_

**Name:** `SL:DICT-MEMBER`, Generic Function

**Syntax:**

`SL:DICT-MEMBER` *dict key* → *(values present-p value)*

**Arguments and Values:**

- *dict* — a `SL:DICTP` object.
- *key* — any object acceptable to the dict's test.
- *present-p* — a generalized boolean: true when *key* is present in *dict*.
- *value* — the value associated with *key* in *dict*, or the value
  `SL:DICT-REF` returns on absence (`NIL`) when *key* is absent.

**Description:**

Returns two values: whether *key* is present in *dict* (primary), and the
value associated with *key* (secondary). This is the derived membership
operation: its default method is
`(multiple-value-bind (val present-p) (SL:DICT-REF dict key) (values present-p val))`.

Exactly two values are guaranteed. There is no *default* argument; the
secondary value on absence is the value returned by `SL:DICT-REF` (`NIL`).

**Method Signatures:**

- `SL:DICT-MEMBER (`*dict* `SL:PLIST-DICT-VIEW)` *key* — first-match `EQ` membership.
- `SL:DICT-MEMBER (`*dict* `T)` *key* — the default method: flips the two
  values of `SL:DICT-REF`. Signals `TYPE-ERROR` if *dict* is not a `SL:DICTP`
  object (via `SL:DICT-REF`).

**Extensibility:**

`SL:DICT-MEMBER` is a derived generic function, not a primitive
(Section 9.1.4). A user dict type that defines `SL:DICT-REF` gets
`SL:DICT-MEMBER` through the default method without defining anything
further. A type that needs different membership semantics may specialize
`SL:DICT-MEMBER` directly.

**Exceptional Situations:**

- Signals an error of type `TYPE-ERROR` if *dict* is not a `SL:DICTP` object.

**See Also:**

`SL:DICT-REF`; `SL:DICT-TEST`; Section 9.1.4; Chapter 4.


### SL:DICT-MERGE* (variadic) _Generic Function_

**Name:** `SL:DICT-MERGE*`, Generic Function

**Syntax:**

`SL:DICT-MERGE*` *dict1 dict2* `&rest` *more-dicts* → *result*

**Arguments and Values:**

- *dict1*, *dict2*, *more-dicts* — `SL:DICTP` objects. At least two dicts are
  required.
- *result* — a dict: the left fold of the inputs under binary
  `SL:DICT-MERGE` with `:collision :last-wins`.

**Description:**

Merges two or more dicts from left to right by a left fold of binary
`SL:DICT-MERGE` with `:collision :last-wins`. There is no `:collision` option;
`SL:DICT-MERGE*` is always last-wins. The binary `SL:DICT-MERGE` remains the
operation with a `:collision` keyword.

The operation starts from *dict1*, rather than from an empty dict. The result type at each pairwise fold
step follows type preservation (Section 9.1.12).

The operation is eager: it consumes all finite input and returns a fully constructed result at call time.

**Method Signatures:**

- `SL:DICT-MERGE* (`*dict1* `T)` *dict2* `&rest` *more-dicts* — requires at least
  two `SL:DICTP` arguments and signals `TYPE-ERROR` if any argument is not a
  `SL:DICTP` object. Result construction routes through `SL:DICT-COLLECT` at
  each fold step.

**Extensibility:**

A user dict type participates through its `SL:DICT-COLLECT` method, as for
binary `SL:DICT-MERGE` (Sections 9.1.7 and 9.1.12).

**Exceptional Situations:**

- Signals an error of type `PROGRAM-ERROR` if fewer than two arguments are
  supplied.
- Signals an error of type `TYPE-ERROR` if any argument is not a `SL:DICTP`
  object.

**See Also:**

`SL:DICT-MERGE`; `SL:DICT-COLLECT`; `SL:DICT-TEST`; Section 9.1.12; Chapter 4.


### SL:DICT-UPDATE _Generic Function_

**Name:** `SL:DICT-UPDATE`, Generic Function

**Syntax:**

`SL:DICT-UPDATE` *dict key fn* `&key` *default* → *new-dict*

**Arguments and Values:**

- *dict* — a `SL:DICTP` object whose type supports `SL:DICT-SET`, including a
  standard `hash-table`.
- *key* — any object acceptable to the dict's test.
- *function* — a function designator of one argument.
- *default* — any object; the default is `NIL`.
- *new-dict* — a dict: *dict* with *key* set to the value returned by
  calling *function* on the current value of *key*.

**Description:**

Applies *function* to the value associated with *key* in *dict* and sets *key* to
the result. For a supported write, the value transformation is equivalent to
`(SL:DICT-SET dict key (funcall fn (SL:DICT-REF dict key default)))`,
subject to the validation ordering below.
For a standard hash-table, this produces the fresh shallow-copy result of `SL:DICT-SET`;
the source table is unchanged. Works on any dict supporting `SL:DICT-SET`; signals `PROGRAM-ERROR` on a
dict that declines `SL:DICT-SET` (same as calling `SL:DICT-SET` directly).

After validation permits invocation, *function* is invoked exactly once, at call time
(eager), and only its primary return value is used; zero values installs `NIL`.
The operation returns the fully constructed *new-dict* as its only value. If
control exits nonlocally from *function*, no result is returned; the operation does not
mutate the input container or roll back arbitrary callback effects.

When *key* is absent, *function* receives *default*. A present key always passes its
associated value, including `NIL`, regardless of *default*. Absence alone does
not signal an error. *default* is an ordinary eagerly evaluated argument, even
when the key is present; a function object supplied as *default* is passed as
an object, not called. Detectable argument errors and detectable lack of write
support are rejected before callback invocation. There is no `:signal` keyword.

**Method Signatures:**

- `SL:DICT-UPDATE (`*dict* `T)` *key fn* `&key (default NIL)` — the default
  method. Signals `TYPE-ERROR` if *dict* is not a `SL:DICTP` object; signals
  `PROGRAM-ERROR` if *dict* is a `SL:DICTP` object whose type declines
  `SL:DICT-SET`.

**Extensibility:**

A user dict type supporting `SL:DICT-SET` gets `SL:DICT-UPDATE` through the
default method without defining anything further. Specialized methods must be observationally
equivalent to the default behavior.

**Exceptional Situations:**

- Signals an error of type `TYPE-ERROR` if *function* is not a function designator.
- Signals an error of type `TYPE-ERROR` if *dict* is not a `SL:DICTP` object.
- Signals an error of type `PROGRAM-ERROR` if *dict* is a `SL:DICTP` object
  whose type declines `SL:DICT-SET`.
- An unrecognized keyword, including `:signal`, is subject to ordinary Common
  Lisp keyword argument checking.

**See Also:**

`SL:DICT-SET`; `SL:DICT-REF`; `SL:DICT-MEMBER`; `SL:DICT-UPDATE-IN`; Section 9.1.4; Chapter 4.


### SL:DICT-UPDATE-IN _Generic Function_

**Name:** `SL:DICT-UPDATE-IN`, Generic Function

**Syntax:**

`SL:DICT-UPDATE-IN` *dict keys fn* `&key` *default* → *new-dict*

**Arguments and Values:**

- *dict* — a `SL:DICTP` object whose type supports `SL:DICT-SET`, including a
  standard `hash-table`.
- *keys* — a seqable of keys forming a path into *dict*; the shared path protocol is in Section 9.1.17.
- *function* — a function designator of one argument.
- *default* — any object; the default is `NIL`.
- *new-dict* — a dict: *dict* with the leaf at *keys* updated by
  applying *function* to its current value.

**Description:**

The nested path protocol of Section 9.1.17 applies. A single key is equivalent to
`SL:DICT-UPDATE` with the same *default*. After path preparation permits
invocation, *function* is invoked exactly once, at call time, and only its primary
return value is used; zero values installs `NIL`. The operation returns
*new-dict* as its only value. Rebuilding a standard hash-table ancestor uses
fresh shallow copies and preserves its test;
no input ancestor is mutated.

When the leaf key is absent, *function* receives *default*. A present leaf passes its
associated value, including `NIL`, regardless of *default*. Absence alone does
not signal an error. *default* applies only at the leaf; it does not replace
missing intermediates or suppress path errors. It is an ordinary eagerly
evaluated argument, even when the leaf is present, and is not called when it
is a function object. There is no `:signal` keyword.

**Method Signatures:**

- `SL:DICT-UPDATE-IN (`*dict* `T)` *keys fn* `&key (default NIL)` — the default
  method.

**Extensibility:**

A user dict type supporting `SL:DICT-SET` gets `SL:DICT-UPDATE-IN` through
the default method without defining anything further.

**Exceptional Situations:**

- Signals an error of type `TYPE-ERROR` if *function* is not a function designator.
- Signals an error of type `TYPE-ERROR` if *dict* is not a `SL:DICTP` object.
- Path and unsupported-write conditions are specified in Section 9.1.17.
- An unrecognized keyword, including `:signal`, is subject to ordinary Common
  Lisp keyword argument checking.

**See Also:**

`SL:DICT-UPDATE`; `SL:DICT-SET`; `SL:DICT-SET-IN`; `SL:DICT-REF-IN`; `SL:DICT-COLLECT`; Section 9.1.4; Section 9.1.7; Chapter 4.


### SL:DICT-SET-IN _Generic Function_

**Name:** `SL:DICT-SET-IN`, Generic Function

**Syntax:**

`SL:DICT-SET-IN` *dict keys value* → *new-dict*

**Arguments and Values:**

- *dict* — a `SL:DICTP` object whose type supports `SL:DICT-SET`, including a
  standard `hash-table`.
- *keys* — a seqable of keys forming a path into *dict*; the shared path protocol is in Section 9.1.17.
- *value* — any object.
- *new-dict* — a dict: *dict* with the leaf at *keys* set to *value*.

**Description:**

The nested path protocol of Section 9.1.17 applies. A single key is equivalent to
`SL:DICT-SET`. There are no keyword arguments; the operation sets the leaf value
and creates missing intermediates as specified in Section 9.1.17. Standard
hash-table ancestors are rebuilt with fresh shallow copies preserving their tests;
no input ancestor is mutated.

**Method Signatures:**

- `SL:DICT-SET-IN (`*dict* `T)` *keys value* — the default method.

**Extensibility:**

A user dict type supporting `SL:DICT-SET` gets `SL:DICT-SET-IN` through the
default method without defining anything further.

**Exceptional Situations:**

- Signals an error of type `TYPE-ERROR` if *dict* is not a `SL:DICTP` object.

**See Also:**

`SL:DICT-SET`; `SL:DICT-UPDATE-IN`; `SL:DICT-REF-IN`; `SL:DICT-COLLECT`; Section 9.1.4; Section 9.1.7; Chapter 4.


### SL:DICT-REF-IN _Generic Function_

**Name:** `SL:DICT-REF-IN`, Generic Function

**Syntax:**

`SL:DICT-REF-IN` *dict keys* `&optional` *default* → *(values value present-p)*

**Arguments and Values:**

- *dict* — a `SL:DICTP` object.
- *keys* — a seqable of keys forming a path into *dict*; the shared path protocol is in Section 9.1.17.
- *default* — any object; the default is `NIL`.
- *value* — the value at the leaf of *keys*, or *default* if any key in the
  path is absent.
- *present-p* — a generalized boolean: true if every key in the path was
  present and the leaf was reached; false if any key was absent.

**Description:**

The nested path protocol of Section 9.1.17 applies. If any key in the path is absent, the
operation returns `(values default NIL)`; it does not signal on absence. A single key is equivalent to
`SL:DICT-REF`. A present leaf whose value is `NIL` returns `(values NIL t)`. `SL:DICT-REF-IN` has no
setter; `SL:DICT-SET-IN` is the setter.

**Method Signatures:**

- `SL:DICT-REF-IN (`*dict* `T)` *keys* `&optional` *default* — the default
  method. Signals `TYPE-ERROR` if *dict* is not a `SL:DICTP` object.

**Extensibility:**

A user dict type that defines `SL:DICT-REF` gets `SL:DICT-REF-IN` through
the default method without defining anything further. Specialized methods must be observationally
equivalent to the default behavior.

**Exceptional Situations:**

- Signals an error of type `TYPE-ERROR` if *dict* is not a `SL:DICTP` object.

**See Also:**

`SL:DICT-REF`; `SL:DICT-MEMBER`; `SL:DICT-SET-IN`; `SL:DICT-UPDATE-IN`; Chapter 8; Section 9.1.4.


### 9.2.2 The Hash-Set Protocol

### Hash-Set Protocol _Protocol_

**Name:** Hash-Set Protocol

Covers: `SL:HASH-SET` (type), `SL:HASH-SET` (function), `SL:HASH-SET-P`,
`SL:SET-MEMBER`, `SL:SET-ADD`, `SL:SET-REMOVE`, `SL:SET-UNION`,
`SL:SET-INTERSECTION`, `SL:SET-MINUS`, `SL:SET-SUBSET-P`, and
`SL:SET-SIZE`.

This section covers 10 symbols in 11 dictionary entries; `SL:HASH-SET` has
separate type and function entries. `Exceptional Situations` lists specified situations and is
non-exhaustive.

The protocol describes the persistent hash-set type `SL:HASH-SET`, its
seqability and collector participation, and the set operations that accept
any seqable. A hash-set is not a `SL:DICTP` object (Section 9.1.11). The `#u()`
reader macro provides literal syntax (Chapter 3).

For set operations, a dict operand contributes entries (`SL:MAP-ENTRY` objects),
not keys. A dict's custom key test is ignored.

**Extension Contract:**

User methods for `SL:SET-MEMBER`, `SL:SET-ADD`, `SL:SET-REMOVE`,
`SL:SET-UNION`, `SL:SET-INTERSECTION`, `SL:SET-MINUS`, `SL:SET-SUBSET-P`, and
`SL:SET-SIZE` must preserve `SL:EQUALS` semantics, seqability checks,
`TYPE-ERROR` behavior for non-seqable arguments, eagerness, and result identity
where applicable. Each operand is traversed through one coherent traversal view
for the operation. Result-producing methods must return the fixed
`SL:HASH-SET` result type and must not mutate their inputs.

### SL:HASH-SET _Type_

**Name:** `SL:HASH-SET`, Type

**Syntax:**

`SL:HASH-SET`

**Arguments and Values:**

None.

**Description:**

`SL:HASH-SET` names the type of the persistent, unordered collection constructed by the
`SL:HASH-SET` function and the `hash-set` target of `SL:SEQ-INTO`. See Section 9.1.11 for its
collection and set-operation protocol, Section 9.1.5 for seqability, and Section 9.1.16 for
equality, comparison, and hashing.

A hash-set prints as `#u(...)` with its elements in their printed representation.

**Exceptional Situations:**

- Signals an error of type `PRINT-NOT-READABLE` if `*PRINT-READABLY*` is true and any element is unreadable.

**See Also:**

`SL:HASH-SET` (Function); `SL:HASH-SET-P`; `SL:SET-MEMBER`; `SL:SET-ADD`; `SL:SET-REMOVE`;
`SL:SET-UNION`; `SL:SET-INTERSECTION`; `SL:SET-MINUS`; `SL:SET-SUBSET-P`; `SL:SET-SIZE`;
Chapter 4; Chapter 7; Sections 9.1.5, 9.1.11, and 9.1.16.


### SL:HASH-SET _Function_

**Name:** `SL:HASH-SET`, Function

**Syntax:**

`SL:HASH-SET` `&rest` *elements* → *hash-set*

**Arguments and Values:**

- *elements* — zero or more objects, any acceptable to `SL:EQUALS` and
  `SL:HASH-CODE`.
- *hash-set* — an `SL:HASH-SET` containing the distinct elements among
  *elements*.

**Description:**

Constructs a hash-set from its arguments. Duplicate elements are silently
deduplicated: the resulting set contains one occurrence of each distinct
element. The operation is eager; result identity is unspecified.

**Exceptional Situations:**

Signals no conditions of its own; the consequences are undefined as specified
for `SL:EQUALS` and `SL:HASH-CODE` (Chapter 7).

**See Also:**

`SL:HASH-SET` (Type); `SL:HASH-SET-P`; `SL:SEQ-INTO`; `SL:SET-ADD`;
`SL:SET-UNION`; Chapter 4; Chapter 7; Sections 9.1.11 and 9.1.16.


### SL:HASH-SET-P _Generic Function_

**Name:** `SL:HASH-SET-P`, Generic Function

**Syntax:**

`SL:HASH-SET-P` *object* → *generalized-boolean*

**Arguments and Values:**

- *object* — any object.
- *generalized-boolean* — true if *object* is a `SL:HASH-SET`, otherwise
  false.

**Description:**

Returns true if *object* is a `SL:HASH-SET`, otherwise false. This is the
type predicate for the hash-set type. A hash-set is not a `SL:DICTP` object;
`SL:DICTP` returns false for a hash-set.

**Method Signatures:**

- `SL:HASH-SET-P (*object* SL:HASH-SET)` — returns true.
- `SL:HASH-SET-P (*object* T)` — returns false.

**Extensibility:**

`SL:HASH-SET-P` is an extensible generic function. The built-in
`SL:HASH-SET` method returns true, and the `T` method returns `NIL`.
More-specific methods on user subclasses take effect through normal CLOS
dispatch. The built-in semantics are exact for the built-in type.

**Exceptional Situations:**

None.

**See Also:**

`SL:HASH-SET` (Type, Function); `SL:DICTP`; `SL:SET-MEMBER`; Chapter 4;
Chapter 7; Sections 9.1.11 and 9.1.16.


### SL:SET-MEMBER _Generic Function_

**Name:** `SL:SET-MEMBER`, Generic Function

**Syntax:**

`SL:SET-MEMBER` *item sequence* → *generalized-boolean*

**Arguments and Values:**

- *item* — any object.
- *sequence* — any seqable.
- *generalized-boolean* — true if *item* is an element of *sequence* under
  `SL:EQUALS`, otherwise false.

**Description:**

Returns true if *item* is an element of *sequence* under `SL:EQUALS`. On a
hash-set, the test is O(1) expected. On other seqables, it delegates to
traversal (O(n)). This is the boolean membership test that `SL:SEQ-MEMBER`
is not (`SL:SEQ-MEMBER` returns a lazy-seq tail, not a boolean).

On a dict, `SL:SET-MEMBER` checks whether any entry (`SL:MAP-ENTRY`
object) matches *item* — this is incidental to dicts being seqable; because `SL:EQUALS` is not coerced
across types, `SL:SET-MEMBER` on a dict returns false for any item that is not itself an `SL:MAP-ENTRY`
object equal to a traversed entry. A dict's custom key test is ignored. For key membership, use
`SL:DICT-MEMBER` or `(SL:SET-MEMBER item (SL:DICT-KEYS d))`.

The operation is eager on unbounded inputs: an unsuccessful `SL:SET-MEMBER`
does not terminate on an infinite seqable.

**Method Signatures:**

- `SL:SET-MEMBER (*item* T) (*sequence* SL:HASH-SET)` — O(1) expected
  lookup under `SL:EQUALS`.
- `SL:SET-MEMBER (*item* T) (*sequence* T)` — traversal-based membership
  under `SL:EQUALS`.

**Exceptional Situations:**

- Signals an error of type `TYPE-ERROR` if *sequence* is not seqable.
- Does not terminate on an unbounded seqable when *item* is not present.

**See Also:**

`SL:SEQ-MEMBER`; `SL:SET-ADD`; `SL:SET-REMOVE`; `SL:SET-SUBSET-P`;
`SL:SET-SIZE`; `SL:DICT-MEMBER`; `SL:DICT-KEYS`; Chapter 4; Chapter 7;
Sections 9.1.11 and 9.1.16.


### SL:SET-ADD _Generic Function_

**Name:** `SL:SET-ADD`, Generic Function

**Syntax:**

`SL:SET-ADD` *item sequence* → *hash-set*

**Arguments and Values:**

- *item* — any object.
- *sequence* — any seqable.
- *hash-set* — a `SL:HASH-SET` containing the elements of *sequence*
  plus *item* (deduplicated).

**Description:**

Returns a `SL:HASH-SET` containing the distinct elements of
*sequence* plus *item*. The result is always a hash-set regardless of the
input type. Deduplicating the source gives O(1) expected future membership
checks on the result.

Returns a hash-set containing the element; if the element is already present, the
result may be the input.

The operation is eager: it consumes all finite input at call time.

**Method Signatures:**

- `SL:SET-ADD (*item* T) (*sequence* T)` — constructs a hash-set
  from the elements of *sequence* plus *item*.

**Exceptional Situations:**

- Signals an error of type `TYPE-ERROR` if *sequence* is not seqable.
- Does not terminate on an unbounded seqable.

**See Also:**

`SL:HASH-SET` (Function); `SL:SET-MEMBER`; `SL:SET-REMOVE`; `SL:SET-UNION`;
`SL:SET-INTERSECTION`; `SL:SET-MINUS`; Chapter 4; Chapter 7; Sections 9.1.11 and 9.1.16.


### SL:SET-REMOVE _Generic Function_

**Name:** `SL:SET-REMOVE`, Generic Function

**Syntax:**

`SL:SET-REMOVE` *item sequence* → *hash-set*

**Arguments and Values:**

- *item* — any object.
- *sequence* — any seqable.
- *hash-set* — a `SL:HASH-SET` containing the distinct elements of
  *sequence* minus *item*.

**Description:**

Returns a `SL:HASH-SET` containing the distinct elements of
*sequence* with *item* removed (under `SL:EQUALS`). The result is always a
hash-set regardless of the input type. If *item* was absent and *sequence* was a
hash-set, the result may be *sequence* itself.

The operation is eager.

**Method Signatures:**

- `SL:SET-REMOVE (*item* T) (*sequence* T)` — constructs a hash-set
  from the elements of *sequence* minus *item*.

**Exceptional Situations:**

- Signals an error of type `TYPE-ERROR` if *sequence* is not seqable.
- Does not terminate on an unbounded seqable.

**See Also:**

`SL:SET-MEMBER`; `SL:SET-ADD`; `SL:SET-MINUS`; `SL:SET-UNION`;
`SL:SET-INTERSECTION`; Chapter 4; Chapter 7; Sections 9.1.11 and 9.1.16.


### SL:SET-UNION _Generic Function_

**Name:** `SL:SET-UNION`, Generic Function

**Syntax:**

`SL:SET-UNION` *s1 s2* `&rest` *more-sets* → *hash-set*

**Arguments and Values:**

- *s1*, *s2* — any seqables.
- *more-sets* — zero or more additional seqables.
- *hash-set* — a `SL:HASH-SET` containing the distinct elements of
  *s1*, *s2*, and all *more-sets* combined.

**Description:**

Returns a `SL:HASH-SET` containing the union of the elements of
*s1*, *s2*, and all *more-sets* under `SL:EQUALS`. The operation is variadic
with minimum arity 2. The result is always a hash-set, and the operation is
eager.

**Method Signatures:**

- `SL:SET-UNION (*s1* T) (*s2* T) &rest *more-sets*` — constructs a
  hash-set from the elements of *s1*, *s2*, and all *more-sets*.

**Exceptional Situations:**

- Signals an error of type `PROGRAM-ERROR` if fewer than two arguments are
  supplied (the usual argument-count error).
- Signals an error of type `TYPE-ERROR` if *s1*, *s2*, or any *more-sets*
  is not seqable.
- Does not terminate on an unbounded seqable.

**See Also:**

`SL:SET-ADD`; `SL:SET-REMOVE`; `SL:SET-INTERSECTION`; `SL:SET-MINUS`;
`SL:SET-SUBSET-P`; `SL:SET-SIZE`; Chapter 4; Chapter 7; Sections 9.1.11 and 9.1.16.


### SL:SET-INTERSECTION _Generic Function_

**Name:** `SL:SET-INTERSECTION`, Generic Function

**Syntax:**

`SL:SET-INTERSECTION` *s1 s2* `&rest` *more-sets* → *hash-set*

**Arguments and Values:**

- *s1*, *s2* — any seqables.
- *more-sets* — zero or more additional seqables.
- *hash-set* — a `SL:HASH-SET` containing the elements present in
  *s1*, *s2*, and all *more-sets* under `SL:EQUALS`.

**Description:**

Returns a `SL:HASH-SET` containing the intersection of the elements
of *s1*, *s2*, and all *more-sets* under `SL:EQUALS`. The operation is
variadic with minimum arity 2. The result is always a hash-set, and the
operation is eager.

**Method Signatures:**

- `SL:SET-INTERSECTION (*s1* T) (*s2* T) &rest *more-sets*` — constructs a
  hash-set from the elements common to *s1*, *s2*, and all *more-sets*.

**Exceptional Situations:**

- Signals an error of type `PROGRAM-ERROR` if fewer than two arguments are
  supplied (the usual argument-count error).
- Signals an error of type `TYPE-ERROR` if *s1*, *s2*, or any *more-sets*
  is not seqable.
- Does not terminate on an unbounded seqable.

**See Also:**

`SL:SET-UNION`; `SL:SET-MINUS`; `SL:SET-SUBSET-P`; `SL:SET-MEMBER`;
`SL:SET-SIZE`; Chapter 4; Chapter 7; Sections 9.1.11 and 9.1.16.


### SL:SET-MINUS _Generic Function_

**Name:** `SL:SET-MINUS`, Generic Function

**Syntax:**

`SL:SET-MINUS` *s1 s2* `&rest` *more-sets* → *hash-set*

**Arguments and Values:**

- *s1*, *s2* — any seqables.
- *more-sets* — zero or more additional seqables.
- *hash-set* — a `SL:HASH-SET` containing the elements of *s1* that
  are not in *s2* or any *more-sets* under `SL:EQUALS`.

**Description:**

Returns a `SL:HASH-SET` containing the elements of *s1* that are not
in *s2* or any *more-sets* under `SL:EQUALS` (set difference). The
operation is variadic with minimum arity 2. The result is always a
hash-set, and the operation is eager.

**Method Signatures:**

- `SL:SET-MINUS (*s1* T) (*s2* T) &rest *more-sets*` — constructs a
  hash-set from the elements of *s1* not in *s2* or any *more-sets*.

**Exceptional Situations:**

- Signals an error of type `PROGRAM-ERROR` if fewer than two arguments are
  supplied (the usual argument-count error).
- Signals an error of type `TYPE-ERROR` if *s1*, *s2*, or any *more-sets*
  is not seqable.
- Does not terminate on an unbounded seqable.

**See Also:**

`SL:SET-UNION`; `SL:SET-INTERSECTION`; `SL:SET-REMOVE`; `SL:SET-SUBSET-P`;
`SL:SET-SIZE`; Chapter 4; Chapter 7; Sections 9.1.11 and 9.1.16.


### SL:SET-SUBSET-P _Generic Function_

**Name:** `SL:SET-SUBSET-P`, Generic Function

**Syntax:**

`SL:SET-SUBSET-P` *s1 s2* → *generalized-boolean*

**Arguments and Values:**

- *s1*, *s2* — any seqables.
- *generalized-boolean* — true if every element of *s1* is in *s2* under
  `SL:EQUALS`, otherwise false.

**Description:**

Returns true if *s1* is a subset of *s2* (every element of *s1* is in *s2*
under `SL:EQUALS`). The empty set is a subset of every set. The operation is
eager on unbounded inputs: it does not terminate on infinite seqables.

**Method Signatures:**

- `SL:SET-SUBSET-P (*s1* T) (*s2* T)` — traversal-based subset test under
  `SL:EQUALS`.

**Exceptional Situations:**

- Signals an error of type `TYPE-ERROR` if *s1* or *s2* is not seqable.
- Does not terminate on an unbounded seqable.

**See Also:**

`SL:SET-MEMBER`; `SL:SET-INTERSECTION`; `SL:SET-SIZE`; `SL:HASH-SET-P`;
Chapter 4; Chapter 7; Sections 9.1.11 and 9.1.16.


### SL:SET-SIZE _Generic Function_

**Name:** `SL:SET-SIZE`, Generic Function

**Syntax:**

`SL:SET-SIZE` *sequence* → *count*

**Arguments and Values:**

- *sequence* — any seqable.
- *count* — a non-negative integer: the number of distinct elements in
  *sequence* under `SL:EQUALS`.

**Description:**

Returns the number of distinct elements in *sequence* under `SL:EQUALS`.
On a hash-set, the count is O(1) (maintained incrementally). On other
seqables, it is expected O(n) (traversal with deduplication).

`SL:SET-SIZE` is the distinct element count, not sequence length:
`(SL:SET-SIZE '(1 1 1 1))` → `1`, while `(SL:SEQ-LENGTH '(1 1 1 1))` →
`4`. The operation is eager on unbounded inputs: it does not terminate on
infinite seqables.

**Method Signatures:**

- `SL:SET-SIZE (*sequence* SL:HASH-SET)` — O(1) distinct element count.
- `SL:SET-SIZE (*sequence* T)` — expected O(n) traversal with deduplication
  under `SL:EQUALS`.

**Exceptional Situations:**

- Signals an error of type `TYPE-ERROR` if *sequence* is not seqable.
- Does not terminate on an unbounded seqable.

**See Also:**

`SL:SEQ-LENGTH`; `SL:SET-MEMBER`; `SL:SET-ADD`; `SL:SET-REMOVE`;
`SL:SET-UNION`; `SL:SET-INTERSECTION`; `SL:SET-SUBSET-P`; Chapter 4;
Chapter 7; Sections 9.1.11 and 9.1.16.

