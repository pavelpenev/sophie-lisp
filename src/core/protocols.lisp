;;;; Public generic-function contracts.
;;;;
;;;; This file intentionally declares the protocol surface only.  Concrete
;;;; methods belong to the units that own the corresponding behavior.

(in-package #:sophie-lisp.internal)

;;; Chapter 4 protocol primitives.
(defgeneric seqablep (object)
  (:documentation "Test whether OBJECT participates in the seq protocol."))

(defgeneric seq-emptyp (source)
  (:documentation "Test whether SOURCE is empty."))

(defgeneric seq-first (source)
  (:documentation "Return the first element of SOURCE."))

(defgeneric seq-rest (source)
  (:documentation "Return the sequence after the first element of SOURCE."))

(defgeneric seq-ref (source index &optional default)
  (:documentation "Return the element of SOURCE at INDEX and T, or DEFAULT and NIL when absent. A
negative INDEX counts from the end and requires a finite SOURCE; omitting
DEFAULT makes an absent position an error. An out-of-range position without a
supplied DEFAULT signals TYPE-ERROR; a negative INDEX on a source whose
SL:SEQ-LENGTH is NIL signals SIMPLE-ERROR, even when DEFAULT is supplied."))

(defgeneric (setf seq-ref) (new-value source index &optional default)
  (:documentation "Set the element of SOURCE at INDEX to NEW-VALUE."))

(defgeneric seq-length (source)
  (:documentation "Return the finite length of SOURCE, or NIL when unboundedness is known.
Determining the length may traverse SOURCE and may not terminate when its
boundedness is unknown."))

(defgeneric make-collector-for (target &rest options &key)
  (:documentation "Create mutable collector state for TARGET, using OPTIONS."))

(defgeneric collector-accumulate (collector element)
  (:documentation "Add ELEMENT to COLLECTOR and return the same COLLECTOR object."))

(defgeneric collector-result (collector)
  (:documentation "Return the completed result from COLLECTOR."))

;;; Chapter 6 sequence operations.
(defgeneric seq-last (source)
  (:documentation "Return the last element of SOURCE; signal an error when SOURCE is empty."))

(defgeneric seq-find (item source &key test key start end from-end)
  (:documentation "Return the source element matching ITEM under the supplied search options, or
NIL; :FROM-END T selects the last match."))

(defgeneric seq-find-if (predicate source &key key start end from-end)
  (:documentation "Return the source element satisfying PREDICATE, or NIL; :FROM-END T selects
the last match."))

(defgeneric seq-position (item source &key test key start end from-end)
  (:documentation "Return the position of ITEM in SOURCE, or NIL if absent."))

(defgeneric seq-position-if (predicate source &key key start end from-end)
  (:documentation "Return the position of the element satisfying PREDICATE, or NIL; :FROM-END T
selects the last match."))

(defgeneric seq-member (item source &key test key)
  (:documentation "Return a lazy sequence of the elements of SOURCE from the first match of ITEM
onward, or NIL; the result is always a lazy sequence regardless of the source
type."))

(defgeneric seq-count (item source &key test key start end from-end)
  (:documentation "Return the number of matching ITEM elements in SOURCE."))

(defgeneric seq-count-if (predicate source &key key start end from-end)
  (:documentation "Return the number of elements in SOURCE satisfying PREDICATE."))

(defgeneric seq-search
  (pattern source &key test key start1 end1 start2 end2 from-end)
  (:documentation "Return the subject position of a PATTERN occurrence, or NIL; :FROM-END T
selects the rightmost occurrence."))

(defgeneric seq-mismatch
  (source1 source2 &key test key start1 end1 start2 end2 from-end)
  (:documentation "Return the position of the first mismatch between SOURCE1 and SOURCE2, or NIL;
with :FROM-END T, return one past the rightmost mismatch, following
CL:MISMATCH."))

(defgeneric seq-every (predicate source &rest more-sources)
  (:documentation "Return true if PREDICATE is true for corresponding elements of the sources."))

(defgeneric seq-some (predicate source &rest more-sources)
  (:documentation "Return the first true value produced by PREDICATE over corresponding elements."))

(defgeneric seq-notevery (predicate source &rest more-sources)
  (:documentation "Return true if PREDICATE is false for some corresponding elements."))

(defgeneric seq-notany (predicate source &rest more-sources)
  (:documentation "Return true if PREDICATE is false for every corresponding element."))

(defgeneric seq-min (source &key key default)
  (:documentation "Return the element of SOURCE whose keyed value is least under SL:COMPARE, or
DEFAULT for an empty source; an empty source without DEFAULT or an
incomparable pair of keys signals an error."))

(defgeneric seq-max (source &key key default)
  (:documentation "Return the element of SOURCE whose keyed value is greatest under SL:COMPARE,
or DEFAULT for an empty source; an empty source without DEFAULT or an
incomparable pair of keys signals an error."))

(defgeneric seq-reduce
  (function source &key key start end from-end initial-value)
  (:documentation "Reduce SOURCE with FUNCTION and return the accumulated value; an empty
selected region requires :INITIAL-VALUE."))

(defgeneric seq-map (function sequence &rest more-sequences)
  (:documentation "Return a sequence containing FUNCTION results over the supplied sequences."))

(defgeneric seq-map-indexed (function sequence)
  (:documentation "Return a sequence of FUNCTION results, calling FUNCTION with a zero-based
index and the corresponding element."))

(defgeneric seq-filter
  (predicate sequence &key from-end start end key count)
  (:documentation "Return the elements of SEQUENCE satisfying PREDICATE."))

(defgeneric seq-keep (function sequence)
  (:documentation "Return a sequence of non-NIL results produced by FUNCTION over SEQUENCE."))

(defgeneric seq-remove
  (item sequence &key test key start end from-end count)
  (:documentation "Return SEQUENCE without elements matching ITEM."))

(defgeneric seq-remove-if
  (predicate sequence &key key start end from-end count)
  (:documentation "Return SEQUENCE without elements satisfying PREDICATE."))

(defgeneric seq-substitute
  (newitem olditem sequence &key test key start end from-end count)
  (:documentation "Return SEQUENCE with matching OLDITEM elements replaced by NEWITEM."))

(defgeneric seq-substitute-if
  (newitem predicate sequence &key key start end from-end count)
  (:documentation "Return SEQUENCE with elements satisfying PREDICATE replaced by NEWITEM."))

(defgeneric seq-mapcat (function sequence)
  (:documentation "Map FUNCTION over SEQUENCE and concatenate the resulting sequences."))

(defgeneric seq-take (count sequence)
  (:documentation "Return the first COUNT elements of SEQUENCE."))

(defgeneric seq-drop (count sequence)
  (:documentation "Return SEQUENCE after dropping its first COUNT elements."))

(defgeneric seq-take-while (predicate sequence)
  (:documentation "Return the leading elements of SEQUENCE satisfying PREDICATE."))

(defgeneric seq-drop-while (predicate sequence)
  (:documentation "Return SEQUENCE after its leading elements cease satisfying PREDICATE."))

(defgeneric seq-subseq (sequence start &optional end)
  (:documentation "Return the subsequence of SEQUENCE from START up to but not including END, or
to the end of SEQUENCE when END is omitted or NIL."))

(defgeneric seq-take-nth (count sequence)
  (:documentation "Return the elements of SEQUENCE at zero-based positions 0, COUNT, 2*COUNT, and
so on; COUNT must be a positive integer."))

(defgeneric seq-remove-duplicates
  (sequence &key test key start end from-end)
  (:documentation "Return SEQUENCE with duplicate elements removed."))

(defgeneric seq-dedupe (sequence &key test)
  (:documentation "Return SEQUENCE with adjacent duplicate elements removed."))

(defgeneric seq-trim-left (sequence &key predicate)
  (:documentation "Return SEQUENCE without its leading run of elements satisfying PREDICATE.
PREDICATE defaults to the character whitespace test for a string source and is
required for a non-string source; explicitly supplying NIL signals
PROGRAM-ERROR."))

(defgeneric seq-reductions (function sequence &key initial-value)
  (:documentation "Return the intermediate accumulated values from reducing SEQUENCE with FUNCTION."))

(defgeneric seq-concatenate (sequence &rest more-sources)
  (:documentation "Return a sequence formed by concatenating SEQUENCE and MORE-SOURCES."))

(defgeneric seq-interleave (&rest sources)
  (:documentation "Return a sequence formed by alternating elements from SOURCES."))

(defgeneric seq-split
  (sequence &key delimiter predicate test)
  (:documentation "Return a lazy sequence of portions of SEQUENCE split at delimiter or predicate
boundaries. Exactly one of :DELIMITER or :PREDICATE must be supplied;
supplying both or neither signals PROGRAM-ERROR. :TEST applies only in
delimiter mode."))

(defgeneric seq-split-at (count sequence)
  (:documentation "Return a two-element pair: the first COUNT elements of SEQUENCE, and the
remainder."))

(defgeneric seq-split-with (predicate sequence)
  (:documentation "Return two portions of SEQUENCE: the leading prefix satisfying PREDICATE and the suffix beginning at the first element that does not."))

(defgeneric seq-partition (count sequence &key step pad)
  (:documentation "Return SEQUENCE in chunks of COUNT elements, with chunk starts separated by
STEP (default COUNT); a short final chunk is dropped unless PAD is supplied."))

(defgeneric seq-partition-by (key-function sequence &key test)
  (:documentation "Return SEQUENCE split into maximal runs of adjacent elements whose
KEY-FUNCTION results are equal under TEST; non-adjacent runs are never
combined."))

(defgeneric seq-tree-seq (branch-function children-function tree)
  (:documentation "Return a lazy depth-first preorder traversal of TREE. BRANCH-FUNCTION returns
true for branch nodes; CHILDREN-FUNCTION returns their children."))

(defgeneric seq-drop-last (count sequence)
  (:documentation "Return SEQUENCE without its last COUNT elements."))

(defgeneric seq-reverse (sequence)
  (:documentation "Return SEQUENCE in reverse order."))

(defgeneric seq-sort (sequence &key test key)
  (:documentation "Return a sorted copy of SEQUENCE."))

(defgeneric seq-stable-sort (sequence &key test key)
  (:documentation "Return a stably sorted copy of SEQUENCE."))

(defgeneric seq-take-last (count sequence)
  (:documentation "Return the last COUNT elements of SEQUENCE."))

(defgeneric seq-trim-right (sequence &key predicate)
  (:documentation "Return SEQUENCE without its trailing run of elements satisfying PREDICATE.
PREDICATE defaults to the character whitespace test for a string source and is
required for a non-string source; explicitly supplying NIL signals
PROGRAM-ERROR."))

(defgeneric seq-trim (sequence &key predicate)
  (:documentation "Return SEQUENCE without its leading and trailing runs of elements satisfying
PREDICATE. PREDICATE defaults to the character whitespace test for a string
source and is required for a non-string source; explicitly supplying NIL
signals PROGRAM-ERROR."))

(defgeneric seq-into (target-designator source)
  (:documentation "Collect SOURCE into the target designated by TARGET-DESIGNATOR."))

(defgeneric seq-join (target-designator sequences &key separator)
  (:documentation "Join SEQUENCES into the target designated by TARGET-DESIGNATOR using SEPARATOR."))

;;; Chapter 7 equality and comparison protocols.
(defgeneric equals (object1 object2)
  (:documentation "Test whether OBJECT1 and OBJECT2 are equal under the Sophie equality protocol."))

(defgeneric compare (left-object right-object)
  (:documentation "Compare LEFT-OBJECT and RIGHT-OBJECT and return :LESS, :EQUAL, :GREATER, or :UNEQUAL."))

(defgeneric hash-code (object)
  (:documentation "Return a non-negative integer hash for OBJECT consistent with SL:EQUALS:
objects equal under SL:EQUALS receive equal hash codes; unequal objects may
collide."))

;;; Chapter 8 reference facade.
(defgeneric ref (object key &optional default)
  (:documentation "Return the value associated with KEY in OBJECT and true, or DEFAULT (default
NIL) and false when KEY is absent. Always returns two values."))

(defgeneric (setf ref) (new-value object key &optional default)
  (:documentation "Set KEY in OBJECT to NEW-VALUE and return the assigned value."))

;;; Chapter 9 dictionary protocol.
(defgeneric dictp (object)
  (:documentation "Test whether OBJECT participates in the dictionary protocol."))

(defgeneric dict-ref (dictionary key &optional default)
  (:documentation "Return the value for KEY in DICTIONARY and true, or DEFAULT (default NIL) and
false when KEY is absent; the second value distinguishes a stored NIL from an
absent key, like CL:GETHASH."))

(defgeneric (setf dict-ref) (new-value dictionary key &optional default)
  (:documentation "Set KEY in DICTIONARY to NEW-VALUE and return the assigned value."))

(defgeneric dict-test (dictionary)
  (:documentation "Return the equality-test designator used for key matching in DICTIONARY: a
symbol (EQ, EQL, EQUAL, or EQUALP) for a hash table, or a function for other
dict types."))

(defgeneric dict-size (dictionary)
  (:documentation "Return the number of entries in DICTIONARY."))

(defgeneric dict-set (dictionary key value)
  (:documentation "Return a dictionary like DICTIONARY with KEY associated with VALUE."))

(defgeneric dict-without (dictionary key)
  (:documentation "Return a dictionary like DICTIONARY without KEY."))

(defgeneric dict-collect (source entries &key test)
  (:documentation "Return a dict of the same type as prototype dictionary SOURCE, built from the
ENTRIES seqable of SL:MAP-ENTRY objects; SOURCE contributes only its type,
test, and configuration state. TEST (default EQL) propagates SOURCE's test to
the result and is ignored by fixed-test types such as SL:DICT."))

(defgeneric dict-keys (collection)
  (:documentation "Return a lazy sequence of the keys of COLLECTION's entries."))

(defgeneric dict-keys-map (function dictionary &key collision)
  (:documentation "Return a dictionary mapping FUNCTION over the keys of DICTIONARY."))

(defgeneric dict-vals (collection)
  (:documentation "Return a lazy sequence of the values of COLLECTION's entries."))

(defgeneric dict-values-map (function dictionary)
  (:documentation "Return a dictionary mapping FUNCTION over the values of DICTIONARY."))

(defgeneric dict-frequencies (sequence)
  (:documentation "Return a dictionary counting occurrences in SEQUENCE."))

(defgeneric dict-group-by (key-function sequence)
  (:documentation "Return a dictionary grouping elements of SEQUENCE by KEY-FUNCTION."))

(defgeneric dict-count-by (key-function sequence)
  (:documentation "Return a dictionary counting elements of SEQUENCE by KEY-FUNCTION."))

(defgeneric dict-reduce-kv (function initial-value dictionary)
  (:documentation "Left-fold DICTIONARY with FUNCTION called as (accumulator key value) for each
entry, starting from INITIAL-VALUE, and return the final accumulator."))

(defgeneric dict-select-keys (dictionary keys)
  (:documentation "Return DICTIONARY restricted to KEYS."))

(defgeneric dict-remove-keys (dictionary keys)
  (:documentation "Return DICTIONARY without KEYS."))

(defgeneric dict-zipmap (keys values)
  (:documentation "Return a dictionary pairing KEYS with VALUES."))

(defgeneric dict-merge (dict1 dict2 &key collision)
  (:documentation "Return the merge of DICT1 and DICT2 using COLLISION for duplicate keys."))

(defgeneric dict-merge-with (combine dict1 dict2)
  (:documentation "Return the merge of DICT1 and DICT2 combining duplicate values with COMBINE."))

(defgeneric dict-transform (function dictionary &key collision)
  (:documentation "Return a dictionary whose entries are produced by applying FUNCTION to each
key and value of DICTIONARY; FUNCTION must return exactly two values, the new
key and the new value. COLLISION is :LAST-WINS (default) or :ERROR for
transformed-key collisions."))

(defgeneric dict-member (dictionary key)
  (:documentation "Return two values: whether DICTIONARY contains KEY, and the value associated
with KEY (NIL when absent)."))

(defgeneric dict-merge* (dict1 dict2 &rest more-dicts)
  (:documentation "Return the merge of DICT1, DICT2, and MORE-DICTS."))

(defgeneric dict-update (dictionary key function &key default)
  (:documentation "Return DICTIONARY with KEY updated by FUNCTION, using DEFAULT when absent."))

(defgeneric dict-update-in (dictionary keys function &key default)
  (:documentation "Return DICTIONARY with the nested value at KEYS updated by FUNCTION."))

(defgeneric dict-set-in (dictionary keys value)
  (:documentation "Return DICTIONARY with the nested value at KEYS set to VALUE."))

(defgeneric dict-ref-in (dictionary keys &optional default)
  (:documentation "Return the nested value at KEYS in DICTIONARY and true, or DEFAULT (default
NIL) and false when any key in the path is absent."))

;;; Chapter 9 hash-set protocol.
(defgeneric hash-set-p (object)
  (:documentation "Test whether OBJECT is a hash set."))

(defgeneric set-member (item sequence)
  (:documentation "Test whether ITEM is a member of SEQUENCE."))

(defgeneric set-add (item sequence)
  (:documentation "Return a fresh SL:HASH-SET of the distinct elements of SEQUENCE plus ITEM."))

(defgeneric set-remove (item sequence)
  (:documentation "Return a fresh SL:HASH-SET of the distinct elements of SEQUENCE without ITEM."))

(defgeneric set-union (first-set second-set &rest more-sets)
  (:documentation "Return the union of FIRST-SET, SECOND-SET, and MORE-SETS."))

(defgeneric set-intersection (first-set second-set &rest more-sets)
  (:documentation "Return the intersection of FIRST-SET, SECOND-SET, and MORE-SETS."))

(defgeneric set-minus (first-set second-set &rest more-sets)
  (:documentation "Return a fresh SL:HASH-SET of the elements of FIRST-SET not present in
SECOND-SET or MORE-SETS, under SL:EQUALS."))

(defgeneric set-subset-p (first-set second-set)
  (:documentation "Test whether FIRST-SET is a subset of SECOND-SET."))

(defgeneric set-size (sequence)
  (:documentation "Return the number of distinct elements of SEQUENCE under SL:EQUALS (not its
length); the operation is eager and does not terminate on an unbounded
SEQUENCE."))
