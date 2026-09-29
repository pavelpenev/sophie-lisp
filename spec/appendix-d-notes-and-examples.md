# Appendix D: Notes and Examples

This appendix is informative. It collects the Notes and Examples from
the normative chapters, organized by operator. The authoritative
specification of each operator is in its dictionary entry.

**Chapter index:** [D.1 Ch 4](#d-1-chapter-4-lazy-sequences) | [D.2 Ch 5](#d-2-chapter-5-sources) | [D.3 Ch 7](#d-3-chapter-7-equality-and-comparison) | [D.4 Ch 2](#d-4-chapter-2-packages-and-namespaces) | [D.5 Ch 3](#d-5-chapter-3-reader-syntax) | [D.6 Ch 6](#d-6-chapter-6-sequence-operations) | [D.7 Ch 8](#d-7-chapter-8-binding-destructuring-and-threading) | [D.8 Ch 9](#d-8-chapter-9-dictionaries) | [D.9 Ch 9 operations](#d-9-chapter-9-dictionary-operations)

## D.1 Chapter 4: Lazy Sequences

### SL:LAZY-SEQ _Type_ (Chapter 4)

**Notes:**

Use `SL:LAZY-SEQ-P` to test for both nodes and the empty lazy sequence.

**Examples:**

```lisp
(TYPEP (SL:LAZY-CONS 1 NIL) 'SL:LAZY-SEQ) → T
(TYPEP NIL 'SL:LAZY-SEQ) → NIL
```

### SL:LAZY-SEQ _Macro_ (Chapter 4)

**Notes:**

The form is equivalent in effect to
`(SL:MAKE-LAZY-SEQ (LAMBDA () form))`, subject to the macro-expansion variable
naming requirement of Chapter 4.

**Examples:**

```lisp
(LET ((x 10))
  (SL:SEQ-FIRST (SL:LAZY-SEQ (SL:LAZY-CONS x NIL)))) → 10
```

### SL:MAKE-LAZY-SEQ (Chapter 4)

**Examples:**

```lisp
(SL:SEQ-FIRST
  (SL:MAKE-LAZY-SEQ
    (LAMBDA () (SL:LAZY-CONS :ready NIL)))) → :READY
```

### SL:LAZY-CONS (Chapter 4)

**Examples:**

```lisp
(SL:SEQ-FIRST (SL:LAZY-CONS 'a NIL)) → A
(SL:SEQ-FIRST (SL:SEQ-REST
                (SL:LAZY-CONS 'a (SL:LAZY-CONS 'b NIL)))) → B
```

### SL:LAZY-SEQ-P (Chapter 4)

**Examples:**

```lisp
(SL:LAZY-SEQ-P NIL) → T
(SL:LAZY-SEQ-P (SL:LAZY-CONS 1 NIL)) → T
(SL:LAZY-SEQ-P '(1)) → NIL
```

### SL:SEQABLEP (Chapter 4)

**Examples:**

```lisp
(SL:SEQABLEP #(1 2)) → T
(SL:SEQABLEP (SL:MAP-ENTRY :a 1)) → NIL
(SL:SEQABLEP 42) → NIL
```

### SL:SEQ-EMPTYP (Chapter 4)

**Examples:**

```lisp
(SL:SEQ-EMPTYP NIL) → T
(SL:SEQ-EMPTYP #(1)) → NIL
(SL:SEQ-EMPTYP (SL:LAZY-SEQ NIL)) → T
```

### SL:SEQ-FIRST (Chapter 4)

**Notes:**

Use `SL:SEQ-EMPTYP` when a first element of `NIL` must be distinguished from an
empty source.

**Examples:**

```lisp
(SL:SEQ-FIRST '(a b)) → A
(SL:SEQ-FIRST '(NIL b)) → NIL
(SL:SEQ-FIRST NIL) → NIL
```

### SL:SEQ-REST (Chapter 4)

**Examples:**

```lisp
(SL:SEQ-REST '(a b c)) → (B C)
(SL:SEQ-REST '(a)) → NIL
(SL:LAZY-SEQ-P (SL:SEQ-REST #(1 2))) → T
```

### SL:SEQ-REF (Chapter 4)

**Examples:**

```lisp
(SL:SEQ-REF #(10 20 30) 1) → 20 T
(SL:SEQ-REF #(10 20 30) 5 :missing) → :MISSING NIL
(SL:SEQ-REF '(10) 1) ; signals TYPE-ERROR
```

### (SETF SL:SEQ-REF) (Chapter 4)

**Examples:**

```lisp
(LET ((v (VECTOR 1 2 3)))
  (SETF (SL:SEQ-REF v 1) 20)
  v) → #(1 20 3)
```

### SL:SEQ-LENGTH (Chapter 4)

**Examples:**

```lisp
(SL:SEQ-LENGTH '(a b c)) → 3
(SL:SEQ-LENGTH "Sophie") → 6
```

### SL:DOSEQ (Chapter 4)

**Notes:**

An infinite source without an explicit `RETURN` does not terminate. Leading
declarations precede the implicit `TAGBODY`; element and index declarations
apply each time their bindings are established, while free declarations do not
govern the source expression or destructuring defaults.

**Examples:**

```lisp
(LET ((result NIL))
  (SL:DOSEQ (x '(a b c))
    (PUSH x result))
  (NREVERSE result)) → (A B C)

(SL:DOSEQ ((x i) #(10 20 30))
  (WHEN (= i 1)
    (RETURN (LIST x i)))) → (20 1)

(let ((results nil))
  (SL:DOSEQ (entry (SL:DICT :a 1 :b 2))
    (push (list (SL:ENTRY-KEY entry) (SL:ENTRY-VALUE entry)) results))
  results)
; → ((:b 2) (:a 1))  ; order unspecified for dict
```

```lisp
(SL:DOSEQ ((x i) #(10 20))
  (DECLARE (TYPE FIXNUM i))
  (WHEN (= i 0) (GO continue))
  (RETURN (LIST x i))
 continue)
→ (20 1) ; declarations precede the implicit TAGBODY
```

### SL:MAP-ENTRY _Type_ (Chapter 4)

**Examples:**

```lisp
(TYPEP (SL:MAP-ENTRY :a 1) 'SL:MAP-ENTRY) → T
(SL:SEQABLEP (SL:MAP-ENTRY :a 1)) → NIL
```

### SL:MAP-ENTRY _Function_ (Chapter 4)

**Examples:**

```lisp
(SL:ENTRY-KEY (SL:MAP-ENTRY :answer 42)) → :ANSWER
(SL:ENTRY-VALUE (SL:MAP-ENTRY :answer 42)) → 42
```

### SL:MAKE-COLLECTOR-FOR (Chapter 4)

**Examples:**

```lisp
;; Extension method for the MY-BAG result target.
(DEFMETHOD SL:MAKE-COLLECTOR-FOR
    ((target (EQL (FIND-CLASS 'my-bag))) &KEY)
  (DECLARE (IGNORE target))
  (MAKE-MY-BAG-COLLECTOR)) → a method object
```

### SL:COLLECTOR-ACCUMULATE (Chapter 4)

**Examples:**

```lisp
(LET ((collector
        (SL:MAKE-COLLECTOR-FOR (FIND-CLASS 'list))))
  (SL:COLLECTOR-ACCUMULATE collector 10)
  (SL:COLLECTOR-ACCUMULATE collector 20)
  (SL:COLLECTOR-RESULT collector)) → (10 20)
```

### SL:COLLECTOR-RESULT (Chapter 4)

**Examples:**

```lisp
(LET ((collector
        (SL:MAKE-COLLECTOR-FOR (FIND-CLASS 'list))))
  (SL:COLLECTOR-ACCUMULATE collector :a)
  (LET ((result (SL:COLLECTOR-RESULT collector)))
    (VALUES result
            (EQ result (SL:COLLECTOR-RESULT collector))))) → (:A) T
```

## D.2 Chapter 5: Sources

### SL:RANGE (Chapter 5)

**Examples:**

```lisp
(SL:SEQ-INTO 'list (SL:RANGE :end 5)) → (0 1 2 3 4)
(SL:SEQ-INTO 'list (SL:RANGE :start 2 :end 10 :step 3)) → (2 5 8)
(SL:SEQ-INTO 'list (SL:RANGE :start 5 :end 0 :step -2)) → (5 3 1)
(SL:SEQ-INTO 'list (SL:RANGE :start 4 :end 4)) → NIL
(SL:SEQ-INTO 'list (SL:SEQ-TAKE 4 (SL:RANGE :start 10))) → (10 11 12 13)
```

### SL:REPEATEDLY (Chapter 5)

**Examples:**

```lisp
(SL:SEQ-INTO 'list (SL:REPEATEDLY (lambda () :x) :count 3)) → (:X :X :X)
(SL:SEQ-EMPTYP (SL:REPEATEDLY (lambda () :unused) :count 0)) → T

(let ((n 0))
  (SL:SEQ-INTO 'list
               (SL:REPEATEDLY (lambda () (incf n)) :count 3))) → (1 2 3)
```

### SL:ITERATE (Chapter 5)

**Notes:**

Demanding only the first element does not invoke *function*. A failed force
retries the function application for the same element position, applying it to
the memoized preceding element, which has been successfully produced.

**Examples:**

```lisp
(SL:SEQ-INTO 'list (SL:SEQ-TAKE 5 (SL:ITERATE #'1+ 0))) → (0 1 2 3 4)
(SL:SEQ-INTO 'list
             (SL:SEQ-TAKE 4
                          (SL:ITERATE (lambda (x) (* x 2)) 1))) → (1 2 4 8)
```

### SL:CYCLE (Chapter 5)

**Examples:**

```lisp
(SL:SEQ-INTO 'list
             (SL:SEQ-TAKE 5 (SL:CYCLE '(0 1)))) → (0 1 0 1 0)
(SL:SEQ-INTO 'list
             (SL:SEQ-TAKE 3 (SL:CYCLE "ab"))) → (#\a #\b #\a)
(SL:SEQ-EMPTYP (SL:CYCLE nil)) → T
```

## D.3 Chapter 7: Equality and Comparison

### SL:EQUALS (Chapter 7)

**Notes:**

An implementation may immediately return true for identical arguments. This can
allow `(SL:EQUALS s s)` to terminate without forcing an unbounded lazy sequence.
Collisions in `SL:HASH-CODE` do not imply equality.

**Examples:**

```lisp
(SL:EQUALS 1 1.0) → t
(SL:EQUALS "Hello" "hello") → nil
(SL:EQUALS '(a (b c)) '(a (b c))) → t
(SL:EQUALS #(1 2 3) #(1 2 3)) → t
(SL:EQUALS "abc" #(#\a #\b #\c)) → t
(SL:EQUALS nil (SL:LAZY-SEQ nil)) → t
(SL:EQUALS (SL:MAP-ENTRY :a 1) (SL:MAP-ENTRY :a 1)) → t
```

### SL:COMPARE (Chapter 7)

**Examples:**

```lisp
(SL:COMPARE 1 2) → :LESS
(SL:COMPARE 2 1) → :GREATER
(SL:COMPARE #\a #\b) → :LESS
(SL:COMPARE "ab" "ac") → :LESS
(SL:COMPARE '(1) '(1 2)) → :LESS
(SL:COMPARE #(1 3) #(1 2)) → :GREATER
(SL:COMPARE #'car #'cdr) → :UNEQUAL
(SL:COMPARE (SL:MAP-ENTRY :a 1) (SL:MAP-ENTRY :a 2)) → :LESS
(SL:COMPARE (SL:LAZY-CONS 1 nil) nil) → :GREATER
```

### SL:LT, SL:LTE, SL:GT, SL:GTE (Chapter 7)

**Examples:**

```lisp
(SL:LT 1 2) → t
(SL:LTE 1 1) → t
(SL:GT 2 1) → t
(SL:GTE 1 2) → nil
(SL:LT #'car #'cdr) → signals simple-error
```

### SL:HASH-CODE (Chapter 7)

**Notes:**

Equal objects receive equal non-negative hash codes; unequal objects may collide. The
algorithm and amount of traversal are implementation-defined. Mutating a resident key
has undefined consequences.

**Examples:**

```lisp
(integerp (SL:HASH-CODE 'anything)) → t
(minusp (SL:HASH-CODE 'anything)) → nil
(= (SL:HASH-CODE 1) (SL:HASH-CODE 1.0)) → t
(= (SL:HASH-CODE "abc")
   (SL:HASH-CODE #(#\a #\b #\c))) → t
(= (SL:HASH-CODE (SL:MAP-ENTRY :a 1))
   (SL:HASH-CODE (SL:MAP-ENTRY :a 1))) → t
```

## D.4 Chapter 2: Packages and Namespaces

### `SOPHIE-LISP` _Package_ (Chapter 2)

**Notes:**

The re-exported symbols are the original COMMON-LISP and
SOPHIE-LISP-EXTENSIONS symbol objects, not newly interned symbols.

**Examples:**

```lisp
(EQ 'CL:CAR 'SL:CAR) → T
```

### `SL-USER` _Package_ (Chapter 2)

**Notes:**

SL-USER is provided as a convenience and is not required for Sophie Lisp
usage. It is intended for interactive development and for code that does not
define its own package. A program that defines its own packages with
`(:USE :SL)` does not need it.

**Examples:**

```lisp
(IN-PACKAGE :SL-USER)
```

### `SOPHIE-LISP-EXTENSIONS` _Package_ (Chapter 2)

**Examples:**

```lisp
(EQ 'SL:EQUALS 'SL-EXT:EQUALS) → T
```

## D.5 Chapter 3: Reader Syntax

### #^() _Reader Macro_ (Chapter 3)

**Notes:**

The outermost-replacement clause is operative through `SL:OP`, whose expression
may be an atom. A `#^` expression is always a parenthesized form.

**Examples:**

```lisp
#^(1+ %)        → (lambda (#:g1) (1+ #:g1))
#^(+ %1 %2)     → (lambda (#:g1 #:g2) (+ #:g1 #:g2))
#^(list %2)     → (lambda (#:g1 #:g2)
                     (declare (ignorable #:g1))
                     (list #:g2))
#^(apply #'+ %&) → (lambda (&rest #:g1) (apply #'+ #:g1))
#^(random 10)   → (lambda () (random 10))
```

### SL:OP _Macro_ (Chapter 3)

**Examples:**

```lisp
(funcall (SL:OP (1+ %)) 5) → 6
(funcall (SL:OP (+ %1 %2)) 2 3) → 5
```

### #v() _Reader Macro_ (Chapter 3)

**Examples:**

```lisp
#v(1 2 3)     → an adjustable vector containing 1, 2, and 3
#v((+ 1 2) 4) → an adjustable vector containing 3 and 4
#v()          → an empty adjustable vector with a fill pointer
```

### #h() _Reader Macro_ (Chapter 3)

**Notes:**

Test-specifier detection operates on the form as read; for example, a symbol
produced by `#.` is treated as a test specifier.

**Examples:**

```lisp
#h(:a 1 :b 2)    → a fresh EQUAL hash table with keys :A and :B
#h(eq :a 1)      → a fresh EQ hash table with key :A
#h(:eq 1)        → a fresh EQUAL hash table mapping :EQ to 1
#h('eq 1)        → a fresh EQUAL hash table mapping the symbol EQ to 1
#h()             → an empty EQUAL hash table
```

### #d() _Reader Macro_ (Chapter 3)

**Examples:**

```lisp
#d(:a 1 :b 2)      → a dict mapping :A to 1 and :B to 2
#d(:a 1 :a 2)      → a dict mapping :A to 2
#d((+ 1 2) :three) → a dict mapping 3 to :THREE
#d()               → an empty dict
```

### #u() _Reader Macro_ (Chapter 3)

**Examples:**

```lisp
#u(:a :b :c)  → a set containing :A, :B, and :C
#u(:a :a :b)  → a set containing :A and :B
#u((+ 1 2) 3) → a set containing 3
#u()          → an empty set
```

### #?"..." _Reader Macro_ (Chapter 3)

**Examples:**

```lisp
#?"Hello, world!" → "Hello, world!"
(let ((name "Sophie")) #?"Hello, ${name}!") → "Hello, Sophie!"
#?"2 + 2 = ${(+ 2 2)}" → "2 + 2 = 4"
#?"Items: @{(list 1 2 3)}" → "Items: 1 2 3"
#?"Price: \${price}" → "Price: ${price}"
```

### SL:*LIST-DELIMITER* _Special Variable_ (Chapter 3)

**Examples:**

```lisp
(let ((SL:*LIST-DELIMITER* ", "))
  #?"${(length '(a b c))}: @{(list 'a 'b 'c)}") → "3: A, B, C"
```

## D.6 Chapter 6: Sequence Operations

### Vector element-type preservation (Chapter 6)

**Notes:**

The vector-preserving roster retains the actual source element type for
selection and rearrangement, including empty results. Element-changing and
multi-source operations still use their general-vector rules. Nested
split/partition operations specialize inner pieces only; their outer container
keeps its existing representation. `SL:SEQ-PARTITION` widens only the chunk
whose actual padding does not fit.

**Examples:**

```lisp
(let ((bits #*10101))
  (list (array-element-type (SL:SEQ-FILTER #'IDENTITY bits))
        (array-element-type (SL:SEQ-REVERSE bits))))
→ (BIT BIT)

(let* ((bytes (make-array 3 :element-type '(UNSIGNED-BYTE 8)
                           :initial-contents '(10 20 30)))
       (actual-type (array-element-type bytes))
       (empty (SL:SEQ-TAKE 0 bytes))
       (selected (SL:SEQ-DROP 1 bytes)))
  (list (equal (array-element-type empty) actual-type)
        (equal (array-element-type selected) actual-type)))
→ (T T) ; compare with the source's actual type: implementations may upgrade
         ; (UNSIGNED-BYTE 8) when the array is made

(array-element-type (SL:SEQ-MAP #'1+ #*101))
→ T ; element-changing results do not infer a specialized type

(let ((pieces (SL:SEQ-SPLIT-AT 2 #*1010)))
  (list (array-element-type pieces)
        (array-element-type (aref pieces 0))
        (array-element-type (aref pieces 1))))
→ (T BIT BIT) ; only the inner pieces are specialized

(SL:SEQ-INTO 'list
  (SL:SEQ-PARTITION 2 #*101 :PAD '(0)))
→ (#*10 #*10) ; compatible padding keeps both chunks specialized

(SL:SEQ-INTO 'list
  (SL:SEQ-PARTITION 2 #*101 :PAD '(2)))
→ (#*10 #(1 2)) ; only the padded chunk widens
```

### SL:SEQ-LAST (Chapter 6)

**Notes:**

The returned value is an element, not a sequence, and no source tail is returned.

**Examples:**

```lisp
(SL:ENTRY-VALUE (SL:SEQ-LAST (SL:DICT :a 1))) → 1 ; dict traversal yields an entry
```

### SL:SEQ-FIND, SL:SEQ-FIND-IF (Chapter 6)

**Notes:**

A matching element whose value is `NIL` is indistinguishable from no match. Use `SL:SEQ-POSITION` when the presence of a matching element must be distinguished.

**Examples:**

```lisp
(SL:SEQ-FIND-IF #'NULL '(1 NIL 3)) → NIL ; matching NIL is ambiguous
```

### SL:SEQ-POSITION, SL:SEQ-POSITION-IF (Chapter 6)

**Notes:**

The index is an absolute coordinate in *source*, including any starting offset.

**Examples:**

```lisp
(SL:SEQ-POSITION 3 #(0 1 3 4) :START 1) → 2 ; absolute source index
```

### SL:SEQ-MEMBER (Chapter 6)

**Notes:**

The operation can distinguish an absent match from a matching element by the result being `NIL` or a lazy sequence, but it does not turn the match into a scalar value.

**Examples:**

```lisp
(SL:SEQ-INTO 'list (SL:SEQ-MEMBER 2 '(1 2 3))) → (2 3)
(SL:SEQ-MEMBER 9 '(1 2 3)) → NIL
```

### SL:SEQ-COUNT, SL:SEQ-COUNT-IF (Chapter 6)

**Notes:**

`:FROM-END` changes traversal direction only; it does not change *count*. The returned count is the number of matches.

**Examples:**

```lisp
(SL:SEQ-COUNT 1 '(1 2 1) :FROM-END T) → 2 ; direction does not change count
```

### SL:SEQ-SEARCH (Chapter 6)

**Notes:**

The pattern is completely forced before any subject search begins. The index is never relative to the pattern or to `:START2`.

**Examples:**

```lisp
(SL:SEQ-SEARCH "bc" "abcd") → 1
(SL:SEQ-SEARCH "" "abcd") → 0
```

### SL:SEQ-MISMATCH (Chapter 6)

**Notes:**

The exhaustion exception forces no more than the single corresponding node needed to determine whether the regions end together. The returned index includes `:START1`.

**Examples:**

```lisp
(SL:SEQ-MISMATCH "abx" "abc") → 2
(SL:SEQ-MISMATCH '(1 2) '(1 2)) → NIL
```

### SL:SEQ-EVERY, SL:SEQ-SOME, SL:SEQ-NOTEVERY, SL:SEQ-NOTANY (Chapter 6)

**Notes:**

The predicate receives one element from each source for the current lockstep step, in source order. The return value of `SL:SEQ-SOME` is the predicate value itself, not a Boolean conversion.

**Examples:**

```lisp
(SL:SEQ-EVERY #'< '(1 2) '(2 3)) → T
(SL:SEQ-SOME #'IDENTITY '(NIL 4)) → 4
(SL:SEQ-NOTEVERY #'< '(1 3) '(2 2)) → T
(SL:SEQ-NOTANY #'EVENP '(1 3 5)) → T
```

### SL:SEQ-MIN (Chapter 6)

**Notes:**

The complete source is required even when an early element appears to be minimal.

**Examples:**

```lisp
(SL:SEQ-MIN '(3 1 2)) → 1
(SL:SEQ-MIN '((a 3) (b 1)) :KEY #'SECOND) → (B 1)
(SL:SEQ-MIN '() :DEFAULT 0) → 0
```

### SL:SEQ-MAX (Chapter 6)

**Notes:**

The complete source is required even when an early element appears to be maximal.

**Examples:**

```lisp
(SL:SEQ-MAX '(3 1 2)) → 3
(SL:SEQ-MAX '((a 3) (b 1)) :KEY #'SECOND) → (A 3)
(SL:SEQ-MAX '() :DEFAULT 0) → 0
```

### SL:SEQ-REDUCE (Chapter 6)

**Notes:**

The initial value is not passed through *key*. The complete selected region is required even when the reduction function could otherwise determine a result early.

**Examples:**

```lisp
(SL:SEQ-REDUCE #'+ '(1 2 3) :INITIAL-VALUE 0) → 6
(SL:SEQ-REDUCE #'- '(1 2 3) :FROM-END T :INITIAL-VALUE 0) → 2
```

### SL:SEQ-MAP (Chapter 6)

**Examples:**

```lisp
(SL:SEQ-MAP #'+ '(1 2 3) '(10 20 30 40)) → (11 22 33)
(SL:SEQ-MAP #'CHAR-UPCASE "ab") → "AB"
(SL:SEQ-MAP #'CHAR-CODE "ab") → #(97 98)
```

### SL:SEQ-MAP-INDEXED (Chapter 6)

**Examples:**

```lisp
(SL:SEQ-MAP-INDEXED #'LIST '(a b c)) → ((0 A) (1 B) (2 C))
(SL:SEQ-MAP-INDEXED (lambda (i c) (if (EVENP i) (CHAR-UPCASE c) c)) "abcd")
→ "AbCd"
(SL:SEQ-INTO 'list (SL:SEQ-MAP-INDEXED #'CONS #(x y))) → ((0 . X) (1 . Y))
```

### SL:SEQ-FILTER (Chapter 6)

**Examples:**

```lisp
(SL:SEQ-FILTER #'EVENP '(1 2 3 4)) → (2 4)
(SL:SEQ-FILTER #'EVENP '(1 2 3 4 5 6) :COUNT 2) → (2 4)
(SL:SEQ-FILTER #'EVENP '(1 2 3 4 5 6) :COUNT 2 :FROM-END T) → (4 6)
(SL:SEQ-FILTER #'EVENP '((a 1) (b 2) (c 3)) :KEY #'SECOND) → ((b 2))
```

### SL:SEQ-KEEP (Chapter 6)

**Examples:**

```lisp
(SL:SEQ-KEEP (lambda (x) (when (EVENP x) (* x x))) '(1 2 3 4)) → (4 16)
(SL:SEQ-KEEP #'IDENTITY '(a NIL b NIL c)) → (A B C)
(SL:SEQ-INTO 'list (SL:SEQ-KEEP (lambda (c) (and (ALPHA-CHAR-P c) c)) "a1b"))
→ (#\a #\b)
```

### SL:SEQ-REMOVE, SL:SEQ-REMOVE-IF (Chapter 6)

**Examples:**

```lisp
(SL:SEQ-REMOVE 2 '(1 2 3 2)) → (1 3)
(SL:SEQ-REMOVE 2 '(2 1 2 3 2) :COUNT 2) → (1 3 2)
(SL:SEQ-REMOVE 2 '(2 1 2 3 2) :COUNT 2 :FROM-END T) → (2 1 3)
(SL:SEQ-REMOVE-IF #'ODDP #(1 2 3 4)) → #(2 4)
```

### SL:SEQ-SUBSTITUTE, SL:SEQ-SUBSTITUTE-IF (Chapter 6)

**Examples:**

```lisp
(SL:SEQ-SUBSTITUTE :X 2 '(1 2 3 2)) → (1 :X 3 :X)
(SL:SEQ-SUBSTITUTE :X 2 '(2 1 2 3 2) :COUNT 2) → (:X 1 :X 3 2)
(SL:SEQ-SUBSTITUTE :X 2 '(2 1 2 3 2) :COUNT 2 :FROM-END T) → (2 1 :X 3 :X)
(SL:SEQ-SUBSTITUTE-IF #\_ #'DIGIT-CHAR-P "a1b2") → "a_b_"
```

### SL:SEQ-MAPCAT (Chapter 6)

**Examples:**

```lisp
(SL:SEQ-MAPCAT (lambda (x) (list x x)) '(1 2 3)) → (1 1 2 2 3 3)
(SL:SEQ-MAPCAT #'IDENTITY '((a b) () (c))) → (A B C)
(SL:SEQ-INTO 'list (SL:SEQ-MAPCAT (lambda (x) (list x (* x 10))) '(1 2)))
→ (1 10 2 20)
```

### SL:SEQ-TAKE, SL:SEQ-DROP (Chapter 6)

**Examples:**

```lisp
(SL:SEQ-TAKE 2 '(1 2 3 4)) → (1 2)
(SL:SEQ-DROP 2 #(1 2 3 4)) → #(3 4)
(SL:SEQ-INTO 'list (SL:SEQ-TAKE 3 (SL:RANGE))) → (0 1 2)
(SL:SEQ-INTO 'list (SL:SEQ-DROP 3 (SL:SEQ-TAKE 6 (SL:RANGE)))) → (3 4 5)
```

### SL:SEQ-TAKE-WHILE, SL:SEQ-DROP-WHILE (Chapter 6)

**Examples:**

```lisp
(SL:SEQ-TAKE-WHILE #'PLUSP '(2 1 0 3)) → (2 1)
(SL:SEQ-DROP-WHILE #'PLUSP '(2 1 0 3)) → (0 3)
(SL:SEQ-INTO 'list (SL:SEQ-TAKE 4 (SL:SEQ-TAKE-WHILE #'EVENP (SL:RANGE))))
→ (0)
```

### SL:SEQ-SUBSEQ (Chapter 6)

**Examples:**

```lisp
(SL:SEQ-INTO 'list (SL:SEQ-SUBSEQ (SL:RANGE) 2 5)) → (2 3 4)
```

### SL:SEQ-TAKE-NTH (Chapter 6)

**Examples:**

```lisp
(SL:SEQ-INTO 'list (SL:SEQ-TAKE 4 (SL:SEQ-TAKE-NTH 2 (SL:RANGE))))
→ (0 2 4 6)
```

### SL:SEQ-REMOVE-DUPLICATES (Chapter 6)

**Notes:**

The complete selected region is required before the first result node even in
default mode; the operation does not stream a lazy prefix.

**Examples:**

```lisp
(SL:SEQ-REMOVE-DUPLICATES '(a b a c b)) → (A B C)
(SL:SEQ-REMOVE-DUPLICATES '(a b a c b) :FROM-END T) → (A C B)
(SL:SEQ-REMOVE-DUPLICATES '((a 1) (b 1) (c 2)) :KEY #'SECOND)
→ ((A 1) (C 2))
```

### SL:SEQ-DEDUPE (Chapter 6)

**Examples:**

```lisp
(SL:SEQ-DEDUPE '(1 1 2 1 3 3 3)) → (1 2 1 3)
(SL:SEQ-DEDUPE "aaabbcc") → "abc"
(SL:SEQ-DEDUPE '(1 1 2 1) :TEST #'=) → (1 2 1)
```

### SL:SEQ-TRIM-LEFT (Chapter 6)

**Examples:**

```lisp
(SL:SEQ-TRIM-LEFT "  hello"
                   :PREDICATE (lambda (c)
                                (find c '(#\Space #\Tab #\Newline))))
→ "hello"
```

### Built-in dictionary-preserving sequence operations (Chapter 6)

**Notes:**

The exact entry-subset roster preserves built-in dictionary type, hash-table test,
and retained key/value associations. It uses one traversal and runs selection
callbacks at call time; result order is unspecified. User-defined dicts and
read-only plist views retain their existing contracts. `SL:SEQ-DROP-LAST`,
sorting, reversal, mapping, and nested-result operations remain outside this
roster.

**Examples:**

```lisp
(typep
 (SL:SEQ-FILTER (lambda (entry)
                  (eq (SL:ENTRY-KEY entry) :keep))
                (SL:DICT :keep 1 :drop 2))
 'SL:DICT)
→ T

(let ((h (make-hash-table :test #'eql)))
  (setf (gethash 1 h) :one
        (gethash 1.0 h) :float)
  (let ((result
          (SL:SEQ-FILTER (lambda (entry)
                           (eql (SL:ENTRY-KEY entry) 1))
                         h)))
    (list (hash-table-p result)
          (hash-table-test result)
          (gethash 1 result)
          (nth-value 1 (gethash 1.0 result))
          (nth-value 1 (gethash 1.0 h)))))
→ (T EQL :ONE NIL T) ; the source and EQL-distinct key remain unchanged

(let ((calls 0)
      (h #h(:a 1 :b 2)))
  (SL:SEQ-FILTER (lambda (entry) (declare (ignore entry)) (incf calls) t) h)
  calls)
→ 2 ; selection runs during the eager call, in one traversal

(SL:SEQ-DROP-LAST 1 (SL:DICT :a 1 :b 2)) → a lazy sequence ; excluded by the roster
```

### SL:SEQ-REDUCTIONS (Chapter 6)

**Examples:**

```lisp
(SL:SEQ-REDUCTIONS #'+ '(1 2 3 4)) → (1 3 6 10)
(SL:SEQ-REDUCTIONS #'+ '(1 2 3) :INITIAL-VALUE 100) → (100 101 103 106)
(SL:SEQ-REDUCTIONS #'LIST '(a b c)) → (A (A B) ((A B) C))
(SL:SEQ-INTO 'list (SL:SEQ-TAKE 4 (SL:SEQ-REDUCTIONS #'+ (SL:RANGE))))
→ (0 1 3 6)
```

### SL:SEQ-CONCATENATE (Chapter 6)

**Examples:**

```lisp
(SL:SEQ-CONCATENATE '(1 2) '(3 4)) → (1 2 3 4)
(SL:SEQ-CONCATENATE #(1 2) "ab") → a lazy sequence
(SL:SEQ-CONCATENATE (SL:RANGE) '(done)) → a lazy sequence that never reaches '(done)
```

### SL:SEQ-INTERLEAVE (Chapter 6)

**Examples:**

```lisp
(SL:SEQ-INTERLEAVE '(1 2 3) '(a b)) → (1 a 2 b)
(SL:SEQ-INTERLEAVE #(1 2) #(a b)) → #(1 a 2 b)
(SL:SEQ-INTERLEAVE) → NIL — the empty lazy sequence without source traversal
```

### SL:SEQ-SPLIT (Chapter 6)

**Examples:**

```lisp
(SL:SEQ-INTO 'list
  (SL:SEQ-MAP (lambda (piece) (SL:SEQ-INTO 'string piece))
              (SL:SEQ-SPLIT "a,b" :DELIMITER #\,)))
→ ("a" "b")

(SL:SEQ-INTO 'list
  (SL:SEQ-MAP (lambda (piece) (SL:SEQ-INTO 'string piece))
              (SL:SEQ-SPLIT "a,,b," :DELIMITER #\,)))
→ ("a" "" "b" "")

(SL:SEQ-INTO 'list
  (SL:SEQ-MAP (lambda (piece) (SL:SEQ-INTO 'list piece))
              (SL:SEQ-SPLIT '(1 2 3 4) :PREDICATE #'EVENP)))
→ ((1) (3) NIL)
```

### SL:SEQ-SPLIT-AT (Chapter 6)

**Examples:**

```lisp
(SL:SEQ-SPLIT-AT 2 '(1 2 3 4))
→ ((1 2) (3 4))

(SL:SEQ-SPLIT-AT 0 '(1 2 3))
→ (NIL (1 2 3))

(SL:SEQ-SPLIT-AT 9 "abc")
→ #("abc" "")

(let ((pieces (SL:SEQ-SPLIT-AT 0 #*101)))
  (list (array-element-type pieces)
        (array-element-type (aref pieces 0))
        (array-element-type (aref pieces 1))))
→ (T BIT BIT) ; the empty prefix retains the specialized piece type
```

### SL:SEQ-SPLIT-WITH (Chapter 6)

**Examples:**

```lisp
(SL:SEQ-SPLIT-WITH #'EVENP '(2 4 1 3))
→ ((2 4) (1 3))

(SL:SEQ-SPLIT-WITH #'EVENP '(1 2 3))
→ (NIL (1 2 3))
```

### SL:SEQ-PARTITION (Chapter 6)

**Examples:**

```lisp
(SL:SEQ-INTO 'list
  (SL:SEQ-MAP (lambda (chunk) (SL:SEQ-INTO 'list chunk))
              (SL:SEQ-PARTITION 2 '(1 2 3 4 5))))
→ ((1 2) (3 4))

(SL:SEQ-INTO 'list
  (SL:SEQ-MAP (lambda (chunk) (SL:SEQ-INTO 'list chunk))
              (SL:SEQ-PARTITION 2 '(1 2 3 4 5) :PAD T)))
→ ((1 2) (3 4) (5))

(SL:SEQ-INTO 'list
  (SL:SEQ-MAP (lambda (chunk) (SL:SEQ-INTO 'list chunk))
              (SL:SEQ-PARTITION 2 '(1 2 3 4 5)
                                :PAD (SL:CYCLE '(0)))))
→ ((1 2) (3 4) (5 0))

(SL:SEQ-INTO 'list
  (SL:SEQ-MAP (lambda (chunk) (SL:SEQ-INTO 'list chunk))
              (SL:SEQ-PARTITION 2 '(1 2 3 4) :STEP 1)))
→ ((1 2) (2 3) (3 4))
```

### SL:SEQ-PARTITION-BY (Chapter 6)

**Examples:**

```lisp
(SL:SEQ-INTO 'list
  (SL:SEQ-MAP (lambda (chunk) (SL:SEQ-INTO 'list chunk))
              (SL:SEQ-PARTITION-BY #'EVENP '(1 1 2 2 2 3 1))))
→ ((1 1) (2 2 2) (3 1))

(SL:SEQ-INTO 'list
  (SL:SEQ-MAP (lambda (chunk) (SL:SEQ-INTO 'list chunk))
              (SL:SEQ-PARTITION-BY #'IDENTITY "aabbcc")))
→ ((#\a #\a) (#\b #\b) (#\c #\c))
```

### SL:SEQ-TREE-SEQ (Chapter 6)

**Examples:**

```lisp
(SL:SEQ-INTO 'list
  (SL:SEQ-TREE-SEQ #'LISTP #'IDENTITY '(1 (2 3) 4)))
→ ((1 (2 3) 4) 1 (2 3) 2 3 4)

(SL:SEQ-INTO 'list
  (SL:SEQ-TREE-SEQ #'CONSP #'CDR '(1 2 3)))
→ ((1 2 3) 2 3)
```

### SL:SEQ-DROP-LAST (Chapter 6)

**Notes:**

String and vector inputs are traversed and reconstructed eagerly. The result is
fresh even when *n* is zero. A vector result retains the source's actual element
type; traversal respects the source's active length. Lists, user-defined collections, dictionaries, hash tables, hash sets,
and lazy sequences retain the lazy lookahead behavior, with no finiteness
pre-scan.

**Examples:**

```lisp
(SL:SEQ-INTO 'list (SL:SEQ-DROP-LAST 2 '(1 2 3 4 5)))
→ (1 2 3) ; the list branch remains lazy until consumed

(let* ((source "abcd")
       (result (SL:SEQ-DROP-LAST 0 source)))
  (values result (not (eq result source))))
→ "abcd", T ; eager and fresh even for n=0

(let ((bits (SL:SEQ-DROP-LAST 1 #*101)))
  (values bits (array-element-type bits)))
→ #*10, BIT

(SL:SEQ-DROP-LAST 1 '(1 2 3)) → a lazy sequence
(SL:SEQ-DROP-LAST 1 (SL:DICT :a 1 :b 2)) → a lazy sequence

(SL:SEQ-INTO 'list
  (SL:SEQ-TAKE 3 (SL:SEQ-DROP-LAST 1 (SL:RANGE))))
→ (0 1 2) ; bounded lookahead does not pre-scan the unbounded source
```

### SL:SEQ-REVERSE (Chapter 6)

**Examples:**

```lisp
(SL:SEQ-REVERSE "abc") → "cba"
```

### SL:SEQ-SORT, SL:SEQ-STABLE-SORT (Chapter 6)

**Notes:**

The `:KEY` function is not cached and may be re-invoked on the same element across comparisons. Stability is defined in terms of comparison outcomes actually observed. A `:KEY` whose result is not consistent for an element has undefined consequences, consistent with the equivalence-relation ruling in Chapter 6.

**Examples:**

```lisp
(SL:SEQ-SORT '(3 1 2)) → (1 2 3)
(SL:SEQ-SORT '("bbb" "a" "cc") :KEY #'LENGTH) → ("a" "cc" "bbb")
(SL:SEQ-STABLE-SORT '((a 1) (b 1) (c 0))
                    :KEY #'SECOND) → ((c 0) (a 1) (b 1))
```

### SL:SEQ-TAKE-LAST (Chapter 6)

**Examples:**

```lisp
(let ((n 0))
  (values (SL:SEQ-TAKE-LAST 2
            (SL:REPEATEDLY (lambda () (incf n)) :count 4))
          n)) → (3 4), 4 ; the complete source is forced
```

### SL:SEQ-TRIM-RIGHT (Chapter 6)

**Examples:**

```lisp
(SL:SEQ-TRIM-RIGHT (CONCATENATE 'STRING "text " (STRING #\Tab) (STRING #\Newline))
                    :PREDICATE (lambda (c)
                                 (find c '(#\Space #\Tab #\Newline))))
→ "text"
```

### SL:SEQ-TRIM (Chapter 6)

**Examples:**

```lisp
(SL:SEQ-TRIM (CONCATENATE 'STRING (STRING #\Tab) " hello " (STRING #\Newline))
             :PREDICATE (lambda (c)
                          (find c '(#\Space #\Tab #\Newline))))
→ "hello"
```

### SL:SEQ-INTO (Chapter 6)

**Examples:**

```lisp
(SL:SEQ-INTO 'LIST (SL:SEQ-TAKE 3 (SL:RANGE))) → (0 1 2)
(SL:SEQ-INTO 'STRING '(#\a #\b #\c)) → "abc"
(SL:SEQ-INTO '(VECTOR :ELEMENT-TYPE INTEGER) '(1 2 3)) → #(1 2 3)
(SL:SEQ-INTO 'LAZY-SEQ (SL:RANGE)) → a lazy sequence
```

### SL:SEQ-JOIN (Chapter 6)

**Examples:**

```lisp
(SL:SEQ-JOIN 'STRING '("a" "b" "c") :SEPARATOR ",") → "a,b,c"
(SL:SEQ-JOIN 'LIST '((1 2) NIL (3))) → (1 2 3)
(SL:SEQ-JOIN 'VECTOR '((1 2) (3 4)) :SEPARATOR '(0)) → #(1 2 0 3 4)
```

## D.7 Chapter 8: Binding, Destructuring, and Threading

### SL:BIND (Chapter 8)

**Notes:**

A `SL:?` clause neither supplies the optional `SL:REF` default nor exposes
`present-p`. Use a simple or multiple-value clause around an explicit `SL:REF`
call when either is needed. Leading declarations use ordinary Common Lisp
meanings; declarations naming introduced bindings also govern subsequent clause
initializers, while free declarations govern only the body.

**Examples:**

```lisp
(SL:BIND ((a 1)
          (q r (floor 10 3))
          ((x . tail) '(4 5 6)))
  (list a q r x tail))
→ (1 3 1 4 (5 6))

(SL:BIND (((:entry key value) (SL:MAP-ENTRY :port 8080)))
  (list key value))
→ (:PORT 8080)

(let ((table (make-hash-table)))
  (setf (gethash :host table) "example.test")
  (SL:BIND ((((host :host)) SL:? table))
    host))
→ "example.test"
```

```lisp
(SL:BIND ((x 1)
          (y (+ x 2)))
  (DECLARE (TYPE INTEGER x y) (IGNORABLE y))
  (LIST x y))
→ (1 3) ; the declaration covers the successive bindings and body
```

### SL:? (Chapter 8)

**Examples:**

```lisp
(let ((table (make-hash-table)))
  (setf (gethash :answer table) 42)
  (SL:BIND ((((answer :answer)) SL:? table))
    answer))
→ 42
```

### SL:@ (Chapter 8)

**Examples:**

```lisp
(SL:BIND ((((name :name)) SL:@ person))
  name)
→ the value of PERSON's NAME slot
```

### SL:REF (Chapter 8)

**Notes:**

The second value distinguishes a present entry containing `NIL` from an absent
entry, and an in-range sequence element from an exhausted sequence when a
default is supplied.

**Examples:**

```lisp
(SL:REF #(10 20 30) 1)       → 20 t
(SL:REF #(10 20 30) 7 :none) → :none nil

(let ((table (make-hash-table)))
  (setf (gethash "a" table) nil)
  (values (multiple-value-list (SL:REF table "a"))
          (multiple-value-list (SL:REF table "b"))))
→ (NIL T) (NIL NIL)
```

### (SETF SL:REF) (Chapter 8)

**Notes:**

Accepting the ignored *default* allows read-modify-write operators to use the
same argument list for the reader and writer of an `SL:REF` place.

**Examples:**

```lisp
(let ((vector (vector 10 20 30)))
  (setf (SL:REF vector 1 :ignored) 99)
  vector)
→ #(10 99 30)
```

### SL:FBIND (Chapter 8)

**Examples:**

```lisp
(let ((offset 10))
  (SL:FBIND ((add-offset (lambda (x) (+ x offset))))
    (add-offset 5)))
→ 15
```

### SL:IF-BIND (Chapter 8)

**Examples:**

```lisp
(let ((table (make-hash-table)))
  (setf (gethash :ready table) nil)
  (SL:IF-BIND ((present (nth-value 1 (SL:REF table :ready))))
      :found
      :missing))
→ :FOUND

(SL:IF-BIND ((a 2) (b (+ a 3)))
    (* a b)
    :failed)
→ 10
```

### SL:WHEN-BIND (Chapter 8)

**Examples:**

```lisp
(SL:WHEN-BIND ((x 4) (y (and (evenp x) 6)))
  (+ x y))
→ 10

(SL:WHEN-BIND ((x nil) (y (error "not evaluated")))
  (+ x y))
→ nil
```

**Notes:**

Leading declarations distinguish bindings introduced by `SL:WHEN-BIND` from
free declarations about surrounding variables. A bound declaration applies from
establishment through its scope, including later clause initializers and
bindings established before short-circuiting. A free declaration, including
`OPTIMIZE`, governs only the successful body; it does not govern tested
expressions or destructuring defaults. Use `LOCALLY` inside an `SL:IF-BIND`
branch when a branch-local declaration is needed.

**Examples:**

```lisp
(SL:WHEN-BIND ((x 4))
  (DECLARE (TYPE INTEGER x) (OPTIMIZE (SPEED 3)))
  (+ x 1))
→ 5

(SL:IF-BIND ((x 1))
  (LOCALLY (DECLARE (TYPE INTEGER x)) (+ x 1))
  0)
→ 2
```

### SL:FN (Chapter 8)

**Examples:**

```lisp
(funcall (SL:FN ((a . b)) (list b a)) '(1 . 2))
→ (2 1)

(funcall (SL:FN ((a b) (c d)) (list a b c d)) '(1 2) '(3 4))
→ (1 2 3 4)

;; &rest is a lambda-list keyword, not a parameter named "&REST"
(funcall (SL:FN (x &rest ys) (list x ys)) 1 2 3)
→ (1 (2 3))

(funcall (SL:FN (#(x y)) (+ x y)) #(1 2))
→ 3

(funcall (SL:FN ((:entry k v)) (cons k v)) (SL:MAP-ENTRY :a 1))
→ (:A . 1)
```

```lisp
(funcall (SL:FN (x)
  (DECLARE (TYPE INTEGER x) (OPTIMIZE (SPEED 3)))
  (1+ x))
 4)
→ 5
```

### SL:-> (Chapter 8)

**Notes:**

Use another threading macro when the subject is not the first argument.

**Examples:**

```lisp
(SL:-> x (f a) (g b)) ≡ (g (f x a) b)

(SL:-> 5 (+ 1) (* 2))
→ 12

(SL:SEQ-INTO 'string
  (SL:-> "a,b,c"
    (SL:SEQ-SPLIT :delimiter ",")
    (SL:REF 1)))
→ "b"
```

### SL:->> (Chapter 8)

**Notes:**

A trailing keyword tail receives the threaded form after its keywords; use
`SL:AS->` or `SL:~>` for such a step.

**Examples:**

```lisp
(SL:->> x (f a) (g b)) ≡ (g b (f a x))

(SL:->> '(1 2 3 4 5)
  (SL:SEQ-FILTER #'evenp)
  (SL:SEQ-MAP #'1+)
  (SL:SEQ-INTO 'list))
→ (3 5)

(SL:->> (SL:RANGE :end 100)
  (SL:SEQ-TAKE 5)
  (SL:SEQ-MAP (SL:OP (* % %)))
  (SL:SEQ-INTO 'list))
→ (0 1 4 9 16)
```

### SL:AS-> (Chapter 8)

**Notes:**

The caller chooses the threading variable; it is an ordinary successive binding,
not an implicit placeholder or an occurrence-substitution mechanism. Each step is
left as written, so unused steps, keyword constants, closures, quotation, and
macros follow ordinary Common Lisp evaluation.

**Examples:**

```lisp
(SL:AS-> x $ (f a $ b) (g $)) ≡ (let* (($ x) ($ (f a $ b))) (g $))

(SL:AS-> (SL:RANGE :end 10) $
  (SL:SEQ-FILTER #'evenp $ :count 3)
  (SL:SEQ-INTO 'list $))
→ (0 2 4)

(SL:AS-> "a,b,c" s
  (SL:SEQ-SPLIT s :delimiter ",")
  (SL:SEQ-MAP #'string-upcase s)
  (SL:SEQ-JOIN 'string s :separator "-"))
→ "A-B-C"
```

```lisp
(SL:AS-> 1 value (progn value :discarded) :done)
→ :DONE ; the unused final step is an ordinary keyword constant

(SL:AS-> 10 value
  (let ((f (lambda () value)))
    (let ((value 20))
      (funcall f)))
  value)
→ 10 ; closure capture and shadowing follow ordinary lexical rules

(SL:AS-> 10 value '(value))
→ (VALUE) ; QUOTE is not scanned for substitution

(SL:AS-> :start value (values :one :two))
→ :ONE :TWO ; the final step preserves multiple values
```

### SL:~> (Chapter 8)

**Notes:**

The explicit hole permits keyword tails without naming a threading variable.

**Examples:**

```lisp
(SL:~> 5 1+)
→ 6

(SL:~> "a,b,c"
  (SL:SEQ-SPLIT SL:<> :delimiter ",")
  (SL:SEQ-INTO 'list SL:<>))
→ ("a" "b" "c")

;; a list step with no SL:<> signals PROGRAM-ERROR:
;; (SL:~> x (SL:SEQ-FILTER #'evenp))
```

### SL:<> (Chapter 8)

**Examples:**

```lisp
(SL:~> 5 (+ SL:<> 1))
→ 6
```

### SL:JUXT (Chapter 8)

**Notes:**

Under the lexicographic `SL:COMPARE` of Chapter 7, a `SL:JUXT` result can serve
as a composite sort key.

**Examples:**

```lisp
(funcall (SL:JUXT #'1+ #'1-) 5)
→ (6 4)

(mapcar (SL:JUXT #'car #'cdr) '((1 2) (3 4)))
→ ((1 (2)) (3 (4)))

(SL:SEQ-SORT '((a 2) (b 1)) :key (SL:JUXT #'second #'first))
→ ((b 1) (a 2))
```

### SL:COMPOSE (Chapter 8)

**Notes:**

For example, `(SL:COMPOSE #'f #'g #'h)` composes `f` with the composition of
`g` and `h`.

**Examples:**

```lisp
(funcall (SL:COMPOSE #'1+ (lambda (x) (* x x))) 3)
→ 10

(mapcar (SL:COMPOSE #'1+ (lambda (x) (* x x))) '(1 2 3))
→ (2 5 10)
```

## D.8 Chapter 9: Dictionaries and the Dict Protocol

### Ordered dictionaries (Chapters 4, 6–9)

**Notes:**

`SL:ORDERED-DICT-P` tests the concrete type; `SL:DICTP` tests participation
in the Dict protocol. The constructor's alternating arguments have no options.
The ordinary Collector rejects options, while batch `SL:DICT-COLLECT` ignores
`:TEST`. These examples describe the normative contract, not a readable printer
syntax. Ordered dictionaries print diagnostically; readable printing signals
`PRINT-NOT-READABLE` even for an empty instance.

**Examples:**

```lisp
(SL:DICT-ALIST (SL:ORDERED-DICT :a 1 :b 2 :a 3))
→ ((:A . 3) (:B . 2))

(let* ((d (SL:ORDERED-DICT :a 1 :b 2))
       (r (SL:DICT-SET (SL:DICT-WITHOUT d :a) :a 3)))
  (list (SL:DICT-ALIST d) (SL:DICT-ALIST r)))
→ (((:A . 1) (:B . 2)) ((:B . 2) (:A . 3)))

(let* ((first (copy-seq "k")) (last (copy-seq "k"))
       (value (list :shared))
       (d (SL:DICT-SET (SL:ORDERED-DICT first value) last value)))
  (eq last (SL:ENTRY-KEY (SL:SEQ-FIRST d))))
→ T ; equal value identity does not suppress latest key replacement

(let ((d (SL:ORDERED-DICT 9 :first 0 :zero)))
  (list (SL:REF d 0) (SL:ENTRY-KEY (SL:SEQ-REF d 0))))
→ (:ZERO 9) ; keyed value versus positional entry

(SL:BIND ((#(a b) (SL:ORDERED-DICT 1 :one 0 :zero))) (list a b))
→ (:ZERO :ONE) ; vector patterns use integer keys, not stored positions

(SL:DICT-ALIST
 (SL:SEQ-MAP (lambda (entry) (SL:MAP-ENTRY :same (SL:ENTRY-VALUE entry)))
             (SL:ORDERED-DICT :a 1 :b 2)))
→ ((:SAME . 2)) ; two emissions, one resident key

(SL:ORDERED-DICT-P (SL:SEQ-KEEP (constantly nil) (SL:ORDERED-DICT :a 1)))
→ T ; typed empty, not NIL
(SL:SEQ-MAP #'SL:ENTRY-VALUE (SL:ORDERED-DICT :a 1))
; signals TYPE-ERROR; use an explicit list/lazy source for scalar projection
(SL:SEQ-MAP #'SL:ENTRY-VALUE
            (SL:SEQ-INTO 'list (SL:ORDERED-DICT :a 1 :b 2)))
→ (1 2)

(SL:SEQ-REDUCTIONS #'LIST (SL:ORDERED-DICT) :INITIAL-VALUE NIL)
; signals TYPE-ERROR: the supplied initial state is emitted
(SL:ORDERED-DICT-P (SL:SEQ-REDUCTIONS #'LIST (SL:ORDERED-DICT)))
→ T ; no states emitted

(SL:DICT-ALIST
 (SL:SEQ-SUBSTITUTE-IF :unused (constantly nil) (SL:ORDERED-DICT :a 1)))
→ ((:A . 1)) ; unused non-entry replacement is not rejected

(SL:DICT-ALIST
 (SL:DICT-SET (SL:SEQ-REVERSE (SL:ORDERED-DICT :a 1 :b 2)) :c 3))
→ ((:B . 2) (:A . 1) (:C . 3)) ; new stored order governs later insertion

(let* ((pair (SL:SEQ-SPLIT-AT 0 (SL:ORDERED-DICT :a 1)))
       (prefix (SL:SEQ-FIRST pair)))
  (list (SL:ORDERED-DICT-P prefix) (SL:SEQ-EMPTYP prefix)
        (eq prefix (SL:SEQ-FIRST pair))))
→ (T T T) ; lazy outer pair, typed empty prefix, memoized identity

(SL:DICT-ALIST
 (SL:SEQ-FIRST
  (SL:SEQ-PARTITION 2 (SL:ORDERED-DICT :a 1)
                    :PAD (list (SL:MAP-ENTRY :a 2)))))
→ ((:A . 2)) ; a complete two-emission window, one unique key

(let ((chunks (SL:SEQ-PARTITION 2 (SL:ORDERED-DICT :a 1) :PAD '(bad))))
  (SL:SEQ-FIRST chunks))
; signals TYPE-ERROR at chunk forcing, not at PARTITION call time

(SL:DICT-ALIST
 (SL:DICT-MERGE (SL:ORDERED-DICT :a 1 :b 2)
                (SL:ORDERED-DICT :b 3 :c 4)))
→ ((:A . 1) (:B . 3) (:C . 4))

(SL:EQUALS (SL:ORDERED-DICT :a 1 :b 2) (SL:ORDERED-DICT :b 2 :a 1))
→ NIL
(SL:COMPARE (SL:ORDERED-DICT :a 1) (SL:ORDERED-DICT :b 2))
→ :UNEQUAL ; stored order does not provide dictionary ordering
(SL:EQUALS (SL:ORDERED-DICT) (SL:DICT)) → NIL
(SL:EQUALS (SL:DICT) (SL:ORDERED-DICT)) → NIL

(SL:ORDERED-DICT-P
 (SL:DICT-REF (SL:DICT-SET-IN (SL:ORDERED-DICT) '(:a :b) 1) :a))
→ T ; missing child preserves its parent type
(typep (SL:DICT-FREQUENCIES (SL:ORDERED-DICT :a 1)) 'SL:DICT) → T
; fixed-result producers do not infer ordered result types
```

### Promotion examples (Chapter 6)

**Notes:**

Two categories of operation on built-in dictionary inputs promote their result
to `SL:ORDERED-DICT`. Sorting and reversal operations normalize entries into a
stable order and then reorder them; callbacks observe the original entries.
Transforming operations, such as `SL:SEQ-MAP`, emit transformed entries and
then reconstruct; reconstruction coalesces keys under `SL:EQUALS`, so keys that
were distinct under a source hash-table test may coalesce when the callback
changes a key.

**Examples:**

```lisp
(SL:SEQ-MAP (lambda (e)
              (SL:MAP-ENTRY (SL:ENTRY-KEY e)
                            (1+ (SL:ENTRY-VALUE e))))
            #h(:a 1 :b 2))
→ an SL:ORDERED-DICT with :A → 2 and :B → 3

(SL:DICT-ALIST
 (SL:SEQ-SORT #h(:b 2 :a 1)
              :KEY (lambda (e) (SYMBOL-NAME (SL:ENTRY-KEY e)))))
→ ((:A . 1) (:B . 2))
; normalize-then-reorder ensures a sorted result; keys coalesce under
; SL:EQUALS before sorting

(SL:SEQ-REVERSE (SL:DICT :a 1 :b 2))
→ an SL:ORDERED-DICT with entries in reverse of the source traversal order

(SL:ORDERED-DICT-P
 (SL:SEQ-CONCATENATE (SL:DICT :a 1) (SL:DICT :b 2)))
→ T

(SL:LAZY-SEQ-P (SL:SEQ-CONCATENATE #d(:a 1) (list 2 3)))
→ T ; mixed dict and list input stays lazy
```

### Collision illustration (Chapter 6)

An EQ-keyed hash table can contain two distinct string objects whose contents
are both `"a"`. Promotion coalesces them under `SL:EQUALS`, so the result has
fewer entries than the source.

```lisp
(let* ((key-1 (copy-seq "a"))
       (key-2 (copy-seq "a"))
       (h (make-hash-table :test #'eq)))
  (setf (gethash key-1 h) 1
        (gethash key-2 h) 2)
  (let ((result
          (SL:SEQ-MAP (lambda (entry)
                        (SL:MAP-ENTRY (SL:ENTRY-KEY entry)
                                      (SL:ENTRY-VALUE entry)))
                      h)))
    (list (hash-table-count h) (SL:DICT-SIZE result))))
→ (2 1)
```

### Dictionary mapping, selection, merging, counting, and reduction (Chapter 9)

**Examples:**

```lisp
(SL:DICT-VALUES-MAP #'1+ #d(:a 1 :b 2))
→ #d(:a 2 :b 3)

(SL:DICT-KEYS-MAP #'STRING-DOWNCASE #d("A" 1 "B" 2))
→ #d("a" 1 "b" 2)

(SL:DICT-KEYS-MAP (constantly :same) #d(:a 1 :b 2) :collision :error)
; signals PROGRAM-ERROR if two keys collide

(SL:DICT-SELECT-KEYS #d(:a 1 :b 2 :c 3) '(:a :c))
→ #d(:a 1 :c 3)

(SL:DICT-REMOVE-KEYS #d(:a 1 :b 2 :c 3) '(:b))
→ #d(:a 1 :c 3)

(SL:DICT-MERGE-WITH #'+ #d(:a 1 :b 2) #d(:a 3))
→ #d(:a 4 :b 2)

(SL:DICT-COUNT-BY #'EVENP '(1 2 3 4 5 6))
→ #d(NIL 3 T 3)

(SL:DICT-REDUCE-KV (lambda (acc k v) (+ acc v))
                   0
                   #d(:a 1 :b 2 :c 3))
→ 6
```

### Escape hatch (Chapter 6)

```lisp
(SL:SEQ-MAP fn (SL:SEQ-INTO 'SL:LAZY-SEQ dict))
→ a lazy sequence, not an SL:ORDERED-DICT
```

### SL:DICT _Type_ (Chapter 9)

**Notes:**

The name `SL:DICT` is shared between the type and the element constructor, as `CL:CONS` is shared
between the function and the type. The empty dict is `(SL:DICT)`; there is no distinct empty-object
constant, and the identity of two separately constructed empty dicts is unspecified.

**Examples:**

```lisp
(typep (SL:DICT :a 1 :b 2) 'SL:DICT)              ; → T
(SL:SEQABLEP (SL:DICT :a 1))                      ; → T
```

### SL:DICT _Function_ (Chapter 9)

**Examples:**

```lisp
(SL:DICT-REF (SL:DICT :a 1 :b 2) :b)     ; → 2, T
(SL:DICT-SIZE (SL:DICT :a 1 :a 2))       ; → 1 (last-wins)
(SL:DICT-REF (SL:DICT 1 :int 1.0 :float) 1) ; → :FLOAT, T (1 and 1.0 are SL:EQUALS)
```

### SL:DICTP (Chapter 9)

**Examples:**

```lisp
(SL:DICTP (SL:DICT :a 1)) ; → T
(SL:DICTP '((:a . 1)))    ; → NIL (an alist is not a dict)
(SL:DICTP 42)             ; → NIL
```

### SL:DICT-REF (Chapter 9)

**Notes:**

Use `SL:DICT-MEMBER` when presence must be tested directly.

**Examples:**

```lisp
(SL:DICT-REF (SL:DICT :a 1 :b 2) :c)          ; → NIL, NIL
(SL:DICT-REF (SL:DICT :a 1 :b 2) :c :missing) ; → :MISSING, NIL
(let ((h #h(:a 1)))
  (SETF (SL:DICT-REF h :a) 10)
  (SL:DICT-REF h :a))                         ; → 10
```

### (SETF SL:DICT-REF) (Chapter 9)

**Notes:**

`(SETF SL:DICT-REF)` is the destructive dict write operation. The default argument is never read.

**Examples:**

```lisp
(let ((h #h(:a 1)))
  (SETF (SL:DICT-REF h :a :ignored) 10)
  (SL:DICT-REF h :a))                         ; → 10, T
```

### SL:DICT-TEST (Chapter 9)

**Notes:**

The dict protocol has no configurable-test constructor for `SL:DICT`: the constructor takes no
`:test`, and the `SL:DICT` `SL:DICT-COLLECT` method ignores the *test* argument, because `SL:DICT`
has exactly one test, `SL:EQUALS`. Users needing a different test for keyed lookup use a hash
table with the corresponding standard test.

**Examples:**

```lisp
(EQ (SL:DICT-TEST (SL:DICT :a 1)) #'SL:EQUALS) ; → T
(SL:DICT-TEST #h(:a 1))                        ; → EQUAL (the #h() default)
(member (SL:DICT-TEST #h(:a 1)) '(EQ EQL EQUAL EQUALP)) ; → (EQUAL EQUALP)
```

### SL:DICT-SIZE (Chapter 9)

**Examples:**

```lisp
(SL:DICT-SIZE (SL:DICT))                  ; → 0
(SL:DICT-SIZE (SL:DICT :a 1 :b 2))        ; → 2
(SL:DICT-SIZE #h(:a 1 :b 2))              ; → 2
```

### SL:DICT-SET (Chapter 9)

**Notes:**

On a standard hash table, `SL:DICT-SET` makes a fresh shallow copy, preserving the
hash-table test and resident key/value object identity; it does not mutate the source.

**Examples:**

```lisp
(let ((d (SL:DICT :a 1))
      (dict2 (SL:DICT-SET (SL:DICT :a 1) :b 2)))
  (values (SL:DICT-SIZE d)               ; original unchanged
          (SL:DICT-SIZE dict2)
          (SL:DICT-REF dict2 :b)))          ; → 1, 2, 2, T
(SL:DICT-REF (SL:DICT-SET (SL:DICT :a 1) :a 9) :a) ; → 9, T

(let* ((h #h(:a 1))
       (copy (SL:DICT-SET h :b 2)))
  (list (not (eq h copy)) (hash-table-test copy)
        (gethash :a h) (gethash :b copy)))
; → (T EQUAL 1 2), with H unchanged
```

### SL:DICT-WITHOUT (Chapter 9)

**Notes:**

On a standard hash table, `SL:DICT-WITHOUT` makes a fresh shallow copy even when the
key is absent. It preserves the hash-table test, shares resident key/value objects,
and leaves the source unchanged.

**Examples:**

```lisp
(SL:DICT-REF (SL:DICT-WITHOUT (SL:DICT :a 1 :b 2) :a) :a) ; → NIL, NIL
(SL:DICT-SIZE (SL:DICT-WITHOUT (SL:DICT :a 1 :b 2) :a))   ; → 1
(SL:DICT-SIZE (SL:DICT-WITHOUT (SL:DICT :a 1) :absent))   ; → 1 (no-op)

(let* ((h #h(:a 1))
       (copy (SL:DICT-WITHOUT h :absent)))
  (list (not (eq h copy)) (hash-table-test copy)
        (gethash :a h) (gethash :a copy)))
; → (T EQUAL 1 1), with H unchanged
```

### SL:DICT-COLLECT (Chapter 9)

**Examples:**

```lisp
;; Built-in participation:
(typep (SL:DICT-COLLECT (SL:DICT) (SL:SEQ-INTO 'LAZY-SEQ #h(:a 1)))
       'SL:DICT)                                   ; → T
;; User participation:
(defmethod SL:DICT-COLLECT ((source my-dict) entries &key (test 'EQL))
  (my-dict-from-entries entries test))
```

### SL:DICT-KEYS (Chapter 9)

**Examples:**

```lisp
(SL:SEQ-INTO 'list (SL:DICT-KEYS (SL:DICT :a 1 :b 2))) ; → (:A :B) in some order
```

### SL:DICT-VALS (Chapter 9)

**Examples:**

```lisp
(SL:SEQ-INTO 'list (SL:DICT-VALS #h(:a 1 :b 2))) ; → (1 2) in some order
```

### SL:DICT-FREQUENCIES (Chapter 9)

**Examples:**

```lisp
(SL:DICT-REF (SL:DICT-FREQUENCIES '(:a :b :a :c :b :a)) :a) ; → 3
(SL:DICT-SIZE (SL:DICT-FREQUENCIES '(:a :b :a :c :b :a)))   ; → 3
(SL:DICT-REF (SL:DICT-FREQUENCIES '(1 1.0 2)) 1)      ; → 2 (1 and 1.0 are SL:EQUALS)
```

### SL:DICT-GROUP-BY (Chapter 9)

**Examples:**

```lisp
(SL:DICT-REF (SL:DICT-GROUP-BY #'evenp '(1 2 3 4 5)) t)    ; → (2 4)
(SL:DICT-REF (SL:DICT-GROUP-BY #'evenp '(1 2 3 4 5)) NIL)  ; → (1 3 5)
(SL:SEQ-INTO 'list
             (SL:DICT-REF (SL:DICT-GROUP-BY #'length '("a" "bb" "c" "dd")) 2))
; → ("bb" "dd")
```

### SL:DICT-ZIPMAP (Chapter 9)

**Examples:**

```lisp
(SL:DICT-REF (SL:DICT-ZIPMAP '(:a :b :c) '(1 2 3)) :b)  ; → 2
(SL:DICT-SIZE (SL:DICT-ZIPMAP '(:a :b) '(1 2 3)))      ; → 2 (stops at shorter)
(SL:DICT-REF (SL:DICT-ZIPMAP '(:a :a) '(1 2)) :a)      ; → 2 (last-wins)
```

### SL:DICT-MERGE (Chapter 9)

**Notes:**

For more than two dicts, use `SL:DICT-MERGE*`. A caller starting with an entry seq must first
convert it with `(SL:SEQ-INTO 'dict entry-seq)`; an entry seq is not an accepted input to
`SL:DICT-MERGE`. With `:collision :error`, the selected result test also detects distinct keys
that coalesce within one source, and the operation stops at the first detected collision without
returning a partial dictionary. Result traversal order is unspecified for
`SL:DICT` and hash-table results; when both sources are `SL:ORDERED-DICT`,
the result is an `SL:ORDERED-DICT` with left positions preserved and right
collisions replacing associations without movement, as specified in
Chapter 9.

**Examples:**

```lisp
(SL:DICT-REF (SL:DICT-MERGE (SL:DICT :a 1 :b 2) (SL:DICT :b 3 :c 4)) :b)
; → 3 (rightmost wins)
(SL:DICT-SIZE (SL:DICT-MERGE (SL:DICT :a 1) (SL:DICT :b 2))) ; → 2
(typep (SL:DICT-MERGE #h(:a 1) #h(:b 2)) 'hash-table)        ; → T (same test)
(typep (SL:DICT-MERGE (SL:DICT :a 1) #h(:b 2)) 'SL:DICT)     ; → T (mixed types)
(SL:DICT-MERGE (SL:DICT :a 1) (SL:DICT :a 2) :collision :error)
; signals PROGRAM-ERROR

(let ((eql-table #h(eql 1 :one 1.0 :float))
      (empty (SL:DICT))
      (outcomes nil))
  (dolist (order (list (list eql-table empty) (list empty eql-table)))
    (push
     (handler-case
         (apply #'SL:DICT-MERGE (append order (list :collision :error)))
       (program-error () :collision))
     outcomes))
  (nreverse outcomes))
; → (:COLLISION :COLLISION); the mixed-test source's 1 and 1.0 coalesce under SL:EQUALS
```

### SL:DICT-TRANSFORM (Chapter 9)

**Notes:**

Swapping key and value with `(lambda (k v) (values v k))` is the map-invert idiom. Under
`:collision :error`, transformed keys are checked after the callback's two-value result is
validated; a collision stops processing, runs no later callbacks, returns no partial dictionary,
and does not roll back earlier callback side effects.

**Examples:**

```lisp
(SL:DICT-REF (SL:DICT-TRANSFORM (lambda (k v) (values k (* v 10)))
                                (SL:DICT :a 1 :b 2))
             :a)                                          ; → 10
(SL:DICT-REF (SL:DICT-TRANSFORM (lambda (k v) (values v k))
                                (SL:DICT :a 1 :b 2))
             1)                                           ; → :A (map-invert)
(SL:DICT-TRANSFORM (lambda (k v) (values :same v))
                   (SL:DICT :a 1 :b 2)
                   :collision :error)
; signals PROGRAM-ERROR (both entries coalesce onto :SAME)

(let ((calls 0) (effects nil)
      (source (SL:DICT :a 1 :b 2 :c 3)))
  (handler-case
      (SL:DICT-TRANSFORM
       (lambda (k v)
         (incf calls) (push k effects)
         (values :same v))
       source :collision :error)
    (program-error () (list calls (length effects) (SL:DICT-SIZE source)))))
; → (2 2 3); No third callback is made; the identities of the two visited entries are unspecified.
; SOURCE is unchanged, and callback effects remain
```

### SL:ALIST-DICT (Chapter 9)

**Notes:**

An alist is a seq of conses, not a dict: `SL:DICTP` is false for it, and
`SL:DICT-REF` signals on it. The reverse conversion is `SL:DICT-ALIST`. The
conversion is O(n) and does not share the source list's outer alist spine or association-wrapper
conses; keys and values may be shared.

**Examples:**

```lisp
(SL:DICT-SIZE (SL:ALIST-DICT '((a . 1) (a . 2)))) ; → 1 (last-wins: 2)
```

### SL:PLIST-DICT (Chapter 9)

**Examples:**

```lisp
(SL:DICT-REF (SL:PLIST-DICT '(:a 1 :b 2)) :a) ; → 1, T
```

### SL:PLIST-DICT-VIEW _Type_ (Chapter 9)

**Notes:**

The backing plist is not copied. Mutation of it after adapter creation has undefined consequences.

### SL:PLIST-DICT-VIEW _Function_ (Chapter 9)

**Examples:**

```lisp
(SL:DICT-REF (SL:PLIST-DICT-VIEW '(:a 1 :b 2)) :a)    ; → 1, T
(SL:DICT-REF (SL:PLIST-DICT-VIEW '(:a 1 :b 2)) :c)    ; → NIL, NIL
(SL:DICT-SIZE (SL:PLIST-DICT-VIEW '(:a 1 :a 2)))      ; → 1 (first-match: 1)
(SL:DICT-REF (SL:PLIST-DICT-VIEW '(:a 1 :a 2)) :a)     ; → 1, T (first-match)
(SL:DICT-TEST (SL:PLIST-DICT-VIEW '(:a 1)))           ; → EQ
(SL:DOSEQ ((:entry k v) (SL:PLIST-DICT-VIEW '(:a 1 :b 2)))
  (format t "~A=~A " k v))                            ; prints :A=1 :B=2
(SL:DICT-SET (SL:PLIST-DICT-VIEW '(:a 1)) :b 2)
; signals PROGRAM-ERROR (read-only)
```

### SL:DICT-ALIST (Chapter 9)

**Notes:**

The reverse conversion is `SL:ALIST-DICT`. Round-tripping an `SL:DICT`
through `SL:DICT-ALIST` and `SL:ALIST-DICT` recovers an equal `SL:DICT`;
round-tripping a hash table or user dict through it may change the type and
test of the result (`SL:ALIST-DICT` always constructs an `SL:DICT`), and may
coalesce keys that were distinct under the source's test. Round-tripping an
alist through `SL:DICT-ALIST` loses duplicate keys and reorders pairs,
because the dict in between has unique keys and unordered traversal.

**Examples:**

```lisp
(CL:ASSOC :a (SL:DICT-ALIST (SL:DICT :a 1 :b 2))) ; → (:A . 1)
```

### SL:DICT-PLIST (Chapter 9)

**Notes:**

The reverse conversion is `SL:PLIST-DICT`. As with `SL:DICT-ALIST`,
round-tripping an `SL:DICT` through `SL:DICT-PLIST` and `SL:PLIST-DICT`
recovers an equal `SL:DICT`; round-tripping a hash table or user dict
through it may change the type and test of the result (`SL:PLIST-DICT`
always constructs an `SL:DICT`), and may coalesce keys that were distinct
under the source's test. The reverse direction loses duplicate keys and
reorders pairs.

**Examples:**

```lisp
(CL:GETF (SL:DICT-PLIST (SL:DICT :a 1 :b 2)) :a) ; → 1
```

### SL:DICT-MEMBER (Chapter 9)

**Notes:**

A present key whose value is `NIL` returns `(values t NIL)`; the primary
value alone is always a correct presence test.

**Examples:**

```lisp
(SL:DICT-MEMBER (SL:DICT :a 1 :b 2) :a)  ; → T, 1
(SL:DICT-MEMBER (SL:DICT :a 1 :b 2) :c)  ; → NIL, NIL
(SL:DICT-MEMBER (SL:DICT :a NIL) :a)     ; → T, NIL (present key, NIL value)
(SL:DICT-MEMBER #h(:a 1) :a)             ; → T, 1
```

### SL:DICT-MERGE* (variadic) (Chapter 9)

**Notes:**

The binary `SL:DICT-MERGE` with its `:collision` option remains for the
two-input case where a non-last-wins collision policy is needed.

**Examples:**

```lisp
(SL:DICT-REF (SL:DICT-MERGE* (SL:DICT :a 1) (SL:DICT :a 2) (SL:DICT :a 3)) :a)
; → 3 (rightmost wins)
(SL:DICT-SIZE (SL:DICT-MERGE* (SL:DICT :a 1) (SL:DICT :b 2) (SL:DICT :c 3))) ; → 3
(typep (SL:DICT-MERGE* #h(:a 1) #h(:b 2) #h(:c 3)) 'hash-table) ; → T (same test)
(typep (SL:DICT-MERGE* (SL:DICT :a 1) #h(:b 2) (SL:DICT :c 3)) 'SL:DICT)   ; → T (mixed)
```

### SL:DICT-UPDATE (Chapter 9)

**Notes:**

`SL:DICT-UPDATE` invokes its callback once and uses only its primary value. On a standard
hash table it returns the fresh shallow-copy result of `SL:DICT-SET`; present `NIL` is
not absence, and a callback failure leaves the input table unchanged.

**Examples:**

```lisp
(SL:DICT-REF (SL:DICT-UPDATE (SL:DICT :a 1) :a #'1+) :a)            ; → 2
(SL:DICT-REF (SL:DICT-UPDATE (SL:DICT :a 1) :b (lambda (x) 99)) :b)  ; → 99 (absent, NIL passed)
(SL:DICT-REF (SL:DICT-UPDATE (SL:DICT :a 1) :b #'1+ :default 0) :b) ; → 1
(SL:DICT-REF (SL:DICT-UPDATE (SL:DICT :a NIL) :a (lambda (x) 1)) :a) ; → 1 (present NIL value)

(let ((h #h(eql :a nil)) (calls 0))
  (let ((copy (SL:DICT-UPDATE h :a (lambda (x) (incf calls) (values :updated :ignored)))))
    (list calls (not (eq h copy)) (hash-table-test copy)
          (gethash :a h) (gethash :a copy))))
; → (1 T EQL NIL :UPDATED), with H unchanged and only the primary callback value used
```

### SL:DICT-UPDATE-IN (Chapter 9)

**Notes:**

Nested updates rebuild each ancestor non-destructively. A missing child under a hash table
is a fresh hash table with the parent's test; a mixed hash-table/`SL:DICT` path preserves
each ancestor's supported type and test. Present `NIL` remains distinct from a missing leaf,
and malformed or read-only intermediates are rejected before the callback.
The eagerly evaluated `:default` supplies only an absent leaf's callback input;
it is not an intermediate dictionary or a default-producing thunk.

**Examples:**

```lisp
(SL:DICT-REF (SL:DICT-UPDATE-IN (SL:DICT :a (SL:DICT :b 1)) '(:a :b) #'1+) :a)
; → #d(:b 2)
(SL:DICT-REF (SL:DICT-UPDATE-IN (SL:DICT) '(:a :b) (lambda (x) 99)) :a)
; → #d(:b 99) (missing intermediates constructed)
(SL:DICT-REF-IN (SL:DICT-UPDATE-IN (SL:DICT) '(:a :b) #'1+ :default 0) '(:a :b))
; → 1, T (DEFAULT applies at the absent leaf)
(SL:DICT-UPDATE-IN (SL:DICT :a 1) '(:a :b) (lambda (x) x))
; signals TYPE-ERROR (:a is present but not a dict)
(SL:DICT-UPDATE-IN (SL:DICT :a 1) '() (lambda (x) x))
; signals PROGRAM-ERROR (empty keys)

(let* ((h #h(eql :a (SL:DICT :b 1)))
       (copy (SL:DICT-UPDATE-IN h '(:a :b) #'1+)))
  (list (hash-table-test copy) (typep (gethash :a copy) 'SL:DICT)
        (SL:DICT-REF (gethash :a h) :b)
        (SL:DICT-REF (gethash :a copy) :b)))
; → (EQL T 1 2), with both source containers unchanged
```

### SL:DICT-SET-IN (Chapter 9)

**Notes:**

`SL:DICT-SET-IN` constructs missing intermediates and rebuilds existing ancestors using
non-destructive `SL:DICT-SET`; standard hash-table ancestors retain their tests and inputs
remain unchanged.

**Examples:**

```lisp
(SL:DICT-REF (SL:DICT-SET-IN (SL:DICT :a (SL:DICT :b 1)) '(:a :b) 99) :a)
; → #d(:b 99)
(SL:DICT-REF (SL:DICT-SET-IN (SL:DICT) '(:x :y) 42) :x)
; → #d(:y 42) (missing intermediates constructed)
(SL:DICT-SET-IN (SL:DICT :a 1) '(:a :b) 42)
; signals TYPE-ERROR (:a is present but not a dict)

(let* ((h (make-hash-table :test 'equal))
       (copy (SL:DICT-SET-IN h '(:x :y) 42)))
  (list (hash-table-test copy)
        (hash-table-p (gethash :x copy))
        (gethash :x h) (gethash :y (gethash :x copy))))
; → (EQUAL T NIL 42), with H unchanged
```

### SL:DICT-REF-IN (Chapter 9)

**Examples:**

```lisp
(SL:DICT-REF-IN (SL:DICT :a (SL:DICT :b 1)) '(:a :b))        ; → 1, T
(SL:DICT-REF-IN (SL:DICT :a (SL:DICT :b 1)) '(:a :x))        ; → NIL, NIL
(SL:DICT-REF-IN (SL:DICT :a (SL:DICT :b 1)) '(:x :b))        ; → NIL, NIL
(SL:DICT-REF-IN (SL:DICT :a (SL:DICT :b NIL)) '(:a :b))      ; → NIL, T
(SL:DICT-REF-IN (SL:DICT :a "not a dict") '(:a :b))          ; signals TYPE-ERROR
(SL:DICT-REF-IN (SL:DICT :a "not a dict") '(:a))            ; → "not a dict", T
(SL:DICT-REF-IN (SL:DICT :a (SL:DICT :b 2)) '(:a :b) :missing)
; → 2, T
(SL:DICT-REF-IN (SL:DICT :a (SL:DICT)) '(:a :b) :missing)
; → :MISSING, NIL
(SL:DICT-REF-IN (SL:DICT :a 1) '())                          ; signals PROGRAM-ERROR
```

### SL:HASH-SET _Type_ (Chapter 9)

**Notes:**

The `#u()` reader macro provides literal syntax (Chapter 3).

**Examples:**

```lisp
(SL:SEQ-LENGTH (SL:HASH-SET :a :a :b))  ; → 2 (deduplicated)
(SL:DICTP (SL:HASH-SET :a))             ; → NIL (not a dict)
(SL:EQUALS (SL:HASH-SET :a :b) (SL:HASH-SET :b :a)) ; → T (order-independent)
```

### SL:HASH-SET _Function_ (Chapter 9)

**Notes:**

For constructing a hash-set from a seqable, use
`(SL:SEQ-INTO 'SL:HASH-SET sequence)`. The `#u()` reader macro provides
literal syntax (Chapter 3).

**Examples:**

```lisp
(SL:HASH-SET)              ; → empty hash-set
(SL:HASH-SET :a :b :c)     ; → hash-set of :a, :b, :c
(SL:HASH-SET :a :a :b)     ; → hash-set of :a, :b (deduplicated)
(SL:HASH-SET 1 1.0)        ; → hash-set of one element (1 and 1.0 coalesce under SL:EQUALS)
```

### SL:HASH-SET-P (Chapter 9)

**Notes:**

`SL:HASH-SET-P` is true only of `SL:HASH-SET` objects; it is false for
dicts, hash tables, and lists.

**Examples:**

```lisp
(SL:HASH-SET-P (SL:HASH-SET :a))  ; → T
(SL:HASH-SET-P (SL:DICT :a 1))    ; → NIL
(SL:HASH-SET-P '(:a :b))          ; → NIL
(SL:HASH-SET-P #h(:a 1))          ; → NIL
```

### SL:SET-MEMBER (Chapter 9)

**Notes:**

Membership is always under `SL:EQUALS`; there is no `:test` keyword.

**Examples:**

```lisp
(SL:SET-MEMBER :a (SL:HASH-SET :a :b :c))  ; → T
(SL:SET-MEMBER :d (SL:HASH-SET :a :b :c))  ; → NIL
(SL:SET-MEMBER 1 '(1 2 3))                 ; → T (list as set)
(SL:SET-MEMBER 1.0 '(1 2 3))               ; → T (1 and 1.0 coalesce under SL:EQUALS)
```

### SL:SET-ADD (Chapter 9)

**Notes:**

To add an element to a list and still get a list, use
`SL:SEQ-CONCATENATE` or `CL:CONS`; `SL:SET-ADD` always returns a
hash-set.

**Examples:**

```lisp
(SL:SET-ADD :a '(:b :c))            ; → hash-set containing :a, :b, and :c (order unspecified)
(SL:SET-ADD :a (SL:HASH-SET :a :b)) ; → hash-set containing :a and :b (may be input)
```

### SL:SET-REMOVE (Chapter 9)

**Notes:**

To remove an element from a list and still get a list, use
`SL:SEQ-REMOVE`; `SL:SET-REMOVE` always returns a hash-set.

**Examples:**

```lisp
(SL:SET-REMOVE :a '(:a :b :c))         ; → hash-set containing :b and :c (order unspecified)
(SL:SET-REMOVE :d (SL:HASH-SET :a :b))  ; → hash-set of :a, :b
```

### SL:SET-UNION (Chapter 9)

**Notes:**

`SL:SET-UNION` always returns a hash-set regardless of input types.

**Examples:**

```lisp
(let ((result (SL:SET-UNION (SL:HASH-SET :a :b) (SL:HASH-SET :b :c))))
  (list (SL:SET-SIZE result)             ; → 3
        (SL:SET-MEMBER :a result)        ; → T
        (SL:SET-MEMBER :c result)))      ; → T
```

### SL:SET-INTERSECTION (Chapter 9)

**Notes:**

`SL:SET-INTERSECTION` always returns a hash-set regardless of input types.

**Examples:**

```lisp
(SL:SET-INTERSECTION '(:a :b :c) '(:b :c :d))
; → a hash-set containing :b and :c (order unspecified)
(SL:SET-INTERSECTION (SL:HASH-SET :a) '(:b))
; → an empty hash-set
```

### SL:SET-MINUS (Chapter 9)

**Examples:**

```lisp
(SL:SET-MINUS '(:a :b :c) '(:b :d))
; → a hash-set containing :a and :c (order unspecified)
```

### SL:SET-SUBSET-P (Chapter 9)

**Examples:**

```lisp
(SL:SET-SUBSET-P '(:a :b) '(:a :b :c)) ; → T
(SL:SET-SUBSET-P '(:a :d) '(:a :b :c)) ; → NIL
(SL:SET-SUBSET-P '() '(:a :b))         ; → T (empty set is a subset)
```

### SL:SET-SIZE (Chapter 9)

**Notes:**

`SL:SET-SIZE` counts distinct elements; `SL:SEQ-LENGTH` counts all
elements. On a hash-set, `SL:SET-SIZE` equalsp `SL:SEQ-LENGTH` (all
elements are distinct by construction).

**Examples:**

```lisp
(SL:SET-SIZE '(1 1 1 1))  ; → 1 (distinct count)
(SL:SEQ-LENGTH '(1 1 1 1)) ; → 4 (sequence length)
```
