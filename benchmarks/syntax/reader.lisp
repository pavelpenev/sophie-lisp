;;;; Reader benchmarks: the Sophie literal syntaxes against plain CL reading.
;;;;
;;;; Matrix H covers the reader surface. The CL baselines come first (category
;;;; :READER-BASELINE) so every Sophie bench (category :READER) can reference
;;;; its baseline by registration order. Every comparison bench carries a
;;;; :TIER fairness label and a note with the shared measurement caveat below.
;;;;
;;;; Readtable activation decision: the Sophie literals are live only under the
;;;; named SL-CORE-SYNTAX readtable, so NAMED-READTABLES:IN-READTABLE at the
;;;; top of this file would be wrong; it would leave the readtable active for
;;;; every later file and for the baselines. Instead the readtable is fetched
;;;; once at load time into *SL-SYNTAX-READTABLE*, and each timed call binds
;;;; *READTABLE* dynamically around READ-FROM-STRING. That one special-variable
;;;; bind/unbind happens inside the timed region and is included in every
;;;; Sophie measurement, disclosed in the shared caveat; the readtable lookup
;;;; itself is outside the timed region. The baselines read through BENCH-READ,
;;;; the same wrapper shape without the binding, so the binding is the only
;;;; structural asymmetry. Reading is pure (the source string is unchanged), so
;;;; standard benches suffice: :SETUP builds the source string outside the timed
;;;; region and :CALL reads it per call.
;;;;
;;;; Sizing follows the suite rules: (10 100 1000 10000), with size 1 added to
;;;; CL-READ-LIST only for the fixed-shape placeholder bench; ECL caps sizes at
;;;; 10000 through the harness host seam. No reader feature conditionals appear
;;;; in this file; host differences live in benchmarks/host.lisp.

(in-package #:sophie-lisp.benchmarks)

;;; Readtable state and the two read wrappers every bench goes through.

(defparameter *sl-syntax-readtable* nil
  "The SL-CORE-SYNTAX readtable used by the Sophie reader benches, fetched
once at load time so no timed call pays a readtable lookup.")

(eval-when (:load-toplevel :execute)
  ;; FIND-READTABLE signals here at load time when Sophie Lisp has not been
  ;; loaded first, which is the correct failure point for this suite.
  (setf *sl-syntax-readtable* (named-readtables:find-readtable :sl-core-syntax)))

(defun bench-read (source)
  "Read one object from the source string SOURCE under the ambient readtable.
The wrapper gives every baseline the same call shape as the Sophie benches,
whose reads go through SL-BENCH-READ."
  (read-from-string source))

(defun sl-bench-read (source)
  "Read one object from the source string SOURCE under the SL-CORE-SYNTAX
readtable. The dynamic *READTABLE* binding happens per call inside the timed
region and is included in the measurement; the readtable itself was fetched
once at load time."
  (let ((*readtable* *sl-syntax-readtable*))
    (read-from-string source)))

;;; Source builders. Every builder runs inside :SETUP, outside the timed
;;; region; the harness rebuilds the string fresh per rep.

(defun parenthesized-source (prefix elements)
  "Return the source string PREFIX followed by ELEMENTS in parentheses,
space-separated. ELEMENTS may be any objects acceptable to the ~a FORMAT
directive; the builders below pass integers or preformatted token strings."
  (with-output-to-string (stream)
    (write-string prefix stream)
    (write-char #\( stream)
    (loop for element in elements
          for first = t then nil
          do (unless first
               (write-char #\space stream))
             (format stream "~a" element))
    (write-char #\) stream)))

(defun symbol-tokens (n)
  "Return N distinct symbol token strings e0 to eN-1 for the list sources."
  (loop for index below n
        collect (format nil "e~d" index)))

(defun integer-elements (n)
  "Return the integers 0 to N-1 as source elements for the element-wise
container literals."
  (loop for index below n
        collect index))

(defun pair-elements (n)
  "Return N fixnum key/value pairs flattened as 2N source elements, key I
mapped to its triple, for the associative container literals."
  (loop for key below n
        append (list key (* key 3))))

(defun interpolation-source (n)
  "Return a #? template source string with N numeric dollar-brace
insertions, each preceded by a literal x segment."
  (with-output-to-string (stream)
    (write-string "#?\"" stream)
    (loop for index below n
          do (format stream "x${~d}" index))
    (write-char #\" stream)))

;;; Shared note text. Every comparison bench pairs the caveat with its own
;;; specifics through READER-NOTE.

(alexandria:define-constant +reader-caveat+
  "Sophie reads run under the SL-CORE-SYNTAX readtable through a per-call
dynamic *READTABLE* binding inside the timed region; that one bind/unbind is
included in the measurement, and the readtable lookup happens once at load."
  :test #'equal
  :documentation "Shared measurement caveat carried by every reader
comparison bench note.")

(defun reader-note (specific)
  "Return the note for one reader comparison bench: the shared measurement
caveat followed by the bench's SPECIFIC text."
  (concatenate 'string +reader-caveat+ " " specific))

;;; CL baselines. Each builds its source string inside :SETUP, outside the
;;; timed region, and measures the plain CL read in :CALL.

(define-bench cl-read-list
  (:category :reader-baseline)
  (:sizes (1 10 100 1000 10000))
  (:setup (n) (parenthesized-source "" (symbol-tokens n)))
  (:call (context) (bench-read context))
  (:note "READ-FROM-STRING of a plain list of N distinct symbols e0 to eN-1
under the ambient readtable; the read-only baseline for the reader matrix.
Size 1 exists for the fixed-shape placeholder bench."))

(define-bench cl-read-vector
  (:category :reader-baseline)
  (:sizes (10 100 1000 10000))
  (:setup (n) (parenthesized-source "#" (integer-elements n)))
  (:call (context) (bench-read context))
  (:note "READ-FROM-STRING of the simple-vector literal #(0 1 ... n-1) under
the ambient readtable; the read-only baseline for vector-shaped sources."))

;;; Sophie benches. Every literal read expands during the read into a
;;; construction form, so each comparison is read plus form build against the
;;; baseline's read-only source; each note discloses its expansion shape.

(define-bench read-vector-literal
  (:category :reader)
  (:baseline cl-read-vector)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (parenthesized-source "#v" (integer-elements n)))
  (:call (context) (sl-bench-read context))
  (:note (reader-note
           "Reading #v(0 1 ... n-1): the literal expands during the read into
a LET/MAKE-ARRAY/SETF-AREF construction form, so the measurement is read plus
form build; the baseline's read of the #(...) literal itself constructs the
N-element vector, so the honest contrast is Sophie building the vector from an
unevaluated construction form against the baseline reading a finished vector
literal.")))

(define-bench read-hash-literal
  (:category :reader)
  (:baseline cl-read-list)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (parenthesized-source "#h" (pair-elements n)))
  (:call (context) (sl-bench-read context))
  (:note (reader-note
           "Reading #h(...) of N fixnum key/value pairs: the literal expands
during the read into a MAKE-HASH-TABLE plus N SETF GETHASH construction form
under the default #'EQUAL test, so the comparison is read plus construct-form
against the baseline's read-only list. Element asymmetry against
CL-READ-LIST: this source carries 2N fixnum tokens (N key/value pairs) while
the baseline reads N distinct symbols, each paying token parse plus intern,
which biases the ratio in Sophie's favor.")))

(define-bench read-dict-literal
  (:category :reader)
  (:baseline cl-read-list)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (parenthesized-source "#d" (pair-elements n)))
  (:call (context) (sl-bench-read context))
  (:note (reader-note
           "Reading #d(...) of N fixnum key/value pairs: the literal expands
during the read into a DICT plus N DICT-SET persistent-construction form, so
the comparison is read plus construct-form against the baseline's read-only
list. Element asymmetry against CL-READ-LIST: this source carries 2N fixnum
tokens (N key/value pairs) while the baseline reads N distinct symbols, each
paying token parse plus intern, which biases the ratio in Sophie's
favor.")))

(define-bench read-set-literal
  (:category :reader)
  (:baseline cl-read-list)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (parenthesized-source "#u" (integer-elements n)))
  (:call (context) (sl-bench-read context))
  (:note (reader-note
           "Reading #u(...) of N fixnum elements: the literal expands during
the read into a HASH-SET plus N SET-ADD construction form, so the comparison
is read plus construct-form against the baseline's read-only list. Element
asymmetry against CL-READ-LIST: this source carries N fixnum tokens while the
baseline reads N distinct symbols, each paying token parse plus intern,
which biases the ratio in Sophie's favor.")))

(define-bench read-interpolation
  (:category :reader)
  (:baseline cl-read-list)
  (:tier :same-op)
  (:sizes (10 100 1000 10000))
  (:setup (n) (interpolation-source n))
  (:call (context) (sl-bench-read context))
  (:note (reader-note
           "Reading a #? template with N numeric dollar-brace insertions: the
read produces a WITH-OUTPUT-TO-STRING construction form, not a finished
string, so the comparison is read plus form build against the baseline's
read-only list.")))

(define-bench read-placeholder-lambda
  (:category :reader)
  (:baseline cl-read-list)
  (:tier :same-op)
  (:sizes (1))
  (:setup (n) (declare (ignore n)) "#^(+ %1 %2)")
  (:call (context) (sl-bench-read context))
  (:note (reader-note
           "Reading the fixed-shape #^(+ %1 %2): the reader walks the
expression, allocates the two parameter variables, and builds a LAMBDA form;
measured at one size against the size-1 baseline list read.")))

(define-bench readtable-dispatch-overhead
  (:category :reader)
  (:baseline cl-read-list)
  (:tier :dispatch)
  (:sizes (10 100 1000 10000))
  (:setup (n) (parenthesized-source "" (symbol-tokens n)))
  (:call (context) (sl-bench-read context))
  (:note (reader-note
           "Reading the baseline's plain symbol list under SL-CORE-SYNTAX
instead of the ambient readtable: that table is a pristine standard copy plus
six # dispatch entries, so a source with no # dispatch is expected to cost
about the same as the baseline read; the measured factor documents the
dispatch cost when no literals are present.")))
