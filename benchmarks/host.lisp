;;;; Benchmark host seam.
;;;
;;; Every reader conditional in the benchmark system lives in this file.
;;; The harness and calibration files call only the portable functions
;;; defined here, so each host's differences stay behind one boundary.

(in-package #:sophie-lisp.benchmarks)

;;; ECL's Boehm GC otherwise crosses a heap threshold inside timed batches.
;;; The largest observed per-rep batch allocation is ~42 MB; 1 GiB gives
;;; ~24x heap-to-batch-allocation headroom, not a measured GC-threshold margin.
(defconstant +ecl-heap-target-bytes+ 1073741824
  "Target Boehm heap size for ECL benchmark runs, in bytes.")

(defvar *ecl-heap-target-bytes* nil
  "Requested ECL Boehm heap size in bytes, or NIL on other hosts.")

(defvar *ecl-heap-achieved-bytes* nil
  "Observed ECL Boehm heap size after expansion, or NIL on other hosts.")

#+ecl
(defvar *ecl-gc-count-function* nil
  "Compiled ECL thunk reading Boehm's collection counter.")

#+ecl
(eval-when (:load-toplevel :execute)
  ;; C-INLINE cannot run in ECL's interpreter; compile the FFI thunks at load time.
  (let* ((heap-size
           (compile nil
                    '(lambda ()
                       (ffi:c-inline () () :unsigned-long "GC_get_heap_size()"
                                     :one-liner t :side-effects nil))))
         (expand-heap
           (compile nil
                    '(lambda (nbytes)
                       (ffi:c-inline (nbytes) (:unsigned-long) :int
                                     "GC_expand_hp((size_t)ecl_fixnum(v1nbytes))"
                                     :one-liner t :side-effects t))))
         (gc-count
           (compile nil
                    '(lambda ()
                       (ffi:c-inline () () :unsigned-long "GC_get_gc_no()"
                                     :one-liner t :side-effects nil))))
         (current (funcall heap-size))
         (delta (- +ecl-heap-target-bytes+ current)))
    (setf *ecl-gc-count-function* gc-count
          *ecl-heap-target-bytes* +ecl-heap-target-bytes+)
    (when (plusp delta)
      (funcall expand-heap delta))
    (setf *ecl-heap-achieved-bytes* (funcall heap-size))
    (when (< *ecl-heap-achieved-bytes* *ecl-heap-target-bytes*)
      (error "ECL benchmark heap expansion failed: target ~D bytes, achieved ~D bytes."
             *ecl-heap-target-bytes* *ecl-heap-achieved-bytes*))))

(defun host-name ()
  "Return a keyword naming the host Lisp implementation running the benchmarks.
CCL is recognized through either of its :CCL or :CLOZURE feature keywords."
  (or #+sbcl :sbcl
      #+ccl :ccl
      #+ecl :ecl
      (error "Sophie Lisp benchmarks support SBCL, CCL, and ECL only.")))

(defun measure-timer-resolution (&optional (samples 1000))
  "Return the smallest observable GET-INTERNAL-RUN-TIME delta in ticks.
Spins on the internal run-time clock SAMPLES times, waiting in each sample
for the reading to advance past its starting value, and returns the minimum
observed delta.  The result approximates the host timer's resolution and is
always a positive integer."
  (loop repeat samples
        minimize (let ((start (get-internal-run-time)))
                   (loop for now = (get-internal-run-time)
                         when (> now start)
                         return (- now start)))))

(defun full-gc ()
  "Run a full garbage collection through TRIVIAL-GARBAGE."
  (tg:gc :full t))

;;; SBCL has no public cumulative GC counter. Its after-GC hook advances once
;;; per collection (validated on SBCL 2.6.8); the harness reads only the
;;; counter before and after each timed batch, without changing GC policy.
#+sbcl
(defvar *sbcl-gc-count* 0
  "Number of collections observed by the SBCL benchmark GC hook.")

#+sbcl
(defvar *sbcl-benchmark-gc-hook* nil
  "Function object installed in SBCL's after-GC hook list on the last load.")

#+sbcl
(defun note-benchmark-gc ()
  (incf *sbcl-gc-count*))

#+sbcl
(eval-when (:load-toplevel :execute)
  ;; Reloading replaces the function object; discard the previous hook first.
  (when *sbcl-benchmark-gc-hook*
    (setf sb-ext:*after-gc-hooks*
          (remove *sbcl-benchmark-gc-hook* sb-ext:*after-gc-hooks* :test #'eq)))
  (setf *sbcl-benchmark-gc-hook* #'note-benchmark-gc)
  (push *sbcl-benchmark-gc-hook* sb-ext:*after-gc-hooks*))

#+sbcl
(defun gc-count ()
  "Return the number of collections since the SBCL benchmark GC hook was installed.
Only within-run deltas are meaningful; the harness records those deltas."
  *sbcl-gc-count*)

;;; CCL exposes its collection counter only as an internal symbol; FULL-GCCOUNT
;;; is the same function CCL's own ROOM reporting reads, and it advances by one
;;; per collection (verified on CCL 1.13).
#+ccl
(defun gc-count ()
  "Return the number of garbage collections CCL has performed so far."
  (ccl::full-gccount))

#+ecl
(defun gc-count ()
  "Return the number of Boehm garbage collections ECL has performed so far."
  (funcall *ecl-gc-count-function*))

#-(or sbcl ccl ecl)
(defun gc-count ()
  "Return NIL when the host exposes no comparable collection counter."
  nil)

(defun bench-compiled-p (function)
  "Whether FUNCTION is a compiled function, as timed benchmarks require."
  (compiled-function-p function))

(defun default-size-cap ()
  "Return the default cap on benchmark input sizes, or nil for no cap.
ECL runs the generic arithmetic and bignum paths without SBCL's or CCL's
optimizations, so uncapped input sizes are impractical there; every other
supported host runs uncapped and returns nil."
  #+ecl 10000
  #-ecl nil)

;;; GET-BYTES-CONSED is SBCL-only.  The measurement is for a separate
;;; non-timed pass: the full GC and the counter reads themselves cons and
;;; would pollute timed runs.
#+sbcl
(defun with-allocation-bytes (thunk)
  "Run THUNK and return the number of bytes it allocated.
A full collection precedes the reading so the delta covers only THUNK's
own allocation.  Use this in a separate non-timed pass only."
  (full-gc)
  (let ((before (sb-ext:get-bytes-consed)))
    (funcall thunk)
    (- (sb-ext:get-bytes-consed) before)))

#-sbcl
(defun with-allocation-bytes (thunk)
  "Run THUNK and return the bytes it allocated, or nil when unavailable.
Hosts without SBCL's GET-BYTES-CONSED expose no equivalent counter, so
THUNK is not called and nil is returned; callers skip the allocation
pass entirely on those hosts."
  (declare (ignore thunk))
  nil)
