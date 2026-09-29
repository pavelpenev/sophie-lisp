# Benchmarks

## Contents

- [Summary](#summary)
- [Results](#results)
- [Running and comparing](#running-and-comparing)
- [Methodology](#methodology)
- [Coverage appendix](#coverage-appendix)
- [Development history (pre-1.0)](#development-history-pre-10)

## Summary

The suite measures Sophie operations against standard Common Lisp equivalents;
it records a performance envelope, hotspots, and a regression baseline, not
conformance requirements. The committed SBCL/CCL/ECL three-host matrix is in
`benchmarks/results/` (`baseline-{sbcl,ccl,ecl}.json`).

- At 10000 entries, persistent `dict-set` is 453.7x faster than
  copy-hash-table-then-update on SBCL (`:persistent-vs-copy`; different
  persistence semantics).
- `seq-map` @10000 takes 4.4x the time of CL `MAP` on SBCL (`:same-op`,
  generic fresh-result vs direct CL); comparisons carry explicit fairness tiers.
- On SBCL, `hash-code` for a fixnum costs 99.9 ns versus 10.6 ns for
  `SXHASH` (9.5x; `:same-op`, different hash semantics). The narrow discipline
  selects `mix64-limb` and 32-bit combining on SBCL and CCL; ECL uses the
  limb mixer with wide 64-bit combining.
- Warm `range` re-traversal @10000 is 496000.0 ns versus 2669000.0 ns cold
  on SBCL; hashing shared DAG substructure takes 2076.5 ns versus 273891 ns
  for the fresh tree (132x). These are within-Sophie contrasts.
- ECL requires heap pre-growth to avoid in-batch GC threshold crossings
  while leaving GC enabled during measurement.

See the [full results](#results) and [running instructions](#running-and-comparing)
below.

## Results

Timing numbers below are medians from the committed
`baseline-{sbcl,ccl,ecl}.json` under `benchmarks/results/` (1012 records per
host); units are ns unless marked us or ms. The registry has 278 distinct
bench names in each committed JSON file. The reporting rule from
[Comparison fairness](#comparison-fairness) applies throughout: a difference
below `max(2x combined relative MAD, 5%)` is printed as `~=`, never as a
bare ratio. Sophie-vs-CL contrasts state their tier and caveat; ratios are
rounded.

For round and stage labels, see the [development-history glossary](#round-and-stage-labels).

### SBCL headline tables

Dispatch overhead (`:dispatch` tier — constant factors, size 10000 unless
marked size 1):

| Sophie op | CL baseline | Sophie ns | CL ns | Ratio (Sophie / CL) |
|---|---|---:|---:|---:|
| `seq-ref` on vector | `ELT` (`cl-elt`) | 31.4 | 10.8 | 2.9x |
| `seq-first` on list | `CAR` | 11.8 | 8.9 | 1.3x |
| `seq-length` on list | `LENGTH` | 9625.0 | 9608.4 | ~= |
| `ref` on vector | `ELT` (`cl-elt-vector`) | 43.8 | 11.0 | 4.0x |
| `ref` on hash table | `GETHASH` | 30.4 | 9.6 | 3.2x |
| `ref` on dict (absolute; record tier `:same-op`, not `:dispatch`) | — | 189.6 | — | — |
| `seqablep` gateway (absolute, size 1) | — | 10.3-10.8 | — | — |

The `seqablep` gateway costs 10.3-10.8 ns against an 8.8 ns empty-loop
harness floor. `ref` on a dict includes the persistent-trie walk (189.6
ns at 10000), not just dispatch.

Same-op contrasts (`:same-op` tier — same operation, different semantics;
Sophie is persistent, structurally equal, and generic; the CL baseline is
mutable and direct):

| Sophie op | CL baseline (CL operation) | Sophie ns | CL ns | Ratio (Sophie / CL) |
|---|---|---:|---:|---:|
| `dict-ref` hit, fixnum key @1000 | `GETHASH` | 179.9 | 10.1 | 17.9x |
| `dict-ref` hit, string key @1000 | `GETHASH` on fixnum keys, `:test #'equal` | 913.3 | 10.1 | 90.7x |
| `seq-map` @10000 | `MAP` | 478812.5 | 108718.8 | 4.4x |
| `seq-filter` @10000 | `REMOVE-IF-NOT` | 292453.1 | 95195.3 | 3.1x |
| `seq-reduce` @10000 | `REDUCE` | 253640.6 | 47406.2 | 5.4x |
| `seq-find` @10000 | `FIND` | 64753.9 | 26390.6 | 2.5x |
| `seq-sort` @10000 | `SORT` | 5302500.0 | 1425625.0 | 3.7x |
| `collector` list @10000 | `LOOP COLLECT` | 358187.5 | 64158.2 | 5.6x |
| `read-dict-literal` @10000 | plain `READ` | 9290500.0 | 1887250.0 | 4.9x |
| `hash-code` fixnum (size 1) | `SXHASH` | 99.9 | 10.6 | 9.5x |

The string-key row follows its recorded `ht-ref-hit` link, whose baseline
uses fixnum keys; it is not a string-key `GETHASH` comparison. `hash-code`
on strings is prefix-bounded (64 elements) while `SXHASH` hashes the whole
string: at 10000 chars the medians are 3265.9 and 9575.7 ns, so the
ratio does not compare the same work. `seq-sort`'s baseline is destructive
and already sorted from call 2 onward; Sophie's uses a fresh copy and
structural comparison.

Persistent-vs-copy (`:persistent-vs-copy` tier — one persistent update
against copy-then-mutate; `copy-hash-table` is an alexandria utility, not
ANSI):

| Size | `dict-set` ns | copy + `setf` ns | Ratio (CL / Sophie) |
|---|---:|---:|---:|
| 10 | 288.7 | 506.7 | 1.8x |
| 100 | 498.4 | 2951.9 | 5.9x |
| 1000 | 603.4 | 35834.0 | 59.4x |
| 10000 | 649.0 | 294468.8 | 453.7x |

At 10000 entries a persistent `dict-set` costs 0.65 us against 294.47 us
for copy-then-mutate — a trie update against a full table copy; the
persistent update is faster at all four reported sizes. `dict-without` costs 700.4 ns at 10000
against 14.2 ns for in-place `REMHASH`, but the baseline measures the
absent-key path after its first call; the ratio is not a like-for-like
removal cost. Reads after update on original and updated dicts at size 100
are 174.6 vs 176.1 ns; at size 10000 they are ~= (173.9 vs 175.1 ns).
These measurements do not imply a size-independent read penalty.

Lazy realization (absolute, cold and warm measured on the same host):

| Bench (ns) | 10 | 1000 | 10000 |
|---|---:|---:|---:|
| `range-cold` | 3843.8 | 264937.5 | 2669000.0 |
| `range-warm` | 550.5 | 49531.2 | 496000.0 |

Warm re-traversal is about 0.14-0.19x cold at those sizes. First forcing
a fresh cell costs 156.2 ns; a memo-hit re-read costs 21.9 ns.
Deep-chain realization costs 175250 ns at 1000, 1711000 at 10000,
and 17397000 at 100000 (~174 ns/element), without stack growth.

Memoization payoff (`hash-code` on shared substructure, 1023-node shapes):
the DAG costs 2076.5 ns against 273891 ns for the fresh tree — 132x.
Separate work-count probes (not timed records) find 21 `hash-code` calls
for the DAG against 2047 for the tree, with equal hash values.

Syntax (size 1; expansion is compile-time, so runtime contrasts measure
only what the host does not optimize away):

| Sophie form | CL baseline | Sophie ns | CL ns | Ratio (Sophie / CL) |
|---|---|---:|---:|---:|
| `->` | nested calls | 8.4 | 8.4 | ~= |
| `->>` | nested calls | 8.4 | 8.4 | ~= |
| `~>` | nested calls | 8.4 | 8.4 | ~= |
| `as->` | nested calls | 8.4 | 8.4 | ~= |
| `bind` | `DESTRUCTURING-BIND` | 33.4 | 20.9 | 1.6x |
| `fbind` | `LABELS` call | 25.4 | 8.6 | 2.9x |
| `compose` | nested calls | 35.3 | 8.4 | 4.2x |

On SBCL `->`, `->>`, `~>`, and `as->` are ~= the nested baseline in this
run. `fbind` pays its forwarding-cell and `APPLY` cost; `compose` pays
per-step designator resolution. A representative `MACROEXPAND-1` step of
a `bind` plus `->` pair costs 7873.0 ns at compile time, not per runtime
call.

### CCL

For the CCL baseline's recording history, see
[superseded baseline provenance](#superseded-baseline-provenance).

On the same machine, CCL's empty-loop floor is 8.1 ns (SBCL 8.8 ns),
and `hash-code-fixnum` is 448.7 vs SBCL 99.9 ns (4.5x).
The contrasts: `seq-ref` on vector 48.6 vs its recorded `cl-elt`
18.8 ns (2.6x); `dict-ref` fixnum hit @1000 702.7 vs `ht-ref-hit`
65.7 ns (10.7x); `seq-map` @10000 1563750 vs `cl-map` 163578 ns (9.6x);
`seq-sort` @10000 11509000 vs `cl-sort` 1592000 ns (7.2x);
`collector` list @10000 1486000 vs `LOOP COLLECT` 83992 ns (17.7x).
Same-op rows have the persistent/generic vs mutable/direct caveat above;
the sort baseline is destructive and becomes sorted. In the
persistent-vs-copy tier, `dict-set` @10000 takes 3522.5 ns vs 1716250 ns
for copy+`setf` (CL / Sophie: 487.2x). `set-member-hit` @10000 takes
731.0 ns vs list `MEMBER` 13355 ns (Sophie / CL: 0.055x; persistent trie
vs direct list scan). Warm `range` @10000 takes 2473375 ns vs cold
5764500 ns (0.4x; no CL baseline).

CCL retains the `as->` finding: its `LET*` rebind chain (`as-thread`)
takes 121.5 ns vs the recorded nested-calls baseline 10.3 ns (11.8x),
while SBCL's 8.4 vs 8.4 ns is ~=. CCL's `->`, `->>`, and `~>`
cost 10.1-11.0 ns against the 10.3 ns nested baseline (some
differences are ~= under the reporting rule). ECL also shows an `as->`
gap (147.8 vs 39.7 ns, 3.7x); this is an expansion-shape finding,
not a cost of every threading macro.

### ECL

The committed idle-rhea ECL baseline has 1012 records, with the heap remedy
in effect. All entries below are medians from
`benchmarks/results/baseline-ecl.json`:

| ECL bench (us/op) | @100 | @1000 | @10000 |
|---|---:|---:|---:|
| `dict-update` | 18.46 | 18.38 | 19.71 |
| `dict-ref-miss-fixnum` | 3.33 | 3.54 | 3.66 |
| `dict-without` | 8.06 | 8.13 | 9.58 |
| `ordered-dict-ref` | 3.93 | 3.92 | 4.06 |
| `dict-ref-hit-fixnum` | 3.62 | 3.36 | 4.05 |
| `dict-ref-hit-string` | 22.35 | 21.37 | 21.53 |
| `dict-ref-miss-string` | 22.35 | 22.56 | 22.54 |
| `set-add` | 7.96 | 8.39 | 8.78 |
| `set-member-miss` | 3.07 | 3.53 | 3.64 |
| `set-member-hit` | 3.63 | 3.37 | 3.75 |

`set-member-hit` @10000 is 3.75 us vs its recorded list `MEMBER`
baseline at 10.28 us: `:same-op`, persistent generic trie membership vs
direct list scan. ECL's own CL baselines remain expensive at size 10000:
`cl-remove-duplicates` is 201.53 ms and `cl-union`/`cl-intersection`
56.31/61.03 ms. The linked `cl-remove-duplicates-list` is 198.91 ms;
`seq-remove-duplicates-list` is 38.92 ms (0.20x of that linked
baseline), comparing the recorded operations, not equivalent
persistent/mutable semantics.

Warm `range` again beats cold at every reported size (absolute timings,
no CL baseline):

| Size | `range-cold` ms | `range-warm` ms | Warm / cold |
|---|---:|---:|---:|
| 10 | 0.02287 | 0.01061 | 0.5x |
| 100 | 0.19997 | 0.10153 | 0.5x |
| 1000 | 1.94825 | 1.00525 | 0.5x |
| 10000 | 20.92600 | 10.01250 | 0.5x |

Effective-size caps: the 12 ECL records with `ecl_cap_applied` true are
`ht-make-n`, `ht-iterate`, `dict-make-n`, `dict-keys`, `dict-vals`, and
`dict-reduce-kv` at nominal 100000 (effective 10000); `dict-update-in`,
`dict-set-in`, and `dict-ref-in` at 10000 (effective 1000);
`dict-ref-collision` at 1000 and 10000 (both effective 100); and
`deep-chain-realize` at 100000 (effective 10000). The last records
16518500 ns for only 10000 elements, vs SBCL's 17397000 ns for the
full 100000. Comparing those nominal-size records across hosts is invalid;
use `effective_size` and `ecl_cap_applied` to filter comparisons.

### Hotspot analysis

The remaining concentrations use the committed rhea baselines; Sophie/CL
comparisons specify their tier and semantics caveat:

- `seq-map-list` @10000 is 4.4x `MAP` on SBCL (`:same-op`, generic
  fresh-result Sophie vs direct CL). Callback/collector work remains;
  list/vector fast paths avoid per-element view-node cost.
- `seq-sort` @10000 is 3.7x `SORT` on SBCL, 7.2x on CCL and 7.7x on
  ECL (`:same-op`; Sophie copies and uses structural comparison, CL
  mutates and becomes sorted after its first call). Comparison/sort
  itself dominates.
- `ref` on vector remains 4.0x `ELT` on SBCL (`:dispatch`, facade vs
  direct vector access).
- `collector` list @10000 remains 5.6x `LOOP COLLECT` on SBCL
  (`:same-op`, generic collector and fresh result vs direct CL);
  collector dispatch remains a cost.
- `read-dict-literal` @10000 is 4.9x plain `READ` on SBCL
  (`:same-op`, but the Sophie input reads 2N fixnums and builds an
  unevaluated construction form vs N symbols; no persistent dict is
  constructed).
- `fbind` 2.9x `LABELS` and `compose` 4.2x nested calls on SBCL
  (`:same-op`, forwarding-cell/`APPLY` and designator-resolution
  indirection).
- Hash-code remains a cross-host floor: fixnum hash-code is 99.9 ns
  on SBCL, 448.7 on CCL, and 2651.1 on ECL (absolute). These
  medians cover the selected narrow discipline on SBCL/CCL and ECL's
  fixnum-safe `mix64-limb` mixer with wide 64-bit combining.
- Persistent `dict-set` at size 10000 costs 0.65 us and `dict-without`
  0.70 us on SBCL; trie updates pay for structural sharing. In the
  `:persistent-vs-copy` tier, `dict-set` is 453.7x faster than
  copy-then-mutate at that size (CL / Sophie).

## Running and comparing

### Local before/after workflow

Use the same idle machine, Lisp host, benchmark settings, and full-matrix
context for both runs. From a checkout discoverable by ASDF, run a before
snapshot, make the intended change, then run an after snapshot on that same
machine. For example, from the repository root with roswell and SBCL:

    mkdir -p benchmarks/results/scratch
    ros -L sbcl-bin run -- \
      --eval '(push (truename #p"./") asdf:*central-registry*)' \
      --eval '(asdf:load-system "sophie-lisp/benchmarks")' \
      --eval '(sophie-lisp.benchmarks:run-benchmarks :output "benchmarks/results/scratch/before-sbcl.json")' --quit

After the change, run the same command with a different output name:

    ros -L sbcl-bin run -- \
      --eval '(push (truename #p"./") asdf:*central-registry*)' \
      --eval '(asdf:load-system "sophie-lisp/benchmarks")' \
      --eval '(sophie-lisp.benchmarks:run-benchmarks :output "benchmarks/results/scratch/after-sbcl.json")' --quit

Compare the two files in an image with `sophie-lisp/benchmarks` loaded:

    (sophie-lisp.benchmarks:compare-runs
      "benchmarks/results/scratch/after-sbcl.json"
      "benchmarks/results/scratch/before-sbcl.json")

`benchmarks/results/scratch/` is gitignored. Never write local runs to the
committed `baseline-{sbcl,ccl,ecl}.json` files: those were measured on the
reference machine rhea and serve as regression-comparison records, not as
local output paths. Compare local before/after runs with each other; use the
committed baseline for comparable reference-machine runs. To record a future
committed baseline, copy the scratch run to the appropriate
`benchmarks/results/baseline-{sbcl,ccl,ecl}.json` filename and record its source
commit and machine, as for the baselines in the development-history appendix.

### Reference environment (rhea)

SBCL 2.6.8.roswell, CCL Version 1.13 (v1.13) LinuxX8664, and
ECL 26.5.5 report 1,000,000 internal time units per second and 1 tick
measured resolution on rhea. From `~/sophie-lisp-bench` on rhea (or a
checkout at the relevant commit), the registry push makes the checkout
discoverable to ASDF. The same invocation applies to each host; replace
`sbcl-bin` with `ccl-bin` or `ecl` and choose a fresh scratch output name:

    ssh rhea 'cd ~/sophie-lisp-bench && mkdir -p benchmarks/results/scratch && ros -L sbcl-bin run -- \
      --eval '\''(push (truename #p"./") asdf:*central-registry*)'\'' \
      --eval '\''(asdf:load-system "sophie-lisp/benchmarks")'\'' \
      --eval '\''(sophie-lisp.benchmarks:run-benchmarks :output "benchmarks/results/scratch/current-sbcl.json")'\'' --quit'

No parameter overrides: default reps/warmups/floor are 15/3/10 ms on
SBCL and CCL, 25/5/20 ms on ECL.

### Regression cadence

Run the full SBCL matrix on idle rhea from the repository checkout, using
the [reference-environment command](#reference-environment-rhea) with a fresh
scratch output name.

The fixed eight-bench subset below is a CCL/SBCL timing spot-check and
an ECL clean-floor smoke check. ECL subsets remain clean under the heap
remedy, but fresh-process checks of former-victim cells differed from
full-matrix cells by -5.5% to +9.0% (only 3 of 8 met the strict MAD-band
rule). They cannot replace full-matrix timing comparisons:

    ssh rhea 'cd ~/sophie-lisp-bench && mkdir -p benchmarks/results/scratch && ros -L ccl-bin run -- \
      --eval '\''(push (truename #p"./") asdf:*central-registry*)'\'' \
      --eval '\''(asdf:load-system "sophie-lisp/benchmarks")'\'' \
      --eval '\''(sophie-lisp.benchmarks:run-benchmarks :names (mapcar (lambda (s) (intern (string s) (find-package "SOPHIE-LISP.BENCHMARKS"))) (quote (hash-code-fixnum hash-code-string dict-ref-hit-fixnum dict-update dict-set set-member-hit range-cold range-warm))) :output "benchmarks/results/scratch/spot-check-ccl.json")'\'' --quit'

For SBCL use `-L sbcl-bin`; for ECL use `-L ecl`. CCL and SBCL
subset timings may be compared with their full-matrix host baselines:
their observed smoke timings were consistent with full-matrix timings.
Revisit this if either host shows context sensitivity. ECL timing
regression checks still require the full matrix on idle rhea, using the
[reference-environment command](#reference-environment-rhea) with an ECL
scratch output name. Do not compare ECL subset
medians numerically to the committed full matrix, even though subset
smoke checks stay at clean floors. Compare a timing run
with its own host's committed baseline:

    (sophie-lisp.benchmarks:compare-runs
      "benchmarks/results/scratch/current-<host>.json"
      "benchmarks/results/baseline-<host>.json")

Benchmark only on an idle machine; rhea is the designated reference host.
Historical main-machine drift is documented in the development history. Re-run a
flagged regression under low load; if it disappears, classify the flag as
environmental, not a code regression. For ECL, keep the full-matrix
context in that re-run: subset/full drift alone neither establishes nor
dismisses a regression. Use the committed heap-provenance-bearing ECL
baseline for reference-machine full-matrix comparisons.

A regression is a median ratio above 1.15 AND non-overlapping median +/- MAD
bands. Parameter mismatches (k, reps, warmups, floor-ticks) print a warning
and flag the row PARAM-MISMATCH: k is adaptive, so a one-step k difference
between runs is expected and benign — the flag matters when reps, warmups,
or the floor differ, i.e. when the runs were configured differently.

### Recalibrating the four index thresholds

1. **Prepare the workload.** Measure both the linear/bijection and
   indexed/probe path with the same prebuilt workload as the corresponding
   benchmark; keep setup, GC, and warmups outside each timed call. The
   thresholds are `defconstant`s, so do not rebind them to force a path.
2. **Time both paths.** Use the matching prebuilt inputs for each operation:
   - Merge: time the internal `dict-merge-with-linear` and
     `dict-merge-with-indexed` helpers directly on the same prebuilt pairs
     near the candidate threshold.
   - Select/remove: time the `:linear` versus `:table`/`:hash` branches of
     `dict-select-remove-keys` by choosing requested-key counts immediately
     below/above the current constant.
   - Equality: compare `container-bijection-p` on prebuilt
     `container-trie-items` against the right-trie `trie-ref` probe path in
     the `sl:equals` dict/set methods (or size both containers just
     below/above the current cutoff).
   - Distinct: compare
     `sophie-lisp.internal::selection-distinct-linear-result` with
     `sophie-lisp.internal::selection-distinct-indexed-result` on the same
     prebuilt entries. Both take `(entries test from-end)`; the indexed helper
     also takes `(kind standard)` (use the values from `index-kind-for-test`).
     `entries` is a list of `(original-element . keyed-value)` pairs in
     reverse encounter order, as accumulated by `selection-distinct`.
3. **Sweep.** If below/above sizing is used where dispatch cannot be
   isolated, account for workload differences and sweep more than one size
   on each side. Sweep below and above the expected crossover. In each sweep,
   time each path at the operation's workload shape (using the direct helpers
   where available and adjacent sizes where dispatch is inseparable) rather
   than timing only one side of the threshold-dispatch wrapper.
4. **Choose the cutoff.** Choose a cutoff at a measured tie-to-win boundary
   or below it, allowing for timing drift. Repeat on every supported host
   and use the worst host.
5. **Re-verify.** Re-verify the affected public-entry benchmark cells on all
   supported hosts whenever a new constant is chosen.

## Methodology

The [threshold recalibration procedure](#recalibrating-the-four-index-thresholds)
is part of the contributor workflow above. The observed crossover data and
chosen cutoffs are preserved in the [development history](#optimization-round-a-algorithms-and-eager-traversal).

The [hash machinery terminology](portability.md#hash-machinery-terminology)
defines the mixer, combining discipline, and narrow discipline used here.
The benchmark baselines use narrow combining on SBCL/CCL and wide combining
with the limb mixer on ECL.

The benchmark suite measures the performance of the Sophie surface against
standard Common Lisp equivalents. Its deliverables are a documented performance
envelope, hotspot identification, and a regression baseline: committed JSON
snapshots under `benchmarks/results/` plus a comparator that checks a current
run against them.

The specification deliberately defines no performance requirements. This
suite measures; it does not gate conformance.

Timing uses pure ANSI `GET-INTERNAL-RUN-TIME`.

**Batch sizing.** The per-batch operation count `k` doubles until one batch
takes at least `max(floor-ms, 150 timer ticks)`, where `floor-ms` defaults to
10 ms on SBCL/CCL and 20 ms on ECL.

**Warmups and reps.** Each bench runs warmup batches with the identical call
shape, then timed reps — by default 3 warmups and 15 reps on SBCL/CCL,
5 warmups and 25 reps on ECL. ECL uses more conservative parameters:
the calibration gate requires run-to-run median drift under 5% across at
least 3 fresh processes per host. At the common defaults, ECL measured
5.19% against that threshold; with the ECL parameters, Sophie-operation
benches measured 1.3-2.4%. The harness-overhead bench has a
10% ECL drift threshold because its calibration measurement at ~20 ns/op
showed ~1 ns process-to-process spread (5% of 20 ns is 1 ns, at the edge of
meaningful resolution). The committed ECL baseline records 39.5 ns/op for
this bench. This exception affects only harness overhead, not
Sophie-operation benches. A prior one-off 2.4x transient on one bench in
one process did not reproduce across four other fresh processes and is
attributed to environmental load. All values are recorded per record in the
JSON output (`reps`, `warmups`, `floor-ticks` fields), and callers can
override them via `run-benchmarks` keyword arguments.

**GC policy.** `TG:GC` runs before each rep and the GC stays enabled during
the rep — a mid-rep GC is real cost and stays in the headline number.

**Per-op time and reported statistics.** Per-op time is `median(batch)/k`.
Reported statistics are median, min, and MAD. No means, no confidence
intervals.

**Cold-bench floor caveat.** Cold benches (K capped at pool size) and very
cheap operations may not reach the batch-time floor: `floor_reached=false`
in 29/22/21 committed SBCL/CCL/ECL records, respectively; per-op
quantization is coarser at small K.

Measurement invariants:

- Fresh inputs are built per rep, outside the timed region.
- COLD benches consume a fresh unrealized input per call from a pre-built
  pool. Lazy-seq forcing memoizes at the node, so cold and warm are separate,
  labeled benches.
- A global sink is consumed after each batch (dead-code elimination defense).
- The empty-loop overhead is a registered bench of its own and is never
  subtracted from results.
- Work counters and allocation probes never run inside timed reps. The SBCL
  after-GC hook is the exception: an in-batch GC runs its single fixnum INCF
  inside the timing interval.

Host seam: all reader feature conditionals live in `benchmarks/host.lisp`
only; `src/` remains conditional-free.

**ECL size and compile policy.** Per-bench size caps (default 10000 on ECL); compile mode is
recorded per bench (`compiled-function-p`); interpret-only benches are
flagged via the compile-mode record field, and exclusion from cross-host
ratios is applied at the reporting stage (the results tables), not by the
harness.

**ECL heap policy.** On ECL, the host seam pre-grows Boehm's heap at load time to a
named 1 GiB target (`+ecl-heap-target-bytes+`), using runtime-compiled FFI
thunks; loading fails with an error if the achieved size falls short. The
largest observed per-rep batch allocation was about 42 MB: the target heap
size is about 24x that allocation, a heap-size-to-observed-batch-allocation
headroom figure, not a measured margin to Boehm's GC threshold. GC remains
enabled during timed reps.

**Manual ECL heap settings.** For manual ECL runs, a plain byte count in
`GC_INITIAL_HEAP_SIZE` is always safe. Single-letter suffixes were
verified working (`512M` and `1G` both took effect; `1G` produced a
startup heap of exactly 1073741824 bytes), but multi-letter suffixes
such as `512MB` are silently ignored — with `512MB` the heap stayed at
about 13 MB. The benchmark host seam sets its own heap target on load.

Allocation profiling is opt-in and separate from timed reps. After loading
`sophie-lisp/benchmarks` on SBCL, run, for example:

    (sophie-lisp.benchmarks:run-allocation-pass
      :names '(sophie-lisp.benchmarks::doseq-list
               sophie-lisp.benchmarks::seq-map-list)
      :sizes '(10000) :output "benchmarks/results/scratch/allocation.json")

`run-allocation-pass` writes allocation-only JSON (`bytes_per_op`, calls,
bench, size, and provenance), not a timing baseline. It accepts the same
`:categories` and `:names` filters as `run-benchmarks`, an optional `:sizes`
filter and `:calls` count (default 32); setup and warmup are outside the
counter. The measurement includes the sink store and any forcing in the call,
not only traversal nodes. Other hosts return NIL without writing a file.

For eager-traversal changes, the established equivalence check runs the full
test corpus twice: the normal list/vector fast path and a test-only binding
of `sophie-lisp.internal::*force-generic-traversal*` that routes it through
generic `open-view`/`view-step`. Tests compare results, callback counts,
arguments and order, error positions, no-prefetch, and lazy forcing. This
switch is a testing seam, not a user-facing performance option; retain that
pattern for future traversal changes.

### Comparison fairness

Every comparison is labeled with one of three tiers; a bare ratio never
appears. Baseline links may also reference another Sophie bench for
Sophie-internal comparisons (e.g. crafted-collision vs sequential-key
dicts); such internal comparisons carry no tier label — tier labels apply
to Sophie-vs-CL comparisons.

- `:dispatch` — isolates CLOS dispatch and argument processing (e.g.
  `seq-ref` vs `ELT`).
- `:same-op` — the same operation with an explicit semantics caveat in every
  table (e.g. `dict-ref` vs `gethash :test #'equal`: Sophie is persistent,
  structurally equal, and generic; the CL baseline is mutable and direct).
- `:persistent-vs-copy` — `dict-set` vs `copy-hash-table`-then-`setf`;
  caveat: `alexandria:copy-hash-table` is an alexandria utility, not ANSI.

The MAD band is the median +/- MAD, shared by two rules with distinct roles:

- Regression rule (comparator, baseline vs current run): median ratio > 1.15
  AND non-overlapping MAD bands.
- Reporting rule (doc tables): a difference below
  `max(2x combined relative MAD of both sides, 5%)` is printed as `~=`, not
  as a ratio.

### Environment records

Run-level JSON fields are `schema_version`, `host`,
`lisp_implementation_version`, `internal_time_units_per_second`,
`timer_resolution_ticks` (measured timer resolution), `timestamp`,
`machine`, `commit` (the latter two null unless supplied),
`ecl_heap_target_bytes`, and `ecl_heap_achieved_bytes` (null on SBCL/CCL);
they are not repeated per record. Each benchmark record carries `k`, reps,
compile mode, GC count where exposed, cold flag, tier, baseline link, and a
semantics note. `gc_count` is recorded on SBCL via an after-GC hook,
on CCL via `ccl::full-gccount`, and on ECL through the host seam
(the runtime-compiled `GC_get_gc_no` FFI). Historical null-count snapshots
are described in [development history](#development-history-pre-10);
compare GC splits directly in runs with recorded counts. The run-level
heap fields also record the heap remedy's provenance. Bench
names are symbols in the benchmarks package; where a bench name coincides
with an `SL-EXT` export name, the inherited `SL-EXT` symbol is used, so
`:names` filtering must intern names in the benchmarks package.

## Coverage appendix

The completed table below maps every exported `SL-EXT` symbol to a bench name
or "not benched" with a one-line rationale. The 144 count refers to the 144
exported `SL-EXT` symbols and is normative, enforced by
`tests/integration/api.lisp`.

| Symbol | Bench | Rationale / Note |
|---|---|---|
| `*list-delimiter*` | not benched | Runtime reader/print configuration variable — the delimiter printed between successive elements of a list interpolation — not a per-call operation; the reader benches measure literal dispatch, not delimiter configuration. |
| `->` | `thread-first` | Threads 16 through five unary `1+`/`sqrt` steps and expands at compile time to exactly the hand-written nested baseline; runtime equality confirms zero macro overhead. |
| `->>` | `thread-last` | Threads the same steps into the last-argument position, which for unary operators is the sole argument position; both insertion positions are covered against the same nested baseline. |
| `<>` | `hole-thread` | Hole marker consumed by `~>` at expansion time, never a runtime value; benched implicitly inside `hole-thread`, whose steps name the hole explicitly. |
| `?` | not benched | Binding-clause access marker: a `?` clause compiles to `SL:REF` calls, whose dispatch cost is covered by the `:dispatch`-tier `ref-*` matrices. |
| `@` | not benched | Binding-clause access marker: an `@` clause compiles to `SLOT-VALUE` calls; the marker pair adds no dispatch layer of its own beyond the calls the `:dispatch`-tier matrices already measure. |
| `alist-dict` | `alist-dict` | Persistent dict from an N-entry alist; no ANSI counterpart. |
| `as->` | `as-thread` | Expands to a `LET*` chain rebinding the named variable per step rather than direct nesting; the ratio shows the `LET*` temporaries' cost against the nested baseline. |
| `bind` | `bind-destructure` | One nested list pattern clause against hand-written `DESTRUCTURING-BIND`; expansion is compile-time, so runtime should be ~equal, and the expansion step itself is measured by `macroexpand-compile-time`. |
| `collector-accumulate` | `collector-list`, `collector-vector`, `collector-string`, `collector-hashtable`, `collector-dict` | N accumulate calls sit inside every collector bench's timed region, one per source element, across the five targets. |
| `collector-result` | `collector-list`, `collector-vector`, `collector-string`, `collector-hashtable`, `collector-dict` | The finalization step of every collector bench: list reversal, exact-length copy, or table/dict finalization. |
| `compare` | `compare-numbers` | Generic three-way comparison on fixnums against direct `<`. |
| `compose` | `compose-call` | One closure over the same five `1+`/`sqrt` steps as the nested baseline, built outside the timed region; the ratio shows the per-step designator resolution indirection. |
| `cycle` | `cycle-take-cold` | First N cells of a fresh `(CYCLE SOURCE)` replay over an N/10-element list; no CL counterpart, absolute. |
| `dict` | `dict-make-n`, `dict-collect` | The `&rest` constructor as a timed op is covered by `dict-make-n`, loop-built to avoid `CALL-ARGUMENTS-LIMIT` at 100k pairs; the empty `(dict)` seed is measured inside it and `dict-collect`. |
| `dict-alist` | `dict-alist` | Traversal of an N-pair dict into a fresh alist. |
| `dict-collect` | `dict-collect` | Build from prebuilt `map-entry` objects. |
| `dict-count-by` | `dict-count-by` | Counting by `(mod x 10)` against the `ht-frequencies` baseline. |
| `dict-frequencies` | `dict-frequencies` | Occurrence counting against the `ht-frequencies` baseline. |
| `dict-group-by` | `dict-group-by` | Grouping into ten list-valued groups. |
| `dict-keys` | `dict-keys`, `ordered-dict-iteration` | Lazy key seq realized via `seq-into`; also the realization vehicle of the ordered-dict iteration bench. |
| `dict-keys-map` | `dict-keys-map` | Full rebuild mapping `#'1+` over the keys. |
| `dict-member` | `dict-member` | Presence-plus-value membership. |
| `dict-merge` | `dict-merge` | Two-way merge of dicts overlapping in N/10 keys. |
| `dict-merge*` | `dict-merge*` | Three-way merge. |
| `dict-merge-with` | `dict-merge-with` | Merge with `#'+` combining overlapping values. |
| `dict-plist` | `dict-plist` | Traversal of an N-pair dict into a fresh plist. |
| `dict-ref` | `dict-ref-hit-fixnum`, `dict-ref-miss-fixnum`, `dict-ref-hit-string`, `dict-ref-miss-string`, `dict-ref-collision`, `read-after-update-original`, `read-after-update-updated`, `ordered-dict-ref`, `plist-dict-view-ref` | Hit/miss on fixnum and string keys, crafted shared-prefix collisions, the read-after-update sharing pair, ordered-dict lookup, and plist-view lookup. |
| `dict-ref-in` | `dict-ref-in` | Nested lookup along a fixed path. |
| `dict-reduce-kv` | `dict-reduce-kv` | Left fold summing the values. |
| `dict-remove-keys` | `dict-remove-keys` | Rebuild dropping N/2 present keys. |
| `dict-select-keys` | `dict-select-keys` | Rebuild restricted to N/2 present keys. |
| `dict-set` | `dict-set`, `dict-set-new-key`, `ordered-dict-set`, `ordered-dict-set-new` | One persistent update of a present and a fresh key; also the ordered-dict update/insert benches and the insert op of every construction loop. |
| `dict-set-in` | `dict-set-in` | Nested set along a fixed path. |
| `dict-size` | `dict-size` | Entry count against `hash-table-count`. |
| `dict-test` | `dict-test` | Trivial equality-designator accessor, benched at one size for coverage only. |
| `dict-transform` | `dict-transform` | Full rebuild producing a new key and value per entry. |
| `dict-update` | `dict-update` | Read, apply, rebuild. |
| `dict-update-in` | `dict-update-in` | Nested update along a fixed path. |
| `dict-vals` | `dict-vals` | Lazy value seq realized via `seq-into`. |
| `dict-values-map` | `dict-values-map` | Full rebuild mapping `#'1+` over the values. |
| `dict-without` | `dict-without` | One persistent removal against in-place `remhash`. |
| `dict-zipmap` | `dict-zipmap` | Pairing two prebuilt N-element lists. |
| `dictp` | not benched | Trivial one-dispatch type predicate; the generic-dispatch floor is measured by every other bench. |
| `doseq` | `doseq-list`, `doseq-vector`, `doseq-lazy` | Macro runtime over list, vector, and pre-forced lazy seq; CL has no generic iteration equivalent, so absolute. |
| `entry-key` | not benched | Trivial accessor; `map-entry` objects are exercised as inputs by `dict-collect`. |
| `entry-value` | not benched | Trivial accessor; `map-entry` objects are exercised as inputs by `dict-collect`. |
| `equals` | `equals-cons-equal`, `equals-cons-differ-first`, `equals-cons-differ-last`, `equals-vector`, `equals-dict`, `ordered-dict-equals` | Equal and differing lists, vectors, and dicts, plus order-sensitive equality on ordered dicts. |
| `fbind` | `fbind-call` | Establish-and-call shape matching the `LABELS` baseline; the ratio shows the forwarding-cell check and `APPLY` indirection against a direct local call. |
| `fn` | `fn-call` | The expansion wraps a pattern-capable outer lambda (gensym argument, `&rest`, `APPLY` into the native inner lambda); the ratio shows that wrapper's cost against a direct `LAMBDA` call. |
| `gt` | not benched | Same CLOS dispatch shape as `lt` (benched as `compare-numbers`/`lt-numbers`); not separately benched. |
| `gte` | not benched | Same CLOS dispatch shape as `lt`; not separately benched. |
| `hash-code` | `hash-code-fixnum`, `-string`, `-cons-shallow`, `-cons-deep`, `-vector`, `-bignum`, `-rational`, `-float`, `-dict`, `-dict-in-dict`, `-tree`, `-dag`, `-identity-first-call`, `-identity-repeat`, `-flat-overhead` | Every primitive and structural shape, plus the memoization and identity paths. NaN is excluded by design: `hash-code` signals `TYPE-ERROR` there (the spec leaves consequences undefined). |
| `hash-set` | `hash-set-make-n` | Empty-set constructor inside loop-built construction; one variadic call would exceed `CALL-ARGUMENTS-LIMIT` at the larger sizes. |
| `hash-set-p` | not benched | Trivial one-dispatch type predicate; the generic-dispatch floor is measured by every other bench. |
| `if-bind` | not benched | Same pattern-compiler expansion class as `bind` plus a truth test; no distinct plain-CL same-op baseline exists, and the expansion-cost class is covered by `macroexpand-compile-time`. |
| `iterate` | `iterate-take-cold` | Bounded realization of the first N cells of a fresh `(ITERATE #'1+ 0)`; no CL counterpart, absolute. |
| `juxt` | `juxt-call` | One invocation of a prebuilt combiner yielding the list of its constituents' primary values; no idiomatic CL form, so absolute. A hand-written mirror was not benched because juxt's per-call result-list allocation is the quantity of interest; that allocation and the per-step designator resolution are inside the timed call. |
| `lazy-cons` | `lazy-cons-chain-cold`, `deep-chain-realize`, `forcing-overhead`, `memo-hit` | Chains built from `lazy-cons` cells measure the cold forcing floor and deep-chain realization; single `(LAZY-CONS 42 NIL)` cells measure the forcing/memo-hit pair. |
| `lazy-seq` | not benched | Macro expansion is compile-time; runtime is identical to `make-lazy-seq`, the untimed setup of every cold pool entry. |
| `lazy-seq-p` | not benched | Trivial type predicate; the lazy-seq dispatch path is measured by `seqablep-gateway-lazy-seq`. |
| `lt` | `lt-numbers` | Goes through `compare`, against direct `<`. |
| `lte` | not benched | Same CLOS dispatch shape as `lt`; not separately benched. |
| `make-collector-for` | `collector-list`, `collector-vector`, `collector-string`, `collector-hashtable`, `collector-dict` | The raw generic function dispatching on class objects and prototype instances; the creation step of every collector bench and the target-resolution seam behind every `seq-into` call. |
| `make-lazy-seq` | not benched | The untimed `:SETUP` cost of every cold pool entry in the lazy suite; forcing, not construction, is the timed quantity. |
| `map-entry` | not benched | Trivial constructor; `map-entry` objects are exercised as inputs by `dict-collect`. |
| `op` | `op-call` | `(1+ %)` expands to a plain `LAMBDA` with the placeholder as its parameter; ~equality with the direct `LAMBDA` call baseline confirms zero overhead. |
| `ordered-dict` | `ordered-dict-make-sequential`, `ordered-dict-make-random` | Empty constructor inside loop-built sequential and shuffled construction; the ref/set/iteration benches exercise the result. |
| `ordered-dict-p` | not benched | Trivial one-dispatch type predicate; the generic-dispatch floor is measured by every other bench. |
| `plist-dict` | `plist-dict` | Persistent dict from an N-entry plist. |
| `plist-dict-view` | `plist-dict-view-ref` | Read-only view over a live plist, lookup under `eq`. |
| `range` | `range-cold`, `range-warm` | First forcing of a fresh `(RANGE :END N)` against eager LOOP construction, and re-traversal of a pre-forced seq against list re-traversal. |
| `ref` | `ref-vector`, `ref-hashtable`, `ref-dict`, `ref-list` | The generic facade over `ELT`, `GETHASH`, the persistent-dict trie walk, and the list spine walk. `(SETF REF)` — the mutation facade — is not benched: its persistent-update cost is covered by the `dict-set` benches. |
| `repeatedly` | `repeatedly-cold` | First forcing of a fresh `(REPEATEDLY ... :COUNT N)` seq; the per-element callback cost is part of the measurement. |
| `seq-concatenate` | `seq-concatenate` | Two N/2-element lists into one fresh N-element list against CL `CONCATENATE` 'LIST. |
| `seq-count` | `seq-count-list` | Count of the middle fixnum over an N-element list under the default structural test against CL `COUNT`. |
| `seq-count-if` | `seq-count-list` | Predicate path of the benched item-based sibling; same scan machinery. |
| `seq-dedupe` | `seq-remove-duplicates-list` | Adjacent-duplicate sibling; same traversal without the equality set. |
| `seq-drop` | `seq-filter-list` | Selection sibling; same traversal and reconstruction with a position-based keep. |
| `seq-drop-last` | `seq-filter-list` | Selection sibling; suffix drop on the same machinery. |
| `seq-drop-while` | `seq-filter-list` | Selection sibling; predicate-driven prefix drop on the same machinery. |
| `seq-emptyp` | `seq-first-list` | Constant-work traversal primitive beside `seq-first`; also the timed realization op of every lazy bench's traversal. |
| `seq-every` | `seq-every-list` | `#'INTEGERP` over an all-fixnum list against CL `EVERY`; the predicate holds everywhere, so both sides scan fully. |
| `seq-filter` | `seq-filter-list`, `seq-filter-over-dict-keys` | CL `REMOVE-IF-NOT` same-op shape on a list; over lazy dict keys the deferred result construction is the measured work. |
| `seq-find` | `seq-find-list`, `seq-find-keyword-full` | Scan to the middle hit against CL `FIND`, plus the full keyword option set (`:TEST`/`:KEY`/`:START`/`:END`). |
| `seq-find-if` | `seq-find-list` | Predicate path of the benched item-based sibling; same scan machinery. |
| `seq-first` | `seq-first-list` | One CLOS dispatch over constant work against direct `CAR`. |
| `seq-interleave` | `seq-concatenate` | Lockstep sibling; same lazy-outer construction and reconstruction. |
| `seq-into` | `seq-into-list-from-lazy`, `seq-into-vector`, `seq-into-list`, `seq-into-string`, `seq-into-hashtable`, `seq-into-dict`, `seq-into-hash-set`, `seq-into-ordered-dict` | `SEQ-INTO 'LIST` conversion of a pre-forced lazy seq over memoized cells; the facade suite adds one bench per eager target — vector, list, string, hash table, dict, hash set, ordered dict — each collecting a prebuilt source through the collector protocol. |
| `seq-join` | `seq-concatenate` | Collector conversion; reconstruction via the benched concatenate machinery. |
| `seq-keep` | `seq-map-list` | Map callback-mode sibling; same traversal with a nil-filtering callback. |
| `seq-last` | `seq-first-list` | Full O(N) traversal to the final cell; shares the traversal cost shape the seq benches exercise, with `seq-first-list` covering the per-cell dispatch primitive. |
| `seq-length` | `seq-length-list`, `seq-length-on-dict`, `seq-length-on-set` | O(N) list count against `LENGTH`, plus the O(1) count reads on dict and hash-set. |
| `seq-map` | `seq-map-list`, `seq-map-over-lazy` | CL `MAP` 'LIST same-op shape on a list; over a lazy source the deferred result node construction is the measured work. |
| `seq-map-indexed` | `seq-map-list` | Map callback-mode sibling; same traversal with the index passed in. |
| `seq-mapcat` | `seq-map-list` | Map callback-mode sibling; callback results concatenated in reconstruction. |
| `seq-max` | `seq-reduce-list` | Extremum walk is the benched reduce traversal with a comparing callback. |
| `seq-member` | `seq-find-list` | Query sibling of find; same scan with a boolean result. |
| `seq-min` | `seq-reduce-list` | Extremum walk is the benched reduce traversal with a comparing callback. |
| `seq-mismatch` | `seq-position-list` | Query sibling of find/position; same paired traversal. |
| `seq-notany` | `seq-every-list` | Truth machinery shared with the benched `seq-every`; negated quantifier over the same scan. |
| `seq-notevery` | `seq-every-list` | Truth machinery shared with the benched `seq-every`; negated quantifier over the same scan. |
| `seq-partition` | `seq-subseq-vector`, `seq-concatenate` | Lazy-outer structure op; realization cost sits in the lazy matrix, piece reconstruction via the benched subseq/concatenate. |
| `seq-partition-by` | `seq-subseq-vector`, `seq-concatenate` | Lazy-outer structure op; realization cost sits in the lazy matrix, piece reconstruction via the benched subseq/concatenate. |
| `seq-position` | `seq-position-list` | Position of the middle fixnum under the default structural test against CL `POSITION`. |
| `seq-position-if` | `seq-position-list` | Predicate path of the benched item-based sibling; same scan machinery. |
| `seq-reduce` | `seq-reduce-list`, `seq-reduce-over-ordered-dict` | Sum over a list against CL `REDUCE`, plus `:KEY`/`:INITIAL-VALUE` reduction over ordered-dict entries. |
| `seq-reductions` | `seq-reduce-list` | The benched reduce fold plus result-list construction. |
| `seq-ref` | `seq-ref-vector`, `seq-ref-on-lazy` | Vector access at N/2 against direct `ELT` (:dispatch tier), plus the positional fallback walking memoized lazy nodes. |
| `seq-remove` | `seq-remove-list` | Removal of the middle fixnum under the default structural test against CL `REMOVE`. |
| `seq-remove-duplicates` | `seq-remove-duplicates-list` | N/10 distinct fixnums under the structural test against CL `REMOVE-DUPLICATES` under EQL. |
| `seq-remove-if` | `seq-remove-list` | Predicate path of the benched item-based sibling; same traversal and reconstruction. |
| `seq-rest` | `seq-first-list` | Constant-work traversal primitive beside `seq-first`; also the timed realization op of every lazy bench's traversal. |
| `seq-reverse` | `seq-reverse-list` | Materialize-and-reconstruct reversal against CL `REVERSE`. |
| `seq-search` | `seq-position-list` | Query sibling of find/position; same paired traversal. |
| `seq-some` | `seq-every-list` | Truth machinery shared with the benched `seq-every`; same scan with early exit. |
| `seq-sort` | `seq-sort` | Non-destructive sorted copy of a shuffled vector against destructive CL `SORT`; the baseline's already-sorted best case from call 2 is disclosed there. |
| `seq-split` | `seq-subseq-vector`, `seq-concatenate` | Lazy-outer structure op; realization cost sits in the lazy matrix, piece reconstruction via the benched subseq/concatenate. |
| `seq-split-at` | `seq-subseq-vector`, `seq-concatenate` | Lazy-outer structure op; realization cost sits in the lazy matrix, piece reconstruction via the benched subseq/concatenate. |
| `seq-split-with` | `seq-subseq-vector`, `seq-concatenate` | Lazy-outer structure op; realization cost sits in the lazy matrix, piece reconstruction via the benched subseq/concatenate. |
| `seq-stable-sort` | `seq-stable-sort` | Stability-guaranteed sorted copy sharing `seq-sort`'s merge sort, paired with the same CL `SORT` baseline. |
| `seq-subseq` | `seq-subseq-vector` | Vector slice 2..N-2 against CL `SUBSEQ`, same fresh result shape. |
| `seq-substitute` | `seq-substitute-list` | Replacing the middle fixnum with 0 under the structural test against CL `SUBSTITUTE`. |
| `seq-substitute-if` | `seq-substitute-list` | Predicate path of the benched item-based sibling; same traversal and reconstruction. |
| `seq-take` | `seq-filter-list` | Selection sibling; same traversal and reconstruction with a position-based keep. |
| `seq-take-last` | `seq-filter-list` | Selection sibling; suffix keep on the same machinery. |
| `seq-take-nth` | `seq-filter-list` | Selection sibling; strided keep on the same machinery. |
| `seq-take-while` | `seq-filter-list` | Selection sibling; predicate-driven prefix keep on the same machinery. |
| `seq-tree-seq` | `seq-subseq-vector`, `seq-concatenate` | Lazy-outer structure op; realization cost sits in the lazy matrix, piece reconstruction via the benched subseq/concatenate. |
| `seq-trim` | `seq-filter-list` | Trim sibling of the selection family; same traversal with a prefix/suffix cut. |
| `seq-trim-left` | `seq-filter-list` | Trim sibling of the selection family; same traversal with a prefix cut. |
| `seq-trim-right` | `seq-filter-list` | Trim sibling of the selection family; same traversal with a suffix cut. |
| `seqablep` | `seqablep-gateway`, `seqablep-gateway-vector`, `seqablep-gateway-dict`, `seqablep-gateway-hash-set`, `seqablep-gateway-lazy-seq` | The dispatch gateway every seq op pays, on list, vector, dict, hash-set, and lazy seq; absolute, no CL baseline. |
| `set-add` | `set-add` | One persistent insert against `adjoin`. |
| `set-intersection` | `set-intersection` | Intersection of two overlapping persistent sets. |
| `set-member` | `set-member-hit`, `set-member-miss` | Membership hit and miss. |
| `set-minus` | `set-minus` | Difference of two overlapping persistent sets. |
| `set-remove` | `set-remove` | One persistent removal of a present key. |
| `set-size` | `set-size` | Distinct-element count under `equals`, not list length. |
| `set-subset-p` | `set-subset-p` | Subset test of an N/2-element set inside an N-element one. |
| `set-union` | `set-union` | Union of two overlapping persistent sets. |
| `sl-core-syntax` | `read-vector-literal`, `read-hash-literal`, `read-dict-literal`, `read-set-literal`, `read-interpolation`, `read-placeholder-lambda`, `readtable-dispatch-overhead` | The named readtable every reader bench binds around `READ-FROM-STRING`; `readtable-dispatch-overhead` measures its dispatch entries on literal-free source and each literal bench reads under it. |
| `when-bind` | not benched | Same pattern-compiler expansion class as `bind` plus a truth test; no distinct plain-CL same-op baseline exists, and the expansion-cost class is covered by `macroexpand-compile-time`. |
| `~>` | `hole-thread` | Substitutes the threaded value into each step's explicit `<>` hole (bare steps gain it implicitly), expanding to the same nested form; runtime cost is that of the expansion. |

## Development history (pre-1.0)

These observations preserve optimization-round and superseded-baseline evidence;
use the current committed JSON files, not historical recordings, for comparisons.

### Round and stage labels

Optimization round A introduced indexed algorithms and eager traversal.
Round B extended traversal and assessed deferred candidates.
Round C selected the narrow discipline on SBCL alongside CCL and re-recorded
all three host baselines. These are successive performance-improvement passes
over the whole surface; stages label benchmark-suite calibration and coverage.
Work-package codes such as B2, B4, B5c, B6c, and C9 are historical labels
explained by their context in this development history.

### Superseded baseline provenance

Earlier 219-name/776-record
counts described the superseded optimization-round matrix, not this one.

The current SBCL, CCL, and ECL baselines were re-recorded on idle `rhea`
for round C; the committed JSON provenance fields record the measured tree
from pre-1.0 development. The round-B baselines and earlier recordings on
the same host (SBCL/CCL before round B, ECL after the heap remedy) are
superseded for future comparisons. Each host has 1012 records.
Earlier main-machine runs retained in `benchmarks/results/scratch/` are
gitignored, recording-machine-only historical evidence, not part of a fresh
checkout. The prior full-matrix logs' warning status and wall times (SBCL
8:05, CCL 18:57, ECL 53:21) describe those earlier runs only; neither
warning status nor elapsed wall times are asserted for the optimization
re-record.

These are round-C idle-rhea measurements from the committed CCL JSON.
CCL selected the 32-bit combining discipline before round C; round C
extended that discipline to SBCL, not ECL. Unlike the earlier
optimization-round baseline, these timings cover CCL's new path. The
independent fixnum-width mixer seam remains unchanged on all hosts.

Earlier SBCL snapshots and ECL snapshots before the B6c host seam retain
null `gc_count` values.

Historical pre-B4 ECL measurements boxed about 87% of wide 64-bit hashes
in affected reads, allocating about 6.5-16 KB per operation. Round B's B4
load-time mixer seam now selects the fixnum-safe `mix64-limb` mixer on ECL
and CCL; those historical allocation figures do not describe the new path.

The earlier main-machine runs at ~11.7 load average produced sporadic
1.15x+ comparator flags that did not reproduce across runs. The earlier ECL run
took 53:21.

### Resolved ECL measurement artifact

The old ECL baseline had two apparent anomalies: elevations in several
dict/set reads and updates (often @1000, but not tied to that size), and
a warm/cold `range` inversion @10000. They had one harness cause. Each
rep performs full GC, builds its input, then times a batch of `k` calls;
input-build garbage is still live when the batch starts. With adaptive
`k` and the resulting allocation, Boehm crossed its then-current heap
threshold inside some timed batches. A roughly 31-36 ms collection pause,
divided by `k`, raised reported per-op time: at `k=64` by roughly 12-13x,
at `k=2048` by roughly 1.5x. Those affected old cells measured GC
cadence, not Sophie operation cost. Size 1000 was never intrinsically
special: the elevation moved between runs with adaptive-`k` selection.

Causal checks disabled GC around batches or pre-grew the heap: both
eliminated every elevation at every size. GC-free batches under identical
heap pollution ran at clean floors, ruling out fragmentation as the
explanation. Input hashes and trie shapes were host-independent, with
bit-identical ECL/SBCL trie shapes. The proposed bignum-probe explanation
ran opposite to the data: probe hashes were fixnums at the elevated size
1000 and bignums at clean size 10000. These checks rule out the earlier
trie-shape and bignum-probe hypotheses.

The adopted remedy pre-grows Boehm's heap at ECL host-seam
load to 1 GiB (requested and achieved in this run: 1073741824 bytes).
Unlike turning GC off, it preserves the stated policy that GC remains on
during every timed rep; it avoids the observed in-batch threshold
crossings. The largest observed per-rep batch allocation was about 42 MB,
roughly 24x below the heap size; that comparison is *not* a measured
margin to Boehm's collection threshold. At the time of this historical run ECL had no exposed `gc_count`;
B6c now provides it. Preserve target and achieved heap fields when
comparing runs across the seam.

### Historical ECL heap-remedy re-record (now superseded by round-C baseline)

The 53:21 idle-rhea ECL 26.5.5 full-matrix run
re-recorded all 776 cells after the heap remedy, with heap target =
achieved = 1073741824 bytes. All seven frozen validation gates passed
(record count and bench coverage; provenance fields; clean floors on the
ten previously-degraded cells; range warm/cold inversion gone; empty-loop
and calibration stability; comparator scan vs the anomalous baseline;
GC-pause-signature check). Historical examples of anomalous -> remedied
medians (us/op): `dict-update` @1000 527.05 -> 40.29,
`dict-ref-miss-fixnum` @1000 136.35 -> 14.22,
`dict-ref-hit-string` @1000 544.50 -> 51.45,
`set-member-hit` @10000 156.55 -> 13.86, and `range-warm` @10000
26.44850 -> 10.18800 ms (cold then 19.83200 ms). These are *not* the
current round-C medians; neither historical ECL file is a
valid comparison target for future runs. Use the committed baseline instead.

In that historical comparison against the anomalous file, the comparator
reported 119 improved, 638 flat, and 19 regressed of 776. One apparent
regression cluster comprised small fixed-overhead benches at roughly
1.15-1.17x, tracking a 9.9% empty-loop shift (37.7 -> 41.4 ns). Another
comprised allocating benches up to 1.54x: e.g. `cl-subseq` @10000 7.75
-> 11.96 us and `ordered-dict-equals` @10000 7.34 -> 10.65 ms. Those
were observations about the historical heap-remedy run, not evidence of
an optimization-round regression. Sophie `src/` did not change between
those historical recordings; only the harness provenance fields, host
seam, and bench `:note` strings in `benchmarks/core/hashing.lisp` changed.

Fresh-process C9 subset runs of the former victim cells stayed at clean
floors. The 8 former-victim cells (sizes 1000 and 10000 of the 4 C9
benches) differed from that historical full-matrix run by -5.5% to
+9.0%, with only 3 of 8 satisfying the strict MAD-band consistency rule;
the full 16-cell C9 run spanned -6.0% to +9.0%. Subsets are useful
clean-floor smoke checks, not numerically interchangeable with the full
matrix. Full-matrix-only ECL timing regression guidance remains in force.

### Optimization round A: algorithms and eager traversal

Round A added an SBCL-only allocation pass, thresholded indexes, and eager
traversal. The indexed algorithms replace quadratic scans for
`dict-merge-with` (hash-bucket index above
`+dict-merge-with-index-threshold+` = 64 total entries),
`dict-select-keys`/`dict-remove-keys` (requested-key index above
`+dict-requested-key-index-threshold+` = 64), dict/hash-set equality
(right-trie probing above `+equality-probe-threshold+` = 768), and
`seq-remove-duplicates` (seen index above
`+selection-distinct-index-threshold+` = 768). These original round-A
cutoffs were calibrated on SBCL/CCL. The three revised cutoffs below use
post-B4 crossover measurements on SBCL, CCL, and ECL; the requested-key
cutoff remains unchanged. Guarded hash failures fall
back rather than propagating; lazy-seq values are not hashed. Exotic
tests and small sizes use linear paths. First-match order and exact
`:test` call orientation are preserved; only hash/equals call counts can
change, as the specification permits.

The reusable [recalibration procedure](#recalibrating-the-four-index-thresholds)
is in the contributor workflow above.

The requested-key row retains its round-A calibration; the other three
rows reflect the post-B4 SBCL/CCL/ECL same-size crossover sweep:

| Constant | Workload and size unit | Observed crossover / host context | Chosen cutoff |
|---|---|---|---:|
| `+dict-merge-with-index-threshold+` | Two ranged dicts, N/10 overlapping keys; total input entries | Post-B4 SBCL/CCL/ECL crossover 32-64; boundary tie-to-win on all hosts, indexed >=1.5x at 128 and 6.1-7.7x at 1024 | 64 |
| `+dict-requested-key-index-threshold+` | N-pair ranged dict, N/2 present fixnum requests; requested-key count | Between 50 and 100 requests, SBCL 2.6.1 on cube (50: 68/84 us linear/indexed; 100: 202/172 us) | 64 |
| `+equality-probe-threshold+` | Equal-size dicts/sets, unique resident keys; entries per container | Post-B4 crossover 512-1024 on SBCL/CCL, 128-256 on ECL; probes 1.54-2.59x faster at 1024; 768 retains SBCL margin | 768 |
| `+selection-distinct-index-threshold+` | N elements, N/10 distinct fixnums; input element count | Post-B4 crossover 384-768; indexed wins on all hosts at 768 (ECL 1.23x), but is 1.55x slower on ECL at 384; up to 6.9x win by 3072 | 768 |

For the requested-key case the rounded cutoff is inside the observed 50–100
crossover interval rather than strictly below its lower endpoint; a fresh
measurement is needed before claiming a stronger margin.

Internal `do-view-elements` and `make-view-cursor`/`view-cursor-step`
traverse list/vector sources without per-element view nodes; generic
sources still use `open-view`/`view-step`. Converted paths include scalar
find/position/count/every/some/last/min/max; map/filter produce loops
(with direct-build eager-policy results for eager list/vector sources);
reduce/aggregation materialization; `doseq` (no prefetch); and `seq-into`
and container-construction drains. Round B additionally converts `seq-member` (retaining its lazy tail),
`seq-mapcat` inner traversal, `seq-search`/`seq-mismatch`, multi-source
lockstep, and the split/partition families to retained view cursors. Reader
printing remains outside this traversal optimization. The corpus-equivalence test seam is described in Methodology.

Ratios below are the *optimization-round / then-superseded* medians at size
10000 across the three rhea hosts; these historical within-Sophie comparisons
are not CL fairness tiers or round-C ratios. The superseded medians were in
the baselines preceding the optimization-round re-record.

| Bench @10000 | SBCL | CCL | ECL |
|---|---:|---:|---:|
| `dict-merge-with` | 0.017x | 0.026x | 0.021x |
| `dict-select-keys` / `dict-remove-keys` | 0.055x / 0.055x | 0.078x / 0.078x | 0.059x / 0.056x |
| `equals-dict` | 0.233x | 0.537x | 0.202x |
| `seq-remove-duplicates-list` | 0.177x | 0.273x | 0.185x |
| `seq-map-list` / `seq-filter-list` | 0.152x / 0.112x | 0.231x / 0.169x | 0.211x / 0.175x |
| `doseq-list` / `doseq-vector` | 0.048x / 0.056x | 0.029x / 0.034x | 0.043x / 0.065x |
| `seq-into-list` / `seq-into-vector` | 0.206x / 0.289x | 0.356x / 0.381x | 0.292x / 0.328x |
| `seq-reduce-list` / `seq-reverse-list` | 0.158x / 0.279x | 0.124x / 0.407x | 0.098x / 0.353x |

For historical scale, SBCL `dict-merge-with` @10000 fell from 2718031000 ns to
45845000 ns; @1000 the new/superseded ratios are 0.149x (SBCL),
0.237x (CCL), and 0.181x (ECL). Threshold hybrids retain the linear
behavior at small sizes; single small-cell differences should not be
mistaken for a general speedup. An opt-in
*local* SBCL allocation pass, not a committed rhea timing baseline,
measured `doseq` dropping from 160 B/element to zero; map/filter/into
allocation at 0.08-0.35x of before. Indexed dict operations allocate
roughly twice as much, and `equals-dict` @10000 about 3.7x as much:
these are speed-for-allocation trade-offs, not free wins. The exact
allocation ratios are local measurements, not fields in the timed JSON.

### Round B dispositions after the post-B4 baseline

The traversal matrix now covers consumed member tails, mapcat inner pieces,
search/mismatch, lockstep, and full/partial split and partition results; the
`-b` suffix keeps those measurements distinct from the older baseline names.
These benches were workload controls during round B and are included in the
round-C committed three-host matrix. Round B kept the recalibrated merge (64 total entries), equality
(768 resident entries), and distinct (768 input elements) index thresholds;
the requested-key threshold remains 64. The same-size post-B4 crossovers and
worst-host boundary evidence are in the threshold table above.

Three candidates were explicitly deferred, not silently left unconverted:

- **B2 bulk dictionary builder:** local fresh-process 10k collector-dict
  candidate/baseline was 0.973x SBCL, 1.051x CCL, and 1.094x ECL. It missed
  the <=0.70x all-host target and regressed CCL/ECL; the builder was reverted.
  Merge/select/remove integration was not shipped downstream of that rejection.
- **B5c equality:** a fixnum hash prototype improved dict equality to 0.613x
  on SBCL but measured 0.938x on CCL and 1.016x on ECL. Cons/vector loop
  prototypes retaining public component dispatch likewise missed the cross-host
  0.70x target; skipping user hash/equality methods would change semantics.
- **B5d lazy cursor:** direct-step diagnostics found no narrow cursor change
  meeting the 0.75x cross-host consuming-workload target. A large part of
  realization's cost is the benchmark's public `seq-emptyp`/`seq-first`/
  `seq-rest` dispatch, not cursor dispatch; bypassing that protocol would
  change extension behavior. No speculative fast path was shipped.

The round-B headline rows formerly printed here have been replaced by the
round-C JSON measurements above. The round-B traversal and deferred-candidate
evidence remains historical comparison context, not a new timing baseline.

### Re-record drift and regression interpretation

For the earlier optimization re-record against its then-superseded baselines,
comparator regression flags numbered 16 on SBCL, 11 on CCL, and 8 on ECL.
Those historical flags were not correlated with changed code paths. Elevated
`deep-chain-realize` and `iterate-take-cold` cells in the first pass
resolved in the second, while `lazy-over-dict`/`range-warm` appeared;
pure-CL baseline benches also moved in the 1.15-1.5x band. This pointed
to ambient per-process drift, not a demonstrated code regression. ECL
`read-vector-literal` @10 was especially process-sensitive (0.93x-3.24x
over the two passes); monitor reader cells in future full-matrix re-records
rather than treating a lone cell as causal evidence.

The round-C re-record, compared with the round-B baselines, has 259 improved /
730 flat / 23 regressed SBCL records, 160 / 846 / 6 on CCL, and 10 / 1000 / 2
on ECL (1012 records per host).

**Flag classification.** The historical analysis classified 30 regression
flags as ambient, confirmed by isolated rechecks and local probes across
two development stages, and one as a sanctioned hash-change cost: SBCL
`dict-reduce-kv` @100000 at 1.19x. It found zero unexplained regressions.

**Resolved watch item.** Subsequent profiling resolves the earlier
watch-item step from pre-B4 (~14.0 ms) to post-B4 (~21.1 ms), ~1.51x,
as an explained and accepted GC-phase artifact, not a traversal regression.
The genuine build allocation improvement during round B reduced construction
by ~285 bytes per `dict-set` (173 MB to 144 MB per fixture, ~23% faster builds), shifting one
GC from setup into the timed reduction. The pre-B4 ~13.7 ms re-run median
on the same checkout as the recorded ~14.0 ms baseline median was the
artifact: it happened to avoid an in-op GC. With a full GC inserted before
timing as a profiling control, all commits converge at ~22-24 ms with exactly
one in-op GC; this control is not part of the benchmark harness. The timed
path allocates identically (~26.6 MB/op) and has identical `sb-sprof`
hotspots across the measured stages. The round-C hash-change step
(~1.19x) remains sanctioned and shows the same signature: equal op bytes and
GC-free time, with the difference in in-op GC cost.

**Standing guidance.** Earlier baseline JSONs
had null SBCL `gc_count`, so they could not expose these GC splits; new runs
record them. Re-run single-cell flags on unchanged paths under the same
full-matrix conditions before investigating; the current committed baselines
re-anchor future comparisons. The comparator's mechanical >1.15 and
disjoint-MAD flagging rule remains unchanged.

### Round-C SBCL narrow-hash spot check (local, not a baseline)

Before round C, SBCL still selected the wide `mix64-wide` mixer and wide 64-bit combining;
round C selects the fixnum-safe `mix64-limb` mixer *and* 32-bit combining (the narrow discipline). Three interleaved
fresh-process runs per side on the local machine used 5 timed batches,
2 warmups, and a 3 ms adaptive floor. Figures are medians of per-run
medians in ns/op, with the MAD across those three medians (not the
within-run MAD). Before/after share the same registered benchmark inputs.
These local measurements do not replace the idle-rhea full-matrix baseline.

| Cell | Before (median ± MAD) | After (median ± MAD) | Speedup |
|---|---:|---:|---:|
| hash-code cons-shallow @10 | 5,735 ± 56 | 1,938 ± 1 | 2.96x |
| hash-code cons-shallow @100 | 8,686 ± 25 | 2,845 ± 10 | 3.05x |
| hash-code vector @100 | 24,672 ± 47 | 6,012 ± 0 | 4.10x |
| hash-code string @100 | 9,633 ± 96 | 2,774 ± 2 | 3.47x |
| hash-code cons-deep @7 | 4,455 ± 42 | 1,356 ± 2 | 3.29x |
| hash-code dict @100 | 85,281 ± 1,000 | 23,953 ± 63 | 3.56x |
| dict-ref-hit fixnum @10000 | 378.1 ± 3.9 | 126.6 ± 0.2 | 2.99x |
| dict-ref-hit string @10000 | 2,140.6 ± 0.7 | 764.4 ± 1.8 | 2.80x |
| equals-dict @10000 | 5,757,000 ± 12,000 | 2,133,000 ± 51,000 | 2.70x |
| dict-set @10000 | 859.9 ± 0.5 | 559.1 ± 0.3 | 1.54x |

Two interleaved fresh-process runs per side on CCL and ECL (same 5/2/3
parameters) spot-checked hash-code vector @100 and dict-ref-hit fixnum
@10000. CCL before/after cross-run medians (ns/op): 26,043/26,176 and
513.6/511.5; ECL: 125,953/120,531 and 2,273.9/2,274.2.
These small samples show no systematic regression; ECL vector readings
are noisy (before-run MAD 6,828 ns). A ten-value CCL hash corpus and its
property tests still cover its pre-round-C combining path; committed
golden pins now cover ECL, SBCL, and CCL independently of those properties.

**Historical baseline caveat:** The local round-C spot check above is
not the committed full-matrix oracle. The three committed round-C JSON files
were re-recorded on idle rhea for the selected hash disciplines, including
SBCL's new narrow path and CCL's pre-round-C path. Compare future
full-matrix runs against those files, with matching host and parameters.
Round-B and earlier timings and ratios remain evidence only for their recorded
development stages; in particular, the round-B SBCL hash-sensitive cells
do not represent round-C performance.
ECL's combining discipline did not change in round C, but its current
committed timing oracle is also the round-C re-record.
