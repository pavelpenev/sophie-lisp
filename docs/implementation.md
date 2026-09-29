# Implementation status and limitations

Sophie Lisp 1.0.0 is the current system version. This repository includes a
reference implementation developed and tested on Linux with SBCL 2.6.8.roswell,
CCL 1.13, and ECL 26.5.5. See the [portability notes](portability.md) for the
host matrix, the portable dependency set, and per-host behavioral notes.

For test prerequisites and the ASDF test command, see [README: Test](../README.md#test).
These tests characterize and exercise the current implementation; they do not
prove conformance or establish behavior on untested hosts, every representation,
or every performance property.

## Status and limitations

- Identity-hash allocation is guarded by a `bordeaux-threads` lock around the
  shared weak-key table and token counter (`src/core/support.lisp`). Structural
  hashing's memoization table is dynamically bound per `SL:HASH-CODE` invocation
  (`src/containers/trie.lisp`); these mechanisms do not provide a general
  thread-safety guarantee for containers, mutable values, or callbacks.
- Hash mixer selection and some hash seeds are established at load time. The
  `*narrow-hash-discipline-hosts*` seam installs the narrow discipline when
  `trie.lisp` loads; populated trie leaves retain their old hash values. Start
  a fresh image after changing hosts or selecting a different hash discipline,
  especially when containers are populated. Reloading `support.lisp` alone on
  SBCL restores the wide mixer function cell until `trie.lisp` is reloaded;
  avoid that mixed image. See
  [remaining portability caveats](portability.md#remaining-caveats).
- **Known specification tension (pending clarification):** The explicit
  cons-chain loops in `SL:EQUALS` and `SL:COMPARE` bypass generic dispatch for
  intermediate cons-cons tail pairs. An `eql`-specialized user method on such a
  pair may therefore be skipped. This is a disclosed deviation from the letter
  of [Chapter 7 §7.1.5](../spec/chapter-07-equality-and-comparison.md#715-performance),
  which requires user-defined methods to still take effect; the specification
  has not been amended. See [known specification tension](portability.md#known-specification-tension)
  for the implementation rationale, distinct from conforming tradeoffs.

## Sealed representations

The specification's sealing requirement is program-facing: programs must not
subclass or directly construct the sealed abstractions; it does not require the
implementation to reject every such attempt. On SBCL, the host's
structure-class rules reject subclassing `SL:LAZY-SEQ` and `SL:MAP-ENTRY`. A
direct `MAKE-INSTANCE` of either type nevertheless succeeds and produces a
lazy node with a `NIL` thunk or a map entry with `NIL` fields. This is a
current SBCL characterization, not supported construction behavior or a
cross-host guarantee. Use the supplied constructors `SL:LAZY-SEQ`,
`SL:MAKE-LAZY-SEQ`, `SL:LAZY-CONS`, and `SL:MAP-ENTRY` instead.

## Notable operator behaviors

- The Chapter 6 result policies make specified order-producing operations on
  built-in hash tables and `SL:DICT` return `SL:ORDERED-DICT`. Sorting and
  reversal normalize before reordering; the complete operation roster and
  exceptions are listed in the [user guide](user-guide.md#12-type-preservation-and-promotion).
- `DICT-UPDATE` and `DICT-UPDATE-IN` accept `:DEFAULT` (defaulting to `NIL`),
  not `:SIGNAL`. An absent key or leaf supplies that default to the callback; a
  present value, including `NIL`, is passed unchanged. Nested defaults do not
  replace missing intermediate dictionaries or suppress path-validation
  errors.
- For user sources with reconstruction Collectors, split operations have a
  lazy outer result and reconstruct each piece in the source type from shared
  traversal when that piece is observed. Successful pieces are memoized;
  Collector refusals propagate when the affected piece is forced, without
  fallback reconstruction. Concrete list, vector, and string inputs follow
  their specified concrete result policies.
- Numeric comparison follows Common Lisp numeric order for unequal real
  numbers. `CL:=` yields `:EQUAL`; unequal comparisons involving a complex
  number yield `:UNEQUAL`. Composite comparisons propagate those results under
  their specified lexicographic rules.

## What the reference implementation includes

The reference implementation includes:

- package definitions, sequence protocols, conditions, lazy sequences with
  successful memoization and retry after failed forcing, coherent traversal
  views, callback/range/cycle sources, and structural equality, comparison,
  and hashing;
- persistent `SL:DICT` and `SL:HASH-SET` implementations backed by a 5-bit
  hash trie, hash-table adapters, read-only plist views, collectors,
  conversions, grouping, merging, updates, and set operations;
- `SL:ORDERED-DICT`, using a persistent AVL order tree and persistent key
  index. Equivalent-key replacement retains the first position and installs
  the latest association; removing and reinserting appends. Equality between
  ordered dicts is order-sensitive;
- the `SL-CORE-SYNTAX` readtable, interpolation, function shorthand and
  collection literals, plus binding, destructuring, threading, and `DOSEQ`
  facilities; and
- the sequence operations, reconstruction policies, dictionary protocols,
  and conservative printers described by the specification and user guide.

These representation choices apply to the reference implementation; user-defined
types need not share its storage or performance characteristics. The ASDF test
system registers core, container, sequence, syntax, and integration tests.
Behavioral and structural checks do not establish every asymptotic property or
measure every temporary allocation.

## Implementation details and choices

- Trim operations use the six ASCII whitespace characters with codes 9 through
  13 and 32 when the source is a string and no predicate is supplied. Omitting
  the predicate for a non-string, or supplying it as `NIL`, signals
  `PROGRAM-ERROR`.
- `MALFORMED-PLIST-ERROR` inherits from both `PROGRAM-ERROR` and `TYPE-ERROR`;
  malformed plist inputs can therefore be handled as either condition class.
- Persistent dict and set storage uses a 5-bit hash trie with normalized
  unsigned-64-bit hashes, collision nodes, and path-copying structural sharing.
  On SBCL and CCL, the `*narrow-hash-discipline-hosts*` load-time seam selects
  the narrow discipline: a fixnum-safe limb mixer and 32-bit combining
  discipline. ECL uses the fixnum-width-selected limb mixer with the wide
  (default 64-bit) combining discipline. Fixed sentinel hashes may remain
  64-bit, and user hash methods may return wider values.
- `SL:ORDERED-DICT` combines a persistent AVL order tree with a persistent key
  index. Expected keyed lookup and tree-operation costs also depend on hash and
  equality callbacks, collisions, and integer size; they are not benchmark
  guarantees.
- Structural hashing has a depth-16 bound. Ordered dictionaries hash a
  canonical stored-order prefix of at most 64 associations plus count and
  termination information. They do not cache content hashes, so resident
  mutable values are observed afresh. External `HASH-CODE` and `EQUALS`
  callbacks are outside the provider's recursion bound. Unordered collections
  use a count-preserving commutative fold. Identity hashes use weak keys and
  monotonic tokens; see [status and limitations](#status-and-limitations) for
  the concurrency scope.
- Reader collection literals evaluate their element forms left to right,
  retain primary values, and perform insertion after evaluation completes.
- Traversals use a retained view for coherent iteration. Native hash-table
  views take one snapshot when first demanded.
- Built-in collectors support list, vector, string, and hash-table targets.
  User-defined targets participate through ordinary CLOS methods on target
  class objects or source instances; no alternate dispatch path is provided.
- `SL:SEQ-SUBSEQ` uses a guarded direct-construction fast path for vector
  and string sources that falls back to protocol reconstruction whenever any
  non-standard Collector method is applicable, or a built-in Collector method
  has been removed or redefined. The specification's
  reconstruction clause (Chapter 6, "Reconstruction mechanism") states the
  observable obligations of reconstruction, not the internal mechanism.

## Testing

The ASDF test system registers core, container, sequence, syntax, and
integration tests. For dependencies and the test command, see
[README: Test](../README.md#test).
