# Chapter 5: Sources

## 5.1 Concepts

### 5.1.1 Source Constructors

A source constructor is a function that produces a lazy sequence. `SL:RANGE`,
`SL:REPEATEDLY`, `SL:ITERATE`, and `SL:CYCLE` are source constructors; they
produce elements on demand. Construction does not traverse an input collection
or invoke a generation function. Forcing, memoization, and lazy-node behavior
are specified in Chapter 4, Section 4.1.3; failed-force retry is specified in
Section 4.1.4.

Each source constructor returns an `SL:LAZY-SEQ` node whose resolution can
be `NIL`. Separate calls produce independent results with independent forcing and
memoization behavior. An empty result is a node that resolves to `NIL`; no source
constructor in this chapter returns `NIL` itself.

`SL:RANGE` produces an arithmetic progression. `SL:REPEATEDLY` produces the
successive values of a zero-argument function. `SL:ITERATE` produces an initial
value followed by successive applications of a one-argument function.
`SL:CYCLE` repeats one traversal view of a seqable source.

A symbol designator supplied to a source constructor is resolved to its current
global function definition at each force-time invocation; redefinition between
construction and forcing affects later invocations (Chapter 1). Conditions
signaled by a generation function propagate at force time per Chapter 4,
Section 4.1.4.

### 5.1.2 Bounded and Unbounded Sources

A source is **bounded** when its production reaches an end after finitely many
elements. It is **unbounded** when production has no such end.

`SL:RANGE` is unbounded when *end* is `NIL`. When *end* is a real number, it is
bounded when repeated addition of *step* reaches or crosses *end* in the
direction of *step*, and unbounded when it does not, such as when
floating-point addition stagnates (see the `SL:RANGE` entry). A range whose
initial value is already beyond *end* in the direction of *step* is empty and
bounded (length 0).
`SL:REPEATEDLY` is unbounded when *count* is `NIL` and bounded otherwise.
`SL:ITERATE` is always unbounded.

`SL:CYCLE` is unbounded when its view is nonempty; it is bounded (with length
zero) only when its view is empty.

The termination and eagerness of operations that consume bounded or unbounded
sources are specified in Chapter 6. The seqable types of Chapter 9 participate
as sources as specified there.

## 5.2 Dictionary

Notes and examples for this chapter appear in Appendix D.

### 5.2.1 Source Constructors

### SL:RANGE _Function_

**Name:** `SL:RANGE`, Function

**Syntax:**

`(SL:RANGE` `&KEY` *start end step* `)` → *lazy-sequence*

**Arguments and Values:**

- *start* — a real number; the default is `0`.
- *end* — a real number or `NIL`; the default is `NIL`.
- *step* — a nonzero real number; the default is `1`.
- *lazy-sequence* — a lazy sequence.

**Description:**

The first element, when the result is nonempty, is *start*; later elements are
computed by repeatedly adding *step* to the preceding element.
Construction does not perform an addition; each later value is computed when
demanded. Conditions signaled by deferred arithmetic, such as floating-point
overflow, occur at force time and propagate to the demanding caller; the node
remains retryable as specified in Chapter 4, Section 4.1.4.

When *end* is a real number and *step* is positive, an element is produced only
while it is less than *end*. When *end* is a real number and *step* is
negative, an element is produced only while it is greater than *end*. The value of *end* is excluded. Thus the
result is empty when *step* is positive and *start* is greater than or equal to
*end*, or when *step* is negative and *start* is less than or equal to *end*.
In either case the returned node resolves to `NIL`.

When *end* is `NIL`, the result is unbounded.

Boundedness and `SL:SEQ-LENGTH` behavior follow Section 5.1.2 and Chapter 4,
Section 4.1.2.

Repeated addition is significant for inexact real numbers: an addition can
stagnate by rounding to the current value, in which case the source does not
reach its bound and traversal does not terminate.

**Exceptional Situations:**

Signals an error of type `TYPE-ERROR` if *start* is not a real number, if *end*
is neither a real number nor `NIL`, or if *step* is not a nonzero real number.

### SL:REPEATEDLY _Function_

**Name:** `SL:REPEATEDLY`, Function

**Syntax:**

`(SL:REPEATEDLY` *function* `&KEY` *count* `)` → *lazy-sequence*

**Arguments and Values:**

- *function* — a usable function designator for a function of no arguments.
- *count* — a non-negative integer or `NIL`; the default is `NIL`.
- *lazy-sequence* — a lazy sequence containing the primary values returned by
  *function*.

**Description:**

The source invokes *function* once for each element successfully produced,
yielding the primary value of each invocation. The function is invoked when that
element is demanded, not when the source is constructed.

When *count* is a non-negative integer, the result contains *count* elements.
When *count* is zero, the returned node resolves to `NIL` and *function* is not
invoked. When *count* is `NIL`, the result is unbounded.

The once-per-element rule applies to successfully produced elements; after a
force exits nonlocally, the node remains unresolved and retryable under
Chapter 4, Section 4.1.4.

**Side Effects:**

Invoking *function* may have arbitrary side effects.

**Exceptional Situations:**

Signals an error of type `TYPE-ERROR` at call time if *function* is not a usable
function designator, or if *count* is neither a non-negative integer nor `NIL`.
At each force-time invocation, signals an error of type `PROGRAM-ERROR` if the
function current for that invocation does not accept zero arguments. At each
force-time invocation, signals an error of type `UNDEFINED-FUNCTION` if a symbol
designator names no current global function definition.

### SL:ITERATE _Function_

**Name:** `SL:ITERATE`, Function

**Syntax:**

`(SL:ITERATE` *function initial* `)` → *lazy-sequence*

**Arguments and Values:**

- *function* — a usable function designator for a function of one argument.
- *initial* — any object.
- *lazy-sequence* — an unbounded lazy sequence.

**Description:**

The first element is *initial*. The node denotes an unbounded sequence. Each
later element is the primary value obtained by applying *function* to the
preceding element.

Construction does not invoke *function*. Each application occurs when the
corresponding later element is demanded. Conditions and retries during an
application are governed by the lazy forcing rules in Chapter 4, Sections 4.1.3
and 4.1.4.

**Side Effects:**

Invoking *function* may have arbitrary side effects.

**Exceptional Situations:**

Signals an error of type `TYPE-ERROR` at call time if *function* is not a usable
function designator. At each force-time invocation, signals an error of type
`PROGRAM-ERROR` if the function current for that invocation does not accept one
argument. At each force-time invocation, signals an error of type
`UNDEFINED-FUNCTION` if a symbol designator names no current global function
definition.

### SL:CYCLE _Function_

**Name:** `SL:CYCLE`, Function

**Syntax:**

`(SL:CYCLE` *source* `)` → *lazy-sequence*

**Arguments and Values:**

- *source* — a seqable object.
- *lazy-sequence* — a lazy sequence containing repetitions of one traversal
  view of *source*.

**Description:**

The result repeats one traversal view of *source*; that view is established on
the first demand for the first element. All subsequent element demands of that
`SL:CYCLE` result traverse the same view, and the implementation maintains the
association between the result and its view. Direct `SL:SEQ-FIRST` and
`SL:SEQ-REST` calls on *source* establish independent views for unordered
sources, as specified in Chapter 4, Section 4.1.1. Such direct calls do not
affect the captured view.

Elements from the view are captured as they are demanded. If the view is empty,
the result node resolves to `NIL`. If the view is finite and nonempty, the
result is unbounded: after the view reaches its end, every subsequent cycle
replays the captured elements in the same order and as the same objects under
`EQ` (including captured `SL:MAP-ENTRY` objects). If the view is unbounded,
the result is unbounded and never reaches a replay cycle.

Boundedness and `SL:SEQ-LENGTH` behavior follow Section 5.1.2 and Chapter 4,
Section 4.1.2.

Traversal, establishment, and capture occur at force time. A condition that
exits the force — including a dotted-tail `TYPE-ERROR` or a forcing failure —
propagates as specified in Chapter 4, Section 4.1.4; whatever view state was
established remains associated with the result, and a later force retries per
Chapter 4, Section 4.1.4.

Consequently, a source whose traversal signals at a fixed position, such as a
dotted list, yields its captured prefix and then signals. Later traversal of the
same result yields the same memoized prefix before retrying the same position
and signaling again.

The source-modification rules of Chapter 4, Section 4.1.7 apply while
`SL:CYCLE` can still read *source*. The end of the view is observed no later than the first demand
that follows its last element; an implementation may observe it earlier. This
latitude applies only to successful end-observation. An implementation may
attempt an early traversal step that can signal, but if that step signals,
the condition is not delivered before the demand for a further element; a
signaling early observation is treated as if it occurred on the following
demand.

**Side Effects:**

Traversal of *source* may invoke user-defined seq methods that have side
effects.

**Exceptional Situations:**

Signals an error of type `TYPE-ERROR` at call time if *source* is not seqable.
Traversal can signal conditions at force time, including the `TYPE-ERROR` signaled
on reaching a dotted list tail.
