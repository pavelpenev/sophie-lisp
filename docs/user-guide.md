# Sophie Lisp User Guide

> **Informative.** This practical guide is non-normative. The
> [Sophie Lisp specification](../spec/chapter-01-introduction.md) is the sole
> authority if this guide and the specification differ. This guide reflects
> the specification in this repository.

Sophie Lisp is a conservative, purely additive Common Lisp extension. It adds
reader conveniences, lazy and generic collection operations, structural
comparison, destructuring, persistent dictionaries, and sets without changing
ANSI Common Lisp behavior.

## Contents

1. [Getting started](#1-getting-started)
2. [Reader syntax](#2-reader-syntax)
   - [2.1 Anonymous functions: `#^()` and `SL:OP`](#21-anonymous-functions--and-slop)
   - [2.2 Collection literals](#22-collection-literals)
   - [2.3 String interpolation](#23-string-interpolation)
3. [Sources and lazy sequences](#3-sources-and-lazy-sequences)
4. [Collection mental model](#4-collection-mental-model)
5. [Sequence operations](#5-sequence-operations)
   - [5.1 Mapping, selection, and substitution](#51-mapping-selection-and-substitution)
   - [5.2 Taking and dropping](#52-taking-and-dropping)
   - [5.3 Splitting and partitioning](#53-splitting-and-partitioning)
   - [5.4 Combining and walking trees](#54-combining-and-walking-trees)
   - [5.5 Reordering, deduplication, and trimming](#55-reordering-deduplication-and-trimming)
   - [5.6 Searching, predicates, and scalar results](#56-searching-predicates-and-scalar-results)
   - [5.7 `SEQ-INTO`](#57-seq-into)
6. [Equality and comparison](#6-equality-and-comparison)
7. [Binding, destructuring, and threading](#7-binding-destructuring-and-threading)
   - [7.1 Sequential binding and patterns](#71-sequential-binding-and-patterns)
   - [7.2 Threading and function utilities](#72-threading-and-function-utilities)
   - [7.3 Generic access with `REF`](#73-generic-access-with-ref)
8. [Dictionaries](#8-dictionaries)
   - [8.1 Construction and conversion](#81-construction-and-conversion)
   - [8.2 Lookup and persistent updates](#82-lookup-and-persistent-updates)
   - [8.3 Merge, projection, transformation, and aggregation](#83-merge-projection-transformation-and-aggregation)
   - [8.4 `DICT-COLLECT` and sequence operations on dicts](#84-dict-collect-and-sequence-operations-on-dicts)
9. [Hash sets](#9-hash-sets)
10. [Collectors and extension](#10-collectors-and-extension)
11. [Decision tables](#11-decision-tables)
   - [11.1 Dict merge result types](#111-dict-merge-result-types)
12. [Type preservation and promotion](#12-type-preservation-and-promotion)
13. [Recipes](#13-recipes)
   - [13.1 Porting shortcuts](#131-porting-shortcuts)
   - [13.2 Small but useful operations](#132-small-but-useful-operations)
   - [13.3 Equality and key normalization](#133-equality-and-key-normalization)
14. [Common Lisp idioms](#14-common-lisp-idioms)
15. [What Sophie does NOT have](#15-what-sophie-does-not-have)
16. [Quick reference](#16-quick-reference)

## 1. Getting started

For prerequisites and installation, follow [README: Getting started](../README.md#getting-started).
This guide uses unqualified Sophie symbol names (`SEQ-FIRST`, `DICT-REF`, etc.)
for readability; the `SL` package prefix is shown where it clarifies ownership.
Load the ASDF system, choose package activation, and independently choose reader
activation:

```lisp
(asdf:load-system "sophie-lisp")

(defpackage :my-app (:use :sl))
(in-package :my-app)

;; Put this near the top of each file that uses Sophie reader syntax.
(named-readtables:in-readtable :sl-core-syntax)
```

| Package | Nickname | Choose it when |
|---|---|---|
| `SOPHIE-LISP` | `SL` | You want CL and Sophie names together. |
| `SL-USER` | — | You want a ready-made interactive package using `SL`. |
| `SOPHIE-LISP-EXTENSIONS` | `SL-EXT` | You want `(:use :cl :sl-ext)` and only Sophie additions. |

Package use does not activate reader syntax. Reader activation is per-file,
like `IN-PACKAGE`: arrange for it before forms containing Sophie syntax are
read. The implementation registers `SL-CORE-SYNTAX` as a named readtable; use
`NAMED-READTABLES:IN-READTABLE`, `NAMED-READTABLES:DEFREADTABLE`, and
`NAMED-READTABLES:FIND-READTABLE` to activate, define, and inspect readtables.
Those are dependency APIs, not `SL` exports. See
[§3.1.1](../spec/chapter-03-reader-syntax.md#311-the-sl-core-syntax-readtable).

## 2. Reader syntax

`SL-CORE-SYNTAX` preserves standard syntax and adds six case-insensitive
dispatch macros. Element forms are evaluated at run time, left to right; merely
reading the syntax does not evaluate them.

### 2.1 Anonymous functions: `#^()` and `SL:OP`

Placeholders `%`/`%1`, `%2`, ... denote required arguments; `%&` denotes the
rest argument. The highest numbered placeholder determines required arity.
Recognition is syntactic by symbol name throughout symbols, conses, and vectors,
including quoted structure; `#^` replaces placeholders in the object it read,
whereas `SL:OP` builds a transformed macro expansion without mutating its input.

```lisp
(mapcar #^(1+ %) '(1 2 3))                 ; → (2 3 4)
(funcall #^(list %1 %2) :a :b)             ; → (:A :B)
(funcall (sl:op (apply #'+ %&)) 1 2 3)     ; → 6
```

See [§3.2](../spec/chapter-03-reader-syntax.md#32-lambda-shorthand).

### 2.2 Collection literals

```lisp
#v(1 (+ 1 1) 3)          ; → adjustable vector #(1 2 3), with fill pointer
#h(:a 1 :b 2)            ; → fresh mutable EQUAL hash table
#h(eq :a 1 :b 2)         ; → fresh mutable EQ hash table
#h('eq :symbol-key)       ; → EQUAL table whose key is the symbol EQ
#d(:a 1 :a 2)            ; → immutable SL:DICT, :A maps to 2
#u(1 1.0 2)               ; → immutable hash-set with two elements
```

For `#h`, an initial non-keyword symbol named `EQ`, `EQL`, `EQUAL`, or `EQUALP`
is a test specifier; quote it when it is intended as a key. `#h` and `#d` require
key/value pairs. Duplicate keys are last-wins. `#u` removes duplicates under
`SL:EQUALS`. Every evaluation of `#v` or `#h` returns a fresh mutable container;
identity of immutable `#d` and `#u` results is unspecified. See
[§3.3](../spec/chapter-03-reader-syntax.md#33-dispatch-macros).

### 2.3 String interpolation

`${...}` prints the primary value of an implicit `PROGN` with `PRINC`. `@{...}`
requires a proper, non-circular list and prints its elements separated by the
dynamically bound `SL:*LIST-DELIMITER*` (initially one space). The delimiter
value is read once, before the first element of each `@{...}` interpolation is
printed, and the same value is used throughout that interpolation.

```lisp
(let ((name "Ada")) #?"Hello, ${name}!")          ; → "Hello, Ada!"
(let ((sl:*list-delimiter* ", "))
  #?"Items: @{(list 1 2 3)}")                     ; → "Items: 1, 2, 3"
#?"line 1\nline 2; \$ and \@ are literal"          ; → a two-line string
```

Escapes are `\$`, `\@`, `\\`, `\"`, `\n`, `\t`, and `\r`. An interpolation-free
template is read as a string directly. See
[`#?"..."`](../spec/chapter-03-reader-syntax.md#33-dispatch-macros).

## 3. Sources and lazy sequences

A lazy sequence is `NIL` or an `SL:LAZY-SEQ` node. A node is forced only as far
as demanded; successful forcing caches the same element and rest. Failure caches
nothing, so forcing may be retried. Forcing one node does not force its tail.
Do not modify a source collection while an operation may still read it, including
through an unforced lazy result.

| Constructor | Signature | Use |
|---|---|---|
| `RANGE` | `(&key start end step)` | Arithmetic progression; defaults `0`, `NIL`, `1`; end is exclusive. |
| `REPEATEDLY` | `(function &key count)` | Invoke a zero-argument function when each element is demanded. |
| `ITERATE` | `(function initial)` | Emit initial, then deferred recurrent applications. |
| `CYCLE` | `(source)` | Repeat one captured traversal view and element identities. |

```lisp
(sl:seq-into 'list (sl:range :start 2 :end 10 :step 3)) ; → (2 5 8)
(sl:seq-into 'list (sl:repeatedly (lambda () :x) :count 3)) ; → (:X :X :X)
(sl:seq-into 'list (sl:seq-take 4 (sl:iterate #'1+ 0))) ; → (0 1 2 3)
(sl:seq-into 'list (sl:seq-take 5 (sl:cycle '(a b))))   ; → (A B A B A)
```

`RANGE` is unbounded without `:END`; `REPEATEDLY` is unbounded without
`:COUNT`; `ITERATE` is always unbounded; `CYCLE` is unbounded for a nonempty
view. Repeated floating-point addition can stagnate before reaching a nominal
bound, making a ranged source fail to terminate. See
[§5.1.2](../spec/chapter-05-sources.md#512-bounded-and-unbounded-sources).

Build nodes directly with `(SL:LAZY-SEQ form)`, `(SL:MAKE-LAZY-SEQ thunk)`, or
`(SL:LAZY-CONS element rest)`. The first two defer work; `LAZY-CONS` evaluates
both arguments normally and requires its rest to be `NIL` or a lazy node. A
thunk must be a function object (not merely a symbol designator) and must return
exactly one value: `NIL` or an `SL:LAZY-SEQ` node.

```lisp
(labels ((from (n)
           (sl:lazy-cons n (sl:lazy-seq (from (1+ n))))))
  (sl:seq-into 'list (sl:seq-take 3 (from 7))))         ; → (7 8 9)
(sl:lazy-seq-p nil)                                      ; → true, without forcing
```

See [lazy construction and failure](../spec/chapter-04-lazy-sequences.md#414-lazy-sequence-construction-and-failure).

## 4. Collection mental model

A **seqable** has elements and supports `SEQABLEP`, `SEQ-EMPTYP`, `SEQ-FIRST`,
`SEQ-REST`, `SEQ-REF`, and `SEQ-LENGTH`. Standard seqables include lists,
vectors and strings (through active length), hash tables, lazy sequences,
`SL:DICT`, `SL:ORDERED-DICT`, `SL:PLIST-DICT-VIEW`, and `SL:HASH-SET`.

* Dicts and hash tables traverse as immutable `SL:MAP-ENTRY` objects. Use
  `ENTRY-KEY` and `ENTRY-VALUE`; an entry itself is not seqable.
* `SEQ-REF` is positional. On a finite source, negative indices count from the
  end: `-1` is last and `-L` is first. Negative access must determine length and
  can force a finite lazy source; it signals on known-unbounded input.
* `SEQ-FIRST` and `SEQ-REST` return `NIL` on empty input. For nonempty
  vector input, `SEQ-REST` returns a lazy-sequence view, not a vector.
  `SEQ-REF` accepts an optional default argument that
  supplies a fallback for an out-of-range position; other errors and termination
  constraints still apply.
* `DICT-REF` is keyed. `REF` chooses the dict protocol before the seq protocol.
  Therefore an integer passed to `REF` on an ordered dict is a key, while
  `SEQ-REF` returns the entry at that stored-order position.
* Hash-table, ordinary dict, and hash-set order is unspecified, though one lazy
  view is self-consistent. A view is a lazy sequence over a concrete source whose
  forcing reads that source; each independently created view has its own
  traversal state. Direct `SEQ-FIRST` and `SEQ-REST` calls on an unordered
  source establish independent views. For coherent traversal, use `DOSEQ` or
  `(SEQ-INTO 'LAZY-SEQ source)`, each of which establishes a single view.

```lisp
(sl:entry-value (sl:map-entry :answer 42))       ; → 42
(sl:seq-ref '(a b c) -1)                         ; → C, true
(sl:seq-length #(10 20 30))                      ; → 3
(sl:doseq (((:entry k v) i) (sl:ordered-dict :a 1 :b 2))
  (format t "~d: ~a=~a~%" i k v))
```

`DOSEQ` evaluates its source once, supports every specification Chapter 8
pattern, an optional
zero-based index, `RETURN`, declarations, and `TAGBODY` tags. A two-element list
pattern binds the element and its index, not two destructured components — use
an explicitly indexed nested pattern or destructure inside the body for that.
See
[the seq protocol](../spec/chapter-04-lazy-sequences.md#412-the-seq-protocol).

## 5. Sequence operations

Specification Chapter 6 operations accept any seqable. Matching `:TEST`
arguments default to
`#'SL:EQUALS`; sorting instead defaults to `#'SL:LT`. `:KEY NIL` means identity.
Selected regions use `:START 0`, end-of-source `:END`, unlimited `:COUNT`, and
forward traversal unless `:FROM-END T`. Multi-source operations traverse in
lockstep and stop at the shortest source where applicable.

### 5.1 Mapping, selection, and substitution

| Operation | Signature | Intent |
|---|---|---|
| `SEQ-MAP` | `(fn source &rest more-sources)` | Map lockstep; no keyword arguments. |
| `SEQ-MAP-INDEXED` | `(fn source)` | Call with `(index element)`. |
| `SEQ-MAPCAT` | `(fn source)` | Map one source, then concatenate returned seqables. |
| `SEQ-KEEP` | `(fn source)` | Map and discard `NIL` callback results. |
| `SEQ-FILTER` | `(predicate source &key from-end start end key count)` | Retain matches. |
| `SEQ-REMOVE` | `(item source &key test key start end from-end count)` | Drop equal elements. |
| `SEQ-REMOVE-IF` | `(predicate source &key key start end from-end count)` | Drop predicate-true elements. |
| `SEQ-SUBSTITUTE` | `(new old source &key test key start end from-end count)` | Replace equal elements. |
| `SEQ-SUBSTITUTE-IF` | `(new predicate source &key key start end from-end count)` | Replace predicate-true elements. |

```lisp
(sl:seq-map #'+ '(1 2) '(10 20 30))                    ; → (11 22)
(sl:seq-map-indexed #'cons '(a b))                      ; → ((0 . A) (1 . B))
(sl:seq-mapcat (lambda (x) (list x x)) '(1 2))         ; → (1 1 2 2)
(sl:seq-keep #'identity '(1 nil 2))                     ; → (1 2)
(sl:seq-filter #'evenp '(1 2 3 4))                     ; → (2 4)
(sl:seq-substitute :x 2 '(1 2 3))                      ; → (1 :X 3)
```

`SEQ-FILTER` omits elements outside its selected region (`:START`/`:END`);
`SEQ-REMOVE` and `SEQ-REMOVE-IF` retain elements outside their selected region.

### 5.2 Taking and dropping

| Operation | Signature | Intent |
|---|---|---|
| `SEQ-TAKE`, `SEQ-DROP` | `(n source)` | Keep or skip the first `n`. |
| `SEQ-TAKE-WHILE`, `SEQ-DROP-WHILE` | `(predicate source)` | Split around the initial true run. |
| `SEQ-TAKE-LAST` | `(n source)` | Keep the final `n`; forces the source. |
| `SEQ-DROP-LAST` | `(n source)` | Delay output by `n`; lazy for lazy-seq sources; eager (fresh same-type result) for string and vector inputs. |
| `SEQ-TAKE-NTH` | `(n source)` | Positions `0, n, 2n, ...`. |
| `SEQ-SUBSEQ` | `(source start &optional end)` | Half-open positional interval `[start,end)`. |

```lisp
(sl:seq-take 2 '(1 2 3))                               ; → (1 2)
(sl:seq-drop-while #'plusp '(2 1 0 3))                 ; → (0 3)
(sl:seq-into 'list (sl:seq-drop-last 2 '(1 2 3 4)))    ; → (1 2)
(sl:seq-take-nth 2 '(a b c d e))                       ; → (A C E)
(sl:seq-subseq #(a b c d) 1 3)                         ; → #(B C)
```

### 5.3 Splitting and partitioning

| Operation | Signature | Intent |
|---|---|---|
| `SEQ-SPLIT` | `(source &key delimiter predicate test)` | Split after each element for which the predicate is true, omitting that element; delimiters may be scalar objects or sequences. |
| `SEQ-SPLIT-AT` | `(n source)` | One two-element sequence: prefix and remainder. |
| `SEQ-SPLIT-WITH` | `(predicate source)` | One two-element sequence: true prefix and remainder. |
| `SEQ-PARTITION` | `(n source &key step pad)` | Fixed-size windows; step defaults to `n`. |
| `SEQ-PARTITION-BY` | `(key-function source &key test)` | Maximal adjacent equal-key runs. |

`SEQ-SPLIT` requires exactly one of `:DELIMITER` and `:PREDICATE`; `:TEST`
belongs only to delimiter mode. `SEQ-SPLIT`, `SEQ-PARTITION`, and
`SEQ-PARTITION-BY` return outer lazy sequences. `SEQ-SPLIT-AT` and
`SEQ-SPLIT-WITH` return a concrete pair (list or general vector) for list,
vector, or string input and a lazy pair for other inputs. Forced inner pieces
are reconstructed per the type-preservation and promotion rules in
[§12](#12-type-preservation-and-promotion). See
[§6.2.4](../spec/chapter-06-sequence-operations.md#624-splitting-and-partitioning)
for details. `SEQ-PARTITION` drops a short final chunk with
`:PAD NIL`, emits it with `T`, or fills from a seqable pad. Once that final short
chunk is handled, no later chunk starts, even when the `:STEP` value would
otherwise schedule one.

```lisp
(sl:seq-split-at 2 '(1 2 3 4))                         ; → ((1 2) (3 4))
(sl:seq-split-with #'evenp '(2 4 1 3))                 ; → ((2 4) (1 3))
(sl:seq-into 'list (sl:seq-partition 3 '(1 2 3 4) :pad t))
; → ((1 2 3) (4))
```

### 5.4 Combining and walking trees

| Operation | Signature | Intent |
|---|---|---|
| `SEQ-CONCATENATE` | `(source &rest more-sources)` | Finish each source before the next. |
| `SEQ-INTERLEAVE` | `(&rest sources)` | One element per source per round; stop at shortest. |
| `SEQ-JOIN` | `(target seqs &key separator)` | Flatten pieces with a separator into an explicit target. |
| `SEQ-TREE-SEQ` | `(branch-fn children-fn tree)` | Lazy depth-first preorder traversal. |

`SEQ-JOIN` skips empty pieces and inserts the separator's elements only
between successive nonempty pieces; no separator is placed before the first
piece or after the last.

```lisp
(sl:seq-concatenate '(1 2) '(3 4))                     ; → (1 2 3 4)
(sl:seq-interleave '(1 2 3) '(a b))                    ; → (1 A 2 B)
(sl:seq-join 'string '("a" "b") :separator ",")       ; → "a,b"
```

### 5.5 Reordering, deduplication, and trimming

`SEQ-REVERSE`, `SEQ-SORT`, `SEQ-STABLE-SORT`, `SEQ-TAKE-LAST`,
`SEQ-TRIM-RIGHT`, and `SEQ-TRIM` force the required complete finite region.

| Operation | Signature | Intent |
|---|---|---|
| `SEQ-REVERSE` | `(source)` | Reverse. |
| `SEQ-SORT`, `SEQ-STABLE-SORT` | `(source &key test key)` | Sort; stable variant preserves ties. |
| `SEQ-DEDUPE` | `(source &key test)` | Collapse adjacent equal runs. |
| `SEQ-REMOVE-DUPLICATES` | `(source &key test key start end from-end)` | Keep one global representative. |
| `SEQ-TRIM-LEFT`, `SEQ-TRIM-RIGHT`, `SEQ-TRIM` | `(source &key predicate)` | Remove matching edge runs; strings use implementation-defined whitespace when `:PREDICATE` is omitted; non-string inputs require a predicate. |

Omitting `:PREDICATE` is allowed only for strings. Supplying
`:PREDICATE NIL` for any source signals `PROGRAM-ERROR`.

`SEQ-REMOVE-DUPLICATES` keeps the first occurrence by default; with `:FROM-END T`, it keeps the last.

```lisp
(sl:seq-reverse '(1 2 3))                              ; → (3 2 1)
(sl:seq-dedupe '(1 1 2 1 3 3))                        ; → (1 2 1 3)
(sl:seq-remove-duplicates '(1 1 2 1 3 3))              ; → (1 2 3)
(sl:seq-trim '(0 1 0) :predicate #'zerop)              ; → (1)
```

### 5.6 Searching, predicates, and scalar results

| Operation | Signature / result |
|---|---|
| `SEQ-LAST` | `(source)` → final element; forces to the end. |
| `SEQ-FIND` | `(item source &key test key start end from-end)` → element or `NIL`. |
| `SEQ-FIND-IF` | `(predicate source &key key start end from-end)` → element or `NIL`. |
| `SEQ-POSITION` | `(item source &key test key start end from-end)` → absolute index or `NIL`. |
| `SEQ-POSITION-IF` | `(predicate source &key key start end from-end)` → absolute index or `NIL`. |
| `SEQ-MEMBER` | `(item source &key test key)` → lazy tail beginning at first match or `NIL`. |
| `SEQ-COUNT` | `(item source &key test key start end from-end)` → count. |
| `SEQ-COUNT-IF` | `(predicate source &key key start end from-end)` → count. |
| `SEQ-SEARCH` | `(pattern source &key test key start1 end1 start2 end2 from-end)` → source index or `NIL`. |
| `SEQ-MISMATCH` | `(source1 source2 &key test key start1 end1 start2 end2 from-end)` → index in source1 or `NIL`. |
| `SEQ-EVERY`, `SEQ-SOME`, `SEQ-NOTEVERY`, `SEQ-NOTANY` | `(predicate source &rest more-sources)` → lockstep predicate result. |
| `SEQ-REDUCE` | `(fn source &key key start end from-end initial-value)` → accumulator. |
| `SEQ-REDUCTIONS` | `(fn source &key initial-value)` → all running accumulators. |
| `SEQ-MIN`, `SEQ-MAX` | `(source &key key default)` → extremum or supplied default. |

```lisp
(sl:seq-position 3 '(1 3 5))                           ; → 1
(sl:seq-into 'list (sl:seq-member 2 '(1 2 3)))          ; → (2 3)
(sl:seq-search "bc" "abcd")                            ; → 1
(sl:seq-some #'identity '(nil 4))                      ; → 4
(sl:seq-reduce #'+ '(1 2 3) :initial-value 0)          ; → 6
(sl:seq-reductions #'+ '(1 2 3))                       ; → (1 3 6)
(sl:seq-min '() :default :none)                        ; → :NONE
```

An omitted `:INITIAL-VALUE` is distinct from a supplied `NIL`; `SEQ-REDUCE` on
an empty source without one signals. `SEQ-REDUCTIONS` on empty unseeded input
emits no states. Short-circuit queries can terminate on an unbounded source when
their answer is found; full counts, extrema, `SEQ-REDUCE`, and from-end searches
require a finite selected region. `SEQ-REDUCTIONS` can consume a finite prefix of
an unbounded lazy source.

### 5.7 `SEQ-INTO`

Options belong inside the target designator, never as trailing arguments. Every
standard target except `LAZY-SEQ` forces the source. `LAZY-SEQ` accepts no
options and wraps one traversal view without forcing.

```lisp
(sl:seq-into 'list #(1 2))                              ; → (1 2)
(sl:seq-into 'vector '(1 2))                            ; → #(1 2)
(sl:seq-into '(vector :element-type fixnum) '(1 2))     ; → specialized #(1 2)
(sl:seq-into 'string '(#\a #\b))                        ; → "ab"
(sl:seq-into '(hash-table :test eq)
             (list (sl:map-entry :a 1)))                ; → EQ hash table
(sl:seq-into 'lazy-seq '(1 2))                          ; → unforced lazy view
(sl:seq-into 'dict (list (sl:map-entry :a 1)))          ; → SL:DICT
(sl:seq-into 'hash-set '(1 1.0 2))                      ; → two-element set
```

Dict and hash-table collectors accept `MAP-ENTRY` objects only; they do not
shape-sniff alists. Use `ALIST-DICT` for alists. See
[`SEQ-INTO`](../spec/chapter-06-sequence-operations.md#slseq-into-generic-function).

## 6. Equality and comparison

`SL:EQUALS` is recursive, structural, and case-sensitive. It descends into
conses, arrays, hash tables, lazy sequences, map entries, Sophie dicts, ordered
dicts, and hash sets. Numbers compare by CL numeric value (1 equals 1.0 under
`SL:EQUALS`), while unsupported types fall back to identity-oriented `EQ`/`EQL`
behavior.
Representations are not generally coerced: compare across representations by
explicitly converting both sides. Empty lazy sequences are the specified
exception: they equal `NIL`; strings can equal rank-one arrays containing the
same characters.

```lisp
(sl:equals '(1 "x") '(1.0 "x"))                        ; → true
(sl:equals "Ada" "ada")                               ; → false
(sl:equals '(1 2) #(1 2))                              ; → false
(sl:equals (sl:seq-into 'list #(1 2)) '(1 2))          ; → true
(sl:equals (sl:ordered-dict :a 1 :b 2)
           (sl:ordered-dict :b 2 :a 1))                ; → false
```

Ordered-dict equality is order-sensitive: two ordered dicts with the same
entries in different order are not `EQUALS`.

`SL:COMPARE` returns `:LESS`, `:GREATER`, `:EQUAL`, or `:UNEQUAL`. Whenever
`EQUALS` is true it returns `:EQUAL`, but the converse need not hold: distinct
non-`NIL` symbols with the same name in different packages compare `:EQUAL`.
Conses, rank-one arrays, and lazy sequences compare lexicographically;
`MAP-ENTRY` compares key then value. Hash tables and Sophie dictionaries have
only equality/incomparability, not ordering.

`SL:LT`, `SL:LTE`, `SL:GT`, and `SL:GTE` interpret `COMPARE`; each signals
`SIMPLE-ERROR` on `:UNEQUAL`. `SL:HASH-CODE` is consistent with `EQUALS` and is
bounded and cycle-safe, but the current specification leaves its exact depth
and element bounds implementation-defined. Defining value-based
`EQUALS` for a user type requires a matching `HASH-CODE` method. Before extending
these protocols, read the [implementation status and limitations](implementation.md#status-and-limitations):
intermediate cons comparisons currently bypass applicable user methods.

Matching operations default to `EQUALS`; `SL:DICT` keys and `SL:HASH-SET`
elements use it. Standard hash tables remain outside this protocol and use their
CL tests. Consequently `1` and `1.0` coalesce in a Sophie dict/set; use an `EQL`
CL hash table when they must remain distinct. See
[Chapter 7](../spec/chapter-07-equality-and-comparison.md#71-concepts).

## 7. Binding, destructuring, and threading

### 7.1 Sequential binding and patterns

`SL:BIND` is `LET*`-style: each clause sees earlier bindings. Clause shapes are:

```lisp
(sl:bind ((x 10)                         ; one value
          (q r (floor x 3))              ; successive multiple values
          ((a b &optional c) '(1 2))     ; list pattern
          (#(first second) #(4 5 6))     ; vector pattern via SL:REF
          ((:entry key value) (sl:map-entry :k 9))
          (((name :name) (age :years)) sl:? (sl:dict :name "Ada" :years 36))
          (((slot-a) (b slot-b)) sl:@ object))
  (list x q r a b c first second key value name age slot-a b))
```

A symbol named `_` ignores a binding. List patterns use destructuring-lambda-list
syntax; vector patterns project integer keys using `REF`; `(:ENTRY key value)`
requires a map entry. In `SL:?` and `SL:@` clauses, each access binding is
either a bare variable, which also serves as its own literal key/slot name,
or `(variable literal-key)`. Bare `_` skips access; `(_ key)` performs and
discards it. The object expression is computed once and accesses proceed left
to right.

`SL:FN` is lambda-like and permits patterns in required parameter positions;
optional, rest, keyword, and aux positions remain ordinary. `?` and `@` clauses
are not parameter syntax.

```lisp
(mapcar (sl:fn ((:entry k v)) (list k v))
        (list (sl:map-entry :a 1)))                     ; → ((:A 1))
```

`SL:IF-BIND` and `SL:WHEN-BIND` test each clause's primary value before binding
it and stop at the first false value. `IF-BIND` evaluates its else form with no
clause bindings; `WHEN-BIND` returns `NIL` on failure.

```lisp
(sl:if-bind ((x (find 2 '(1 2 3))) (y (+ x 10))) y :missing) ; → 12
(sl:when-bind (x (find 2 '(1 2 3))) (1+ x))                   ; → 3
```

`SL:FBIND` is labels-style function-namespace binding for function objects
computed eagerly at run time; all names are visible to all expressions and the
body, enabling recursive closures.

### 7.2 Threading and function utilities

| Form | Placement | Choose it when |
|---|---|---|
| `SL:->` | First argument | APIs take data first. |
| `SL:->>` | Last argument | The source is genuinely the final argument (true for many Sophie sequence operations, but not all — `SEQ-SUBSEQ` is source-first, and keyword tails may follow). Use `~>` or `AS->` when placement is not last. |
| `SL:AS->` | Caller-named variable in arbitrary forms | Placement changes or a step uses the value more than once. |
| `SL:~>` | Replaces one direct `SL:<>` argument | A fixed middle argument is clearest. |

```lisp
(sl:-> 3 1+ (* 10))                                    ; → 40
(sl:->> '(1 2 3 4) (sl:seq-filter #'evenp) (sl:seq-reduce #'+)) ; → 6
(sl:as-> 5 x (+ x 1) (* x x))                          ; → 36
(sl:~> '(1 2 3) (sl:seq-subseq sl:<> 1 3))             ; → (2 3)
```

`SL:<>` is the identity-recognized hole only as a direct argument inside `~>`;
outside it, it is an ordinary symbol. `SL:COMPOSE` composes right-to-left and
returns `#'IDENTITY` with no functions. `SL:JUXT` applies every function to the
same arguments and returns a list of primary values.

```lisp
(funcall (sl:compose #'1+ #'length) '(a b))             ; → 3
(funcall (sl:juxt #'min #'max) 3 1 4)                   ; → (1 4)
```

### 7.3 Generic access with `REF`

`(SL:REF object key &optional default)` always returns value and presence. The
facade dispatches to `DICT-REF` first, otherwise `SEQ-REF`. Supplying a default
makes a well-formed missing read total; it does not suppress malformed keys or
non-accessible objects.

`(SETF SL:REF)` writes lists, vectors, strings, and hash tables. It signals on
lazy sequences and immutable `SL:DICT`/`SL:ORDERED-DICT`; use `DICT-SET` for a
persistent update.

```lisp
(sl:ref #(10 20) 1)                                    ; → 20, true
(sl:ref #(10 20) 9 :missing)                           ; → :MISSING, false
(let ((v (vector 1 2))) (setf (sl:ref v 0) 9) v)       ; → #(9 2)
```

See [Chapter 8](../spec/chapter-08-binding.md#81-concepts).

## 8. Dictionaries

Every dict satisfies `DICTP` and is seqable as map entries. `SL:DICT` and
`SL:ORDERED-DICT` are immutable; hash tables are mutable but Sophie functional
updates copy them. Changing a resident key's or element's equality or hash
behavior after insertion is undefined; keys and elements should be immutable or
treated as immutable while stored. Ordinary dict traversal order is unspecified.
Ordered dicts retain stored order: replacing an equivalent key keeps the first
position but uses the latest key/value association; removing and later
reinserting appends.

### 8.1 Construction and conversion

| Operation | Meaning |
|---|---|
| `(DICT key value ...)`, `#d(...)` | `SL:DICT`, `EQUALS`, duplicate keys last-wins. |
| `(ORDERED-DICT key value ...)` | Stored order; first position/latest association wins. |
| `(ALIST-DICT alist)` | Proper list of conses to `SL:DICT`; last-wins. |
| `(PLIST-DICT plist)` | Alternating plist to `SL:DICT`; last-wins. |
| `(PLIST-DICT-VIEW plist)` | No-copy, read-only dict view; `EQ`, first-match; the backing plist must remain unmodified for the lifetime of the view. |
| `(DICT-ALIST dict)` | Fresh list and fresh pair conses. |
| `(DICT-PLIST dict)` | Fresh plist spine. |
| `(DICT-TEST dict)` | `#'SL:EQUALS` for Sophie dicts; CL test symbol for hash tables. |
| `(DICT-SIZE dict)` | Unique logical key count. |

```lisp
(sl:dict-ref (sl:alist-dict '((:a . 1) (:a . 2))) :a) ; → 2, true
(sl:dict-plist (sl:ordered-dict :a 1 :b 2))            ; → (:A 1 :B 2)
(sl:dict-test (sl:dict))                               ; → #'SL:EQUALS
```

### 8.2 Lookup and persistent updates

`DICT-REF` returns `(value, present-p)` and accepts an optional default.
`DICT-MEMBER` reverses those values to `(present-p, value)` and has no default.
`DICT-SET` and `DICT-WITHOUT` are non-destructive; a hash-table input produces a
fresh shallow table with the same test. `(SETF DICT-REF)` mutates only writable
dict types such as hash tables.

```lisp
(sl:dict-ref (sl:dict :a nil) :a)                      ; → NIL, true
(sl:dict-member (sl:dict :a nil) :a)                   ; → true, NIL
(sl:dict-ref (sl:dict) :a :missing)                    ; → :MISSING, false
(sl:dict-ref (sl:dict-set (sl:dict) :a 1) :a)          ; → 1, true
```

`DICT-UPDATE` has signature `(dict key fn &key default)`; the specification
explicitly rules out `:SIGNAL`, so only `:DEFAULT` is accepted.
`DICT-UPDATE-IN` has signature `(dict keys fn &key default)` and has the same
`:DEFAULT` behavior as `DICT-UPDATE`. `DICT-UPDATE` calls `fn` on the current
value or the default and persistently sets the result.

Nested reads and writes differ deliberately. `DICT-REF-IN` returns default and
false at the first missing key and never builds intermediates. `DICT-SET-IN` and
`DICT-UPDATE-IN` build missing intermediate dictionaries of the parent's
eligible type and test (`SL:DICT` as fallback) and rebuild ancestors; a present
non-dict intermediate signals `TYPE-ERROR`. An empty key list signals
`PROGRAM-ERROR`.

```lisp
(sl:dict-ref-in (sl:dict :user (sl:dict :name "Ada")) '(:user :name))
; → "Ada", true
(sl:dict-ref-in (sl:dict) '(:user :name) :missing)      ; → :MISSING, false
(sl:dict-ref-in (sl:dict-set-in (sl:dict) '(:user :name) "Ada")
                '(:user :name))                        ; → "Ada", true
```

### 8.3 Merge, projection, transformation, and aggregation

| Operation | Signature and purpose |
|---|---|
| `DICT-MERGE` | `(dict1 dict2 &key collision)`; binary, `:LAST-WINS` or `:ERROR`. |
| `DICT-MERGE*` | `(dict1 dict2 &rest more)`; left fold, always last-wins. |
| `DICT-MERGE-WITH` | `(combine dict1 dict2)`; combine `(old incoming)` in encounter order. |
| `DICT-KEYS`, `DICT-VALS` | Lazy projections of any seqable of map entries. |
| `DICT-VALUES-MAP` | `(fn dict)`; retain keys, transform values. |
| `DICT-KEYS-MAP` | `(fn dict &key collision)`; retain values, transform keys. |
| `DICT-TRANSFORM` | `(fn dict &key collision)`; callback `(key value)` returns exactly two values. |
| `DICT-SELECT-KEYS`, `DICT-REMOVE-KEYS` | `(dict finite-keys)`; eager batch selection/removal. |
| `DICT-FREQUENCIES` | `(seq)`; element to count. |
| `DICT-GROUP-BY` | `(key-function seq)`; key to source-order list. |
| `DICT-COUNT-BY` | `(key-function seq)`; callback key to count. |
| `DICT-ZIPMAP` | `(keys vals)`; stops at shortest, last key wins. |
| `DICT-REDUCE-KV` | `(fn initial-value dict)`; callback `(acc key value)`. |

```lisp
(sl:dict-ref (sl:dict-merge-with #'+ (sl:dict :a 1) (sl:dict :a 2)) :a)
; → 3, true
(sl:dict-vals (list (sl:map-entry :a 1)))               ; → lazy sequence yielding 1
(sl:dict-ref (sl:dict-values-map #'1+ (sl:dict :a 1)) :a) ; → 2, true
(sl:dict-ref (sl:dict-select-keys (sl:dict :a 1 :b 2) '(:b)) :b) ; → 2, true
(sl:dict-ref (sl:dict-count-by #'evenp '(1 2 3 4)) t)  ; → 2, true
(sl:dict-reduce-kv (lambda (sum k v) (declare (ignore k)) (+ sum v))
                   0 (sl:dict :a 2 :b 3))              ; → 5
```

`DICT-FREQUENCIES`, `DICT-GROUP-BY`, and `DICT-COUNT-BY` always return
`SL:DICT`. `DICT-KEYS` and `DICT-VALS` are lazy projections and always return
lazy sequences, not reconstructed dicts.

Selection, merge, and transform operations reconstruct source types when
eligible — that is, when the source has a non-default `SL:DICT-COLLECT` method.
For single-source operations, the source dict type is preserved when eligible.

For merges and multi-source operations, participating operands must also have
matching dynamic classes and `EQ`-identical test designators; same-test hash
tables preserve the hash-table type. `DICT-MERGE*` applies this rule at each
binary fold step. For non-identical user dict classes, the result type is
implementation-defined; otherwise the fallback is `SL:DICT`. Requested-key
order does not determine selection result order. See specification
[§9.1.12](../spec/chapter-09-dictionaries.md#9112-type-preservation-for-dict-operations).

### 8.4 `DICT-COLLECT` and sequence operations on dicts

`(DICT-COLLECT source entries &key test)` is the eager, entry-only reconstruction
primitive. It dispatches on the source prototype and is the opt-in used for
user-dict preservation. Duplicate keys are last-wins; ordered results keep the
first position. Do not pass alist conses.

Sequence operations treat a dict as entries. Selection operations can preserve
the built-in dict type; order-producing or entry-changing operations can promote
a built-in dict/hash table to `SL:ORDERED-DICT`. The exact rosters are in §12.

## 9. Hash sets

`(SL:HASH-SET &rest elements)`, `#u(...)`, and `SEQ-INTO 'HASH-SET` construct
immutable, unordered sets using `EQUALS` and `HASH-CODE`. `HASH-SET-P` tests the
type. Traversal yields elements in unspecified order. Changing a resident key's
or element's equality or hash behavior after insertion is undefined; keys and
elements should be immutable or treated as immutable while stored.

| Operation | Meaning |
|---|---|
| `SET-MEMBER` | Boolean membership in any seqable under `EQUALS`. |
| `SET-ADD`, `SET-REMOVE` | `(item sequence)`; persistent single-element change, always a hash-set result. |
| `SET-UNION`, `SET-INTERSECTION`, `SET-MINUS` | Eager, two-or-more seqable operands; hash-set result. |
| `SET-SUBSET-P` | Whether every distinct first-operand element occurs in the second. |
| `SET-SIZE` | Number of distinct elements in any seqable. |

```lisp
(sl:set-member 1.0 (sl:hash-set 1))                    ; → true
(sl:set-size '(1 1 1 1))                               ; → 1
(sl:seq-length '(1 1 1 1))                             ; → 4
(sl:set-subset-p '(1 2) '(2 3 1))                      ; → true
```

A dict operand contributes map-entry elements, not keys; use `DICT-KEYS` when
key set semantics are intended. Set equality is mathematical (order-insensitive),
comparison is `:EQUAL` or `:UNEQUAL`, and hashing is order-independent. See
[§9.1.11](../spec/chapter-09-dictionaries.md#9111-sets).

## 10. Collectors and extension

For `EQUALS`/`HASH-CODE` extensions, see
[implementation status and limitations](implementation.md#status-and-limitations)
for the intermediate cons-comparison dispatch exception.

The collector lifecycle is:

1. `(MAKE-COLLECTOR-FOR target &rest options)` creates mutable state.
2. `(COLLECTOR-ACCUMULATE collector element)` adds one element and returns the
   same collector.
3. `(COLLECTOR-RESULT collector)` finalizes and caches one result; repeated calls
   return the same object under `EQ`.

A refused element signals and contributes nothing; earlier successes remain and
finalization is still defined. Accumulating after finalization has undefined
consequences. See
[§4.1.6](../spec/chapter-04-lazy-sequences.md#416-the-collector-protocol).

To make a user type seqable, define applicable methods for `SEQABLEP` (return
true), `SEQ-EMPTYP`, `SEQ-FIRST`, and `SEQ-REST`. `SEQ-REF` is optional for
direct indexing, and `SEQ-LENGTH` is optional when more direct than traversal
but required for dict types. A mutable type may independently define
`(SETF SEQ-REF)`.

To make a user type an explicit `SEQ-INTO` target, define an
`MAKE-COLLECTOR-FOR` method specialized with `EQL` on its class object and
collector-state methods for `COLLECTOR-ACCUMULATE` and `COLLECTOR-RESULT`. To
participate in type-preserving reconstruction, define a non-default primary
`MAKE-COLLECTOR-FOR` method specialized on the source class. These are two
operation paths using ordinary CLOS dispatch: class-object target versus source
instance.

For a user dict, required primitives are `DICTP`, `DICT-REF`, `DICT-TEST`,
`DICT-SIZE`, and the seq protocol (including non-traversing `SEQ-LENGTH`, with
traversal yielding unique `MAP-ENTRY`s consistent with lookup). `DICT-SET`,
`DICT-WITHOUT`, and `DICT-COLLECT` are optional capabilities; declining an
optional write signals `PROGRAM-ERROR`, while `DICT-COLLECT` opts into
preservation for derived dict operations. Follow the exact laws in
[§9.1.4](../spec/chapter-09-dictionaries.md#914-the-extension-protocol).

The specification Chapter 4 protocol surfaces are open: user types participate
through additional protocol methods, but enumerated specializer tuples cannot
be redefined, and additional methods cannot alter standardized-call behavior
(see [§1.4.4](../spec/chapter-01-introduction.md#144-conforming-extensions)).
The specification Chapter 6 `SEQ-*` operation methods are closed: do not
specialize them; participate through the seq and collector protocols. Do not
subclass sealed `LAZY-SEQ`, `MAP-ENTRY`, `SL:DICT`,
or `SL:ORDERED-DICT` abstractions. Use the supplied constructors and
conversion operations, not direct `MAKE-INSTANCE`; direct construction or
subclassing of these types has undefined consequences.

## 11. Decision tables

| I want to… | Use | Important caveat |
|---|---|---|
| Deduplicate adjacent runs | `SEQ-DEDUPE` | Only neighbors collapse. |
| Deduplicate globally | `SEQ-REMOVE-DUPLICATES` | Must establish global representatives. |
| Map and discard `NIL` results | `SEQ-KEEP` | Tests callback results, not source elements. |
| Retain / drop predicate matches | `SEQ-FILTER` / `SEQ-REMOVE-IF` | Both preserve selected elements. |
| Reduce / emit running folds | `SEQ-REDUCE` / `SEQ-REDUCTIONS` | Initial-value supply is significant. |
| Access by position / key | `SEQ-REF` / `DICT-REF` | `REF` is dict-first. |
| Merge two / many / combine | `DICT-MERGE` / `DICT-MERGE*` / `DICT-MERGE-WITH` | Only binary merge has `:COLLISION`. |
| Count elements / computed keys | `DICT-FREQUENCIES` / `DICT-COUNT-BY` | Both return `SL:DICT`. |
| Group globally / adjacent runs | `DICT-GROUP-BY` / `SEQ-PARTITION-BY` | Different grouping domains. |
| Build dict from entries / alist | `SEQ-INTO 'DICT` / `ALIST-DICT` | Entry collectors do not sniff cons shapes. |
| Mutate state / persistently update | CL hash table / `DICT-SET` | Sophie dicts are immutable. |
| Iterate once coherently | `DOSEQ` | Especially useful for unordered sources. |
| Ensure a concrete boundary type | `SEQ-INTO` | Materialize once at the boundary. |

### 11.1 Dict merge result types

For dict merge result types, see [§8.3](#83-merge-projection-transformation-and-aggregation).

## 12. Type preservation and promotion

| Source / operation | Result and timing |
|---|---|
| List, vector, string; transforming operation | Eager same kind; string widens to general vector for noncharacters. |
| Vector; element-changing operation | Eager general vector for `SEQ-MAP`, `SEQ-MAP-INDEXED`, `SEQ-KEEP`, substitutions, `SEQ-MAPCAT`, `SEQ-REDUCTIONS`. |
| Lazy sequence | Normally lazy sequence. |
| Dict/hash table; selection roster | Same built-in dict type, eager: `SEQ-FILTER`, `SEQ-REMOVE`, `SEQ-REMOVE-IF`, `SEQ-TAKE`, `SEQ-DROP`, `SEQ-TAKE-WHILE`, `SEQ-DROP-WHILE`, `SEQ-SUBSEQ`, `SEQ-TAKE-NTH`, `SEQ-TAKE-LAST`, `SEQ-REMOVE-DUPLICATES`, `SEQ-DEDUPE`, `SEQ-TRIM-LEFT`, `SEQ-TRIM-RIGHT`, `SEQ-TRIM`. |
| Dict/hash table; promotion roster | `SL:ORDERED-DICT`: `SEQ-SORT`, `SEQ-STABLE-SORT`, `SEQ-REVERSE`, `SEQ-MAP`, `SEQ-MAP-INDEXED`, `SEQ-KEEP`, `SEQ-MAPCAT`, `SEQ-SUBSTITUTE`, `SEQ-SUBSTITUTE-IF`, `SEQ-REDUCTIONS`, `SEQ-CONCATENATE`, `SEQ-INTERLEAVE`, multi-source `SEQ-MAP`, `SEQ-SPLIT`, `SEQ-SPLIT-AT`, `SEQ-SPLIT-WITH`, `SEQ-PARTITION`, `SEQ-PARTITION-BY`. The five nested operations have lazy outer results and ordered-dict pieces. |
| Dict/hash table; `SEQ-DROP-LAST`, `SEQ-TREE-SEQ`, `SEQ-MEMBER` | Lazy behavior, not promotion. |
| Multi-source promotion | Only when every source is a built-in dictionary; otherwise lazy sequence. |
| `SL:HASH-SET` | Element-dropping operations return hash-set; changing, forcing, multi-source, and nested operations return lazy sequences. |
| `SEQ-INTO`, `SEQ-JOIN` | Explicit target controls type. |

This is the exact built-in roster from
[§6.1.1](../spec/chapter-06-sequence-operations.md#611-type-preserving-returns).
It excludes user dicts and `PLIST-DICT-VIEW`. Promoted entry-transforming
operations must emit `MAP-ENTRY`s. Promotion normalizes keys under `EQUALS`, so
an identity-test hash table can coalesce keys. For unordered input, resulting
stored order remains based on an unspecified traversal.

Materialize once at the API boundary that requires a concrete type rather than
after every operation. Keep intermediate seqables while the next Sophie
operation accepts them.

## 13. Recipes

These assertion-style recipes require only `(asdf:load-system "sophie-lisp")`.

```lisp
(assert (equal (sl:seq-dedupe '(1 1 2 1 3 3)) '(1 2 1 3)))
(assert (equal (sl:seq-remove-duplicates '(1 1 2 1 3 3)) '(1 2 3)))

(assert (= (sl:seq-reduce #'+ (sl:seq-filter #'identity '(0 nil 2 3))
                          :initial-value 0)
           5))

(let ((answer (sl:seq-map #'identity
                          (make-array 2 :element-type 'fixnum
                                      :initial-contents '(1 2)))))
  (assert (equalp answer #(1 2)))
  (assert (equal (array-element-type answer) t)))

(multiple-value-bind (value present)
    (sl:dict-ref (sl:dict-merge-with #'- (sl:dict :a 10) (sl:dict :a 3)) :a)
  (assert (and present (= value 7))))

(multiple-value-bind (value present) (sl:seq-ref '(a b c) -1)
  (assert (and present (eq value 'c))))
(multiple-value-bind (value present) (sl:seq-ref '(a b c) -3)
  (assert (and present (eq value 'a))))

(assert (equal (sl:seq-into 'list (sl:seq-partition 3 '(1 2 3 4) :pad t))
               '((1 2 3) (4))))

(assert (sl:ordered-dict-p
         (sl:seq-sort (sl:dict :b 2 :a 1) :key #'sl:entry-value)))

(multiple-value-bind (present value) (sl:dict-member (sl:dict :a nil) :a)
  (assert (and present (null value))))
```

For unordered input, retain one view:

```lisp
(let ((view (sl:seq-into 'lazy-seq (sl:dict :a 1 :b 2))))
  (assert (equal (sl:seq-into 'list view)
                 (sl:seq-into 'list view))))
```

### 13.1 Porting shortcuts

```lisp
(sl:dict-values-map #'summarize-group groups)           ; replace only values
(sl:seq-split text :predicate
              (lambda (ch) (not (alphanumericp ch))))  ; tokenize directly
(sl:dict-ref d key 0)                                   ; fallback only
(multiple-value-bind (value present) (sl:dict-ref d key)
  (when present (use value)))                           ; distinguish absence
(sl:doseq ((:entry key value) config) (emit key value)) ; traverse entries
(sl:seq-reduce #'+ (sl:dict-vals d) :initial-value 0)  ; reduce values
(sl:seq-sort d :key #'sl:entry-key)                    ; ordered dict by key
(sl:seq-filter (lambda (e) (wanted-p (sl:entry-key e))) ordered)
```

### 13.2 Small but useful operations

* Use `RANGE` for arithmetic progression, `ITERATE` for state transitions,
  `REPEATEDLY` for generators, and `CYCLE` for repeating a view.
* `SEQ-MIN` and `SEQ-MAX` signal on empty input unless `:DEFAULT` is supplied.
* `DICT-REDUCE-KV` takes `(fn initial-value dict)`, not dict first.
* `DICT-KEYS` and `DICT-VALS` accept any seqable of map entries.
* `DICT-WITHOUT` is persistent; a supporting hash table is copied even for an
  absent key, while persistent identity is unspecified.
* `SEQ-TAKE-NTH` selects `0,n,2n,...`; `SEQ-SUBSEQ` is half-open.

### 13.3 Equality and key normalization

A CL hash table retains its own test, while `SL:ORDERED-DICT` always uses
`SL:EQUALS`:

```lisp
(let* ((a (copy-seq "id"))
       (b (copy-seq "id"))
       (identity (make-hash-table :test #'eq)))
  (setf (gethash a identity) :first
        (gethash b identity) :second)
  (assert (= (hash-table-count identity) 2))
  ;; Intentional normalization; equal strings coalesce, last association wins.
  (assert (= (sl:dict-size (sl:seq-into 'sl:ordered-dict identity)) 1)))
```

Keep the `EQ` table or introduce identity-bearing keys if coalescing is not
wanted; otherwise normalize once and document the policy.

## 14. Common Lisp idioms

| CL idiom | Sophie equivalent | Difference |
|---|---|---|
| `(mapcar fn xs)` | `SEQ-MAP` | Generalizes to seqables and multiple lockstep sources. |
| `(reduce fn xs)` | `SEQ-REDUCE` | Generic seqable, region, direction, key, supplied initial value. |
| `(remove-if-not p xs)` | `SEQ-FILTER` | Retains predicate-true elements. |
| `(remove-duplicates xs)` | `SEQ-REMOVE-DUPLICATES` | Use `SEQ-DEDUPE` for adjacent runs. |
| `(elt xs i)` | `SEQ-REF` | Two values and finite negative indices. |
| `(length xs)` | `SEQ-LENGTH` | May return `NIL` for known-unbounded input. |
| `(gethash key table)` | `DICT-REF` / `REF` | Generic keyed access with value and presence. |
| `(setf (gethash key table) value)` | `(setf (REF table key) value)` | Also handles mutable sequences; Sophie dicts remain immutable. |
| `maphash` accumulation | `DICT-REDUCE-KV` or `DOSEQ` | Explicit scalar fold or direct iteration. |
| custom hash merge | `DICT-MERGE-WITH` | Ordered `(old incoming)` conflict fold. |
| map hash values / rename keys | `DICT-VALUES-MAP` / `DICT-KEYS-MAP` | Non-destructive reconstruction. |
| select/remhash many keys | `DICT-SELECT-KEYS` / `DICT-REMOVE-KEYS` | Eager batch operations. |
| frequency loop | `DICT-FREQUENCIES` / `DICT-COUNT-BY` | Count elements directly or computed keys. |
| set union/intersection/difference | `SET-UNION` / `SET-INTERSECTION` / `SET-MINUS` | Persistent `SL:HASH-SET`, `EQUALS`. |
| `loop for x across/in ...` | `DOSEQ` | One protocol for all seqables, patterns, optional index. |
| nested call pipeline | `->`, `->>`, `AS->`, `~>` | Syntactic placement choices. |

## 15. What Sophie does NOT have

| Not provided | Use instead |
|---|---|
| An `SL:FORMAT` wrapper | `CL:FORMAT` directly. |
| Multi-source `SEQ-MAPCAT` | `SEQ-MAP` over sources, then single-source `SEQ-MAPCAT`/flattening. |
| Mutable `SL:DICT` or `SL:ORDERED-DICT` | A CL hash table for mutable state, or rebind persistent update results. |
| Positional mutation of lazy or Sophie persistent sequences | A CL vector/list/string, or rebuild with `SEQ-INTO` and sequence operations. |
| Case-insensitive `EQUALS` mode | A CL hash table with `EQUALP`, or supply an explicit test where accepted. |
| Sophie replacements for `LET`, `LET*`, `DESTRUCTURING-BIND` | Their unchanged CL forms; use `BIND` when Sophie patterns help. |
| Automatic alist/plist shape inference | `ALIST-DICT`, `PLIST-DICT`, or `PLIST-DICT-VIEW` explicitly. |

## 16. Quick reference

This extension export index is reconciled with `src/packages.lisp`; CL symbols
re-exported by `SL` are intentionally omitted. Readtable-management names are
provided by `NAMED-READTABLES`, not exported here.

| Area | Symbols |
|---|---|
| Reader values | `*LIST-DELIMITER*` |
| Readtable name | `SL-CORE-SYNTAX` |
| Lazy/source | `LAZY-SEQ`, `LAZY-SEQ-P`, `MAKE-LAZY-SEQ`, `LAZY-CONS`, `RANGE`, `REPEATEDLY`, `ITERATE`, `CYCLE` |
| Sequence protocol | `SEQABLEP`, `SEQ-EMPTYP`, `SEQ-FIRST`, `SEQ-REST`, `SEQ-REF`, `SEQ-LENGTH`, `REF`, `DOSEQ`, `MAP-ENTRY`, `ENTRY-KEY`, `ENTRY-VALUE` |
| Sequence operations | `SEQ-CONCATENATE`, `SEQ-COUNT`, `SEQ-COUNT-IF`, `SEQ-DEDUPE`, `SEQ-DROP`, `SEQ-DROP-LAST`, `SEQ-DROP-WHILE`, `SEQ-EVERY`, `SEQ-FILTER`, `SEQ-FIND`, `SEQ-FIND-IF`, `SEQ-INTERLEAVE`, `SEQ-INTO`, `SEQ-JOIN`, `SEQ-KEEP`, `SEQ-LAST`, `SEQ-MAP`, `SEQ-MAP-INDEXED`, `SEQ-MAPCAT`, `SEQ-MAX`, `SEQ-MEMBER`, `SEQ-MIN`, `SEQ-MISMATCH`, `SEQ-NOTANY`, `SEQ-NOTEVERY`, `SEQ-PARTITION`, `SEQ-PARTITION-BY`, `SEQ-POSITION`, `SEQ-POSITION-IF`, `SEQ-REDUCE`, `SEQ-REDUCTIONS`, `SEQ-REMOVE`, `SEQ-REMOVE-DUPLICATES`, `SEQ-REMOVE-IF`, `SEQ-REVERSE`, `SEQ-SEARCH`, `SEQ-SOME`, `SEQ-SORT`, `SEQ-SPLIT`, `SEQ-SPLIT-AT`, `SEQ-SPLIT-WITH`, `SEQ-STABLE-SORT`, `SEQ-SUBSEQ`, `SEQ-SUBSTITUTE`, `SEQ-SUBSTITUTE-IF`, `SEQ-TAKE`, `SEQ-TAKE-LAST`, `SEQ-TAKE-NTH`, `SEQ-TAKE-WHILE`, `SEQ-TREE-SEQ`, `SEQ-TRIM`, `SEQ-TRIM-LEFT`, `SEQ-TRIM-RIGHT` |
| Dicts | `DICT`, `DICTP`, `ORDERED-DICT`, `ORDERED-DICT-P`, `DICT-REF`, `DICT-REF-IN`, `DICT-SET`, `DICT-SET-IN`, `DICT-UPDATE`, `DICT-UPDATE-IN`, `DICT-WITHOUT`, `DICT-MEMBER`, `DICT-SIZE`, `DICT-TEST`, `DICT-COLLECT`, `DICT-MERGE`, `DICT-MERGE*`, `DICT-MERGE-WITH`, `DICT-TRANSFORM`, `DICT-VALUES-MAP`, `DICT-KEYS-MAP`, `DICT-SELECT-KEYS`, `DICT-REMOVE-KEYS`, `DICT-COUNT-BY`, `DICT-REDUCE-KV`, `DICT-KEYS`, `DICT-VALS`, `DICT-FREQUENCIES`, `DICT-GROUP-BY`, `DICT-ZIPMAP`, `ALIST-DICT`, `PLIST-DICT`, `PLIST-DICT-VIEW`, `DICT-ALIST`, `DICT-PLIST` |
| Sets | `HASH-SET`, `HASH-SET-P`, `SET-ADD`, `SET-INTERSECTION`, `SET-MEMBER`, `SET-MINUS`, `SET-REMOVE`, `SET-SIZE`, `SET-SUBSET-P`, `SET-UNION` |
| Equality | `EQUALS`, `COMPARE`, `HASH-CODE`, `LT`, `LTE`, `GT`, `GTE` |
| Binding/utilities | `BIND`, `FN`, `IF-BIND`, `WHEN-BIND`, `FBIND`, `JUXT`, `COMPOSE`, `OP`, `->`, `->>`, `AS->`, `~>`, `<>`, `?`, `@` |
| Collector protocol | `MAKE-COLLECTOR-FOR`, `COLLECTOR-ACCUMULATE`, `COLLECTOR-RESULT` |

For exact signatures and conditions, use the linked specification chapters—this
guide is an operational map, not a duplicate specification.
