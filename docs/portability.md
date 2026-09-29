# Portability notes

## Current status

The reference implementation builds and its test suite runs green on three
Common Lisp hosts, all observed on Linux x86-64 through roswell:

| Host | Observed version | Suite result |
|---|---|---|
| SBCL | 2.6.8.roswell | 95,159 passed / 0 failed / 0 skipped |
| CCL | 1.13 | 95,128 passed / 0 failed / 0 skipped |
| ECL | 26.5.5 | 94,641 passed / 0 failed / 0 skipped |

Counts above were measured after the quality rounds 1–2 test
additions. Some assertions are guarded to the host behavior they
characterize, and some ECL test legs depend on compile mode; thus per-host
passed counts differ and ECL's count varies by roughly ±100 between runs.
Every observed run had 0 failed.

The main system also compiled and loaded with zero warnings and
zero style-warnings on all three hosts in final verification. The known SBCL
cold-cache `REDEFINITION-WITH-DEFMACRO` style-warnings did not appear in that
final verification. The default source path is implementation-independent:
`src/` contains no reader feature conditionals (`#+`/`#-`).

This is a three-host test matrix, not a general portability claim: hosts
outside the matrix are untested.

## Portable dependencies

The implementation depends on portable libraries instead of host-specific
packages:

- `bordeaux-threads` — locks serializing the shared identity-hash state
  (`bt:make-lock`, `bt:with-lock-held` in `src/core/support.lisp`);
- `trivial-garbage` — the implementation (`src/`) uses only
  `tg:make-weak-hash-table` for identity retention; the test system uses weak
  pointers and `tg:gc` (`tests/containers/trie.lisp`), and the benchmark
  system uses `tg:gc` (`benchmarks/host.lisp`);
- `named-readtables` — the named readtable registry used by the reader
  (ANSI Common Lisp does not define such a registry);
- `closer-mop` — portable MOP introspection;
- `alexandria` — utilities.

The former `sb-*` seam (`sb-thread:make-mutex`, `sb-thread:with-mutex`,
`sb-ext:float-infinity-p`, and the SBCL weak-pointer API) is gone.

Two portable load-time seams respond to host capabilities. The fixnum-width
mixer seam retains the `mix64` delegator to the wide `mix64-wide` body on SBCL
and selects the fixnum-safe `mix64-limb` mixer on CCL/ECL by default. The
host-list seam in `src/containers/trie.lisp` installs the limb mixer and
32-bit combining on SBCL and CCL (idempotent for CCL's already-selected
mixer). ECL keeps its fixnum-width-selected limb mixer and default wide
64-bit combining: its cheap C-level bignums made measured 32-bit-combining
variants slower in pre-1.0 measurements. A
hypothetical wide-fixnum host outside the list retains the wide mixer and
default combining.

Normalization inside the infinity/NaN predicates (`float-infinity-p`,
`float-nan-p` in `src/core/support.lisp`) handles the remaining host
difference: SBCL and CCL trap `floating-point-invalid-operation` on unordered
NaN comparisons, while ECL returns a false result without trapping. The
predicates classify the trap with `handler-case` — harmless on a non-trapping
host, where the comparison already yields the same answer — so the observable
result is uniform across hosts.

### Hash machinery terminology

- **Mixer:** The per-value hash mixing function. `mix64-wide` is the wide
  64-bit SplitMix64 body; `mix64-limb` is the fixnum-safe 32-bit finalizer.
  The `mix64` function cell selects the production mixer at load time.
- **Combining discipline:** How component hashes are combined into composite
  hashes: default wide 64-bit combining (`hash-combine`, `hash-unordered`,
  `hash-integer`) or narrow 32-bit combining (their `-32` variants).
- **Narrow discipline:** The limb mixer plus 32-bit combining, installed on
  SBCL and CCL by the `*narrow-hash-discipline-hosts*` load-time seam in
  `src/containers/trie.lisp`. “Wide” and “narrow” describe the combining
  discipline separately from the mixer: ECL uses the limb mixer with wide
  combining; an unlisted wide-fixnum host keeps the wide mixer and wide
  combining.

## Per-host behavioral notes

These are host observations recorded during the port, not Sophie defects.
Where a host difference touched observable Sophie behavior, the source now
enforces the specified behavior on every host; where the specification
delegates a choice to the host, the tests guard to the host's answer.

### CCL

- `rational` accepts a NaN and returns its bit pattern where SBCL signals.
  `hash-real` (`src/containers/trie.lisp`) classifies NaN first via
  `float-nan-p`, so `sl:hash-code` of a NaN raises the same `type-error` on
  every host.
- `read-delimited-list` admits dotted tails that SBCL rejects. The
  container-literal reader enforces the proper-list grammar of the container
  syntax on every host, so a dotted literal signals `reader-error` uniformly.
- `*read-eval*` is enforced under `*read-suppress*`: CCL aborts on `#.`
  where SBCL suppresses the form. The `#.` fixtures in the read-suppression
  tests apply only where the host suppresses.
- Unknown-symbol type specifiers are upgraded to `t` in some type contexts
  instead of being diagnosed. The collector gensym fixture applies only where
  the host rejects the specifier.
- `make-array` reports `character` for a `base-char` element type that its
  own upgrade accepts. The string collector oracle is the element type the
  host itself produces.

### ECL

- `typep` returns a truthy class-precedence list for strict subclasses. The
  affected tests normalize `typep` results to a boolean.
- CLOS accepts unknown generic-function keywords. The specification delegates
  generic-function keyword checking to the host, so the keyword-rejection
  fixtures probe the host first and guard the rejection expectations.
- The compiler validates constant keyword argument lists at compile time.
  The unknown-keyword and odd-length keyword test cases catch the
  host-prescribed condition and exclude the compiled leg on ECL.
- The compiler mis-binds an `&optional` supplied-p variable combined with an
  inner `&key` lambda list. The affected test cases run interpret-only on ECL.
- ECL links global `defun` calls directly, so `symbol-function` interception
  is invisible. Interception-dependent expectations are probed per host and
  guarded.

### ECL weak hash tables

ECL's weak hash table does purge dead keys, with per-key-type timing.
`trivial-garbage`'s `tg:make-weak-hash-table` path and ECL's native
`(make-hash-table :weakness :key)` use the same mechanism; the
`:ecl-weak-hash` feature is present. Entries keyed by structure objects
vanish after one quiet full GC, while entries keyed by standard objects purge
under allocation churn (repeated full GCs with fresh allocation) but not
necessarily after a quiet full GC alone. One quirk remains: entries keyed
by conses are never purged, even under allocation churn, although the conses
are demonstrably dead (weak pointers to identically-created conses read dead
after one full GC). Sophie's identity-hash table only ever receives
standard-object and structure-object keys — `identity-hash` is called only
from the `sl:hash-code` methods for those two types — so the quirk does not
affect the implementation, and the weak-reference regression test passes on
ECL without guards.

## Test-side guards policy

- Reader feature conditionals (`#+`/`#-`) appear in tests only, never in
  `src/`.
- Each test guard carries a stated reason at the guard site.
- Subprocess fixtures spawn roswell's default SBCL (2.6.8.roswell in this
  environment), regardless of the host running the suite; they never count
  as CCL or ECL coverage.

## Known specification tension

The explicit loops in the `sl:equals` and `sl:compare` cons methods
(`src/core/values.lisp`) bypass generic dispatch for intermediate cons-cons
tail pairs: a user-defined `eql`-specialized method on a specific cons does
not take effect for those pairs. This is a disclosed deviation from the letter
of [spec §7.1.5](../spec/chapter-07-equality-and-comparison.md#715-performance),
which says user-defined methods must still take effect, and remains tracked
pending specification clarification; the spec has not been amended. The loops
replace tail recursion that is not viable on hosts without tail-call
optimization; the bypass is disclosed at the loop sites. This is **not** an
accepted conforming tradeoff. See also [implementation status and limitations](implementation.md#status-and-limitations).

## Accepted tradeoff

NaN hashing on SBCL now uniformly raises `type-error`: previously the raw
`floating-point-invalid-operation` surfaced from `rational`. The specification
assigns no condition for NaN hashing — the consequences are undefined
(§7.2.2, `SL:HASH-CODE`) — so the uniform `type-error` is conforming and is
now identical across hosts.

## Remaining caveats

- Observation scope: The comment above `mix64-wide` in
  `src/core/support.lisp` reports that SBCL compiles that wide function to
  raw shifts, XORs, and multiplications with one result box. It does not
  describe the selected round-C production mixer; the wide function's
  internal products still box in the measured SBCL path.
- Seam mechanics: The fixnum-width seam remains intact and supplies the
  limb finalizer to CCL/ECL; the host-list seam additionally selects that
  finalizer for SBCL, while CCL's selection is idempotent. The frozen wide
  formulation matches the exact-integer reference; the narrow formulation is
  checked against its own independent reference.
- Production mixer selection: The production wide `mix64` function cell is
  dormant on all three supported hosts. SBCL and CCL swap it at trie load
  time; ECL selects the limb mixer by fixnum width.
- Mixer test coverage: The direct production-cell bit-identity test runs on
  hypothetical unlisted wide-fixnum hosts. On every supported host, tests
  compare the retained pre-swap load-time `mix64` delegator function object
  and the separate `mix64-wide` formulation against the frozen reference;
  neither test executes the swapped production wide cell.
- Production combining: SBCL and CCL use the 32-bit combining discipline:
  64-bit operands are XOR-folded to 32 bits, integer magnitudes are visited
  in 32-bit limbs, and unordered squared contributions use 16-bit halves.
- Hash-value consequences: Mixed built-in hashes fit in 32 bits (and
  therefore in the unsigned-64 range); fixed sentinels such as
  `NIL`'s hash and infinity hashes may still occupy 64 bits, as may
  user-supplied hash methods. This changes SBCL hash
  values from round B, but not hash equality. CCL's values remain identical
  to its pre-round-C values; ECL keeps its prior combining and hash values.
  Unequal-value collisions can increase trie work but cannot change membership semantics.
  Changed hash values can also change hash-derived, specification-unspecified
  outcomes: dict/set traversal order, printed element order, positional
  selection results, and which callback error surfaces first in order-sensitive
  contexts. §9.1.2 leaves dict traversal order unspecified.
- Operational hazards: See [implementation status and limitations](implementation.md#status-and-limitations)
  for fresh-image discipline switching and the SBCL `support.lisp` reload hazard.
- The former tail-call assumption in recursive cons comparison is gone: the
  comparison uses explicit loops, with deep-chain regression tests covering
  the stack-boundedness the assumption used to provide.
