# Appendix A: Condition Types

This appendix is informative. It provides a cross-operation index of condition
assignments made by Chapters 1–9. The dictionary entry for an operation
is authoritative. This appendix does not assign a condition to a situation for
which Chapter 1 leaves the consequences undefined.

This index is non-exhaustive; additional conditions may be signaled.

## A.1 Condition Policy

### A.1.1 Standard Condition Assignments

Sophie Lisp defines no condition types of its own. This specification uses
standard Common Lisp condition types. The following matrix gathers those
assignments for quick reference.

| Situation | Condition type |
|-----------|----------------|
| Argument of the wrong type, including invalid bounds, indices, and counts, or a non-seqable type | **TYPE-ERROR** |
| An element a collector cannot accept because of its type, such as a non-character into a string or a non-`SL:MAP-ENTRY` into a hash table | **TYPE-ERROR** |
| Malformed forms, macro misuse, and invalid keyword combinations detected at macro-expansion or call time | **PROGRAM-ERROR** |
| A zero count or step argument supplied to `SL:SEQ-PARTITION` or `SL:SEQ-TAKE-NTH` | **PROGRAM-ERROR** |
| A required keyword argument not supplied, such as `:predicate` required by `SL:SEQ-TRIM` for a non-string subject | **PROGRAM-ERROR** |
| A malformed target designator or collector option list | **PROGRAM-ERROR** |
| Recursive forcing (Chapter 4) | **PROGRAM-ERROR** |
| Force-time callback arity errors (Chapter 5) | **PROGRAM-ERROR** |
| A `:collision :error` collision in `SL:DICT-MERGE`, `SL:DICT-TRANSFORM`, or `SL:DICT-KEYS-MAP`, including a collision detected under a fallback result test | **PROGRAM-ERROR** |
| Dict callback contract violations, including a transform callback returning other than two values | **PROGRAM-ERROR** |
| A condition signaled by a dict callback, other than a contract violation | Propagates unchanged |
| Dict path structural errors (non-seqable path, non-dict intermediate) | **TYPE-ERROR** |
| Dict path program errors (empty path) | **PROGRAM-ERROR** |
| `(setf SL:REF)` applied to an `SL:LAZY-SEQ` node | **SIMPLE-ERROR** |
| `(setf SL:DICT-REF)` applied to an immutable `SL:DICT` | **SIMPLE-ERROR** |
| `SL:DICT-SET` or `SL:DICT-WITHOUT` applied to a dict type that declines the optional operation | **PROGRAM-ERROR** |
| An empty source to `SL:SEQ-MIN` or `SL:SEQ-MAX` without `:default` | **SIMPLE-ERROR** |
| An empty selected region to `SL:SEQ-REDUCE` without `:initial-value` | **SIMPLE-ERROR** |
| Other runtime-state violations not assigned a more specific condition or explicitly assigned `PROGRAM-ERROR`, including an empty split delimiter, an empty subject to `SL:SEQ-LAST`, or incomparable objects in ordering operations such as `SL:LT`, `SL:SEQ-MIN`, `SL:SEQ-MAX`, or sorting | **SIMPLE-ERROR** |
| Printing with `*PRINT-READABLY*` true of an unreadable object, including an `SL:MAP-ENTRY`, `SL:DICT`, or `SL:HASH-SET` containing one | **PRINT-NOT-READABLE** |
| A source callback, sequence-operation callback, or binding callback referencing, at force time, a symbol designator with no current global function definition | **UNDEFINED-FUNCTION** |
| Reader macro syntax errors | **READER-ERROR** |
| Odd argument count to `SL:ORDERED-DICT` | **PROGRAM-ERROR**, before key protocol calls |
| Non-entry actually emitted into ordered reconstruction, including used partition padding or a supplied NIL reduction state | **TYPE-ERROR**, at call-time reconstruction or the affected piece's forcing point |
| Options supplied to an ordinary ordered Collector, including `:TEST` | **PROGRAM-ERROR** at creation; batch `SL:DICT-COLLECT` instead ignores its test |
| `(SETF SL:REF)` or `(SETF SL:DICT-REF)` on `SL:ORDERED-DICT`; positional write with no writer | **SIMPLE-ERROR** |
| Printing any `SL:ORDERED-DICT` with `*PRINT-READABLY*` true | **PRINT-NOT-READABLE**, even when empty |
| End of file reached inside an object | **END-OF-FILE** |

Zero counts or steps assigned `PROGRAM-ERROR` are excluded from the broad
`TYPE-ERROR` row for invalid counts.

### A.1.2 Specific and Derived Assignments

For a situation covered by this index, an operation entry that names a condition
type controls that assignment; otherwise, the chapter-level policy or protocol
provision that governs the situation serves as the cross-reference, with the
corresponding matrix row providing an informative summary. An operation's inability to proceed does not change the
assigned condition type.

Malformed bounds, indices, or counts, and strict out-of-range access—including
`SL:REF` without an explicit `:default`—are indexed as TYPE-ERROR. A well-formed
out-of-range `SL:REF` supplied with an explicit `:default` returns
`(values default nil)`.

A collector may refuse an element for a reason other than its type, such as its
capacity, a duplicate key, or a closed sink. Such a refusal must signal an
error. The Collector protocol is described in Chapter 4. A duplicate key is not
refusal for an ordered-dictionary Collector; it is accepted under Chapter 9's
first-position/last-association-wins policy.

Leading declarations in `SL:BIND`, `SL:FN`, `SL:DOSEQ`, and `SL:WHEN-BIND` use
ordinary Common Lisp declaration processing; this index assigns no additional
compiler diagnostic to their contents. `SL:IF-BIND` has no declaration slot,
and its branches remain ordinary expressions, including expressions using
`LOCALLY`.

`SL:AS->` retains its variable-name and minimum-one-step syntax restrictions,
but assigns no condition to an unreferenced step or a keyword constant; its
steps use ordinary Common Lisp evaluation.

## A.2 Condition Type Re-exports

The standard Common Lisp condition types used by this specification are
re-exported from the `SOPHIE-LISP` package unchanged, as specified by the package
and operation chapters.

---

**See Also:**

- Chapter 1 (Error Terminology)
- Common Lisp Hyperspec, Chapter 9 (Conditions)
