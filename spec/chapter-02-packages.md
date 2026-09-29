# Chapter 2: Packages and Namespaces

## 2.1 Package Concepts

### 2.1.1 The Sophie Lisp Packages

Sophie Lisp defines three packages: SOPHIE-LISP, SL-USER, and
SOPHIE-LISP-EXTENSIONS. Chapter 1 requires a conforming implementation to
provide all three.

The SOPHIE-LISP package (nickname SL) is the primary package. It uses the
COMMON-LISP and SOPHIE-LISP-EXTENSIONS packages and re-exports their external
symbols (Section 2.1.4). Using it in place of COMMON-LISP makes all external
symbols of COMMON-LISP and all Sophie-defined symbols accessible without
package prefixes:

```lisp
(DEFPACKAGE :my-app
  (:USE :SL))
```

The SL-USER package is the Sophie Lisp analog of COMMON-LISP-USER. It uses
SOPHIE-LISP and exports no symbols.

The SOPHIE-LISP-EXTENSIONS package (nickname SL-EXT) exports the Sophie-defined
symbols alone (Section 2.1.4). It does not re-export COMMON-LISP symbols. Used
alongside the COMMON-LISP package:

```lisp
(DEFPACKAGE :my-app
  (:USE :CL :SL-EXT))
```

Because Sophie-defined symbol names are disjoint from the external symbol names
of the COMMON-LISP package (Chapter 1), this use configuration introduces
no name conflicts.

All package properties specified in this chapter — export sets, use lists,
nicknames, and the absence of exports from SL-USER — describe the initial state
of the packages as supplied by the implementation.

### 2.1.2 Package Names and Nicknames

The package names and nicknames are:

| Package                | Nickname |
|------------------------|----------|
| SOPHIE-LISP            | SL       |
| SL-USER                | None.    |
| SOPHIE-LISP-EXTENSIONS | SL-EXT   |

Reserved package names, nicknames, and prefixes are governed by Chapter 1.

### 2.1.3 Activation Model

Sophie Lisp activation is two-dimensional, and the dimensions are independent:

1. **Package activation** makes Sophie Lisp symbols accessible: using
   SOPHIE-LISP in place of COMMON-LISP, entering SL-USER instead of
   COMMON-LISP-USER, or using SOPHIE-LISP-EXTENSIONS alongside COMMON-LISP
   (Section 2.1.1).
2. **Reader activation** enables the reader macros defined in Chapter 3 by
   activating the SL-CORE-SYNTAX readtable.

A conforming program may use either dimension without the other. Symbols
introduced by reader-macro expansions are symbols external in SOPHIE-LISP or
fresh uninterned symbols, and their identity is independent of the current
package. Symbols retained from source forms retain their package-dependent
identity. Because the operators and constants needed by the expansions are
introduced as external symbols of SOPHIE-LISP, reader activation without package
activation is supported. Reader activation is defined in Chapter 3.

Evaluating `(IN-PACKAGE :SL-USER)` makes all external symbols of COMMON-LISP
and all Sophie-defined symbols accessible without package prefixes; it does
not activate reader syntax.

### 2.1.4 Export Requirements

The Sophie-defined symbols are interned in the SOPHIE-LISP-EXTENSIONS package,
which is their home package.

`ORDERED-DICT` (the class name and ordinary constructor) and `ORDERED-DICT-P`
(the concrete-type predicate) are Sophie-defined external symbols of
SOPHIE-LISP-EXTENSIONS and are re-exported by SOPHIE-LISP. They are specified in
[Chapter 9](chapter-09-dictionaries.md#9118-ordered-dictionaries).

The following dictionary operation symbols are also exported by SOPHIE-LISP:
`SL:DICT-VALUES-MAP`, `SL:DICT-KEYS-MAP`, `SL:DICT-SELECT-KEYS`,
`SL:DICT-REMOVE-KEYS`, `SL:DICT-MERGE-WITH`, `SL:DICT-COUNT-BY`, and
`SL:DICT-REDUCE-KV`.

A conforming implementation must implement the export of symbols from
SOPHIE-LISP such that:

1. Every external symbol of the COMMON-LISP package is external in
   SOPHIE-LISP.
2. Every external symbol of SOPHIE-LISP-EXTENSIONS is external in SOPHIE-LISP.
3. For each name external in COMMON-LISP or SOPHIE-LISP-EXTENSIONS and
   external in SOPHIE-LISP, the symbol objects are identical.

SOPHIE-LISP has no other external symbols. It uses the COMMON-LISP and
SOPHIE-LISP-EXTENSIONS packages.

## 2.2 Dictionary

Notes and examples for this chapter appear in Appendix D.

### `SOPHIE-LISP` _Package_

**Name:** `SOPHIE-LISP`, Package

**Nickname:** SL

**Use List:** COMMON-LISP, SOPHIE-LISP-EXTENSIONS

**Description:**

The primary package of the Sophie Lisp system, whose external symbols are
exactly the external symbols of COMMON-LISP together with the Sophie-defined
symbols (Section 2.1.4).

**See Also:**

- `SL-USER`
- `SOPHIE-LISP-EXTENSIONS`
- Section 2.1.4 (Export Requirements)

### `SL-USER` _Package_

**Name:** `SL-USER`, Package

**Nickname:** None.

**Use List:** SOPHIE-LISP

**Description:**

The Sophie Lisp analog of COMMON-LISP-USER: it uses the SOPHIE-LISP package
and exports no symbols (Section 2.1.1). Entering it activates the package
dimension without reader activation (Section 2.1.3).

**See Also:**

- `SOPHIE-LISP`
- Section 2.1.3 (Activation Model)

### `SOPHIE-LISP-EXTENSIONS` _Package_

**Name:** `SOPHIE-LISP-EXTENSIONS`, Package

**Nickname:** SL-EXT

**Use List:** None.

**Description:**

Exports the Sophie-defined symbols defined by this specification, which have
SOPHIE-LISP-EXTENSIONS as their home package; it does not use COMMON-LISP or
re-export its external symbols (Section 2.1.4).

**See Also:**

- `SOPHIE-LISP`
- Section 2.1.1 (The Sophie Lisp Packages)
