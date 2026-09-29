# Chapter 7: Equality and Comparison

This chapter defines extensible protocols for structural equality, comparison,
and hashing. It also defines four ordinary functions that interpret comparison
results as ordering predicates.

## 7.1 Concepts

### 7.1.1 Protocol Overview

The protocol consists of three generic functions and four ordinary functions:

- `SL:EQUALS` tests two objects for extensible structural equality.
- `SL:COMPARE` reports whether two objects are less, equal, greater, or
  incomparable.
- `SL:HASH-CODE` computes an integer hash consistent with `SL:EQUALS`.
- `SL:LT`, `SL:LTE`, `SL:GT`, and `SL:GTE` interpret the result of
  `SL:COMPARE` as Boolean ordering relations.

The protocol is additive: existing Common Lisp equality and ordering operators
are unaffected. Unless a Sophie-specific rule applies, numeric, character, and
string equality and ordering follow the corresponding CLHS semantics; character
and string comparisons are case-sensitive.

### 7.1.2 Extensibility Contract

A value-based method on `SL:EQUALS` requires a corresponding `SL:HASH-CODE`
method. Whenever `SL:EQUALS` returns true, the two objects must have equal hash
codes. Whenever `SL:COMPARE` returns, it must return `:EQUAL` if `SL:EQUALS`
returns true; the converse is not required.

User-defined protocol obligations are as follows:

- Identity/fallback types require no user-defined methods; the `T` method handles
  them.
- Value-equality types must have applicable `SL:EQUALS` and `SL:HASH-CODE`
  methods.
- Ordered types must have an applicable `SL:COMPARE` method.
- Inherited methods satisfy these obligations.

A user-defined `SL:EQUALS` method specialized on a cross-type pair (for example,
`(my-type T)`) must ensure that the reverse call also returns the correct result.
Both directional method paths must be covered.

User-defined `SL:EQUALS` methods must collectively define an equivalence
relation. User-defined `SL:COMPARE` methods must satisfy these laws:

- **Antisymmetry:** if `SL:COMPARE(a, b)` returns `:LESS`, then
  `SL:COMPARE(b, a)` returns `:GREATER`, and vice versa.
- **`:UNEQUAL` symmetry:** `SL:COMPARE(a, b)` returns `:UNEQUAL` if and only if
  `SL:COMPARE(b, a)` returns `:UNEQUAL`.
- **Transitivity:** if `SL:COMPARE(a, b)` is `:LESS` and
  `SL:COMPARE(b, c)` is `:LESS`, then `SL:COMPARE(a, c)` is `:LESS`; the same
  requirement applies to `:GREATER`.
- **Ordering-equivalence compatibility:** if `(SL:COMPARE a b)` returns
  `:EQUAL` and `(SL:COMPARE b c)` returns `:LESS`, then `(SL:COMPARE a c)` must
  return `:LESS`. The same holds for `:GREATER`. This ensures that
  ordering-equivalent values are substitutable in comparisons.

**Numeric incomparability exception.** The transitivity and ordering-equivalence
compatibility implications above have one exception: their required `:LESS` or
`:GREATER` conclusion may instead be `:UNEQUAL` when that result is required by
the specified numeric comparison rule, either directly or by propagation
through the specified lexicographic comparison rules for conses, rank-one
arrays, lazy sequences, and `SL:MAP-ENTRY` objects, including recursive
combinations of these rules. The exception applies only to the conclusion
forced by those rules; the presence of a number or complex number in an
argument does not otherwise exempt a comparison from either law. It does not
permit an opposite ordering result, change any specified comparison result, or
relax equivalence of `SL:EQUALS`, equality/hash consistency, equality/comparison
consistency, antisymmetry, or `:UNEQUAL` symmetry. User-defined methods remain
subject to these obligations; merely calling `SL:COMPARE` on numeric or compound
values does not confer an exemption.

Every method must satisfy the equality/hash and equality/comparison invariants.
The equivalence, antisymmetry, transitivity, and ordering-equivalence
compatibility requirements, subject only to the numeric incomparability
exception above, apply to every result returned by `SL:EQUALS` and `SL:COMPARE`,
including results returned for circular structures. They do not require either
operation to terminate on a circular structure. The consequences of violating
these obligations are undefined.

**Fallback policy.** Types not covered by a specified or user-defined value
method use identity-oriented fallback behavior. The equality fallback uses
`CL:EQ` for standard objects and `CL:EQL` for structure objects and other `T`
objects. The comparison fallback returns `:EQUAL` exactly when `SL:EQUALS` is
true, and otherwise returns `:UNEQUAL`. Standard objects and structure objects
use stable per-instance identity hashes; the `T` hash fallback is consistent
with its `CL:EQL`-based equality. Identity hashes for different objects may
collide.

The specified behavior for compound built-in types and lazy sequences takes
precedence over methods that would otherwise be selected because of a host
implementation's class hierarchy. An implementation must ensure that its method
selection preserves all such behavior specified in this chapter. Conforming
programs must not override the enumerated standardized methods; methods on
subclasses remain permitted and take effect.

Methods for `SL:DICT`, `SL:ORDERED-DICT`, and `SL:HASH-SET`, including their equality, comparison,
and hashing behavior, are specified in Chapter 9.

The ordered dictionary dispatch cases supplement the entries below:

| Generic function | Specializers | Required behavior |
|---|---|---|
| `SL:EQUALS` | `(SL:ORDERED-DICT SL:ORDERED-DICT)` | Same size and recursively equal corresponding keys and values in stored order. |
| `SL:EQUALS` | `(SL:ORDERED-DICT T)`, `(T SL:ORDERED-DICT)` | False for the other standardized representations enumerated in Chapter 9, including empty list/lazy/vector/dict representations. |
| `SL:COMPARE` | `(SL:ORDERED-DICT SL:ORDERED-DICT)` | `:EQUAL` exactly when `SL:EQUALS` is true; otherwise `:UNEQUAL`. No lexicographic dictionary ordering. |
| `SL:COMPARE` | `(SL:ORDERED-DICT T)`, `(T SL:ORDERED-DICT)` | `:UNEQUAL` for the other standardized representations enumerated in Chapter 9. |
| `SL:HASH-CODE` | `(SL:ORDERED-DICT)` | Bounded, cycle-safe ordered-content hashing consistent with equality; independent of storage shape, edit history, and internal position labels. |

These cross-representation cases do not prescribe behavior for unrelated user
types beyond this chapter's extension laws. Stored order is a sequence order,
not an ordering relation on dictionaries. Unequal orders may hash alike. The
numeric, array, NIL/lazy, finite-prefix, and cycle rules below remain unchanged;
no additional public hash-context protocol is defined.

### 7.1.3 Traversal and Exceptional Conditions

**Canonical array traversal and shape.** A rank-one array is traversed over its
active length, as reported by `CL:LENGTH`; a fill pointer limits the portion
traversed, and allocated capacity is irrelevant. Rank-zero arrays are compared
by their sole elements. Higher-rank arrays require equal ranks and dimensions;
equality compares corresponding row-major elements, and hashing follows the
same equality relation. Strings and other rank-one arrays containing the
same characters therefore participate in the same equality and hash relation.
For comparison, rank-one arrays are ordered lexicographically over their active
elements: the first decisive or incomparable result determines the result, and a
proper prefix is less. An array of any other rank compares by equality (`:EQUAL`
or `:UNEQUAL`) and has no ordering.

**NIL and empty lazy sequences.** An empty lazy sequence is equality- and
hash-equivalent to `NIL`. Comparison treats them as equal and places `NIL`
before nonempty lazy sequences, with the corresponding reverse result in the
opposite argument order. `NIL` has empty-sequence comparison semantics, not
symbol-name ordering: a comparison of `NIL` with any non-`NIL` symbol returns
`:UNEQUAL` in either argument order. This includes a distinct symbol whose name
is `"NIL"`. Empty lazy sequences are likewise incomparable with non-`NIL`
symbols. These rules do not equate `NIL` or empty lazy sequences with empty
strings or other empty arrays. Lazy-sequence representations are not coerced.
The contextual ordering of cons tails is specified in the `SL:COMPARE` entry.

**Traversal and exceptional conditions.** The consequences are undefined if an
argument to `SL:EQUALS`, `SL:COMPARE`, or `SL:HASH-CODE` is a floating-point
NaN. `SL:EQUALS` and `SL:COMPARE` are permitted not to terminate on circular
structures; they are not required to detect finite cycles. If a finite prefix
establishes a decisive equality or comparison result before circular traversal
would continue, that result is returned normally. Any result returned for a
circular structure remains subject to the protocol laws in §7.1.2. No error is
required merely because a structure is circular. `SL:HASH-CODE` remains bounded
and cycle-safe for finite structural objects, including finite cyclic structures,
and must not recurse forever on a finite cycle. Modifying a hash table while it
is being compared or hashed has undefined consequences. Traversal of an
unbounded lazy sequence is not guaranteed to terminate, including traversal through conses,
arrays, hash-table entries, and map-entry components. Traversing a lazy sequence
may force nodes and invoke deferred computations; conditions and non-local exits
propagate, and traversal may not terminate if forcing does not terminate.
Adding or redefining `SL:EQUALS` or `SL:HASH-CODE` methods after objects are
resident in an `SL:DICT`, `SL:ORDERED-DICT`, or `SL:HASH-SET` has undefined consequences.

### 7.1.4 Default Tests in Sophie Operations

Chapter 6 specifies the default equality and ordering tests for Sophie
operations. Standard hash tables continue to use their standard test functions
for key lookup. Programs requiring another ordering use an explicit comparison
function where an operation accepts one. In particular, alphabetical symbol
ordering, including `NIL` under its name `"NIL"`, can use `CL:STRING<` on the
results of `CL:SYMBOL-NAME`. Such a function does not change the semantics of
`SL:COMPARE`; no separate comparison-context protocol is defined.

### 7.1.5 Performance

An implementation may bypass generic dispatch for built-in types when the
observable behavior is identical to full generic dispatch. User-defined methods
must still take effect, including methods more specific than a standardized
method. The standardized-method prohibition and subclass rule are specified in
§7.1.2. Here, standard types mean the exact classes for which methods are
enumerated.

## 7.2 Dictionary

Extensibility and invariants for all entries in this section are specified in
§7.1.2. Entry-specific obligations, if any, are stated in the entry. Notes and
examples for this chapter appear in Appendix D.

### 7.2.1 Equality and Comparison

### SL:EQUALS _Generic Function_

**Name:** `SL:EQUALS`, Generic Function

**Syntax:**

`(SL:EQUALS` *object1 object2* `)` → *generalized-boolean*

**Arguments and Values:**

- *object1*, *object2* — objects.
- *generalized-boolean* — true when the objects are structurally equal;
  otherwise false.

**Description:**

`SL:EQUALS` recursively compares the components of compound values.

Conses are compared by recursively comparing their cars and cdrs with
`SL:EQUALS`. When the recursive comparison of cdrs selects an applicable
lazy-sequence method, that method forces the lazy-sequence argument as needed.

Arrays compare corresponding elements according to the canonical array traversal
and shape rule in §7.1.3.

Two hash tables are equal when they have equal entry counts and there is a
bijection between their distinct entries such that corresponding keys and
values are recursively `SL:EQUALS`. Their hash-table test functions do not
participate in this comparison.

Two lazy sequences are compared element by element. Corresponding elements are
compared recursively, and the sequences are equal exactly when they end together
without a mismatch. A mismatch or an observed end can establish a result after
a finite prefix. Lazy-sequence representations are not coerced. The
`NIL`/empty-lazy-sequence rule is specified in §7.1.3.

Two `SL:MAP-ENTRY` objects are equal when both their keys and their values are
recursively `SL:EQUALS`.

**Method Signatures:**

- `(number number)` — CLHS numeric equality.
- `(character character)` — CLHS case-sensitive character equality.
- `(string string)` — CLHS case-sensitive string equality.
- `(cons cons)` — recursively compares cars and cdrs.
- `(array array)` — compares elements under the canonical array rule; supports
  string/rank-one-array equality.
- `(hash-table hash-table)` — compares entry counts and recursively compares
  corresponding keys and values, independently of test functions.
- `(SL:LAZY-SEQ SL:LAZY-SEQ)` — forces and compares elements.
- `(SL:LAZY-SEQ null)`, `(null SL:LAZY-SEQ)` — determine whether the sequence is
  empty.
- `(SL:MAP-ENTRY SL:MAP-ENTRY)` — recursively compares keys and values.
- `(T T)` — identity fallback: `CL:EQ` for standard objects, `CL:EQL` for all
  other types.

**Side Effects:**

Forcing lazy-sequence arguments may invoke deferred computations. Modifying a
hash table while it is being compared has undefined consequences.

**Exceptional Situations:**

The consequences are undefined if an argument is a floating-point NaN. Traversal
of circular or unbounded structures may not terminate; see §7.1.3.

**See Also:**

- [SL:COMPARE](#slcompare-generic-function)
- [SL:LT, SL:LTE, SL:GT, SL:GTE](#sllt-sllte-slgt-slgte-functions)
- [SL:HASH-CODE](#slhash-code-generic-function)
- Chapter 4
- Chapter 9


### SL:COMPARE _Generic Function_

**Name:** `SL:COMPARE`, Generic Function

**Syntax:**

`(SL:COMPARE` *a b* `)` → *comparison-result*

**Arguments and Values:**

- *a*, *b* — objects.
- *comparison-result* — one of `:LESS`, `:EQUAL`, `:GREATER`, or `:UNEQUAL`.

**Description:**

`SL:COMPARE` reports the relationship of *a* to *b*:

| Result | Meaning |
|---|---|
| `:LESS` | *a* precedes *b*. |
| `:EQUAL` | *a* and *b* compare equal. |
| `:GREATER` | *a* follows *b*. |
| `:UNEQUAL` | *a* and *b* are incomparable. |

Comparison equality (`:EQUAL`) may be coarser than `SL:EQUALS` equality.
Substitutability in ordered comparisons is subject to the numeric
incomparability exception in §7.1.2.

`SL:COMPARE` does not signal merely because its arguments are incomparable; it
returns `:UNEQUAL`.

For two numbers, `SL:COMPARE` returns `:EQUAL` if and only if `CL:=` returns
true. Otherwise, if both arguments are real, it returns `:LESS` or `:GREATER`
according to their CLHS numeric order. Otherwise, at least one argument is
complex and it returns `:UNEQUAL`. In particular, a complex number with a zero
imaginary part can compare `:EQUAL` to a real number without being orderable
against other real numbers.

Non-`NIL` symbols are ordered lexicographically by
their names, so distinct non-`NIL` symbols with equal names compare `:EQUAL`.
`NIL` compares `:EQUAL` with itself and follows the empty-sequence rule in
§7.1.3, not the symbol-name rule.

Conses are compared lexicographically down their cdr chains. Cars are compared
first with `SL:COMPARE`. A decisive or incomparable result is returned
immediately, without examining the cdrs. After an `:EQUAL` car result, an empty
tail is either `NIL` or an `SL:LAZY-SEQ` node that resolves to empty. Lazy cdrs
are forced in left-to-right order as needed to determine emptiness, without
forcing the rest of a nonempty node. Two empty tails compare `:EQUAL`; an empty
tail precedes any nonempty tail, including a dotted atom, with the corresponding
reverse result in the opposite argument order. These are contextual cons-tail
rules: they do not order standalone `NIL` or empty lazy sequences against
unrelated representations. Thus substituting an empty lazy tail for a `NIL`
tail preserves the comparison result.

When neither tail is empty, a lazy tail participates through `SL:COMPARE` on
the two tails. Otherwise, two cons tails or two atom tails are compared with
`SL:COMPARE`; a cons tail and an atom tail are incomparable. For example,
`(SL:COMPARE '(1 . 2) '(1))` returns `:GREATER`, as does comparison with a cons
whose car is `1` and whose cdr is an empty lazy sequence.

Arrays are ordered according to the canonical array traversal and shape rule in
§7.1.3.

Hash tables compare `:EQUAL` when they are `SL:EQUALS` and `:UNEQUAL` otherwise.
Lazy sequences are compared lexicographically while being forced. The first
decisive or incomparable element result determines the result; a sequence that
ends first is less, and sequences that end together after equal elements compare
`:EQUAL`. The `NIL`/empty-lazy-sequence rule is specified in §7.1.3.

`SL:MAP-ENTRY` objects compare lexicographically by key and then value, using
`SL:COMPARE` for each component.

**Method Signatures:**

- `(number number)` — usual numeric order with the Sophie-specific complex rules.
- `(character character)` — CLHS case-sensitive character order.
- `(vector vector)` — lexicographic order for rank-one arrays and strings.
- `(symbol symbol)` — lexicographic order by names for non-`NIL` symbols;
  `NIL` compares equal only with `NIL` among symbols and is incomparable with
  every non-`NIL` symbol.
- `(cons cons)` — lexicographically compares cars and cdrs.
- `(array array)` — orders arrays under the canonical array rule.
- `(hash-table hash-table)` — returns `:EQUAL` or `:UNEQUAL` according to equality.
- `(SL:LAZY-SEQ SL:LAZY-SEQ)` — lexicographically compares forced elements.
- `(SL:LAZY-SEQ null)`, `(null SL:LAZY-SEQ)` — distinguish empty from nonempty.
- `(SL:MAP-ENTRY SL:MAP-ENTRY)` — lexicographically compares keys and values.
- `(T T)` — fallback: returns `:EQUAL` when `SL:EQUALS` is true, otherwise
  `:UNEQUAL`.

**Side Effects:**

Forcing lazy-sequence arguments may invoke deferred computations. Modifying a
hash table while it is being compared has undefined consequences.

**Exceptional Situations:**

The consequences are undefined if an argument is a floating-point NaN. Traversal
of circular or unbounded structures may not terminate; see §7.1.3.

**See Also:**

- [SL:EQUALS](#slequals-generic-function)
- [SL:LT, SL:LTE, SL:GT, SL:GTE](#sllt-sllte-slgt-slgte-functions)
- Chapter 4
- Chapter 6
- Chapter 9


### SL:LT, SL:LTE, SL:GT, SL:GTE _Functions_

**Name:** `SL:LT`, `SL:LTE`, `SL:GT`, `SL:GTE`, Functions

**Syntax:**

`(SL:LT` *a b* `)` → *generalized-boolean*<br>
`(SL:LTE` *a b* `)` → *generalized-boolean*<br>
`(SL:GT` *a b* `)` → *generalized-boolean*<br>
`(SL:GTE` *a b* `)` → *generalized-boolean*

**Arguments and Values:**

- *a*, *b* — objects.
- *generalized-boolean* — true when the named ordering relation holds;
  otherwise false.

**Description:**

Each function calls `SL:COMPARE` on *a* and *b* and interprets the result. `SL:LT`,
`SL:LTE`, `SL:GT`, and `SL:GTE` are not guaranteed to terminate when `SL:COMPARE` would not
terminate, such as when comparing unbounded lazy sequences:

| Function | True comparison results |
|---|---|
| `SL:LT` | `:LESS` |
| `SL:LTE` | `:LESS`, `:EQUAL` |
| `SL:GT` | `:GREATER` |
| `SL:GTE` | `:GREATER`, `:EQUAL` |

**Extensibility:**

These functions are not generic. Programs extend their behavior by defining
applicable `SL:COMPARE` methods, subject to §7.1.2.

**Side Effects:**

Any side effects of the applicable `SL:COMPARE` method occur.

**Exceptional Situations:**

Signals an error of type `SIMPLE-ERROR` if `SL:COMPARE` returns `:UNEQUAL`.
Other conditions signaled by the applicable comparison method propagate.

**See Also:**

- [SL:COMPARE](#slcompare-generic-function)
- [SL:EQUALS](#slequals-generic-function)
- Chapter 6


### 7.2.2 Hashing

### SL:HASH-CODE _Generic Function_

**Name:** `SL:HASH-CODE`, Generic Function

**Syntax:**

`(SL:HASH-CODE` *object* `)` → *hash-code*

**Arguments and Values:**

- *object* — an object.
- *hash-code* — a non-negative integer.

**Description:**

`SL:HASH-CODE` returns a non-negative integer. Objects equal under `SL:EQUALS`
receive equal hash codes; unequal objects may collide. Strings and rank-one arrays
containing equal characters hash identically, and `NIL` and empty lazy sequences
hash identically, as required by §7.1.3.

Hashing terminates for finite structures, including finite cyclic structures, by a
bounded, cycle-safe traversal. It is not guaranteed to terminate for unbounded lazy
sequences whose forcing does not terminate. The specific traversal depth,
element count, and mixing strategy are implementation-defined.

**Method Signatures:**

- `(number)` — hashes numeric values consistently with numeric equality.
- `(character)` — hashes characters consistently with character equality.
- `(cons)` — hashes recursively consistently with equality.
- `(array)` — hashes according to the canonical array rule.
- `(hash-table)` — hashes consistently with hash-table equality.
- `(SL:LAZY-SEQ)` — hashes consistently with lazy-sequence equality.
- `(null)` — produces the empty-lazy-sequence hash.
- `(SL:MAP-ENTRY)` — hashes keys and values consistently with equality.
- `(T)` — identity hash fallback: stable per-instance identity hash for
  standard and structure objects; `CL:EQL`-consistent hash for other types.

**Exceptional Situations:**

The consequences are undefined if an argument is a floating-point NaN. Hashing
of unbounded lazy sequences is not guaranteed to terminate; see §7.1.3.

**See Also:**

- [SL:EQUALS](#slequals-generic-function)
- [SL:COMPARE](#slcompare-generic-function)
- Chapter 4
- Chapter 9
