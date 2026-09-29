# Appendix C: Glossary

## C.1 Terms

This informative glossary summarizes terms used throughout the Sophie Lisp specification; the cited chapter text is authoritative.

**collection**
: An object whose contents may be traversed as a sequence, including standardized seqable collections and user-defined types that participate through the seq protocol.
See Chapter 4 and Chapter 9.

**Collector**
: Mutable construction state governed by `SL:MAKE-COLLECTOR-FOR`, `SL:COLLECTOR-ACCUMULATE`, and `SL:COLLECTOR-RESULT` that accumulates elements and finalizes a result.
See Chapter 4.

**concrete collection**
: A materialized collection—such as a list, vector, string, `hash-table`, `SL:DICT`, `SL:HASH-SET`, or materialized extension result—whose contents are present rather than deferred, with the standardized `(setf SL:SEQ-REF)` write surface covering lists, vectors, and strings, so concreteness alone does not determine writability.
See Chapter 4 and Chapter 9.

**dict**
: An object that indexes values by key through the Dict Protocol, with `SL:DICT` as the standard persistent immutable map type.
See Chapter 9.

**dict-collect**
: The dict-protocol operation `SL:DICT-COLLECT` that constructs a dict from a seq of `SL:MAP-ENTRY` objects, distinct from the incremental Collector lifecycle.
See Chapter 9.

**dictp**
: The predicate generic function `SL:DICTP`, which returns true for objects that satisfy the Dict Protocol.
See Chapter 9.

**facade dispatch**
: The default `SL:REF` routing that tests `SL:DICTP` first and delegates to `SL:DICT-REF`, otherwise tests `SL:SEQABLEP` and delegates to `SL:SEQ-REF`, while permitting direct `SL:REF` methods.
See Chapter 8 and Chapter 9.

**forcing**
: Demand-triggered evaluation and resolution of a lazy-sequence node's deferred computation.
See Chapter 4 and Chapter 6.

**fresh**
: A result property requiring the top-level container to be newly allocated and
not `EQ` to any input container from which it was derived; elements and
immutable substructure may be shared. `NIL`, an immutable singleton, is exempt.
Applies only to mutable Common Lisp result containers. An eager string or
vector result of `SL:SEQ-DROP-LAST` is fresh even when *n* is zero.
See Chapter 4 and Chapter 6.

**hash-code**
: A non-negative integer returned by `SL:HASH-CODE` such that objects equal under `SL:EQUALS` receive equal hash codes, with identity hashing used by the fallback for standard-objects and
structure-objects.
See Chapter 7.

**hash-set**
: An immutable, persistent set with O(1) expected lookup.
See Chapter 9.

**lazy-seq**
: `NIL` or an `SL:LAZY-SEQ` node that may be unresolved or resolved; an unresolved node has deferred computation that is forced and memoized on first successful access; a failed force caches nothing and may be retried; a resolved node has no deferred computation.
See Chapter 4.

**lazy sequence**
: A lazy-seq: `NIL` or an `SL:LAZY-SEQ` node. See **lazy-seq**.

**persistent**
: A property of immutable data structures where updates produce new versions sharing structure with their ancestors, leaving earlier versions unchanged.
See Chapter 9, Section 9.1.2.

**proper sequence**
: A finite or unbounded sequence whose traversal reaches each element through successive `SL:SEQ-REST` calls without encountering a non-seqable tail. A dotted list is seqable but not a proper sequence.
See Chapter 4, Section 4.1.2.

**standardized call**
: A call whose applicable method specializers are standardized types — types defined by this specification or by ANSI Common Lisp — and whose generic function is enumerated in this specification. A call dispatched to a method whose specializers include a user-defined type is not a standardized call.
See Chapter 1, Section 1.4.4.

**usable function designator**
: A function object or a symbol with a global definition as a function; a macro name and a special-operator name are not usable function designators. Distinct from the broader CLHS function designator, which accepts any symbol.
See Chapter 1, Section 1.3.1.

**view**
: A lazy sequence over a concrete source whose forcing reads that source. Each
independently created view has its own traversal state; successive nodes within
that view continue the same traversal. Already-forced nodes retain their values.
See Chapter 4 and Chapter 6.

**lazy-seq view**
: Alias for **view**. The `SL:PLIST-DICT-VIEW` adapter in Chapter 9 is a
distinct kind of view; see its dictionary entry.

**lockstep**
: Multi-source traversal where each source advances one element per round.
See Chapter 6.

**map-entry**
: An immutable `SL:MAP-ENTRY` object holding a key and value, accessed by `SL:ENTRY-KEY` and `SL:ENTRY-VALUE`, serving as the canonical element of keyed collection traversal and not itself being seqable.
See Chapter 4, Chapter 8, and Chapter 9.

**marker symbol**
: A symbol such as `SL:?`, `SL:@`, or `SL:<>` recognized structurally by a binding or threading form.
See Chapter 8.

**ordered dictionary**
: An `SL:ORDERED-DICT`: a persistent structurally immutable dict whose entry
sequence has stored order. The first key occurrence determines position and
the last equivalent association supplies the key object and value. Equality
compares corresponding entries in order, not an unordered association set.
See Chapter 9, Section 9.1.18.

**ordered reconstruction**
: Strict construction of an ordered dictionary from emitted `SL:MAP-ENTRY`
objects. Duplicate keys collapse without moving their first position; emitted
stream size need not equal resident unique-key count. Actual non-entry output
signals `TYPE-ERROR`; there is no widening or fallback after refusal. Nested
operations reconstruct ordered inner pieces, not an ordered outer container.
See Chapter 4 and Chapter 6, Section 6.1.1.

**readtable**
: An object controlling interpretation by the Lisp reader, including Sophie Lisp's
reader macros supplied by `SL-CORE-SYNTAX`.
See Chapter 3.

**reconstruction**
: The process of collecting transformed elements and rebuilding them in the result type determined by the operation's return-type rules, as the Collector protocol specifies.
See Chapter 4 and Chapter 6.

**selected region**
: The portion of a source selected by its `:START`, `:END`, and `:FROM-END` arguments together with its traversal direction.
See Chapter 6.

**seq protocol**
: The mandatory primitives (`SL:SEQ-FIRST`, `SL:SEQ-REST`, `SL:SEQ-EMPTYP`, and `SL:SEQABLEP`) and supporting primitives (`SL:SEQ-REF` and `SL:SEQ-LENGTH`) that make a type seqable.
See Chapter 4.

**seqable**
: A property of types that implement the seq protocol, testable by `SL:SEQABLEP`.
See Chapter 4.

**Sophie Lisp**
: A conservative, purely additive extension of Common Lisp whose specification supplements ANSI Common Lisp behavior.
See Chapter 1.

**source**
: A seqable object traversed by an operation, which may have multiple sources whose roles are specified by the operation's syntax and description. Chapter 5 defines source constructors that produce lazy sequences.
See Chapter 5 and Chapter 6.

**subject**
: The primary sequence argument of a Chapter 6 generic function, on which
generic dispatch occurs. Rules for additional sources are stated by the
operation's syntax and description.
See Chapter 6.

**target designator**
: An argument naming the conversion target for `SL:SEQ-INTO` or the constructed result target for `SL:SEQ-JOIN`.
See Chapter 4 and Chapter 6.

**type preservation**
: The rule under which type-preserving operations retain list, string, and
vector result types when possible. Vector results retain the source's actual
`ARRAY-ELEMENT-TYPE`. Strings widen to general vectors for non-character
results. Multi-source and explicit-target operations follow their stated
result-type rules. Dictionary and hash-set result types follow the
dictionary preservation and promotion rules in Chapter 6, Section 6.1.1.
See Chapter 6, Section 6.1.1 and Chapter 9.

**widening**
: When result elements do not fit the source representation, the result uses the
nearest accommodating representation. Strings widen to general vectors for
non-character results; `SL:SEQ-PARTITION` widens a specialized vector to a
general vector only when an actual padding element does not fit its source
element type, and only that incompatible chunk widens. Element-changing
operations retain their general-vector behavior; this is compatibility checking,
not callback-result type inference.
See Chapter 6.
