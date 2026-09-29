# Sophie Lisp

Sophie Lisp is a conservative, spec-first, purely additive Common Lisp language
extension. It leaves ANSI Common Lisp behavior unchanged.

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
