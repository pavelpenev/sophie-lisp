# Sophie Lisp

Sophie Lisp is a conservative, spec-first, purely additive Common Lisp language
extension. It leaves ANSI Common Lisp behavior unchanged.

## Features

Sophie adds 144 exported symbols. The examples below use the `SL` package
prefix and assume `(asdf:load-system "sophie-lisp")` (see [Getting started](#getting-started)).
The [specification](spec/) defines normative behavior; the [user guide](docs/user-guide.md)
explains day-to-day use.

### Persistent dictionaries, sets, and ordered dictionaries

Immutable dicts and sets use hash-indexed persistent tries; updates share unchanged
structure instead of copying the whole collection. Ordered dicts also retain
stored order. `DICT-SET` returns a new dict without changing the old one:

```lisp
(let* ((old (sl:dict :a 1))
       (new (sl:dict-set old :a 2)))
  (list (sl:dict-ref old :a) (sl:dict-ref new :a)
        (sl:set-size (sl:hash-set 1 1 2))
        (sl:dict-plist (sl:ordered-dict :a 1 :b 2))))
;; => (1 2 2 (:A 1 :B 2))
```

### Lazy sequences

`RANGE`, `ITERATE`, `REPEATEDLY`, and `CYCLE` produce sequences on demand.
Successful realization is memoized, and sequence operations compose before
materialization with `SEQ-INTO`:

```lisp
(sl:seq-into 'list
  (sl:seq-map #'1+ (sl:seq-filter #'evenp (sl:range :end 8))))
;; => (1 3 5 7)
```

### Generic sequence operations

The seqable gateway lets `SEQ-*` operations accept lists, vectors, dicts,
sets, ordered dicts, and lazy sequences. Dicts supply map entries; sets
supply elements. The same operation works on a list and a vector:

```lisp
(list (sl:seq-count-if #'evenp '(1 2 3 4))
      (sl:seq-count-if #'evenp #(1 2 3 4)))
;; => (2 2)
```

### Generic access with `REF`

`REF` reads by position from vectors and other sequences, or by key from
dicts and hash tables; it returns the value and a presence flag. Use
`DICT-SET`, not `(SETF REF)`, to update an immutable dict.

```lisp
(list (sl:ref #(10 20) 1) (sl:ref (sl:dict :a 7) :a))
;; => (20 7)
```

### Binding and function macros

`BIND` destructures sequentially; `FN` accepts parameter patterns, and `OP`
uses placeholders for small functions. Threading macros such as `->>` pass
the prior value as the final argument to each step:

```lisp
(sl:bind (((a b) '(2 3)))
  (sl:->> (list a b 4) (sl:seq-map #'1+) (sl:seq-reduce #'+)))
;; => 12
```

### Reader literals

The optional `SL-CORE-SYNTAX` readtable adds evaluated `#h` hash tables,
`#d` immutable dicts, and `#v` adjustable vectors. Activate it before
reading forms that contain these literals (independently of package use):

```lisp
(named-readtables:in-readtable :sl-core-syntax)
(list (sl:ref #h(:a 1) :a) (sl:dict-ref #d(:a 2) :a)
      (aref #v(3 (+ 1 3)) 1))
;; => (1 2 4)
```

For the full tour, see the [user guide](docs/user-guide.md).

## Getting started

Clone the repository and make its system definition visible to ASDF:

```sh
git clone https://github.com/pavelpenev/sophie-lisp.git
```

In a Lisp image with [Quicklisp](https://www.quicklisp.org/beta/) installed and loaded, install the dependencies and register the cloned directory (adjust the path):

```lisp
(ql:quickload '("named-readtables" "closer-mop" "alexandria" "bordeaux-threads" "trivial-garbage"))
(push #p"/absolute/path/to/sophie-lisp/" asdf:*central-registry*)
```

Alternatively, symlink the cloned directory into `~/quicklisp/local-projects/` before loading. Then try:

```lisp
(asdf:load-system "sophie-lisp")
(sl:seq-into 'list (sl:range :start 2 :end 10 :step 3))
;; => (2 5 8)
```

## Status

Version **1.0.0**. The reference implementation is tested on SBCL, CCL, and ECL
(see the [portability notes](docs/portability.md)).

## Test

The separate `sophie-lisp/tests` system depends on `parachute`. In a clean image,
quickload it before running the suite:

```lisp
(ql:quickload "parachute")
(asdf:test-system "sophie-lisp")
```

## Where to go next

- **Try it:** Follow the quickstart above, then read the [user guide](docs/user-guide.md).
- **Use in production:** Consult the [specification](spec/) for normative behavior and [implementation status and limitations](docs/implementation.md#status-and-limitations) for current constraints.
- **Contribute:** Read the [implementation notes](docs/implementation.md) and [portability notes](docs/portability.md), then run the test command above.
- **Evaluate performance:** See the [benchmarks](docs/benchmarks.md).

Sophie Lisp is distributed under the MIT License.
