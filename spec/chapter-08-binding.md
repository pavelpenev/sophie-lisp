# Chapter 8: Binding, Destructuring, and Threading

This chapter defines forms for value and function-namespace binding, a shared
language of destructuring patterns, conditional binding, and utilities for
threading values through computations. All of these facilities are additive;
Common Lisp binding and function-call semantics remain unchanged.

Sophie defines no `SL:LET`, `SL:LET*`, or `SL:DESTRUCTURING-BIND`. The ANSI
standard forms `CL:LET`, `CL:LET*`, and `CL:DESTRUCTURING-BIND` retain their
original semantics.

## 8.1 Concepts

### 8.1.1 Destructuring Patterns

A **destructuring pattern** describes bindings established from one subject
value. The grammar is shared by `SL:BIND`, `SL:FN`, and `SL:DOSEQ`:

```text
pattern        ::= non-nil-symbol
                 | NIL
                 | list-pattern
                 | vector-pattern
                 | entry-pattern
list-pattern   ::= ( {destructuring-element}* )
                 | ( {destructuring-element}+ . pattern )
entry-pattern  ::= (:ENTRY pattern pattern)
vector-pattern ::= #( {pattern}* )
destructuring-element ::= lambda-list-keyword | pattern
lambda-list-keyword ::= &OPTIONAL | &REST | &KEY | &ALLOW-OTHER-KEYS
                      | &AUX | &WHOLE | &BODY | &ENVIRONMENT
optional-entry ::= pattern [init-form [supplied-p]]
key-entry      ::= pattern [init-form [supplied-p]]
                 | (keyword-name pattern) [init-form [supplied-p]]
rest-entry     ::= pattern
aux-entry      ::= pattern [init-form]
whole-entry    ::= pattern
body-entry     ::= pattern
environment-entry ::= variable
```

A non-`NIL` symbol pattern binds the symbol to the complete subject. A symbol
whose name is `_`, in any package, is ignored: the subject is accepted without
establishing a binding. Every other symbol in a binding position must be
permitted to name a variable. A symbol pattern naming a globally declared
special variable receives the dynamic binding that `LET*` would establish.
`NIL` in pattern position is the empty list pattern; it matches an empty list
and establishes no bindings, and is not a symbol pattern.

A list pattern is interpreted as a destructuring lambda list. `&OPTIONAL` entries
use `optional-entry`, and `&KEY` entries use `key-entry`; `&REST`, `&AUX`,
`&WHOLE`, and `&BODY` entries use their corresponding ordinary
`DESTRUCTURING-BIND` forms. Init forms and supplied-p variables occur exactly
where ordinary `DESTRUCTURING-BIND` syntax permits. `&ENVIRONMENT` is a
lambda-list keyword, never a pattern variable; invalid placement signals
`PROGRAM-ERROR` at macro-expansion time.
Before its elements are parsed as patterns, they are checked for the
`DESTRUCTURING-BIND` lambda-list keywords `&OPTIONAL`, `&REST`, `&KEY`,
`&ALLOW-OTHER-KEYS`, `&AUX`, `&WHOLE`, `&BODY`, and `&ENVIRONMENT`; recognized
keywords retain their `DESTRUCTURING-BIND` meanings. All remaining binding
positions are recursively parsed as patterns. A dotted tail is a pattern
applied to the remaining tail of the subject. The ordinary
`DESTRUCTURING-BIND` rules govern list structure and mismatch conditions;
Sophie adds recursive vector and entry patterns at binding positions without
otherwise changing those rules.

A list whose first element is the keyword symbol `:ENTRY` is always
an entry pattern and is never interpreted as a list pattern. An entry pattern
has exactly the form `(:ENTRY key-pattern value-pattern)`. It requires an
`SL:MAP-ENTRY` subject, processes *key-pattern* first against `SL:ENTRY-KEY`,
then processes *value-pattern* against `SL:ENTRY-VALUE`. These three names are
defined in Chapter 4. Entry patterns may occur at any pattern depth. A dotted
cons pattern applies to a cons and does not project an `SL:MAP-ENTRY`.

A vector pattern uses standard literal-vector syntax `#(...)`; it is data, not
an evaluated vector expression. Its subpatterns are processed in index order
against values obtained by calling `SL:REF` with successive zero-based integer
keys. Pattern matching dispatches through `SL:REF`, which checks the dict
protocol first and then the sequence protocol; a more-specific direct method on
`SL:REF` takes precedence over the facade. More subject elements than
subpatterns are ignored. For a sequence
subject, exhaustion before all subpatterns are supplied signals an error of
type `TYPE-ERROR`. For a keyed subject, each integer is a key and an absent key
supplies `NIL` under the no-default `SL:REF` contract. Subpatterns are applied in index order using `SL:REF`; exhaustion, absent-key, and traversal-view behavior follow `SL:REF` and Chapter 4.

Pattern syntax is inspected without evaluation. The enclosing construct
obtains each subject once, and each vector or entry projection is performed
once. Entry patterns process key before value, `SL:FN` applies required-argument
patterns from left to right, and vector patterns project in increasing index
order. An ignored nested `_` suppresses only its binding; the projection that
obtains the value still occurs.

Expansion-introduced operator and binding-form names are the corresponding
external symbols of `SOPHIE-LISP` or `COMMON-LISP`. Generated variables are
fresh uninterned symbols. A conforming expansion does not capture program names,
does not permit program forms to capture its generated variables, and does not
make those variables accessible to the program at runtime.

The following condition cases are specified; other conditions may also be signaled.

| Situation | Condition and time |
|---|---|
| Malformed pattern or clause syntax | `PROGRAM-ERROR` at macro-expansion time |
| `(:ENTRY key value)` applied to a non-`SL:MAP-ENTRY` subject | `TYPE-ERROR` at runtime |
| A sequence subject is exhausted while satisfying a vector pattern | `TYPE-ERROR` at runtime |
| An ordinary list pattern does not match | The condition prescribed by `DESTRUCTURING-BIND` |
| `SL:REF` has no method more specific than the `T` facade method and its subject is neither `SL:DICTP` nor `SL:SEQABLEP` | `TYPE-ERROR` at runtime; supplying a default does not suppress it |

`SL:FN` inherits the conditions that the corresponding `SL:BIND` pattern
application would signal. `SL:DOSEQ` is defined in Chapter 4 and otherwise uses
the same pattern conditions. Chapter 4 reserves for `SL:DOSEQ` an outer proper
two-element binding form whose first element is a proper two-element list
whose second element is a symbol, for indexed iteration; apart from that
context, the grammar above applies as specified.

**Declaration bodies.** `SL:BIND`, `SL:FN`, `SL:DOSEQ`, and `SL:WHEN-BIND`
admit zero or more leading `(DECLARE ...)` forms in their bodies. The
specifiers are interpreted with their ordinary Common Lisp meanings, including
`TYPE`, `IGNORE`, `IGNORABLE`, `SPECIAL`, `OPTIMIZE`, and `DECLARATION`, as well
as applicable implementation- or user-defined declaration specifiers. A
conforming implementation need not provide compiler diagnostics beyond those
required by Common Lisp.

A declaration naming a variable introduced by the enclosing Sophie construct
is a bound declaration. It applies from establishment of the corresponding
binding through that binding's scope, including subsequent clause initializers.
A declaration naming a repeated variable applies to every binding of that name
introduced by that construct, including bindings introduced by destructuring.
Different declarations for successive bindings with the same name require
nested constructs. `SPECIAL` therefore affects each corresponding binding when
it is established, rather than merely declaring references in the final body.
`IGNORE` and `IGNORABLE` attach to the corresponding actual binding; they do not
suppress evaluation of its subject or destructuring projections.

A declaration concerning a variable not introduced by the enclosing Sophie
construct is a free declaration. Non-variable declarations such as `OPTIMIZE`
are also free declarations; `OPTIMIZE` does not declare a variable. Free
declarations in an admitted body govern only that body's subforms: they do not
govern clause initializers, destructuring defaults, or the `SL:DOSEQ` source
expression. In `SL:WHEN-BIND`, they govern only the successful body and not the
tested expressions. In `SL:DOSEQ`, all leading declarations precede the remaining
implicit `TAGBODY`; tags, `GO`, and the implicit `NIL` block retain their existing
meanings.

`SL:IF-BIND` has no declaration slot and introduces no declaration or branch
syntax. Its then-form and else-form remain ordinary expressions; a program may
use `LOCALLY` within either expression when a declaration is needed, but
`LOCALLY` does not substitute for establishing a special binding.

### 8.1.2 Binding Clauses

`SL:BIND`, `SL:IF-BIND`, and `SL:WHEN-BIND` use binding clauses. Marker clauses
are clause syntax, not destructuring patterns:

| Clause | Meaning |
|---|---|
| `(`*variable expression*`)` | Bind one value. |
| `(`*variable1 variable2 ... expression*`)` with at least two variables | Bind successive multiple values. |
| `(`*compound-pattern expression*`)` | Apply a list, vector, or entry pattern. |
| `((`*access-binding...*`) SL:?` *expression*`)` | Bind values obtained with `SL:REF`. |
| `((`*access-binding...*`) SL:@` *expression*`)` | Bind values obtained with `SLOT-VALUE`. |

An *access-binding* is either a variable or `(variable key)`. A bare binding
uses the variable symbol as the key or slot name. In an explicit pair, *key* is
a literal key or slot name and is quoted rather than evaluated. An `SL:?`
clause calls `SL:REF` without a default and binds only its primary value; an
`SL:@` clause calls `SLOT-VALUE`. The object expression is evaluated exactly
once before accesses, and accesses proceed from left to right. An empty
access-binding list is permitted: the object expression is evaluated exactly
once, no accesses are performed, and no bindings are established.

A bare `_` access-binding suppresses the access. An explicit `(_ key)` performs
the access and discards its result, so conditions from that access are still
signaled. This differs from `_` within a pattern, where obtaining the
corresponding component remains part of pattern application.

Marker recognition by symbol name occurs only in the second position of a
binding clause, between its variable and expression. A marker named `?` or `@`
must occur in a three-element marker clause and must be the symbol `SL:?` or
`SL:@`, respectively. Thus `(x foo:? 5)` is recognized as a marker clause and
rejected as a non-`SL:?` marker with `PROGRAM-ERROR`; it is not a simple binding.
The access-binding list must be proper and contain only symbols or proper
two-element pairs. Symbols named `?` or `@` appearing elsewhere, including in
expression positions, variable positions, or nested forms, are not recognized
as markers. They remain prohibited as binding-variable names, as specified in
the `SL:BIND` entry. Marker recognition for `?` and `@` is by symbol name; recognition of
`SL:<>` is by symbol identity. For `SL:~>`, `SL:<>` is recognized only as a direct
argument of the step operator, not recursively inside nested or quoted forms.

Non-marker clauses are classified by exact arity. A two-element clause whose
first element is a symbol other than `NIL` is a simple binding. A two-element
clause whose first element is a list, including `NIL`, or a vector is a
compound-pattern clause; entry-pattern precedence is specified in Section
8.1.1. A clause with three or more elements is a multiple-value clause whose
elements except the last are variables. Any other shape is malformed. If a
multiple-value expression produces fewer values than variables, the remaining
variables are bound to `NIL`.

`SL:BIND` processes clauses sequentially. Each value form is evaluated once in
an environment containing earlier bindings, and the body is evaluated after
all bindings have been established. A clause `(_ expression)` therefore still
evaluates *expression*.

### 8.1.3 Function-Namespace Binding

`SL:FBIND` establishes local names in the function namespace for function
objects computed at runtime. Function expressions are evaluated eagerly from
left to right. All local names are visible in every function expression and in
the body, permitting self-reference and mutual reference by closures after all
function expressions have completed evaluation. A call to a local name before
its corresponding function expression has completed signals `PROGRAM-ERROR`;
a non-function result signals `PROGRAM-ERROR` at runtime when its binding is
established. The representation of local names and the machinery used to
provide these guarantees are unspecified. The body admits declarations under
`CL:LABELS` semantics; they apply to the entire body, including `OPTIMIZE`
declarations and declarations concerning surrounding variables.

### 8.1.4 Destructuring Parameters

`SL:FN` admits the patterns of Section 8.1.1 in required parameter positions.
The pattern receives the argument in that position, and recursive destructuring
occurs before the body is evaluated. Entry patterns therefore allow a function
to receive an `SL:MAP-ENTRY` element directly, while dotted patterns naturally
receive cons entries.

The `SL:?` and `SL:@` markers are not admitted because they bind components by
name rather than consuming an argument position. Optional, rest, keyword, and
auxiliary parameters retain their ordinary lambda-list roles and introduce
plain variables rather than Sophie patterns. Pattern mismatches and malformed
patterns follow Section 8.1.1.

### 8.1.5 Conditional Binding

`SL:IF-BIND` and `SL:WHEN-BIND` process clauses sequentially but test each
clause before establishing its bindings. A clause's value form is evaluated
exactly once, and its primary value is tested. If that value is false, the
clause is not destructured and no later clause is evaluated. If it is true, all
values produced by the form remain available to the clause's binding operation.

Earlier successful bindings are visible to later value forms and to the success
body. An empty clause list succeeds trivially; the then-form (or body) is
evaluated with no bindings established. The failure branch of `SL:IF-BIND` is
evaluated in the original lexical environment, with none of the clause bindings
visible. If a clause names a globally special variable, its dynamic binding is
unwound before the else-form is evaluated; the else-form runs in the original
dynamic environment. `SL:WHEN-BIND` instead returns `NIL` on failure.

For either macro, a first argument that is a two-element list whose first
element is a symbol is the single-clause shortcut; every other first argument
is interpreted as a clause list.

For a marker clause, the tested value is the object produced by the clause's
expression, not a value extracted from that object. To test an extracted value,
bind an explicit `SL:REF` or `SLOT-VALUE` call in a simple clause. To distinguish
a stored `NIL` from an absent key, test the `present-p` value returned by
`SL:REF`.

### 8.1.6 Threading

The threading macros `SL:->`, `SL:->>`, `SL:AS->`, and `SL:~>` are defined by
syntactic rewrites performed at macro-expansion time. `SL:->` inserts the
threaded form as the first argument of each step, `SL:->>` inserts it as the
last argument, `SL:~>` replaces an `SL:<>` hole, and `SL:AS->` establishes
successive `LET*`-style bindings of a caller-named variable.

A step of `SL:->`, `SL:->>`, or `SL:~>` is either a non-keyword symbol naming
an operator or a proper list `(`*operator* {*argument*}`)` whose operator is a
non-keyword symbol. A bare non-keyword symbol *op* is treated as `(`*op*`)` by
`SL:->` and `SL:->>`, and as `(`*op* `SL:<>`)` by `SL:~>`. A dotted list step is
malformed. A keyword is not a function name: a bare keyword step or a list step
whose operator is a keyword is malformed for these three threading macros. A step
of `SL:AS->` is an arbitrary form, including a keyword constant, and is not
classified or rewritten by these step rules.

The syntactic rewrite is the primary normative semantics. When all rewritten
steps are function calls, the initial form is evaluated exactly once, each
nonfinal step contributes only its primary value to the next call, and the
final call returns all its values. With no steps, `SL:->`, `SL:->>`, and
`SL:~>` return all values of the initial form. When a rewritten step invokes a
macro or special operator, its expansion is the specified syntactic rewrite
itself; that expansion may evaluate the threaded form as many times as the
macro or special operator's semantics require.

`SL:AS->` establishes ordinary successive bindings of *var*. Its expansion is
equivalent in binding and evaluation behavior to

```text
(LET* ((var initial-form)
       (var step-1)
       ...
       (var step-n-1))
  step-n)
```

where at least one step is present and each *step* is left as written. Each
initializer and the final step is evaluated exactly once; each intermediate
binding receives the primary value of its initializer, and the final step
returns all its values. The initial form and every step therefore use ordinary
Common Lisp lexical, special-variable, closure, shadowing, quotation,
backquote, and macro-expansion semantics. In particular, no occurrence scan,
replacement, or mandatory reference to *var* is performed. A step may ignore
its binding or return a keyword constant.

For `SL:AS->`, *var* must be a permitted variable-name symbol, not a keyword,
`NIL`, `T`, a name established by
`DEFCONSTANT`, or a marker symbol named `?` or `@`. At least one step is
required; supplying no step is malformed. The `SL:->`, `SL:->>`, `SL:~>`,
`SL:OP`, and `#^()` contracts are unaffected by `SL:AS->`.

`SL:~>` recognizes a hole by symbol identity. Only the symbol `SL:<>` itself,
as a direct argument of a step operator, is a hole, and exactly one direct
occurrence is required in each list step. Replacement is not recursive; nested
or quoted occurrences are ordinary symbols.

### 8.1.7 Reference Protocol

For `SL:ORDERED-DICT`, `SL:REF` and `SL:DICT-REF` interpret an integer as a
key and return its associated value and presence, never a positional entry.
`SL:SEQ-REF` instead uses a zero-based stored-order position and returns an
`SL:MAP-ENTRY` and presence. An absent keyed read returns `(values NIL NIL)`
without a default or `(values default NIL)` with one; a present NIL value
returns `(values NIL T)`. A positional miss without a supplied default signals
`TYPE-ERROR`, while a supplied default handles exhaustion as in Chapter 4.

Consequently, a vector destructuring pattern on an ordered dictionary obtains
values at integer keys 0, 1, and so on through the existing dict-first facade;
it does not destructure the first entries in stored order. Use explicit
`SL:SEQ-REF` or convert to a list/vector to destructure positional entries.

`(SETF SL:REF)` on an ordered dictionary delegates to `(SETF SL:DICT-REF)`
and signals `SIMPLE-ERROR`, for present or absent keys and regardless of a
supplied default. No mutation API is added. Positional `(SETF SL:SEQ-REF)`
uses the existing no-writer `SIMPLE-ERROR` contract. Functional updates use
`SL:DICT-SET` as specified in Chapter 9.

`SL:REF` and `(SETF SL:REF)` are generic-function facades over direct methods and
the dict and sequence protocols. A more-specific direct method takes precedence
over the method specialized on `T`. When no such direct method applies, the `T`
method tests `SL:DICTP` first and delegates to the corresponding dict operation;
otherwise it tests `SL:SEQABLEP` and delegates to the corresponding sequence
operation. If neither protocol applies, it signals `TYPE-ERROR`. A getter
forwards whether its optional default was supplied; a setter accepts the default
for place compatibility and ignores its value. A supplied getter default does
not suppress an inaccessible-object error.

A program may define direct getter or setter methods for its own types, or define
the corresponding dict or sequence protocol methods for facade dispatch. It
must not override standardized methods. A direct getter on an object satisfying
`SL:DICTP` is observationally equivalent to `SL:DICT-REF`, and otherwise a
direct getter on an object satisfying `SL:SEQABLEP` is observationally equivalent
to `SL:SEQ-REF`. The corresponding setter methods are observationally equivalent
to `(SETF SL:DICT-REF)` and `(SETF SL:SEQ-REF)`, respectively. Conditions from
direct or delegated methods propagate.

## 8.2 Dictionary

Notes and examples for this chapter appear in Appendix D.

### 8.2.1 Binding

### SL:BIND _Macro_

**Name:** `SL:BIND`, Macro

**Syntax:**
```text
(SL:BIND ( {clause}* ) {declaration}* {form}*) → result*
```

**Arguments and Values:**
- *clause* — a binding clause described in Section 8.1.2; compound patterns are
  defined in Section 8.1.1.
- *expression* — a form evaluated to supply values or a pattern subject.
- *declaration* — a leading declaration form interpreted as specified in Section 8.1.1.
- *form* — a body form.
- *result* — the values of the last *form*, or `NIL` when the body is empty.

**Description:**
`SL:BIND` evaluates its clauses sequentially, establishing each binding before
continuing with the next clause, and then evaluates its remaining body as an
implicit progn. Leading declarations have the scope and ordinary Common Lisp
meanings specified in Section 8.1.1; bound declarations therefore affect a
binding's establishment and any later clause initializers within its scope. The
macro returns the values of its last form, or `NIL` when the body is empty.

**Exceptional Situations:**
Signals an error of type `PROGRAM-ERROR` at macro-expansion time for malformed
clause or pattern syntax; a binding variable that is a keyword, `NIL`, `T`, a
name established by `DEFCONSTANT`, or a marker symbol named `?` or `@`; a
misplaced or non-`SL` marker named `?` or `@`; a nonsymbol in a multiple-value
clause variable position. The consequences are undefined if the same variable
name appears more than once in a single binding clause, including a pattern, multiple-value clause, or
access-binding list; `_` is exempt because it establishes no binding. The
consequences are undefined if a pattern or subject is circular. Runtime pattern
conditions follow the matrix in Section 8.1.1. Conditions signaled by a value
form, `SL:REF`, or `SLOT-VALUE` propagate.

**See Also:**
[Marker Symbols](#marker-symbols); [SL:REF](#slref-generic-function);
[SL:IF-BIND](#slif-bind-slwhen-bind-macros);
[SL:WHEN-BIND](#slif-bind-slwhen-bind-macros).


### SL:REF _Generic Function_

**Name:** `SL:REF`, Generic Function

**Syntax:**
`(SL:REF` *object key* `&optional` *default* `)` → *value*, *present-p*

**Arguments and Values:**
- *object* — an object accessible by a standardized method, by the dict or seq
  facade, or by a user-defined method.
- *key* — an access key accepted by *object*; for a sequence, an integer index.
- *default* — an object returned when a well-formed key is absent. Whether this
  argument was supplied is significant.
- *value* — the associated value, or *default* when supplied and the key is
  absent.
- *present-p* — true if *key* names an element or entry; otherwise false.

**Description:**
`SL:REF` accesses an element or keyed value and always returns two values. A
present key returns the associated value and true, including when the associated
value is `NIL`. An absent key in a hash table, dict, or user-defined keyed object
returns `NIL` and false when *default* is omitted, or *default* and false when it
is supplied.

For a sequence, an integer key follows the `SL:SEQ-REF` normalization rule in
Chapter 4. For a finite sequence of length *L*, a negative integer *i* denotes
the effective position *L* + *i*. An in-range effective position returns the
element and true. An out-of-range but otherwise well-formed index signals an
error of type `TYPE-ERROR` when *default* is omitted; when *default* is supplied
it instead returns *default* and false. A malformed key is not an absent key:
for a sequence, a noninteger key signals an error of type `TYPE-ERROR` whether
or not *default* is supplied.

For a dictionary, including an ordered dictionary, `SL:REF` routes to
`SL:DICT-REF`; integer keys remain dictionary keys, so `(SL:REF dict -1)` looks
up key `-1` and does not select the last entry.

Access semantics and facade dispatch for `SL:REF` are specified in Section 8.1.7.

Access to lists, vectors, and strings corresponds respectively to `CL:NTH`,
`CL:AREF`, and `CL:CHAR` within the applicable active bounds. For a negative
index, CL indexing applies after normalization to the effective nonnegative
position. Access to hash tables is equivalent to `CL:GETHASH`, and the table's
own test function governs key equality.

A direct method must implement the same two-value and supplied-default contract.
When a default is supplied, absence of a well-formed key or sequence exhaustion
returns `(values default nil)` instead of signaling an error. Lookup does not arise merely from an object's
being traversable unless the `T` facade reaches `SL:SEQ-REF` or `SL:DICT-REF`.

**Method Signatures:**
User methods distinguish a supplied default from an omitted default using an
`&OPTIONAL` supplied-p parameter:
`(defmethod SL:REF (object key &optional (default nil default-p)) ...)`.
- `((object list) key &optional default)` — positional list access; reaching a
  dotted tail while traversing the list signals an error of type `TYPE-ERROR`.
- `((object vector) key &optional default)` — positional access within the
  vector's active length; a fill pointer, when present, determines that length.
- `((object string) key &optional default)` — positional character access within
  the string's active length; a fill pointer, when present, determines that
  length.
- `((object hash-table) key &optional default)` — keyed hash-table access.
- `((object SL:LAZY-SEQ) key &optional default)` — positional access; for a
  nonnegative key, forcing through the requested index, and for a negative key,
  forcing the full source to determine its length before selecting the effective
  position.

No method on the aggregate type `CL:SEQUENCE` is standardized.

**Exceptional Situations:**
Signals an error of type `TYPE-ERROR` for a noninteger sequence key, for an
out-of-range sequence key when *default* is omitted, or when list traversal
reaches a dotted tail. Supplying *default* handles only absence or sequence
exhaustion; it does not suppress malformed-key conditions. For a negative lazy
index, determining the effective position requires traversing the full source;
a lazy access need not terminate if that traversal requires nonterminating
forcing. A standard hash-table access follows the error policy of `GETHASH`.
Conditions from delegated or user-defined methods propagate.

**See Also:**
[(SETF SL:REF)](#setf-slref-generic-function); Chapter 4; Chapter 9.


### (SETF SL:REF) _Generic Function_

**Name:** `(SETF SL:REF)`, Generic Function

**Syntax:**
`(SETF (SL:REF` *object key* `&optional` *default* `)` *new-value* `)` → *new-value*

**Arguments and Values:**
- *object* and *key* — as for `SL:REF` and accepted by a writable applicable
  method.
- *default* — accepted to preserve the place argument list and ignored for the
  write.
- *new-value* — the object stored and the sole value returned.

**Description:**
`(SETF SL:REF)` stores *new-value* at *key* and returns *new-value* as its only
value. The *object*, *key*, *default*, and *new-value* forms are evaluated in
standard Common Lisp order, from left to right. The *default* form is evaluated
even though its value is ignored. Access to lists, vectors, and strings supports
in-range element replacement. Access to hash tables supports replacing an entry
and adding an absent key. The optional *default* never makes an absent or
out-of-range place writable. Dispatch and extension rules are specified in
Section 8.1.7.

An `SL:LAZY-SEQ` node is not a writable standardized subject. `NIL` in this
operation is treated as the empty list, so every index is out of range. A direct
user-defined setter method supplies storage for its own subject type.

A write to a hash table being traversed by `SL:DOSEQ` or a sequence operation
modifies that source whether it replaces or adds an entry; its consequences
during the mutation window are undefined under Chapter 4. The same
source-modification rule applies to writes through user-defined methods.

**Method Signatures:**
- `((new-value t) (object list) key &optional default)` — replace an in-range
  list element.
- `((new-value t) (object vector) key &optional default)` — replace an in-range
  active vector element.
- `((new-value t) (object string) key &optional default)` — replace an in-range
  character within the string's active length, as determined by a fill pointer
  when present, with a value acceptable to the string.
- `((new-value t) (object hash-table) key &optional default)` — replace or add
  a hash-table entry.
- `((new-value t) (object SL:LAZY-SEQ) key &optional default)` — signal
  `SIMPLE-ERROR`.

**Exceptional Situations:**
Signals an error of type `TYPE-ERROR` for a malformed or out-of-range standard
sequence index on a writable standardized subject, including when *default* is
supplied, or for dotted-tail traversal. Signals an error of type
`SIMPLE-ERROR` when *object* is an `SL:LAZY-SEQ` node; this takes precedence
over index validation, since the node is not writable regardless of index
validity. A standard hash-table write follows the error policy of
`(SETF GETHASH)`. Conditions imposed by the applicable storage operation,
including a delegated setter such as `(SETF SL:SEQ-REF)`, propagate with their
specified types; for example, a string write requires a character value.

**See Also:**
[SL:REF](#slref-generic-function); Chapter 4; Chapter 9.


### SL:FBIND _Macro_

**Name:** `SL:FBIND`, Macro

**Syntax:**
```text
(SL:FBIND ( {(function-name function-expression)}* )
  {declaration}* {form}*) → result*
```

**Arguments and Values:**
- *function-name* — a symbol naming a local function.
- *function-expression* — a form evaluated to produce a function object.
- *declaration* — a declaration admitted by `CL:LABELS`; it applies to the entire
  body, including `OPTIMIZE` declarations and declarations concerning
  surrounding variables.
- *form* — a body form.
- *result* — the values of the last *form*, or `NIL` when the body is empty.

**Description:**
`SL:FBIND` evaluates function expressions eagerly from left to right. Every local
name is visible in every function expression and throughout the body, permitting
recursive and mutually recursive calls by closures. A call to a local name
before its corresponding function expression has completed signals
`PROGRAM-ERROR`; a non-function result signals `PROGRAM-ERROR` when its binding
is established. The representation used to provide these guarantees is
unspecified. Declarations follow `CL:LABELS` semantics and apply to the entire
body, including `OPTIMIZE` declarations and declarations concerning surrounding
variables.

**Exceptional Situations:**
Signals an error of type `PROGRAM-ERROR` at macro-expansion time for malformed
binding syntax, if a *function-name* is a keyword, `NIL`, `T`, or a symbol
naming a constant variable defined by `DEFCONSTANT`, or if duplicate function
names appear in the same binding list. At runtime, signals an error of type
`PROGRAM-ERROR` when a function expression produces a non-function as its
binding is established, or when a local name is called before its function
expression has completed. Conditions from evaluating or invoking functions
propagate.

**See Also:**
[SL:BIND](#slbind-macro); `CL:LABELS`.


### SL:IF-BIND, SL:WHEN-BIND _Macros_

**Name:** `SL:IF-BIND`, `SL:WHEN-BIND`, Macros

**Syntax:**
```text
(SL:IF-BIND ( {clause}* ) then-form [else-form]) → result*
(SL:IF-BIND (variable expression) then-form [else-form]) → result*
(SL:WHEN-BIND ( {clause}* ) {declaration}* {form}*) → result*
(SL:WHEN-BIND (variable expression) {declaration}* {form}*) → result*
```

*clause* has the complete grammar given for `SL:BIND`.

**Arguments and Values:**
- *clause* — a binding clause described in Section 8.1.2.
- *variable*, *expression* — the components of the single-clause shortcut.
- *then-form* — a form evaluated if every clause succeeds.
- *else-form* — a form evaluated by `SL:IF-BIND` upon failure; defaults to `NIL`.
- *declaration* — a leading declaration form interpreted as specified in Section 8.1.1.
- *form* — a body form evaluated by `SL:WHEN-BIND` after success.
- *result* — the values of the selected branch or successful body.

**Description:**
Both macros evaluate and test clauses as specified in Section 8.1.5. A true
primary value causes that clause's binding operation to be performed; a false
primary
value transfers control without destructuring that clause, establishing its
bindings, evaluating later clauses, or evaluating the body. Earlier successful
bindings are visible to later value forms and to the success branch. An empty
clause list succeeds trivially, with no bindings established. The single-clause
shortcut has the same behavior as a one-element clause list containing
`(variable expression)`.

| Macro | Result on failure |
|---|---|
| `SL:IF-BIND` | Evaluates *else-form* in the original lexical and dynamic environment. |
| `SL:WHEN-BIND` | Returns `NIL`. |

After success, `SL:WHEN-BIND` evaluates its implicit progn body; bound
declarations apply from establishment through their scope, including later
clause initializers, while free declarations govern only the successful body.
A successful empty body returns `NIL`. `SL:IF-BIND` has no corresponding
declaration slot; its branch forms remain ordinary expressions.

**Exceptional Situations:**
Both macros signal the same syntax and pattern conditions as `SL:BIND`, including
`PROGRAM-ERROR` at macro-expansion time for malformed syntax. `SL:IF-BIND`
also signals `PROGRAM-ERROR` for forms beyond *then-form* and *else-form*;
declarations in its branches are not a separate syntax and may be supplied by
an ordinary expression such as `LOCALLY`. Conditions from evaluated forms and
accesses propagate.

**See Also:**
[SL:BIND](#slbind-macro); [SL:IF-BIND](#slif-bind-slwhen-bind-macros);
[SL:WHEN-BIND](#slif-bind-slwhen-bind-macros).


### 8.2.2 Function Binding and Destructuring

### SL:FN _Macro_

**Name:**
`SL:FN`, Macro

**Syntax:**

`(SL:FN` *parameter-list* {declaration}* {*form*}+ `)` → *function*

**Arguments and Values:**

- *parameter-list* — an ordinary lambda list whose required parameters may be
  patterns; not evaluated.
- *pattern* — a pattern defined in Section 8.1.1; not evaluated.
- *declaration* — a leading declaration form interpreted as specified in Section 8.1.1.
- *form* — a body form.
- *function* — a function with the arity given by the corresponding ordinary
  lambda list.

**Description:**

`SL:FN` returns a function whose required parameter positions may contain the
patterns of Section 8.1.1. Its ordinary lambda-list, pattern, marker, and
argument-mismatch behavior follows Sections 8.1.1 and 8.1.4. Leading
declarations are processed before the implicit progn body and have the scope
specified in Section 8.1.1. The body is an implicit progn.

**Side Effects:**

When the returned function is invoked: those of the body forms and of
destructuring each argument, including forcing performed by element access in a
pattern.

**Exceptional Situations:**

Signals an error of type `PROGRAM-ERROR` at macro-expansion time if no body form
is supplied. Conditions from destructuring and body forms propagate.

**See Also:**

[SL:BIND](#slbind-macro).


### 8.2.3 Threading

**Threading Conventions:**
Threading semantics are specified in Section 8.1.6. The entries below state only
their individual syntax, distinguishing rules, and exceptional situations.

### SL:->, SL:->> _Macros_

**Name:** `SL:->`, `SL:->>`, Macros

**Syntax:**
```text
(SL:-> form {step}*) → result*
(SL:->> form {step}*) → result*
```

**Arguments and Values:**
- *form* — the initial form.
- *step* — a step specified in Section 8.1.6.
- *result* — the values of the fully rewritten form.

**Description:**
`SL:->` inserts the threaded form as the first argument of each step; `SL:->>`
inserts it as the last argument. A bare non-keyword symbol *op* is treated as a one-element step `(op)` by either macro. All other threading semantics are specified in Section 8.1.6.

**Exceptional Situations:**
Signals an error of type `PROGRAM-ERROR` at macro-expansion time if a step is a
keyword, or is neither a non-keyword symbol nor a proper list whose `CAR` is a
non-keyword symbol. In particular, a list step whose `CAR` is a keyword and a
dotted step are malformed.

**See Also:**
`SL:AS->`; `SL:~>`; Section 8.1.6.

### SL:AS-> _Macro_

**Name:** `SL:AS->`, Macro

**Syntax:**
```text
(SL:AS-> form var {step}+) → result*
```

**Arguments and Values:**
- *form* — the initial form.
- *var* — a symbol bound successively; not evaluated.
- *step* — an arbitrary form, left as written and evaluated under the successive
  binding semantics of Section 8.1.6.
- *result* — the values of the last step.

**Description:**
`SL:AS->` establishes *var* through ordinary successive `LET*`-style bindings.
The initial form and each step are evaluated exactly once; intermediate steps'
primary values establish the next binding, and the final step returns all its
values. Steps are not scanned or rewritten, so closures, shadowing, quotation,
backquote, macros, special variables, and steps that do not reference *var*
follow ordinary Common Lisp semantics. A keyword constant is therefore a permitted step form. Other
threading semantics are specified in Section 8.1.6.

**Exceptional Situations:**
Signals an error of type `PROGRAM-ERROR` at macro-expansion time if *var* is not
a symbol, or is a keyword, `NIL`, `T`, a name established by `DEFCONSTANT`, or
a marker symbol named `?` or `@`; or if no step is supplied. Conditions from
the initial form and step forms propagate.

**See Also:**
`SL:->`; `SL:->>`; `SL:~>`; Section 8.1.6.

### SL:~> _Macro_

**Name:** `SL:~>`, Macro

**Syntax:**
```text
(SL:~> form {step}*) → result*
```

**Arguments and Values:**
- *form* — the initial form.
- *step* — a step specified in Section 8.1.6.
- *result* — the values of the fully rewritten form.

**Description:**
`SL:~>` replaces the direct `SL:<>` hole in each list step with the threaded
form. A bare non-keyword symbol *op* is treated as a step `(op SL:<>)`. The hole
rule and all other threading semantics are specified in Section 8.1.6.

**Exceptional Situations:**
Signals an error of type `PROGRAM-ERROR` at macro-expansion time if a list step
is improper, its `CAR` is not a non-keyword symbol, or it contains other than
exactly one direct occurrence of `SL:<>`; or if a step is neither such a list nor
a non-keyword symbol, including a bare keyword.

**See Also:**
`SL:->`; `SL:->>`; `SL:AS->`; `SL:<>`; Section 8.1.6.

### Marker Symbols

**Name:** Marker Symbols

**Syntax:**
Marker syntax and recognition are specified in Sections 8.1.2 and 8.1.6.

| Symbol | Role | Owning macro |
|---|---|---|
| `SL:?` | Element-access clause marker | `SL:BIND`, `SL:IF-BIND`, `SL:WHEN-BIND` |
| `SL:@` | Slot-access clause marker | `SL:BIND`, `SL:IF-BIND`, `SL:WHEN-BIND` |
| `SL:<>` | Direct hole in a threading step | `SL:~>` |

These symbols have no independent runtime behavior in their marker roles and
are not recognized as markers outside their owning macros. Their recognition,
access rules, and hole rules are specified in Sections 8.1.2 and 8.1.6. The
binding-variable restrictions specified in this chapter still apply.

**See Also:**
`SL:BIND`; `SL:IF-BIND`; `SL:WHEN-BIND`; `SL:~>`.

### 8.2.4 Function Utilities

### SL:JUXT, SL:COMPOSE _Functions_

**Name:** `SL:JUXT`, `SL:COMPOSE`, Functions

**Syntax:**
```text
(SL:JUXT &rest fns) → function
(SL:COMPOSE &rest fns) → function
```

**Arguments and Values:**
- *fns* — usable function designators.
- *function* — a function.

**Description:**
Both functions resolve designators at call time, not construction time. Symbol
designators are looked up with `FDEFINITION` on each invocation of the returned
function.

`SL:JUXT` returns a function that calls each of *fns* from left to right on the
invocation arguments and returns a list of their primary values in that order.
With no *fns*, it returns a function that returns the empty list for any
arguments.

`SL:COMPOSE` returns `#'identity` with no *fns*. With one function designator,
it returns a function that invokes that designated function, the one-function
identity composition. With two or more, it returns their right-associative
composition: the rightmost function receives the invocation arguments, and each
function to its left receives the preceding call's primary value.

**Exceptional Situations:**
When the returned function is invoked, signals an error of type `TYPE-ERROR`
if any element of *fns* is not a usable function designator. A symbol that is a
macro or special-operator name signals `TYPE-ERROR`. A symbol that names no
global function definition signals `UNDEFINED-FUNCTION`.

**See Also:**
Chapter 1.
