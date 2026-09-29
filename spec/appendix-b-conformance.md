# Appendix B: Conformance

## B.1 Authority and Use

This appendix is informative. It provides a quick-reference checklist for
conformance. Chapter 1 establishes the conformance framework; Chapters 2 through
9 provide the normative requirements; the appendices are informative summaries.
The checklists below summarize requirements and point to the authoritative chapter
material; they do not add requirements.

## B.2 Implementation Checklist

Use the following checklist as an informative summary of the requirements in
Chapter 1 and the chapters identified in each item.

### B.2.1 Packages and Reader

1. Runs on a conforming Common Lisp implementation as defined by ANSI INCITS
   226-1994 (R2004) (Chapter 1).
2. Provides the three packages specified in Chapter 2: SOPHIE-LISP (nickname
   SL), SOPHIE-LISP-EXTENSIONS (nickname SL-EXT), and SL-USER, with the use
   lists and export sets defined there. SOPHIE-LISP re-exports the external
   symbols of COMMON-LISP unchanged, and Sophie-defined symbol names are
   disjoint from the external symbol names of COMMON-LISP.
3. Provides the SL-CORE-SYNTAX readtable with the reader macros specified in
   Chapter 3.
4. Loading Sophie Lisp does not modify existing packages, readtables, or reader
   behavior. Programs using no Sophie extensions retain ANSI behavior.

### B.2.2 Protocols and Defined Names

1. Implements all protocols, generic functions, macros, functions, special
   variables, and other names defined by Chapters 2–9, with the semantics
   specified by their authoritative entries.
2. Implements the lazy-seq and Collector protocols, including their
   dispatchable CLOS generic functions, the construction protocol
   (`SL:LAZY-SEQ`, `SL:MAKE-LAZY-SEQ`, and `SL:LAZY-CONS`), and the
   `SL:SEQABLEP` generic function.
3. Supports user-defined collection participation in the seq protocol:
   a participating type provides applicable methods, directly or by inheritance,
   for `SL:SEQ-FIRST`, `SL:SEQ-REST`, and `SL:SEQ-EMPTYP`; a dict also provides
   an applicable method, directly or by inheritance, for `SL:SEQ-LENGTH`; the
   type supports `SL:SEQ-REF` (using the traversal default unless it is
   overridden); and `SL:SEQABLEP` returns a true value. The authoritative
   protocol material is in Chapter 4.
4. Provides `SL:HASH-CODE` as a generic function returning a non-negative
   integer hash for any object for which a hash is defined. Objects equal under
   `SL:EQUALS` have equal `SL:HASH-CODE` values. Under the fallback policy,
   standard-objects and structure-objects have a per-instance identity hash as
   specified in Chapter 7; the implementation mechanism is
   implementation-defined.
5. Supports the binding contracts in Chapter 8: leading ordinary Common Lisp
   declarations are admitted by `SL:BIND`, `SL:FN`, `SL:DOSEQ`, and
   `SL:WHEN-BIND`, with bound and free declaration scopes as specified there.
   `SL:DOSEQ` retains its implicit `TAGBODY`, tags, `GO`, and `NIL` block.
   `SL:IF-BIND` retains ordinary expression branches and has no declaration slot.
6. For the Chapter 6 vector-preserving operation roster, reconstructs vector
   results with the source's actual `ARRAY-ELEMENT-TYPE`, including empty
   results and inner split/partition pieces. `SL:SEQ-PARTITION` widens only a
   chunk whose actual padding is incompatible; element-changing and
   multi-source operations retain general-vector behavior.
7. `SL:SEQ-DROP-LAST` eagerly reconstructs strings and vectors, preserving the
   vector source's actual `ARRAY-ELEMENT-TYPE`, respecting its active length
   during traversal, and producing a fresh mutable result, including when
   `n=0`. Lists, user-defined collections,
   dictionaries, hash tables, hash sets, and lazy sequences retain the lazy
   lookahead behavior and do not require a finiteness pre-scan.
8. For the Chapter 6 built-in dictionary-preserving roster, eagerly reconstructs
   `SL:DICT` inputs as `SL:DICT` and standard hash-table inputs as fresh
   hash tables with the same test, retaining selected associations without
   mutating the source. Selection uses one traversal, callbacks run at call
   time, result order is unspecified, and user-defined dicts and read-only
   plist views retain their existing contracts.
9. For the Chapter 6 built-in dictionary-promotion roster (the 17 roster
   operations `SL:SEQ-SORT`, `SL:SEQ-STABLE-SORT`, `SL:SEQ-REVERSE`,
   `SL:SEQ-MAP`, `SL:SEQ-MAP-INDEXED`, `SL:SEQ-KEEP`, `SL:SEQ-MAPCAT`,
   `SL:SEQ-SUBSTITUTE`, `SL:SEQ-SUBSTITUTE-IF`, `SL:SEQ-REDUCTIONS`,
   `SL:SEQ-CONCATENATE`, `SL:SEQ-INTERLEAVE`, multi-source `SL:SEQ-MAP`,
   `SL:SEQ-SPLIT`, `SL:SEQ-SPLIT-AT`, `SL:SEQ-SPLIT-WITH`,
   `SL:SEQ-PARTITION`, and `SL:SEQ-PARTITION-BY`), promotes built-in
   hash-table and `SL:DICT` inputs to `SL:ORDERED-DICT`. Promotion uses
   `SL:EQUALS`; the source hash-table test is not preserved, and keys may
   coalesce. For `SL:SEQ-SPLIT`, `SL:SEQ-SPLIT-AT`, `SL:SEQ-SPLIT-WITH`,
   `SL:SEQ-PARTITION`, and `SL:SEQ-PARTITION-BY`, the outer result remains
   lazy and each forced piece is an `SL:ORDERED-DICT`.
10. For `SL:SEQ-SORT`, `SL:SEQ-STABLE-SORT`, and `SL:SEQ-REVERSE` on promoted
    inputs, normalizes the source into an `SL:ORDERED-DICT` before reordering;
    the sorted-result contract follows Chapter 6, Section 6.1.1. Promoted
    mapping operations require callback results to be `SL:MAP-ENTRY` objects;
    an actual non-entry signals `TYPE-ERROR` rather than falling back to a lazy
    result.
11. Provides the seven dictionary operations `SL:DICT-VALUES-MAP`,
    `SL:DICT-KEYS-MAP`, `SL:DICT-SELECT-KEYS`, `SL:DICT-REMOVE-KEYS`,
    `SL:DICT-MERGE-WITH`, `SL:DICT-COUNT-BY`, and `SL:DICT-REDUCE-KV`.
    The 15-operation built-in dictionary-preservation roster follows Chapter 6,
    Section 6.1.1, as do `SL:SEQ-DROP-LAST`, `SL:SEQ-TREE-SEQ`,
    `SL:SEQ-MEMBER`, user-defined dict behavior, and read-only plist views.

### B.2.3 Documentation and Extensions

The ordered-dictionary amendment is summarized by Chapters 4, 6, 7, 8, and
9. A conforming implementation provides `SL:ORDERED-DICT` and the ordinary
`SL:ORDERED-DICT-P`, while retaining `SL:DICTP` unchanged. Ordered dictionaries
have fixed `#'SL:EQUALS` designators, persistent first-position/last-association
updates, stable entry traversal, and order-sensitive same-class equality.
Constructor-controlled lifecycle and diagnostic printing do not add reader syntax.

The Chapter 6 ordered matrix covers strict entry-only reconstruction, typed
empties, eager mapping and recurrence, duplicate emission versus resident
cardinality, same-class multi-source reconstruction, heterogeneous lazy results
with independently specified callback timing, and lazy outer/ordered inner
pieces with retry and EQ memoization. Explicit lazy views, scalar queries,
projections, fixed ordinary-dict producers, and fixed hash-set producers retain
their documented result types. Both Collector paths and batch reconstruction
follow the same duplicate policy; only the batch protocol accepts and ignores
`:TEST`. Keyed and positional access remain distinct for integer keys.

Hashing preserves the equal-hash law and finite-cycle termination; equal edit-
history-independent ordered contents hash equally. This checklist is not proof
that arbitrary external recursive or cached hash methods satisfy those laws.
Container complexity guarantees and documentation obligations are those of
Section 9.1.18, not benchmark requirements.

1. Documents implementation-defined behavior described by this specification.
2. May provide additional packages, reader macros, protocols, and utilities
   only within the extension boundary in Chapter 1. Such extensions preserve the
   behavior of conforming programs; the methods enumerated by the specification
   are closed, and the Chapter 6 `SL:SEQ-*` operations are closed to additional
   methods. Non-enumerated specializers elsewhere provide the sanctioned
   extension surface.
3. Does not prevent a conforming program from lexically binding any
   Sophie-defined exported symbol as a local variable, excluding constants or
   special variables defined by this specification (Chapter 1).

## B.3 Program Checklist

Use the following checklist as an informative summary of the requirements in
Chapter 1 and Chapter 2.

1. Is written in Common Lisp as defined by ANSI INCITS 226-1994 (R2004), with
   Sophie Lisp extensions.
2. Does not rely on implementation-dependent, implementation-defined, or
   unspecified behavior, or on undefined consequences, unless the Sophie Lisp
   specification explicitly permits it.
3. Programs must not access unexported symbols of `SOPHIE-LISP` (`SL`),
   `SOPHIE-LISP-EXTENSIONS` (`SL-EXT`), or `SL-USER` via package-internal
   access (`::`).
4. May use any conforming package base. The forms `(:USE :SL)`,
   `(:USE :SL-EXT :CL)`, and a COMMON-LISP package with Sophie symbols
   qualified as `SL:FOO` are sufficient but not exhaustive; a separate package
   with explicit imports is also conforming. Chapter 2 states the package bases
   and namespace details.
5. Avoids collisions with Sophie Lisp's export set or resolves them explicitly
   by qualifying the conflicting symbol, using a separate package with explicit
   imports, or using SL-EXT alongside COMMON-LISP.
6. Defines methods only within the extension boundary in Chapter 1.
7. Does not define a package with a reserved name or nickname, including
   "SOPHIE-LISP", "SOPHIE-LISP-EXTENSIONS", "SL", "SL-EXT", "SL-USER", or
   any name beginning with "SOPHIE-LISP." or "SL.", as specified in
   Section 1.4.4.

## B.4 Extension Checklist

This checklist is an informative summary for an extension that introduces a new
collection type, an explicit result target, or a dict type. A conforming
extension is first a conforming program. Chapter 1 controls the extension
boundary and the normative consequences.

1. **Collection participation.** Provide applicable methods, directly or by
   inheritance, for the mandatory seq primitives
   `SL:SEQ-FIRST`, `SL:SEQ-REST`, and `SL:SEQ-EMPTYP` on the user-defined type,
   have `SL:SEQABLEP` return a true value, and support `SL:SEQ-REF` using the
   traversal default unless overridden. Use the construction protocol
   `SL:LAZY-SEQ`, `SL:MAKE-LAZY-SEQ`, and `SL:LAZY-CONS` when producing
   lazy-seq nodes. These methods must satisfy the six coherence and stability
   requirements in Chapter 4, not merely exist. See Chapter 4 for the
   applicable protocol requirements.
2. **Result targets and reconstruction.** For an explicit `SL:SEQ-INTO`
   conversion target or the constructed result type of `SL:SEQ-JOIN`, specialize
   `SL:MAKE-COLLECTOR-FOR` on its class object; the method for the designator path
   uses an EQL specializer on that class object. A type that participates in
   type-preserving reconstruction, even when it is not an explicit result target,
   needs an applicable non-default primary reconstruction-path
   `SL:MAKE-COLLECTOR-FOR` method for its source object, usually specialized on
   its source class, plus `SL:COLLECTOR-ACCUMULATE` and `SL:COLLECTOR-RESULT` on
   its Collector class. If the source object is itself a class object, an
   applicable non-default primary method with an EQL specializer on that object
   also counts; `:BEFORE`, `:AFTER`, and `:AROUND` methods alone do not establish
   participation. An explicit result target requires designator-path methods.
   Type-preserving reconstruction is a separate obligation. The Collector
   boundary is specified in Chapter 4; the construction-operation boundary is
   specified in Chapter 6.
   These three Collector methods must satisfy refusal recovery, idempotent
   finalization, result identity, and the prohibition on silently dropping or
   truncating refused elements in Chapter 4.
3. **Dict participation.** For a new dict type, define the required Dict
   Protocol primitives `SL:DICTP`, `SL:DICT-REF`, `SL:DICT-TEST`, and
   `SL:DICT-SIZE`, together with `SL:SEQ-FIRST`, `SL:SEQ-REST`,
   `SL:SEQ-EMPTYP`, and `SL:SEQ-LENGTH`. Support `SL:SEQ-REF` using the
   traversal default unless overridden, and have `SL:SEQABLEP` return a true value.
   `SL:DICT-SET`, `SL:DICT-WITHOUT`, and `SL:DICT-COLLECT` are optional; when
   supplied, they obey the behavior specified in Chapter 9. Standard hash tables
   support `SL:DICT-SET` and `SL:DICT-WITHOUT` by shallow, non-destructive copying:
   the result is fresh, preserves the table's standard test, and shares resident
   key and value objects; copying is O(n). `(SETF SL:DICT-REF)` remains the
   destructive write surface, and read-only adapters may still decline the
   functional operations.
4. **Dictionary collisions and updates.** `:collision :error` in `SL:DICT-MERGE`
   and `SL:DICT-TRANSFORM` uses the selected result test, including fallback
   coalescence, stops at the first detected collision, and returns no partial
   dictionary. Transform callbacks run once per processed entry, with no later
   callbacks after detection and no rollback of earlier callback side effects.
   Functional hash-table updates propagate through `SL:DICT-UPDATE`,
   `SL:DICT-UPDATE-IN`, and `SL:DICT-SET-IN` without mutating inputs; present
   `NIL`, missing children, and declined/read-only intermediates retain Chapter 9's
   distinctions and conditions. Both update operations pass `:default` (omitted
   `NIL`) only for an absent key or leaf; a present `NIL` remains `NIL`.
   Neither operation accepts `:signal` or signals merely because a key is absent.
5. Every dict type is seqable and obeys the six dict consistency laws. The sixth
   law specifies undefined consequences when resident-key mutation changes equality
   or hashing, rather than imposing a conformance obligation. `SL:DICT-TEST`
   designators must be stable and EQ-identical across calls. See Chapter 9.

