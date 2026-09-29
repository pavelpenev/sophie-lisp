# Chapter 1: Introduction

## 1.1 Scope and Purpose

Sophie Lisp is a conservative, purely additive extension of Common Lisp as
defined by ANSI INCITS 226-1994 (R2004). It defines a set of extensions —
protocols, reader syntax, and utilities — that layer on top of standard Common
Lisp. A Sophie Lisp implementation runs on a conforming Common Lisp
implementation. All ANSI-required behavior is preserved unchanged.

Sophie Lisp specifies a package model (the SOPHIE-LISP package re-exports all
external symbols of the COMMON-LISP package unchanged, alongside supplementary
packages), a readtable (SL-CORE-SYNTAX, providing lambda shorthand, vector,
hash-table, dictionary and set literals, and string interpolation), an
extensible equality, comparison, and hashing protocol, a lazy-seq protocol for traversing
collections with a collector protocol for constructing concrete results, a
generic sequence operation library with consistent naming and equality-based
matching defaults, unified binding and destructuring constructs, and a
dictionary protocol with persistent map and set types. These extensions are
enumerated chapter by chapter in Section 1.2.

Activation is two-dimensional (package, reader); see Section 2.1.3. Standard
Common Lisp code continues to work; symbols also accessible through SOPHIE-LISP
may be written with the `CL:` package prefix when needed.

## 1.2 Organization of the Document

This specification is organized into chapters that follow the structure of the
Common Lisp Hyperspec. Each chapter except Chapters 1 and 3 contains conceptual
material followed by a dictionary of defined names.

The following chapters define the Sophie Lisp core language:

- Chapter 1 (this chapter): introduction, notational conventions, and
  conformance criteria.
- Chapter 2: packages and namespaces.
- Chapter 3: reader syntax and the SL-CORE-SYNTAX readtable.
- Chapter 4: lazy sequences, collections, and the collector protocol.
- Chapter 5: sources — lazy sequence constructors.
- Chapter 6: generic sequence operations.
- Chapter 7: generic equality and comparison.
- Chapter 8: binding, destructuring, and threading.
- Chapter 9: dictionaries and the dict protocol.

Within each chapter, sections are numbered decimally: chapter number, section
number, subsection number (e.g., 7.2.1). A section numbered N.1 contains
conceptual material, and a section numbered N.2 contains the dictionary entries
for that chapter. Chapters 1 and 3 are the structural exceptions: they do not
follow the N.1/N.2 split. Chapter 3's reader-macro entries appear alongside
the relevant conceptual material.

Appendices A (Condition Types), B (Conformance), C (Glossary), and D (Notes and Examples) are informative supplements.

### 1.2.1 Dictionary Entries

Each dictionary entry documents a single name defined by this specification
(symbol, macro, generic function, reader syntax, etc.). Entries are grouped by
protocol where multiple names form a related set (e.g., the collector protocol
groups `SL:MAKE-COLLECTOR-FOR`, `SL:COLLECTOR-ACCUMULATE`, and
`SL:COLLECTOR-RESULT`).

Dictionary entries use the sections defined in Section 1.3.3 (Interpreting
Dictionary Entries).

## 1.3 Definitions

### 1.3.1 Notational Conventions

**Font Key.** Defined names are written in uppercase monospace with the package
nickname uppercase: `SL:EQUALS`, `SL:SEQ-FIRST`. Parameter names in syntax
descriptions are written in *italic*. Code examples and literal expressions
appear in `monospace`.

**Modified BNF Syntax.** Where the syntax of a form is given, a modified BNF
notation is used:

- `[` and `]` enclose optional components.
- `{` and `}` enclose components that may appear zero or more times.
- `|` separates alternatives.
- A trailing `*` indicates zero or more repetitions.
- A trailing `+` indicates one or more repetitions.
- Literal tokens (symbols, keywords) appear in uppercase monospace.
- *expression* denotes any form.

**Evaluation Notation.** In examples, the notation *form* → *result* indicates
that the evaluation of *form* produces *result*; for reader macros it indicates
the result of evaluating the form returned by the reader macro, consistent
with all other examples. Multiple return values are shown separated by whitespace: *form* →
*value1 value2*.

**Designators.** The term *designator* follows Common Lisp convention. A
*function designator* is either a symbol or a function object. Under ANSI
Common Lisp, the consequences are undefined when a symbol used as a function
designator has a global definition as a macro or special operator.

For Sophie operations that invoke callbacks, a *usable function designator* is
either a function object or a symbol with a global definition as a function; a
macro name and a special-operator name are not usable function designators.
Unless an operation entry states otherwise, a callback parameter described as a
function designator requires a usable function designator. An invalid value
signals an error of type `TYPE-ERROR`. This check occurs at the call time of the
Sophie operation that accepts the designator. A symbol that has no global
function definition at the time of a force-time invocation signals
`UNDEFINED-FUNCTION`, not `TYPE-ERROR`.

A *string designator* is a string, a symbol, or a character. When a parameter is
described as a designator for a type, any object of that type may be used.

### 1.3.2 Error Terminology

This specification uses the following vocabulary for error situations:

**Safe code** is code processed in a lexical environment where the `SAFETY`
optimization quality is 3 (the highest setting), per the Common Lisp standard's
definition. **Unsafe code** is code processed with lower `SAFETY` settings that
permit the implementation to omit certain error checks.

| Phrase                           | Meaning                                                                                                                                                                                                    |
|----------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| "Signals an error of type *T*"   | The situation is always detected, in both safe and unsafe code, and an error condition of type *T* is signaled.                                                                                            |
| "Should signal an error"         | The situation is an error. A conforming implementation is required to detect and signal an error in safe code. In unsafe code, the consequences are undefined.                                             |
| "Might signal an error"          | A conforming implementation is permitted to detect the situation and signal an error, but is not required to do so.                                                                                        |
| "Is an error"                    | The situation is an error. A conforming implementation may or may not detect it. If detected, an error is signaled; the condition type is unspecified unless stated. If undetected, the consequences are undefined.                                                                            |
| "The consequences are undefined" | The specification imposes no requirements on the behavior in this situation. The implementation may take any action.                                                                                       |
| "Implementation-defined"         | The implementation must choose a behavior and document it.                                                                                                                                                 |
| "Implementation-dependent"       | The behavior may vary between implementations; there is no documentation obligation.                                                                                                                       |
| "Unspecified"                    | The specification does not say which of several possible behaviors occurs; a conforming implementation may exhibit any of them, need not document its choice, and portable programs must not depend on it. |

Any signaling phrase in this table may be qualified with 'of type *T*' to name the
condition type. When a signaling phrase appears without 'of type *T*', the
condition type is unspecified.

'The consequences are undefined' attaches only to the specific situation
described and does not relax any other normative requirement of the entry unless
that requirement depends on that situation.

The phrase "signals an error of type *T*" indicates an unconditional check. The
phrase "should signal an error" indicates a safe-code-only check. By default,
the implementation's own entry points perform the checks specified by "signals
an error" phrases unconditionally, regardless of the caller's safety settings.
An entry that specifies a safe-code-only check states this explicitly and
describes the consequences in unsafe code. This default governs the checks an
entry specifies in its Exceptional Situations section; type restrictions
described in Arguments and Values are governed by the rule in that section.

The phrases in the table above are error-terminology terms; the standalone
modals of Section 1.3.4 do not govern them, except that "may" in normative text
always carries the Section 1.3.4 meaning.

### 1.3.3 Interpreting Dictionary Entries

Dictionary entries in this specification are structured per the Common Lisp
Hyperspec convention. Not all sections appear in every entry; a missing section
means "not applicable" for that name. Each entry may contain the following
sections:

- **Name**: The defined name and its kind (Generic Function, Function, Macro,
  Reader Macro, Package, etc.).
- **Syntax**: For functions, the lambda list and return value convention. For
  macros and special operators, the macro syntax in modified BNF. For reader
  macros, the character-level syntax. The symbol `→` separates arguments from
  return values.
- **Arguments and Values**: English prose describing each parameter, including
  its type and role. When a parameter has type restrictions, the consequences
  of violating them are undefined unless otherwise stated.
- **Description**: The normative specification of the name's semantics.
- **Method Signatures** (generic functions only): Each standardized method's
  parameter specializers and return value conventions. Method Signatures
  enumerate the required dispatch cases — the argument specializers for which
  specified behavior must be produced. Whether an implementation realizes each
  case as a distinct specialized method or a single general method with internal
  dispatch is an implementation detail, except where the specification explicitly
  requires a specific method to exist.
- **Argument Precedence Order** (generic functions only): Overrides the
  default left-to-right argument precedence order when applicable.
- **Extensibility** (generic functions only): Which specializers user code may
  add a method on, where that is narrower or wider than the general rule in
  Section 1.4.4.
- **Invariant**: A relation the entry's name must satisfy jointly with another
  name of this specification, binding on every method (for generic functions)
  or on the defined behavior (for functions and macros) of both.
- **Side Effects**: What state is modified by evaluation of the form. The word
  "None." indicates no side effects.
- **Affected By**: Dynamic variables, declarations, reader state, or other
  external context that may influence the behavior of the form.
- **Exceptional Situations**: Conditions that may be signaled, organized into
  two categories: conditions detected and signaled, and conditions that may be
  detected. Exceptional Situations sections are not exhaustive. An implementation
  may signal additional conditions not listed here, provided those conditions are
  consistent with the specified behavior.
- **See Also**: Cross-references to related dictionary entries or concept
  sections.
- **Notes**: Advisory material not part of the normative specification. May
  include cross-references, equivalent code, typical usage patterns, or
  implementation guidance.
- **Examples**: Illustrative code. Not part of the normative specification.

Two kinds of entry carry additional sections:

- A **package** entry (Chapter 2) carries **Nickname** or **Nicknames** — the
  package's nicknames, or "None." — and **Use List**, the packages in its use
  list.
- A **special variable** entry carries **Value Type**, the type of object the
  variable may be bound to, and **Initial Value**, the value it holds before any
  program assigns it.

**Normative status.** All dictionary-entry sections other than Notes and
Examples are normative. All numbered concept sections in chapters 2 through 9
are normative. Sections 1.3 and 1.4 of this chapter are normative. Sections 1.1
and 1.2 of this chapter, including subsection 1.2.1, are not normative. Notes
and Examples sections are not part of the normative specification.

### 1.3.4 Graduated Normative Language

Throughout the normative text of this specification, the following terms carry
precise meaning:

| Term           | Meaning                                                                      |
|----------------|------------------------------------------------------------------------------|
| **must**       | Absolute requirement of the specification.                                   |
| **must not**   | Absolute prohibition.                                                        |
| **should**     | Recommended practice; a valid reason is needed to deviate.                   |
| **should not** | Discouraged practice; a valid reason is needed to do it.                     |
| **may**        | Truly optional; the grammatical subject may or may not provide the behavior. |

The verbs "is", "are", "does", and "do" in the present tense assert facts about
the behavior of conforming implementations and programs. They carry the same
force as "must". In normative sections, all unqualified declarative assertions
—including but not limited to "returns," "evaluates," "calls," "binds," and
"signals"—carry the same force as "must" unless governed by another defined
modal or error phrase.

## 1.4 Conformance

### 1.4.1 Conforming Implementations

A conforming Sophie Lisp implementation must satisfy the following requirements:

1. It must run on a conforming Common Lisp implementation as defined by ANSI
   INCITS 226-1994 (R2004).
2. It must provide the three packages specified in Chapter 2, with the names,
   nicknames, use lists, and export relationships defined there. All
   Sophie-defined symbol names are disjoint from the external symbol names of
   the COMMON-LISP package.
3. It must provide the SL-CORE-SYNTAX readtable with the reader macros specified in
   Chapter 3.
4. It must implement all protocols, generic functions, macros, functions,
   special variables, and other names this specification defines, with the
   semantics defined in their dictionary entries.
5. It must document any implementation-defined behavior described in this
   specification.
6. It must not prevent a conforming program from lexically binding any
   Sophie-defined exported symbol as a local variable, excluding symbols
   defined as constants or special variables by this specification.

A conforming implementation may provide additional packages, reader macros,
protocols, and utilities beyond those specified. Such extensions must not
alter the behavior of conforming programs, and are subject to the extension
boundary rules of Section 1.4.4, which bind implementation-provided extensions
as they bind conforming-program extensions.

### 1.4.2 Conforming Programs

A conforming Sophie Lisp program must satisfy the following requirements:

1. It must be written in Common Lisp as defined by ANSI INCITS 226-1994 (R2004)
   with Sophie Lisp extensions.
2. It must not rely on implementation-dependent, implementation-defined, or
   unspecified behavior, or on the consequences being undefined, unless this
   specification explicitly permits a program to rely on that behavior.
3. It must not access unexported symbols of the SL, SL-EXT, SL-USER, or
   SOPHIE-LISP packages via package-internal access (double-colon notation).
4. It must not rely on the SOPHIE-LISP package as a replacement for the
   COMMON-LISP package unless all symbols it defines do not collide with Sophie
   Lisp's export set. If a collision occurs, the program must either qualify
   the conflicting symbol explicitly, use a separate package with explicit
   imports, or use the SL-EXT package to access Sophie symbols without
   re-exporting Common Lisp symbols.
5. It must define methods only within the extension boundary of Section 1.4.4:
   the methods this specification enumerates are closed, and all other
   specializers are open to user-defined methods, except where a chapter
   explicitly closes a generic function to all additional methods (see Chapter
   6).

A program that uses only standard Common Lisp reader syntax and the syntax defined
in Chapter 3, and uses only symbols available from the SL package, Common Lisp,
and third-party libraries, is a conforming program provided it does not violate
the requirements above.

### 1.4.3 Relationship Between Conforming Programs and Conforming Implementations

A conforming Sophie Lisp program, when executed by a conforming Sophie Lisp
implementation, must produce behavior consistent with the semantics defined in
this specification and in ANSI Common Lisp.

If a conforming program uses no Sophie Lisp extension — no reader macro,
generic function, macro, special variable, type, or utility defined herein —
its behavior must be identical to the behavior of the same program executed by
the underlying Common Lisp implementation with COMMON-LISP in the USE list and
the Sophie Lisp system absent, except that the Sophie packages remain visible to
package introspection operations such as `FIND-PACKAGE` and
`LIST-ALL-PACKAGES`, and the SL-CORE-SYNTAX readtable remains visible to
readtable introspection. The *Sophie Lisp system* is the set of packages, the
readtable, and all names defined by this specification. This guarantee applies
to programs that do not introspect the presence of Sophie Lisp packages or
readtable entries. A program that conditionally branches on such introspection
is responsible for the resulting behavior differences. This guarantee has
three parts, each binding on its own:

1. **Package.** Writing `(:USE :SL)` where a program wrote `(:USE :CL)` changes
   nothing about that program's behavior for names that do not collide with
   Sophie Lisp's export set. A program that defines a name colliding with the
   export set must resolve the collision as specified in Section 1.4.2.
2. **Reader.** SL-CORE-SYNTAX occupies only reader forms that the standard
   readtable leaves undefined or reserves to the user. A program that uses no
   Sophie Lisp reader syntax reads identically under either readtable.
3. **Presence.** Loading Sophie Lisp does not modify any existing package, readtable,
   or reader behavior.

### 1.4.4 Conforming Extensions

A conforming extension is first a conforming program: every clause of section
1.4.2 applies to it. An extension may introduce a new collection type, result
target (a type usable with `SL:SEQ-INTO`), or dict type by participating in the
protocols this specification defines.

**Extension boundary.** "Standardized calls" are calls whose specified
dispatch cases have standardized-type specializers — types defined by this
specification or by ANSI Common Lisp — and whose generic function is
enumerated in this specification. A call whose specified dispatch case
includes a user-defined type is not a standardized call, even though the
user-defined type may be a subtype of a standardized type. Classification
is by specified dispatch cases, not by the method-realization strategy an
implementation chooses, as permitted in Section 1.3.3.

Where this specification enumerates the methods of a generic function — naming
the specializers and stating what each does — those methods are closed: user code
must not define a method with the same generic function and the same specializer
tuple as an enumerated method. A more-specific method on a user-defined subclass
that takes precedence through normal CLOS dispatch is not a violation. An
implementation must provide exactly the behavior specified. Closing applies to
the enumerated methods of that generic function only; it does not close methods
on the same specializers in other generic functions. Everywhere else, defining
a method for a non-enumerated specializer is the sanctioned way to extend the
language. A method on a generic function for a non-enumerated specializer is
conforming only when it does not alter any specified behavior of the operation,
including but not limited to return values, required side effects, condition
signaling, evaluation order, callback invocation count and timing, laziness or
forcing behavior, termination properties, and identity guarantees of
standardized calls. This non-interference rule applies to primary methods and
to `:AROUND`, `:BEFORE`, and `:AFTER` methods, and applies per generic
function.

The generic sequence operations in Chapter 6 (functions named `SL:SEQ-*` other
than the protocol primitives in Chapter 4) are closed to additional methods;
participation occurs only through the protocol primitives specified in Chapter
4 and `SL:SEQABLEP` returning `T`.

`SL:ORDERED-DICT` is a standardized concrete type, not an extension example.
Its enumerated Seq, Collector, Dict, and value dispatch cases are specified in
[Chapter 4](chapter-04-lazy-sequences.md#422-seq-protocol),
[Chapter 7](chapter-07-equality-and-comparison.md#712-extensibility-contract), and
[Chapter 9](chapter-09-dictionaries.md#9118-ordered-dictionaries).
Chapter 9's constructor/subclass restrictions apply independently of method
closure. Ordered support does not open Chapter 6 operations to new methods.

A conforming extension that introduces a new collection type, result target, or
dict type must satisfy the protocol requirements specified in the relevant
chapter: Chapter 4 for the lazy-seq and collector protocols, and Chapter 9 for
the dict protocol.

**Reserved package names and nicknames.** "SOPHIE-LISP",
"SOPHIE-LISP-EXTENSIONS", "SL", "SL-EXT", "SL-USER", and any name beginning
with "SOPHIE-LISP." or "SL." are reserved as both package names and nicknames.
Reserved-name matching is case-insensitive. A conforming program must not define
a package with a reserved name or nickname.
