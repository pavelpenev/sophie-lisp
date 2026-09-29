;;;; Benchmark harness: bench registration, adaptive timing, JSON run files,
;;;; and run comparison.
;;;;
;;;; This file is the measurement core of the benchmark suite. Every host
;;;; difference lives in benchmarks/host.lisp behind the functions it exports;
;;;; timing here is pure ANSI (GET-INTERNAL-RUN-TIME and
;;;; INTERNAL-TIME-UNITS-PER-SECOND) and no reader feature conditionals
;;;; appear in this file.

(in-package #:sophie-lisp.benchmarks)

(defconstant +timed-reps+ 15
  "Default number of timed batches per measured (bench, size) pair on SBCL
and CCL.")
(defconstant +warmup-batches+ 3
  "Default number of warmup batches run before the timed reps on SBCL and
CCL.")
(defconstant +default-floor-ms+ 10
  "Default adaptive-K batch-time floor in milliseconds on SBCL and CCL.")
(defconstant +minimum-floor-ticks+ 150
  "Lower bound on the adaptive-K batch-time floor, in timer ticks.")
(defconstant +maximum-adaptive-k+ 16777216
  "Safety cap on the adaptive batch size for non-cold benches.")

(defun default-measurement-params ()
  "Return the host-appropriate default measurement parameters as a plist.
The plist holds :REPS, :WARMUPS, and :FLOOR-MS, the RUN-BENCHMARKS keyword
parameters these values default to. The pre-remediation Stage 0 drift gate
round measured run-to-run drift on ECL at the common defaults (15 reps, 3
warmups, 10 ms floor) of 5.19% for FIXNUM-HASH and, for example, 4.57% for
EMPTY-LOOP, above the 5% calibration threshold for the cheapest benches; ECL
therefore defaults to the conservative 25 reps, 5 warmups, and 20 ms floor.
SBCL and CCL measured below 1.1% drift and keep the 15/3/10 defaults."
  (if (eq (host-name) :ecl)
      (list :reps 25 :warmups 5 :floor-ms 20)
      (list :reps +timed-reps+
            :warmups +warmup-batches+
            :floor-ms +default-floor-ms+)))

;;; Sink: a dead-code-elimination defense. Every timed call stores its result
;;; here; the count is consumed after each timed batch, outside the timed
;;; region, with a check that does not depend on K. The store is part of the
;;; measured harness overhead and is never subtracted from results.
(defparameter *sink* nil
  "Last value stored by a timed call.")
(defparameter *sink-count* 0
  "Number of results stored in the sink since the last per-batch reset.")

;;; Registry.

(defstruct bench
  "Registered metadata and entry points for one benchmark."
  (name nil :type (or null symbol))
  (category nil :type (or null keyword))
  (tier nil)
  (baseline nil)
  (sizes nil :type list)
  (setup-fn nil :type (or null function))
  (call-fn nil :type (or null function))
  (cold-pool-size nil)
  (ecl-cap nil)
  (note nil))

(defstruct bench-record
  "One measured (bench, size) result from a benchmark run."
  name
  category
  tier
  baseline
  note
  size
  effective-size
  cold-p
  k
  reps
  warmups
  floor-ticks
  floor-reached
  median-ns
  min-ns
  mad-ns
  compile-mode
  gc-count
  ecl-cap-applied)

(defvar *bench-registry* '()
  "Registered benches in definition order.")

(defun find-bench (name)
  "Return the registered bench named by the symbol NAME, or NIL."
  (find name *bench-registry* :key #'bench-name))

(defun registered-benches ()
  "Return all registered benches in definition order."
  (copy-list *bench-registry*))

(defun validate-bench (bench)
  "Check BENCH's metadata before it enters the registry."
  (flet ((fail (format-control &rest format-arguments)
           (apply #'error format-control format-arguments)))
    (unless (symbolp (bench-name bench))
      (fail "Bench name ~S is not a symbol." (bench-name bench)))
    (unless (keywordp (bench-category bench))
      (fail "Bench ~S: :CATEGORY must be a keyword." (bench-name bench)))
    (unless (member (bench-tier bench) '(nil :dispatch :same-op :persistent-vs-copy))
      (fail "Bench ~S: :TIER ~S is not one of NIL, :DISPATCH, :SAME-OP, or :PERSISTENT-VS-COPY."
            (bench-name bench) (bench-tier bench)))
    (unless (listp (bench-sizes bench))
      (fail "Bench ~S: :SIZES must be a list." (bench-name bench)))
    (dolist (size (bench-sizes bench))
      (unless (and (integerp size) (>= size 1))
        (fail "Bench ~S: size ~S is not a positive integer." (bench-name bench) size)))
    (unless (functionp (bench-setup-fn bench))
      (fail "Bench ~S: :SETUP must produce a function." (bench-name bench)))
    (unless (functionp (bench-call-fn bench))
      (fail "Bench ~S: :CALL must produce a function." (bench-name bench)))
    (when (bench-cold-pool-size bench)
      (unless (and (integerp (bench-cold-pool-size bench))
                   (>= (bench-cold-pool-size bench) 1))
        (fail "Bench ~S: :COLD-POOL-SIZE ~S is not a positive integer."
              (bench-name bench) (bench-cold-pool-size bench))))
    (when (bench-ecl-cap bench)
      (unless (and (integerp (bench-ecl-cap bench)) (>= (bench-ecl-cap bench) 1))
        (fail "Bench ~S: :ECL-CAP ~S is not a positive integer."
              (bench-name bench) (bench-ecl-cap bench))))
    (when (bench-note bench)
      (unless (stringp (bench-note bench))
        (fail "Bench ~S: :NOTE ~S is not a string." (bench-name bench) (bench-note bench))))
    (let ((baseline (bench-baseline bench)))
      (when baseline
        (when (eq baseline (bench-name bench))
          (fail "Bench ~S cannot use itself as its baseline." (bench-name bench)))
        (unless (find-bench baseline)
          (fail "Bench ~S: baseline ~S is not a registered bench."
                (bench-name bench) baseline))))))

(defun register-bench (bench)
  "Validate BENCH and enter it in the registry, replacing any same-name entry."
  (validate-bench bench)
  (let ((existing (member (bench-name bench) *bench-registry* :key #'bench-name)))
    (if existing
        (setf (car existing) bench)
        (setf *bench-registry* (append *bench-registry* (list bench)))))
  bench)

(defmacro define-bench (name &body options)
  "Define and register the benchmark named by the symbol NAME.
OPTIONS is a list of (KEY VALUE ...) clauses:

  (:CATEGORY keyword)        required; groups benches for RUN-BENCHMARKS.
  (:TIER keyword-or-nil)     NIL, :DISPATCH, :SAME-OP, or :PERSISTENT-VS-COPY;
                             the comparison-fairness label for every table
                             this bench appears in.
  (:BASELINE symbol-or-nil)  names another registered bench, the plain CL
                             form this bench is measured against. The
                             baseline bench must already be registered when
                             this bench is defined; with :SERIAL T load
                             order, file order determines which definitions
                             are legal.
  (:SIZES list)              required; the positive integer sizes to measure.
  (:SETUP (n) forms)         required; returns a context for size N and is
                             always invoked outside the timed region.
  (:CALL (ctx) forms)        required; returns one result per invocation and
                             is invoked K times inside the timed region.
  (:COLD-POOL-SIZE p)        marks the bench COLD. SETUP must return a pool,
                             a sequence of at least P fresh unrealized
                             inputs; the pool may be any sequence and is
                             coerced to a vector before timing starts. The
                             timed loop passes pool entry I as CTX for
                             call I, each entry used at most once per batch.
                             Warmup and adaptive-K batches draw from
                             separately built pools and never touch the timed
                             pool entries. A setup returning fewer than P
                             entries signals an error naming the bench, the
                             declared size, and the actual pool length.
  (:ECL-CAP n)               per-bench ECL size cap.
  (:NOTE string)             semantics caveat carried into every record.

Without :COLD-POOL-SIZE the bench is STANDARD: SETUP is called once per rep
outside the timed region and the timed loop calls CALL K times on that one
context; inputs are never mutated, so every call sees the same state."
  (let (category tier baseline sizes setup-var setup-body call-var call-body
        cold-pool-size ecl-cap note)
    (dolist (option options)
      (unless (and (consp option) (consp (cdr option)))
        (error "DEFINE-BENCH option ~S is not a (KEY VALUE ...) clause." option))
      (case (first option)
        (:category (setf category (second option)))
        (:tier (setf tier (second option)))
        (:baseline (setf baseline (second option)))
        (:sizes (setf sizes (second option)))
        (:setup (setf setup-var (second option)
                      setup-body (cddr option)))
        (:call (setf call-var (second option)
                     call-body (cddr option)))
        (:cold-pool-size (setf cold-pool-size (second option)))
        (:ecl-cap (setf ecl-cap (second option)))
        (:note (setf note (second option)))
        (t (error "Unknown DEFINE-BENCH option ~S." (first option)))))
    (unless category
      (error "Bench ~S: :CATEGORY is required." name))
    (unless sizes
      (error "Bench ~S: :SIZES is required." name))
    (unless setup-var
      (error "Bench ~S: :SETUP is required." name))
    (unless call-var
      (error "Bench ~S: :CALL is required." name))
    `(register-bench
       (make-bench
         :name ',name
         :category ,category
         :tier ,tier
         :baseline ',baseline
         :sizes ',sizes
         :setup-fn (lambda ,setup-var ,@setup-body)
         :call-fn (lambda ,call-var ,@call-body)
         :cold-pool-size ,cold-pool-size
         :ecl-cap ,ecl-cap
         :note ,note))))

;;; Timing core.

(defun bench-floor-ticks (floor-ms)
  "Return the adaptive-K batch-time floor for FLOOR-MS milliseconds:
max(FLOOR-MS in timer ticks, 150 ticks)."
  (max +minimum-floor-ticks+
       (ceiling (* internal-time-units-per-second floor-ms) 1000)))

(defun run-standard-batch (call-fn context k)
  "Time K calls of CALL-FN on one CONTEXT, storing each result in the sink.
Return the elapsed tick count. The harness loop and the sink store are part of
the measured overhead and are never subtracted from results."
  (let ((start (get-internal-run-time)))
    (dotimes (i k)
      (setf *sink* (funcall call-fn context))
      (incf *sink-count*))
    (- (get-internal-run-time) start)))

(defun run-cold-batch (call-fn pool k)
  "Time K calls of CALL-FN, passing pool entry I as the context for call I.
POOL is the sequence of fresh inputs returned by a cold bench's SETUP; it may
be any sequence and is coerced to a vector before the timed region starts, so
the timed loop indexes it in constant time. Each entry is used at most once
per batch. Return the elapsed tick count."
  (when (< (length pool) k)
    (error "Cold pool has ~D entries but the batch needs K=~D."
           (length pool) k))
  (let* ((pool-vector (coerce pool 'vector))
         (start (get-internal-run-time)))
    (dotimes (i k)
      (setf *sink* (funcall call-fn (aref pool-vector i)))
      (incf *sink-count*))
    (- (get-internal-run-time) start)))

(defun cold-pool (bench n)
  "Return the cold pool BENCH's SETUP builds for size N, length-checked.
The pool must hold at least the bench's declared :COLD-POOL-SIZE entries; a
shorter pool violates the bench's contract and signals an error naming the
bench, the declared size, and the actual pool length."
  (let* ((declared (bench-cold-pool-size bench))
         (pool (funcall (bench-setup-fn bench) n))
         (actual (length pool)))
    (when (< actual declared)
      (error "Bench ~S: cold pool has ~D entries but :COLD-POOL-SIZE is ~D."
             (bench-name bench) actual declared))
    pool))

(defun measure-batch (bench n k)
  "Build a fresh context for size N and time one batch of K calls.
The fresh context keeps adaptive-K and warmup batches from touching any timed
pool entries."
  (if (bench-cold-pool-size bench)
      (run-cold-batch (bench-call-fn bench) (cold-pool bench n) k)
      (run-standard-batch (bench-call-fn bench)
                          (funcall (bench-setup-fn bench) n)
                          k)))

(defun adaptive-k-pass (bench n floor-ticks)
  "Double K until one batch of K calls reaches FLOOR-TICKS.
Return (values k floor-reached). K is capped at the cold pool size for cold
benches and at +MAXIMUM-ADAPTIVE-K+ otherwise; when the floor is unreachable
within the cap, K is the cap and FLOOR-REACHED is NIL."
  (let* ((cold-p (bench-cold-pool-size bench))
         (cap (if cold-p
                  (length (cold-pool bench n))
                  +maximum-adaptive-k+)))
    (let ((k 1))
      (loop
        (when (>= (measure-batch bench n k) floor-ticks)
          (return (values k t)))
        (when (>= k cap)
          (return (values k nil)))
        (setf k (min (* k 2) cap))))))

(defun warmup-batches (bench n k count)
  "Run COUNT warmup batches with the same call shape as the timed reps.
Each batch builds its own fresh context, so cold warmup batches never touch
the timed pool entries."
  (dotimes (i count)
    (measure-batch bench n k)))

(defun run-timed-reps (bench n k reps)
  "Run REPS timed batches; return per-op tick values and the GC count.
Each rep runs a full GC, builds its context outside the timed region, then
times one batch of K calls with the GC enabled; a mid-rep GC is real cost and
stays in the measurement. The sink is consumed after each batch, outside the
timed region, with a check that does not depend on K."
  (let ((per-op '())
        (gc-total 0)
        (gc-supported nil))
    (setf *sink-count* 0)
    (dotimes (rep reps)
      (full-gc)
      (let* ((context (if (bench-cold-pool-size bench)
                          (cold-pool bench n)
                          (funcall (bench-setup-fn bench) n)))
             (gc-before (gc-count))
             (batch-ticks (if (bench-cold-pool-size bench)
                              (run-cold-batch (bench-call-fn bench) context k)
                              (run-standard-batch (bench-call-fn bench) context k)))
             (gc-after (gc-count)))
        (assert (plusp *sink-count*))
        (setf *sink-count* 0)
        (push (/ batch-ticks k) per-op)
        (when (and (not (null gc-before)) (not (null gc-after)))
          (setf gc-supported t)
          (incf gc-total (- gc-after gc-before)))))
    (values (nreverse per-op) (and gc-supported gc-total))))

;;; Statistics.

(defun ticks-to-nanoseconds (ticks)
  "Convert a tick count to nanoseconds as a double-float."
  (/ (* 1.0d9 ticks) internal-time-units-per-second))

(defun median (values)
  "Return the median of the list of real numbers VALUES."
  (let* ((sorted (sort (copy-list values) #'<))
         (count (length sorted))
         (middle (floor count 2)))
    (if (oddp count)
        (nth middle sorted)
        (/ (+ (nth (- middle 1) sorted) (nth middle sorted)) 2))))

(defun median-absolute-deviation (values median-value)
  "Return the median absolute deviation of VALUES around MEDIAN-VALUE."
  (median (mapcar (lambda (value) (abs (- value median-value))) values)))

(defun execute-bench (bench size reps warmups floor-ms)
  "Measure BENCH at SIZE and return a BENCH-RECORD, or NIL when skipped.
REPS timed batches and WARMUPS warmup batches run with an adaptive-K floor
of FLOOR-MS milliseconds; the record's REPS, WARMUPS, and FLOOR-TICKS fields
reflect the values actually used. On ECL the effective size is min(SIZE, the
bench's :ECL-CAP, and the host's default cap); a size whose effective value
falls below 1 is skipped. The reported floor is checked against the median
of the timed batches, not just the calibration batch."
  (let* ((ecl-p (eq (host-name) :ecl))
         (cap (and ecl-p (or (bench-ecl-cap bench) (default-size-cap))))
         (effective-size (if cap (min size cap) size)))
    (when (>= effective-size 1)
      (let ((floor-ticks (bench-floor-ticks floor-ms)))
        ;; A first call may compile a method inside the timed calibration
        ;; batch. Give it a separate fresh context before selecting K.
        (measure-batch bench effective-size 1)
        (multiple-value-bind (initial-k calibration-reached)
            (adaptive-k-pass bench effective-size floor-ticks)
          (declare (ignore calibration-reached))
          (let ((k initial-k))
            (loop
              (warmup-batches bench effective-size k warmups)
              (multiple-value-bind (per-op gc-count)
                  (run-timed-reps bench effective-size k reps)
                (let* ((batch-median (* k (median per-op)))
                       (cold-cap (and (bench-cold-pool-size bench)
                                      (length (cold-pool bench effective-size))))
                       (k-cap (or cold-cap +maximum-adaptive-k+))
                       (floor-reached (>= batch-median floor-ticks)))
                  (when (or floor-reached (>= k k-cap))
                    (let* ((nanoseconds (mapcar #'ticks-to-nanoseconds per-op))
                           (median-ns (median nanoseconds))
                           (min-ns (reduce #'min nanoseconds))
                           (mad-ns (median-absolute-deviation nanoseconds median-ns)))
                      (return
                        (make-bench-record
                          :name (bench-name bench)
                          :category (bench-category bench)
                          :tier (bench-tier bench)
                          :baseline (bench-baseline bench)
                          :note (bench-note bench)
                          :size size
                          :effective-size effective-size
                          :cold-p (not (null (bench-cold-pool-size bench)))
                          :k k
                          :reps reps
                          :warmups warmups
                          :floor-ticks floor-ticks
                          :floor-reached floor-reached
                          :median-ns median-ns
                          :min-ns min-ns
                          :mad-ns mad-ns
                          :compile-mode (if (bench-compiled-p (bench-call-fn bench))
                                            "compiled"
                                            "interpreted")
                          :gc-count gc-count
                          :ecl-cap-applied (and cap (< effective-size size))))))
                  ;; An isolated fast calibration batch can still pick a K
                  ;; whose GC-separated timed reps fall short. Retry with a
                  ;; larger K, never crossing the cold pool or safety cap.
                  (setf k (min (* k 2) k-cap)))))))))))

;;; JSON emitter. Objects are (cons :OBJECT members) with string-keyed alists;
;;; arrays are (cons :ARRAY elements); :TRUE and :FALSE are the boolean
;;; markers. No external JSON library is used.

(defun json-boolean (value)
  "Map a generalized boolean to the emitter's :TRUE and :FALSE markers."
  (if value :true :false))

(defun json-write-string (stream string)
  "Write STRING to STREAM as a quoted JSON string with full escaping."
  (write-char #\" stream)
  (loop for char across string
        do (case char
             ((#\") (write-string "\\\"" stream))
             ((#\\) (write-string "\\\\" stream))
             ((#\backspace) (write-string "\\b" stream))
             ((#\page) (write-string "\\f" stream))
             ((#\newline) (write-string "\\n" stream))
             ((#\return) (write-string "\\r" stream))
             ((#\tab) (write-string "\\t" stream))
             (otherwise
               (if (< (char-code char) 32)
                   (format stream "\\u~4,'0x" (char-code char))
                   (write-char char stream)))))
  (write-char #\" stream))

(defun json-write-value (stream value)
  "Write one JSON value to STREAM.
Arrays are written from (cons :ARRAY elements) and objects from
(cons :OBJECT members); :TRUE and :FALSE are the boolean markers; keywords and
other symbols are written as their lowercase names."
  (cond
    ((null value) (write-string "null" stream))
    ((eq value :true) (write-string "true" stream))
    ((eq value :false) (write-string "false" stream))
    ((integerp value) (format stream "~d" value))
    ((floatp value) (format stream "~f" value))
    ((stringp value) (json-write-string stream value))
    ((symbolp value) (json-write-string stream (string-downcase (symbol-name value))))
    ((and (consp value) (eq (car value) :array))
     (write-char #\[ stream)
     (loop for (element . rest) on (cdr value)
           do (json-write-value stream element)
           when rest
             do (write-char #\, stream))
     (write-char #\] stream))
    ((and (consp value) (eq (car value) :object))
     (write-char #\{ stream)
     (loop for (member . rest) on (cdr value)
           do (json-write-string stream (car member))
              (write-char #\: stream)
              (json-write-value stream (cdr member))
           when rest
             do (write-char #\, stream))
     (write-char #\} stream))
    (t (error "Cannot serialize ~S as a benchmark JSON value." value))))

(defun bench-record-json (record)
  "Return the JSON object representation of one BENCH-RECORD."
  (cons :object
        (list
          (cons "name" (bench-record-name record))
          (cons "category" (bench-record-category record))
          (cons "tier" (bench-record-tier record))
          (cons "baseline" (bench-record-baseline record))
          (cons "note" (bench-record-note record))
          (cons "size" (bench-record-size record))
          (cons "effective_size" (bench-record-effective-size record))
          (cons "cold" (json-boolean (bench-record-cold-p record)))
          (cons "k" (bench-record-k record))
          (cons "reps" (bench-record-reps record))
          (cons "warmups" (bench-record-warmups record))
          (cons "floor_ticks" (bench-record-floor-ticks record))
          (cons "floor_reached" (json-boolean (bench-record-floor-reached record)))
          (cons "median_ns" (bench-record-median-ns record))
          (cons "min_ns" (bench-record-min-ns record))
          (cons "mad_ns" (bench-record-mad-ns record))
          (cons "compile_mode" (bench-record-compile-mode record))
          (cons "gc_count" (bench-record-gc-count record))
          (cons "ecl_cap_applied" (json-boolean (bench-record-ecl-cap-applied record))))))

(defun output-path (output)
  "Resolve the OUTPUT pathname designator to a concrete file pathname.
A designator with a name component is used as the file itself; a directory
pathname receives a generated run file name. Directories are created as
needed."
  (if (pathname-name output)
      (let ((path (pathname output)))
        (ensure-directories-exist
          (make-pathname :directory (pathname-directory path)))
        path)
      (let ((directory (ensure-directories-exist output)))
        (merge-pathnames
          (make-pathname
            :name (format nil "run-~a-~d"
                           (string-downcase (host-name))
                           (get-universal-time))
            :type "json")
          directory))))

(defun write-run-json (path records machine commit)
  "Write one JSON run file at PATH with RECORDS and run metadata.
MACHINE and COMMIT are optional provenance strings, or NIL for JSON null."
  (with-open-file (stream path :direction :output :if-exists :supersede)
    (json-write-value
      stream
      (cons :object
            (list
              (cons "schema_version" 1)
              (cons "host" (string-downcase (host-name)))
              (cons "lisp_implementation_version" (lisp-implementation-version))
              (cons "internal_time_units_per_second" internal-time-units-per-second)
              (cons "timer_resolution_ticks" (measure-timer-resolution))
              (cons "timestamp" (get-universal-time))
              (cons "machine" machine)
              (cons "commit" commit)
              (cons "ecl_heap_target_bytes" *ecl-heap-target-bytes*)
              (cons "ecl_heap_achieved_bytes" *ecl-heap-achieved-bytes*)
              (cons "records" (cons :array (mapcar #'bench-record-json records))))))))

;;; JSON reader, for the comparator. The inverse of the emitter: objects come
;;; back as string-keyed alists, arrays as lists, booleans as :TRUE and
;;; :FALSE, null as NIL, numbers as numbers.

(defun json-parse (string)
  "Parse STRING as a JSON document and return the corresponding Lisp value."
  (let ((index 0)
        (limit (length string)))
    (labels
      ((skip-whitespace ()
         (loop while (and (< index limit)
                           (member (char string index) '(#\space #\tab #\newline #\return)
                                   :test #'char=))
               do (incf index)))
       (consume (expected)
         (unless (and (< index limit) (char= (char string index) expected))
           (error "Expected ~S at JSON position ~D." expected index))
         (incf index))
       (matches (word)
         (and (<= (+ index (length word)) limit)
              (string= word string :start2 index :end2 (+ index (length word)))))
       (parse-value ()
         (skip-whitespace)
         (unless (< index limit)
           (error "Unexpected end of JSON input."))
         (let ((char (char string index)))
           (cond
             ((char= char #\{) (parse-object))
             ((char= char #\[) (parse-array))
             ((char= char #\") (parse-string))
             ((matches "true") (incf index 4) :true)
             ((matches "false") (incf index 5) :false)
             ((matches "null") (incf index 4) nil)
             (t (parse-number)))))
       (parse-object ()
         (consume #\{)
         (let ((members '()))
           (skip-whitespace)
           (unless (and (< index limit) (char= (char string index) #\}))
             (loop
               (let ((key (parse-string)))
                 (skip-whitespace)
                 (consume #\:)
                 (push (cons key (parse-value)) members))
               (skip-whitespace)
               (cond
                 ((and (< index limit) (char= (char string index) #\,))
                  (incf index))
                 (t (return)))))
           (consume #\})
           (nreverse members)))
       (parse-array ()
         (consume #\[)
         (let ((elements '()))
           (skip-whitespace)
           (unless (and (< index limit) (char= (char string index) #\]))
             (loop
               (push (parse-value) elements)
               (skip-whitespace)
               (cond
                 ((and (< index limit) (char= (char string index) #\,))
                  (incf index))
                 (t (return)))))
           (consume #\])
           (nreverse elements)))
       (parse-string ()
         (consume #\")
         (with-output-to-string (chars)
           (loop
             (unless (< index limit)
               (error "Unterminated JSON string."))
             (let ((char (char string index)))
               (cond
                 ((char= char #\")
                  (incf index)
                  (return))
                 ((char= char #\\)
                  (incf index)
                  (unless (< index limit)
                    (error "Unterminated JSON escape."))
                  (let ((escape (char string index)))
                    (incf index)
                    (case escape
                      ((#\" #\\ #\/) (write-char escape chars))
                      ((#\b) (write-char #\backspace chars))
                      ((#\f) (write-char #\page chars))
                      ((#\n) (write-char #\newline chars))
                      ((#\r) (write-char #\return chars))
                      ((#\t) (write-char #\tab chars))
                      ((#\u)
                       (unless (<= (+ index 4) limit)
                         (error "Truncated \\u JSON escape."))
                       (write-char
                         (code-char
                           (parse-integer string :start index :end (+ index 4) :radix 16))
                         chars)
                       (incf index 4))
                      (otherwise (error "Unknown JSON escape ~S." escape)))))
                 (t
                   (write-char char chars)
                   (incf index)))))))
       (parse-number ()
         (let ((start index))
           (when (and (< index limit) (member (char string index) '(#\+ #\-) :test #'char=))
             (incf index))
           (loop while (and (< index limit) (digit-char-p (char string index)))
                 do (incf index))
           (when (and (< index limit) (char= (char string index) #\.))
             (incf index)
             (loop while (and (< index limit) (digit-char-p (char string index)))
                   do (incf index)))
           (when (and (< index limit) (member (char string index) '(#\e #\E) :test #'char=))
             (incf index)
             (when (and (< index limit) (member (char string index) '(#\+ #\-) :test #'char=))
               (incf index))
             (loop while (and (< index limit) (digit-char-p (char string index)))
                   do (incf index)))
           (when (= index start)
             (error "Invalid JSON number at position ~D." start))
           (read-from-string string t nil :start start :end index))))
      (skip-whitespace)
      (let ((value (parse-value)))
        (skip-whitespace)
        (unless (= index limit)
          (error "Trailing data after the JSON document at position ~D." index))
        value))))

(defun file-string (path)
  "Return the entire contents of the file at PATH as a string."
  (with-open-file (stream path)
    (let ((contents (make-string (file-length stream))))
      (read-sequence contents stream)
      contents)))

(defun load-run-records (path)
  "Return the records array at PATH, and run-level metadata as a second value."
  (let* ((root (json-parse (file-string path)))
         (pair (assoc "records" root :test #'string=)))
    (unless pair
      (error "No records found in benchmark run file ~S." path))
    (values (cdr pair) root)))

(defun record-field (record key)
  "Return the value of the string KEY in one parsed JSON record."
  (let ((pair (assoc key record :test #'string=)))
    (unless pair
      (error "Record ~S has no ~S field." record key))
    (cdr pair)))

;;; Runner.

(defun select-benches (categories names)
  "Return the registered benches filtered by CATEGORIES and NAMES.
A NIL filter admits every bench; a non-empty list keeps only benches whose
category or name is a member of the list."
  (loop for bench in *bench-registry*
        when (and (or (null categories)
                      (member (bench-category bench) categories))
                  (or (null names)
                      (member (bench-name bench) names)))
          collect bench))

(defun check-measurement-params (reps warmups floor-ms)
  "Signal an error unless REPS and WARMUPS are integers of at least 1 and
FLOOR-MS is a positive number. RUN-BENCHMARKS calls this before any bench
runs, so an invalid parameter fails fast instead of crashing mid-run."
  (unless (and (integerp reps) (>= reps 1))
    (error ":REPS must be an integer >= 1, but it is ~S." reps))
  (unless (and (integerp warmups) (>= warmups 1))
    (error ":WARMUPS must be an integer >= 1, but it is ~S." warmups))
  (unless (and (realp floor-ms) (plusp floor-ms))
    (error ":FLOOR-MS must be a positive number, but it is ~S." floor-ms)))

(defun run-benchmarks (&key categories names
                       (output #p"benchmarks/results/scratch/")
                       (reps nil reps-supplied-p)
                       (warmups nil warmups-supplied-p)
                       (floor-ms nil floor-ms-supplied-p)
                       machine commit)
  "Run the selected registered benches and write one JSON run file.
CATEGORIES and NAMES restrict the run; NIL admits every registered bench.
REPS, WARMUPS, and FLOOR-MS set the timed batch count, the warmup batch
count, and the adaptive-K floor in milliseconds; any of them left unsupplied
defaults to the host-appropriate value from DEFAULT-MEASUREMENT-PARAMS
(15/3/10 on SBCL and CCL, 25/5/20 on ECL). REPS and WARMUPS must be integers
of at least 1 and FLOOR-MS a positive number; anything else signals an error
before any bench runs. OUTPUT is a file pathname or a directory pathname, the
default being benchmarks/results/scratch/; directories receive a generated
run file name and are created as needed. Returns the BENCH-RECORD list that
was written. MACHINE and COMMIT are optional provenance strings (or NIL),
recorded as run-level JSON fields; NIL is emitted as null."
  (let* ((defaults (default-measurement-params))
         (reps (if reps-supplied-p reps (getf defaults :reps)))
         (warmups (if warmups-supplied-p warmups
                      (getf defaults :warmups)))
         (floor-ms (if floor-ms-supplied-p floor-ms
                       (getf defaults :floor-ms))))
    (check-measurement-params reps warmups floor-ms)
    (unless (or (null machine) (stringp machine))
      (error ":MACHINE must be a string or NIL, but it is ~S." machine))
    (unless (or (null commit) (stringp commit))
      (error ":COMMIT must be a string or NIL, but it is ~S." commit))
    (let* ((selected (select-benches categories names))
           (records (loop for bench in selected
                          append (loop for size in (bench-sizes bench)
                                       for record = (execute-bench bench size
                                                                   reps warmups
                                                                   floor-ms)
                                       when record
                                         collect record)))
           (path (output-path output)))
      (write-run-json path records machine commit)
      (dolist (record records)
        (format t "~&~a ~d: k=~d median=~,2f ns~%"
                (string-downcase (symbol-name (bench-record-name record)))
                (bench-record-size record)
                (bench-record-k record)
                (bench-record-median-ns record)))
      (format t "~&~d record(s) written to ~a~%" (length records) path)
      records)))

;;; Allocation pass. Explicit opt-in, separate from all timing paths.

(defun measure-allocation-cell (bench size calls)
  "Return (values bytes-per-op actual-calls) for BENCH at SIZE.
Warm up on a separate context so one-time dispatch costs are excluded. The
measured context is built before the host seam collects and reads its counter.
Cold benches use distinct inputs per call, up to their pool size. The sink
store is included; no overhead is subtracted."
  (let* ((cold-p (bench-cold-pool-size bench))
         (warm-context (if cold-p
                           (cold-pool bench size)
                           (funcall (bench-setup-fn bench) size))))
    (setf *sink* (funcall (bench-call-fn bench)
                          (if cold-p (elt warm-context 0) warm-context)))
    (let* ((context (if cold-p
                        (coerce (cold-pool bench size) 'vector)
                        (funcall (bench-setup-fn bench) size)))
           (count (if cold-p (min calls (length context)) calls))
           (bytes (with-allocation-bytes
                    (lambda ()
                      (dotimes (i count)
                        (setf *sink*
                              (funcall (bench-call-fn bench)
                                       (if cold-p (aref context i) context))))))))
      (values (/ (float bytes 1.0d0) count) count))))

(defun allocation-record-json (record)
  "Return the JSON representation of an allocation RECORD plist."
  (cons :object
        (list (cons "bench" (getf record :bench))
              (cons "size" (getf record :size))
              (cons "bytes_per_op" (getf record :bytes-per-op))
              (cons "calls" (getf record :calls)))))

(defun write-allocation-json (path records machine commit)
  "Write allocation-only RECORDS and provenance to PATH, not a timing run."
  (with-open-file (stream path :direction :output :if-exists :supersede)
    (json-write-value
      stream
      (cons :object
            (list (cons "schema_version" 1)
                  (cons "measurement" "allocation_bytes_per_op")
                  (cons "host" (string-downcase (host-name)))
                  (cons "lisp_implementation_version" (lisp-implementation-version))
                  (cons "timestamp" (get-universal-time))
                  (cons "machine" machine)
                  (cons "commit" commit)
                  (cons "records" (cons :array (mapcar #'allocation-record-json records))))))))

(defun run-allocation-pass (&key categories names sizes
                            (output #p"benchmarks/results/scratch/")
                            (calls 32) machine commit)
  "Measure allocation in a separate, non-timed, SBCL-only pass.
CATEGORIES and NAMES filter as in RUN-BENCHMARKS; SIZES, when non-NIL,
restricts each bench to its registered sizes. CALLS must be positive; cold
benches cap calls at the length of their fresh input pool. SETUP runs before
the full GC and counter reads inside WITH-ALLOCATION-BYTES. Each call's
result is stored in the sink to prevent elimination; the sink store and any
lazy forcing in CALL are included. This reports total allocation, not an
isolated traversal-node cost. OUTPUT is a file or directory pathname.
Unsupported hosts return NIL without running benchmarks or writing a file."
  (unless (eq (host-name) :sbcl)
    (format t "~&Allocation pass unsupported on ~A; SBCL only.~%" (host-name))
    (return-from run-allocation-pass nil))
  (unless (and (integerp calls) (plusp calls))
    (error ":CALLS must be a positive integer, but it is ~S." calls))
  (unless (or (null machine) (stringp machine))
    (error ":MACHINE must be a string or NIL, but it is ~S." machine))
  (unless (or (null commit) (stringp commit))
    (error ":COMMIT must be a string or NIL, but it is ~S." commit))
  (let* ((records
           (loop for bench in (select-benches categories names)
                 append (loop for size in (bench-sizes bench)
                              when (or (null sizes) (member size sizes))
                                collect (multiple-value-bind (bytes count)
                                            (measure-allocation-cell bench size calls)
                                          (list :bench (bench-name bench)
                                                :size size
                                                :bytes-per-op bytes
                                                :calls count)))))
         (path (output-path output)))
    (write-allocation-json path records machine commit)
    (dolist (record records)
      (format t "~&~(~A~) ~D: ~,2F bytes/op (~D calls)~%"
              (getf record :bench) (getf record :size)
              (float (getf record :bytes-per-op) 1.0d0)
              (getf record :calls)))
    (format t "~&~D allocation record(s) written to ~A~%" (length records) path)
    records))


;;; Comparator.

(defun index-records (records)
  "Index parsed run RECORDS by (name . size) in an EQUAL hash table."
  (let ((table (make-hash-table :test #'equal)))
    (dolist (record records table)
      (setf (gethash (cons (record-field record "name")
                           (record-field record "size"))
                     table)
            record))))

(defun comparison-key-less-p (a b)
  "Order two (name . size) comparison keys by name, then by size."
  (if (string= (car a) (car b))
      (< (cdr a) (cdr b))
      (string< (car a) (car b))))

(defun parameter-mismatches (current-record baseline-record)
  "Return the measurement parameters under which two matched records differ.
The result is a list of (field current-value baseline-value) entries for the
K, REPS, WARMUPS, and FLOOR-TICKS record fields; a nonempty result means the
same (name, size) bench ran under different measurement conditions in the
two runs, so the comparison must be read with care."
  (let ((mismatches '()))
    (dolist (field '("k" "reps" "warmups" "floor_ticks") (nreverse mismatches))
      (let ((current-value (record-field current-record field))
            (baseline-value (record-field baseline-record field)))
        (unless (= current-value baseline-value)
          (push (list field current-value baseline-value) mismatches))))))

(defun compare-records (current-record baseline-record)
  "Return the comparison plist for one matched (name, size) record pair.
The regression flag is set when the median ratio exceeds 1.15 and the
median +/- MAD bands of the two runs do not overlap. The parameter mismatches
entry lists every measurement parameter under which the two records differ."
  (let* ((baseline-median (record-field baseline-record "median_ns"))
         (current-median (record-field current-record "median_ns"))
         (baseline-mad (record-field baseline-record "mad_ns"))
         (current-mad (record-field current-record "mad_ns"))
         (ratio (and (> baseline-median 0)
                     (/ current-median baseline-median)))
         (bands-overlap
           (and (<= (- baseline-median baseline-mad)
                    (+ current-median current-mad))
                (<= (- current-median current-mad)
                    (+ baseline-median baseline-mad)))))
    (list
      :name (record-field current-record "name")
      :size (record-field current-record "size")
      :baseline-median-ns baseline-median
      :current-median-ns current-median
      :ratio ratio
      :parameter-mismatches (parameter-mismatches current-record baseline-record)
      :regression-p (and ratio
                         (> ratio 1.15)
                         (not bands-overlap)))))

(defun compare-runs (current-path baseline-path)
  "Compare the run file at CURRENT-PATH against the one at BASELINE-PATH.
For every (name, size) record present in both files, the comparison reports
the median ratio and the median +/- MAD bands; a regression is a ratio above
1.15 with non-overlapping bands. A record pair whose measurement parameters
(K, REPS, WARMUPS, FLOOR-TICKS) differ between the two runs still gets its
ratio computed, but a warning naming the bench and every differing field is
printed and the table row is flagged PARAM-MISMATCH. Host or Lisp version
differences also produce a prominent warning before the table, without
preventing comparison. A table is printed and the comparison plists are returned."
  (multiple-value-bind (current-records current-metadata)
      (load-run-records current-path)
    (multiple-value-bind (baseline-records baseline-metadata)
        (load-run-records baseline-path)
      (let* ((current (index-records current-records))
             (baseline (index-records baseline-records))
             (keys (sort (loop for key being the hash-key of current
                               when (gethash key baseline)
                                 collect key)
                         #'comparison-key-less-p))
             (results (loop for key in keys
                            collect (compare-records (gethash key current)
                                                     (gethash key baseline)))))
        (let ((current-host (record-field current-metadata "host"))
              (baseline-host (record-field baseline-metadata "host"))
              (current-version (record-field current-metadata "lisp_implementation_version"))
              (baseline-version (record-field baseline-metadata "lisp_implementation_version")))
          (unless (and (equal current-host baseline-host)
                       (equal current-version baseline-version))
            (format t "~&WARNING: benchmark runs have different hosts or Lisp versions; ~
                       comparison may not be comparable.~%")
            (format t "  current: host ~s, Lisp version ~s~%  baseline: host ~s, Lisp version ~s~%"
                    current-host current-version baseline-host baseline-version)))
        (dolist (result results)
          (let ((mismatches (getf result :parameter-mismatches)))
            (when mismatches
              (format t "~&WARNING: ~a size ~d was measured under different ~
                         parameters in the two runs; the ratio below is not ~
                         directly comparable.~%"
                      (getf result :name) (getf result :size))
              (dolist (mismatch mismatches)
                (format t "  ~a: current ~s, baseline ~s~%"
                        (first mismatch) (second mismatch) (third mismatch))))))
        (format t "~&~30a ~8a ~16a ~16a ~10a ~a~%"
                "name" "size" "baseline ns" "current ns" "ratio" "flag")
        (dolist (result results)
          (let ((flags (append (when (getf result :parameter-mismatches)
                                 '("PARAM-MISMATCH"))
                               (when (getf result :regression-p)
                                 '("REGRESSION")))))
            (format t "~&~30a ~8d ~16,2f ~16,2f ~10a ~a"
                    (getf result :name)
                    (getf result :size)
                    (getf result :baseline-median-ns)
                    (getf result :current-median-ns)
                    (if (getf result :ratio)
                        (format nil "~,2f" (getf result :ratio))
                        "-")
                    (format nil "~{~a~^ ~}" flags))))
        (format t "~&~d comparison(s), ~d regression(s), ~d parameter mismatch(es)~%"
                (length results)
                (count-if (lambda (result) (getf result :regression-p)) results)
                (count-if (lambda (result) (getf result :parameter-mismatches)) results))
        results))))

;;; Built-in harness benches.

(define-bench empty-loop
  (:category :harness)
  (:sizes (1))
  (:setup (n) (declare (ignore n)) nil)
  (:call (context) (declare (ignore context)) nil)
  (:note "Harness loop and sink overhead alone; never subtracted from results."))
