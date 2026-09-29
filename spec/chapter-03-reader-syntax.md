# Chapter 3: Reader Syntax

## 3.1 Reader Concepts

### 3.1.1 The SL-CORE-SYNTAX Readtable

Sophie Lisp defines a readtable named SL-CORE-SYNTAX. In its initial
state, it provides exactly the standard Common Lisp reader syntax together with
the following reader macros:

- `#^(` for lambda shorthand (the `#^()` entry in Section 3.2);
- `#v(` for evaluated vector literals (the `#v()` entry in Section 3.3);
- `#h(` for evaluated hash-table literals (the `#h()` entry in Section 3.3);
- `#d(` for evaluated dict literals (the `#d()` entry in Section 3.3);
- `#u(` for evaluated set literals (the `#u()` entry in Section 3.3); and
- `#?"` for string interpolation (the `#?"..."` entry in Section 3.3).

In its initial state, SL-CORE-SYNTAX preserves every standard reader-macro
definition and defines `#^`, `#v`, `#h`, `#d`, `#u`, and `#?` as dispatch
macros. These dispatch sub-characters are undefined or reserved to the user in
the standard readtable. In its initial state, other character syntax is that of
the pristine ANSI standard readtable, independent of any mutations to the
implementation's *READTABLE* variable. The standard readtable must not be
modified by the construction or activation of SL-CORE-SYNTAX. Dispatch
sub-characters are case-insensitive: `#V(` is equivalent to `#v(`, `#H(` to
`#h(`, etc.

A conforming implementation must provide SL-CORE-SYNTAX as a named readtable.
A program may activate it using standard Common Lisp mechanisms, independently
of its package configuration.

The reader macros return ordinary Common Lisp objects or forms. Every symbol
introduced into a returned form must be either the corresponding symbol external
in SOPHIE-LISP or a fresh uninterned symbol used as a generated lexical variable
name. The name of a generated lexical variable introduced by an expansion must
not begin with the character `%`. The identity of an introduced symbol is
independent of the value of `*PACKAGE*`. A symbol retained from a source form
retains the identity established when that form was read, including any
dependence on `*PACKAGE*`. The operators and constants required by an expansion
are introduced symbols; consequently, reader activation does not require
package activation, as specified in Chapter 2.

Sub-forms contained in Sophie reader syntax are read using the active reader
state, including `*PACKAGE*`, `*READTABLE*`, `*READ-SUPPRESS*`, and
`*READ-EVAL*`. No form described in this chapter is evaluated merely because one
of these reader macros reads it. A read-time evaluation form occurring within an
input form retains its standard Common Lisp behavior.

### 3.1.2 Runtime Construction

The `#v`, `#h`, `#d`, and `#u` reader macros return constructor forms. Their
element, key, and value forms are evaluated when the returned form is evaluated,
in the lexical environment of that form and in their source order. Each evaluation
of a `#v` or `#h` literal produces a fresh mutable container. The identity of a
dict or set produced by `#d` or `#u` is unspecified.

The equivalent forms shown in this chapter are descriptive. Implementations
must not impose a `CALL-ARGUMENTS-LIMIT` restriction on these literals.

Reading a Sophie reader macro has no side effects beyond recursively reading
subforms, except for the in-place placeholder replacement performed by `#^` as
specified in Section 3.2. That replacement may mutate conses or vectors produced
by nested read-time evaluation, including objects produced by `#.` that alias
conses or vectors held elsewhere. The `#^` handler does not evaluate literal
elements merely by traversing them; nested read-time evaluation otherwise retains
its standard Common Lisp behavior. Runtime evaluation of those forms may have
arbitrary effects.

The construction contract for each literal is:

- `#v` evaluates its element forms left to right and returns a vector.
- `#h` evaluates its key and value forms left to right and constructs a hash
  table using the selected test.
- `#d` delegates construction and duplicate-key policy to `SL:DICT`.
- `#u` delegates construction and duplicate elimination to `SL:HASH-SET`.

An interpolated `#?"..."` template likewise returns a form whose interpolation
forms are evaluated at runtime. A template containing no interpolation returns
a string directly.

### 3.1.3 Suppressed Reading

When `*READ-SUPPRESS*` is false, if the required opening delimiter does not
immediately follow its dispatch sub-character and the next character is not end
of file, an error of type `READER-ERROR` is signaled. When `*READ-SUPPRESS*` is
false, the reader macros defined in this chapter signal an error of type
`READER-ERROR` if an infix numeric argument is supplied, or if a `.` token
occurs where a form is expected. This prohibition concerns a standalone dot
where the Sophie reader macro expects a form, not dotted-list syntax within a
recursively read object; Section 3.2 explicitly permits `#^` to traverse nested
dotted lists. These rules apply to all reader macros defined in this chapter. End of file encountered where a required opening delimiter is
expected or before the corresponding closing delimiter signals `END-OF-FILE`,
regardless of `*READ-SUPPRESS*`.

When `*READ-SUPPRESS*` is true, each reader macro defined in this chapter must
consume the complete input belonging to that macro and return `NIL`. Semantic
constraints on the consumed input, including placeholder validity, pair counts,
interpolation contents, and infix numeric arguments, must not be checked. If
the required opening delimiter does not immediately follow its dispatch
sub-character and the next character is not end of file, no error is signaled
and no additional input is consumed beyond what the reader has already
consumed. Conditions necessary to delimit input that has begun may still be
signaled.

### sl-core-syntax _Readtable_

**Name:** SL-CORE-SYNTAX, Readtable

**Description:**

SL-CORE-SYNTAX is a named readtable whose initial state is specified in
Section 3.1.1. Its name is external in SOPHIE-LISP.

**See Also:**

- Section 3.1.1 (The SL-CORE-SYNTAX Readtable)

## 3.2 Lambda Shorthand

Notes and examples for this chapter appear in Appendix D.

### #^() _Reader Macro_

**Name:** `#^()`, Reader Macro

**Syntax:**

`#^(` *expression* `)` → *lambda-form*

**Arguments and Values:**

- *expression* — one expression, read but not evaluated by the reader.
- *lambda-form* — a lambda expression whose parameters are derived from the
  placeholders in *expression*.

**Description:**

`#^` reads one nonempty parenthesized expression and returns a lambda
expression. The input ends with the closing parenthesis of that expression; no
form may follow it as part of the `#^` input. Trailing forms after the closing
parenthesis are not consumed by `#^` and remain in the input stream for
subsequent reads.

The following symbol names are placeholders wherever they occur in
*expression*:

- `%` and `%1` denote the first required parameter;
- `%` followed by digits denoting a positive decimal integer *n* denotes the
  *n*th required parameter; leading zeroes are insignificant, so `%01` denotes
  the same parameter as `%1`; and
- `%&` denotes a rest parameter.

Placeholder recognition and replacement are purely syntactic, are by symbol
name, and are independent of the symbol's package. The traversal domain is the
symbols, conses, and vectors of *expression* as read by `#^`, including objects
introduced by read-time evaluation such as `#.`. It descends through the `CAR`
and `CDR` of each cons and through the elements of each vector. Every other
object is opaque; its contents are not examined. A cons or vector already visited
by identity is not traversed again, so traversal of circular structure
terminates.

Replacement is performed destructively in the form as read. Each placeholder at
a replaceable location is replaced in place. Incidental `EQ` identity and
sharing of the result are unspecified.

Placeholder recognition applies to *expression* as read. In particular, when a
nested `SL:OP` form occurs within *expression*, symbols in that form whose names
begin with `%` are placeholders of the enclosing `#^`; at read time they are
ordinary symbols.

Every placeholder token in *expression* is replaced by the corresponding
generated lexical variable. Each such variable is a fresh uninterned symbol.
All occurrences denoting the same parameter refer to one lexical variable. If
the highest numbered placeholder is `%`*n*, the lambda list has *n* required
parameters. Required parameters not referenced by *expression* must be declared
ignorable. If `%&` occurs, an `&REST` parameter follows the required parameters.
If no placeholder occurs, the lambda list is empty.

Placeholder recognition within an implementation-dependent representation of a
backquote form is implementation-defined and must be documented.

The returned lambda expression has the transformed *expression* as its sole body
form.

**Side Effects:**

The reader macro performs the destructive replacement specified above.

**Exceptional Situations:**

Signals an error of type `READER-ERROR` if the parenthesized expression is
empty or is not a proper list. The proper-list requirement applies to the
top-level expression; nested dotted conses are traversed as ordinary list
structure.

Signals an error of type `READER-ERROR` if a symbol in the traversal domain
specified above begins with `%` and is neither `%`, `%&`, nor `%` followed by a
positive decimal integer. Symbols outside that traversal domain are not
validated as placeholders.

Signals an error of type `READER-ERROR` if the number of generated parameters,
including the `%&` rest parameter, exceeds `LAMBDA-PARAMETERS-LIMIT`.

**See Also:**

- `SL:OP`
- Section 3.1.1 (The SL-CORE-SYNTAX Readtable)

### SL:OP _Macro_

**Name:** `SL:OP`, Macro

**Syntax:**

`(SL:OP` *expression* `)` → *function*

**Arguments and Values:**

- *expression* — one expression containing zero or more placeholders.
- *function* — a function object.

**Description:**

`SL:OP` is the macro form of the lambda shorthand. It performs the placeholder
traversal, validation, and replacement specified for `#^()` over *expression*
as ordinary macro input data. All symbols, conses, and vectors in *expression*
are in the traversal domain; no object is excluded because of how it was read.
Replacement constructs and returns a new form without mutating *expression*.
The outermost expression is replaced when it is itself a placeholder. Incidental
graph identity, sharing, and cycle structure of the result are unspecified.
Traversal must terminate for cyclic structures. Each expansion generates fresh
uninterned lexical variables.

The placeholder syntax and lambda-list construction are those specified for
`#^()`. Placeholder recognition inside an implementation-dependent backquote
representation is implementation-defined and must be documented, as specified
for `#^` in Section 3.2. `SL:OP` is available whether or not SL-CORE-SYNTAX is
active.

**Side Effects:**

Macro expansion does not mutate *expression*.

**Exceptional Situations:**

Signals an error of type `PROGRAM-ERROR` during macro expansion if the macro
form is not a proper list containing exactly one *expression*, if *expression*
contains a symbol beginning with `%` that is not a valid placeholder, or if the
number of generated parameters, including the `%&` rest parameter, exceeds
`LAMBDA-PARAMETERS-LIMIT`.

**See Also:**

- `#^()`

## 3.3 Dispatch Macros

### #v() _Reader Macro_

**Name:** `#v()`, Reader Macro

**Syntax:**

`#V(` {*element-form*} `)` → *vector-form*

**Arguments and Values:**

- *element-form* — a form read but not evaluated by the reader.
- *vector-form* — a form that produces an adjustable vector with a fill
  pointer.

**Description:**

`#v` reads a parenthesized sequence of element forms. If there are *n* element
forms, it returns a form that evaluates the element forms left to right and
produces a fresh adjustable vector of length *n* with a fill pointer whose
value is *n*, as specified in Section 3.1.2.

**See Also:**

- `#h()`
- Section 3.1.2 (Runtime Construction)

### #h() _Reader Macro_

**Name:** `#h()`, Reader Macro

**Syntax:**

`#H(` [*test*] {*key-form value-form*} `)` → *hash-table-form*

**Arguments and Values:**

- *test* — an optional non-keyword symbol named `EQ`, `EQL`, `EQUAL`, or
  `EQUALP`, read but not evaluated.
- *key-form* — a form whose value is used as a hash-table key.
- *value-form* — a form whose value is associated with the preceding key.
- *hash-table-form* — a form that produces a hash table.

**Description:**

`#h` reads a parenthesized sequence. If its first element is a non-keyword
symbol whose name is `EQ`, `EQL`, `EQUAL`, or `EQUALP`, compared without regard
to case, that element specifies the hash-table test and is not evaluated. The
corresponding test is the identically named symbol in the COMMON-LISP package.
Otherwise the test is `CL:EQUAL`, and every element belongs to a key and value
pair.

A keyword is never a test specifier. A quoted symbol is a key form rather than
a test specifier.

The reader returns a form that evaluates the key and value forms left to right
and constructs a hash table using the selected test, as specified in Section
3.1.2. Each evaluation of the returned form produces a fresh hash table. If
more than one evaluated key is the same under the selected test, the value from
the last pair is retained.

**Exceptional Situations:**

Signals an error of type `READER-ERROR` if the number of forms following the
optional test specifier is odd.

**See Also:**

- `#v()`
- Section 3.1.2 (Runtime Construction)

### #d() _Reader Macro_

**Name:** `#d()`, Reader Macro

**Syntax:**

`#D(` {*key-form value-form*} `)` → *dict-form*

**Arguments and Values:**

- *key-form* — a form whose value is used as a dict key.
- *value-form* — a form whose value is associated with the preceding key.
- *dict-form* — a form that produces an immutable dict.

**Description:**

`#d` reads a parenthesized sequence of alternating key and value forms. There
is no test specifier; every form belongs to a key and value pair. The reader
returns a form that evaluates the key and value forms left to right and
delegates construction and duplicate-key policy to `SL:DICT`, the dict
constructor specified in Chapter 9, as specified in Section 3.1.2. Each
evaluation of the returned form produces a dict.

**Exceptional Situations:**

Signals an error of type `READER-ERROR` if the number of forms is odd.

**See Also:**

- `#h()`
- `#u()`
- Chapter 9
- Section 3.1.2 (Runtime Construction)

### #u() _Reader Macro_

**Name:** `#u()`, Reader Macro

**Syntax:**

`#U(` {*element-form*} `)` → *set-form*

**Arguments and Values:**

- *element-form* — a form whose value is used as a set element.
- *set-form* — a form that produces an immutable set.

**Description:**

`#u` reads a parenthesized sequence of element forms. There is no test
specifier. The reader returns a form that evaluates the element forms left to
right and delegates construction and duplicate elimination to `SL:HASH-SET`,
the set constructor specified in Chapter 9, as specified in Section 3.1.2. Each
evaluation of the returned form produces a set containing the distinct
values of the element forms under the set's element test.

**See Also:**

- `#d()`
- Chapter 9
- Section 3.1.2 (Runtime Construction)

### #?"..." _Reader Macro_

**Name:** `#?"..."`, Reader Macro

**Syntax:**

`#?"` {*template-part*} `"` → *string-or-form*

*template-part* ::= *literal-text* | *value-interpolation* |
&nbsp;&nbsp;&nbsp;&nbsp;*list-interpolation*

*value-interpolation* ::= `$` *left-brace* *form*+ *right-brace*

*list-interpolation* ::= `@` *left-brace* *form*+ *right-brace*

*left-brace* ::= the literal left-brace character

*right-brace* ::= the literal right-brace character

**Arguments and Values:**

- *literal-text* — characters copied to the result, subject to the escape rules
  below.
- *form* — a form read but not evaluated by the reader.
- *string-or-form* — a string when no interpolation occurs; otherwise, a form
  whose evaluation produces a string.

**Description:**

`#?` reads a double-quoted template containing literal text and zero or more
interpolations.

`${` *form*+ `}` evaluates its forms as an implicit `PROGN` and writes the
primary value of the last form to the result string using `PRINC`.

`@{` *form*+ `}` evaluates its forms as an implicit `PROGN`. At that point, the
primary value of the last form must be a proper, non-circular list. Its
properness is validated before any element is written to the result string.
Non-circularity is validated before any element is written; a circular list
signals an error of type `TYPE-ERROR`. The value of `SL:*LIST-DELIMITER*` is
read once, before the first element of each `@{...}` interpolation is printed,
and the same value is used throughout that interpolation. The elements are
then written to the result string using `PRINC`, with that value written
between successive elements using `PRINC`.
Consequently, the elements output are those of the list when the interpolation
form was evaluated, even if the original list is subsequently mutated.

Interpolation forms are evaluated in the lexical environment containing the
returned form. They are evaluated from left to right among the literal segments
and other interpolations.

Within literal text, the following escape sequences are recognized:

| Sequence | Character |
|----------|-----------|
| `\$`     | `$`       |
| `\@`     | `@`       |
| `\\`     | `\`       |
| `\"`     | `"`       |
| `\n`     | Newline   |
| `\t`     | Tab       |
| `\r`     | Return    |

A `$` or `@` not followed by `{` is literal text. Forms within an interpolation
are read with `}` terminating the interpolation, except inside nested reader
objects. A `}` contained within an object read as part of a form, such as a
string or character literal, does not terminate the interpolation. Consequently,
a symbol containing `}` cannot be written unescaped inside a template;
escaped-symbol syntax such as `|A}B|` remains available.

If the template contains no interpolation, the reader returns the resulting
string. Otherwise it returns a form whose evaluation produces the result string
using standard Common Lisp output operations.

**Affected By:**

- `SL:*LIST-DELIMITER*` during evaluation of `@{...}`.
- Interpolation output is produced as if by `PRINC`; every component of the
  dynamic printer context that affects `PRINC` affects that output.

**Exceptional Situations:**

Signals an error of type `READER-ERROR` if an interpolation contains no form or
if an unrecognized escape sequence occurs in literal text.

Signals an error of type `TYPE-ERROR` at runtime if the value of an `@{...}`
interpolation is not a proper, non-circular list, including when it is a
non-list atom.

Signals an error of type `END-OF-FILE` if end of file is encountered immediately
after a backslash in literal text.

**See Also:**

- `SL:*LIST-DELIMITER*`
- Section 3.1.2 (Runtime Construction)

### SL:*LIST-DELIMITER* _Special Variable_

**Name:** `SL:*LIST-DELIMITER*`, Special Variable

**Syntax:**

`SL:*LIST-DELIMITER*` → *delimiter*

**Arguments and Values:**

- *delimiter* — any object.

**Value Type:** Any object.

**Initial Value:** A string containing one space.

**Description:**

The value of `SL:*LIST-DELIMITER*` is written with `PRINC` between successive
elements produced by an `@{...}` interpolation.

**Affected By:**

Dynamic bindings of `SL:*LIST-DELIMITER*`.

**See Also:**

- `#?"..."`
