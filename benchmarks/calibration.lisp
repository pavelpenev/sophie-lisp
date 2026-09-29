;;;; Calibration benches and the calibration entry point.
;;;;
;;;; The benches here measure the cheapest Sophie operations rather than the
;;;; Sophie surface against CL: SL:HASH-CODE on a fixnum and a hit lookup on
;;;; a small persistent dict. Together with the harness's EMPTY-LOOP they
;;;; establish the noise floor and dispatch cost every other bench is read
;;;; against. RUN-CALIBRATION is the one-command entry point for that run.

(in-package #:sophie-lisp.benchmarks)

(eval-when (:compile-toplevel :load-toplevel :execute)
  ;; The package definition lives in benchmarks/package.lisp. Exporting here as
  ;; well keeps the calibration API usable with single-colon qualification even
  ;; when the package definition does not list these symbols.
  (export '(run-calibration)))

;;; Calibration benches. The package uses SOPHIE-LISP-EXTENSIONS, so the SL
;;; entry points are called unqualified.

(define-bench fixnum-hash
  (:category :calibration)
  (:sizes (1))
  (:setup (n) (+ n 12345))
  (:call (context) (hash-code context))
  (:note "SL:HASH-CODE on a fixnum; the cheapest Sophie hash path."))

(define-bench dict-ref-100
  (:category :calibration)
  (:sizes (100))
  (:setup (n)
    (apply #'dict
           (loop for key below n
                 nconc (list key (* key 3)))))
  (:call (context) (dict-ref context 50))
  (:note "Hit lookup on a persistent dict of 100 fixnum keys; adds generic
dispatch and trie descent to the FIXNUM-HASH cost."))

;;; Calibration entry point.

(defun calibration-output-path ()
  "Return the default calibration run file path for the current host.
The path is benchmarks/results/scratch/calibration-<host>.json, relative to
the current working directory like RUN-BENCHMARKS' own default; the directory
is created by the harness when the run file is written."
  (make-pathname
    :directory '(:relative "benchmarks" "results" "scratch")
    :name (format nil "calibration-~a" (string-downcase (host-name)))
    :type "json"))

(defun print-calibration-summary (records)
  "Print the timer resolution and the per-record dispersion summary of RECORDS.
The timer resolution is reported in ticks; every record reports median, min,
and MAD in nanoseconds, with MAD as a percentage of the median."
  (format t "~&Timer resolution: ~d tick(s)~%" (measure-timer-resolution))
  (dolist (record records)
    (let ((median (bench-record-median-ns record)))
      (format t "~&~a ~d: median=~,2f ns min=~,2f ns mad=~,2f ns (~,1f% of median)~%"
              (string-downcase (symbol-name (bench-record-name record)))
              (bench-record-size record)
              median
              (bench-record-min-ns record)
              (bench-record-mad-ns record)
              (if (plusp median)
                  (* 100 (/ (bench-record-mad-ns record) median))
                  0.0)))))

(defun run-calibration (&key (output (calibration-output-path)))
  "Run the :HARNESS and :CALIBRATION benches and print a calibration summary.
The run goes through RUN-BENCHMARKS with those two categories, so the
measurement parameters default to the host-appropriate values of
DEFAULT-MEASUREMENT-PARAMS. OUTPUT defaults to
benchmarks/results/scratch/calibration-<host>.json, its directory created as
needed. The summary prints the measured timer resolution in ticks and, for
every record, the median, min, and MAD in nanoseconds plus MAD as a
percentage of the median. Returns the BENCH-RECORD list that was written."
  (let ((records (run-benchmarks :categories '(:harness :calibration)
                                 :output output)))
    (print-calibration-summary records)
    records))
