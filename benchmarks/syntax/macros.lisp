;;;; Syntax macro benchmarks: Sophie's compile-time macros against the
;;;; hand-written CL code they expand to.
;;;;
;;;; Matrix G covers BIND, FN, OP, JUXT, COMPOSE, FBIND, and the threading
;;;; family (->, ->>, AS->, ~>). The CL baselines come first (category
;;;; :SYNTAX-BASELINE) so every Sophie bench (category :SYNTAX) can reference
;;;; its baseline by registration order.
;;;;
;;;; Framing: every macro here expands to plain CL code at compile time, so
;;;; the honest runtime comparison is USE of the macro against the
;;;; hand-written equivalent expansion. Runtime equality documents zero
;;;; macro overhead; divergence finds real cost (FN's wrapper lambda,
;;;; FBIND's forwarding cells, COMPOSE's per-step designator resolution).
;;;; One bench, MACROEXPAND-COMPILE-TIME, is labeled COMPILE-TIME: it
;;;; measures the expansion step itself, not runtime. Every shape is fixed,
;;;; so every bench runs at size 1. No reader feature conditionals appear in
;;;; this file; host differences live in benchmarks/host.lisp.

(in-package #:sophie-lisp.benchmarks)

;;; Input builder. Every builder runs inside :SETUP, outside the timed
;;; region; persistent inputs are rebuilt fresh per rep by the harness.

(defun syntax-pair-source (n)
  "Return a fresh two-pair nested list ((N N+1) (N+2 N+3)), the shared input
of both destructuring benches."
  (list (list n (+ n 1)) (list (+ n 2) (+ n 3))))

;;; Shared note text. Every comparison bench pairs the compile-time expansion
;;; caveat with its own specifics through SYNTAX-NOTE.

(alexandria:define-constant +syntax-caveat+
  "Sophie: macro use, expanded to plain code at compile time; CL: the
hand-written equivalent expansion."
  :test #'equal
  :documentation "Shared fairness caveat carried by every syntax comparison
bench.")

(defun syntax-note (specific)
  "Return the note for one syntax comparison bench: the shared compile-time
expansion caveat followed by the bench's SPECIFIC text."
  (concatenate 'string +syntax-caveat+ " " specific))

;;; CL baselines. Each measures the plain CL form in :CALL; the fixed shapes
;;; take no input beyond the harness context.

(define-bench cl-destructuring-bind
  (:category :syntax-baseline)
  (:sizes (1))
  (:setup (n) (syntax-pair-source n))
  (:call (source)
    (destructuring-bind ((a b) (c d)) source (+ a b c d)))
  (:note "Hand-written DESTRUCTURING-BIND on a two-pair nested list; the
baseline for BIND's pattern destructuring."))

(define-bench cl-lambda-call
  (:category :syntax-baseline)
  (:sizes (1))
  (:setup (n) (declare (ignore n)) nil)
  (:call (context)
    (declare (ignore context))
    ((lambda (x) (1+ x)) 41))
  (:note "Direct LAMBDA call on a fixnum; the baseline for FN and OP."))

(define-bench cl-nested-calls
  (:category :syntax-baseline)
  (:sizes (1))
  (:setup (n) (declare (ignore n)) nil)
  (:call (context)
    (declare (ignore context))
    (1+ (sqrt (1+ (sqrt (1+ 16))))))
  (:note "Hand-written nested 1+/SQRT calls, the exact shape the threading
macros expand to; the baseline for the threading and composition benches."))

(define-bench cl-labels-call
  (:category :syntax-baseline)
  (:sizes (1))
  (:setup (n) (declare (ignore n)) nil)
  (:call (context)
    (declare (ignore context))
    (labels ((f (x) (1+ x))) (f 41)))
  (:note "LABELS establishing one local function and calling it once; the
baseline for FBIND."))

;;; Sophie benches. The macro-use benches measure the code the macro
;;; expanded to at compile time, so each is expected to run ~equal to its
;;; hand-written baseline; the ratios document zero runtime overhead or
;;; find where expansion shape costs real time.

(define-bench bind-destructure
  (:category :syntax)
  (:baseline cl-destructuring-bind)
  (:tier :same-op)
  (:sizes (1))
  (:setup (n) (syntax-pair-source n))
  (:call (source)
    (bind ((((a b) (c d)) source)) (+ a b c d)))
  (:note (syntax-note
           "BIND with one nested list pattern clause; the expansion is
compile-time, so runtime should be ~equal to the hand-written
DESTRUCTURING-BIND.")))

(define-bench fn-call
  (:category :syntax)
  (:baseline cl-lambda-call)
  (:tier :same-op)
  (:sizes (1))
  (:setup (n) (declare (ignore n)) nil)
  (:call (context)
    (declare (ignore context))
    (funcall (fn (x) (1+ x)) 41))
  (:note (syntax-note
           "FN with a plain variable parameter; the expansion wraps a
pattern-capable outer lambda (gensym argument, &REST, APPLY into the
native inner lambda), so the ratio shows that wrapper's cost against a
direct LAMBDA call.")))

(define-bench op-call
  (:category :syntax)
  (:baseline cl-lambda-call)
  (:tier :same-op)
  (:sizes (1))
  (:setup (n) (declare (ignore n)) nil)
  (:call (context)
    (declare (ignore context))
    (funcall (op (1+ %)) 41))
  (:note (syntax-note
           "OP is the macro form of the #^() placeholder lambda; (1+ %)
expands to a plain LAMBDA with the placeholder as its parameter, so runtime
should be ~equal to the direct LAMBDA call.")))

(define-bench juxt-call
  (:category :syntax)
  (:sizes (1))
  (:setup (n) (declare (ignore n)) (juxt #'1+ #'1-))
  (:call (combiner) (funcall combiner 10))
  (:note "JUXT returns a function yielding the LIST of its constituents'
primary values ((11 9) here), not multiple values; no idiomatic CL form
exists, and a hand-written mirror (a lambda returning the list of each
function's primary value) was not benched because JUXT's per-call
result-list allocation is the quantity of interest, so this bench is
absolute. The combiner is built once per rep outside the timed region; the
timed call measures one invocation, including the fresh result list
allocation and the per-step designator resolution."))

(define-bench compose-call
  (:category :syntax)
  (:baseline cl-nested-calls)
  (:tier :same-op)
  (:sizes (1))
  (:setup (n) (declare (ignore n)) (compose #'1+ #'sqrt #'1+ #'sqrt #'1+))
  (:call (combiner) (funcall combiner 16))
  (:note (syntax-note
           "COMPOSE builds one closure over the same five 1+/SQRT steps as
the nested baseline; the closure resolves each designator at invocation, so
the ratio shows the composition indirection against direct nesting. The
closure is built once per rep outside the timed region.")))

(define-bench fbind-call
  (:category :syntax)
  (:baseline cl-labels-call)
  (:tier :same-op)
  (:sizes (1))
  (:setup (n) (declare (ignore n)) nil)
  (:call (context)
    (declare (ignore context))
    (fbind ((f (fn (x) (1+ x)))) (f 41)))
  (:note (syntax-note
           "FBIND establishes its forwarding cells and closures, then calls
F once, matching the LABELS baseline's establish-and-call shape; the ratio
shows FBIND's cell check and APPLY indirection against LABELS' direct
local call.")))

(define-bench thread-first
  (:category :syntax)
  (:baseline cl-nested-calls)
  (:tier :same-op)
  (:sizes (1))
  (:setup (n) (declare (ignore n)) nil)
  (:call (context)
    (declare (ignore context))
    (-> 16 (1+) sqrt (1+) sqrt (1+)))
  (:note (syntax-note
           "-> threads 16 through five unary 1+/SQRT steps and expands to
exactly the baseline's nested form at compile time; runtime equality
confirms zero macro overhead.")))

(define-bench thread-last
  (:category :syntax)
  (:baseline cl-nested-calls)
  (:tier :same-op)
  (:sizes (1))
  (:setup (n) (declare (ignore n)) nil)
  (:call (context)
    (declare (ignore context))
    (->> 16 (1+) sqrt (1+) sqrt (1+)))
  (:note (syntax-note
           "->> threads the same unary steps into the last argument
position, which for unary operators is the sole argument position, so it
expands to the same nested form as ->; runtime equality confirms zero macro
overhead for both insertion positions.")))

(define-bench as-thread
  (:category :syntax)
  (:baseline cl-nested-calls)
  (:tier :same-op)
  (:sizes (1))
  (:setup (n) (declare (ignore n)) nil)
  (:call (context)
    (declare (ignore context))
    (as-> 16 x (1+ x) (sqrt x) (1+ x) (sqrt x) (1+ x)))
  (:note (syntax-note
           "AS-> expands to a LET* chain rebinding X per step rather than
direct nesting; the ratio shows the LET* temporaries' cost, expected close
to the nested baseline.")))

(define-bench hole-thread
  (:category :syntax)
  (:baseline cl-nested-calls)
  (:tier :same-op)
  (:sizes (1))
  (:setup (n) (declare (ignore n)) nil)
  (:call (context)
    (declare (ignore context))
    (~> 16 (1+ <>) sqrt (1+ <>) sqrt (1+ <>)))
  (:note (syntax-note
           "~> substitutes the value into each step's explicit <> hole
(bare symbol steps gain the hole implicitly), expanding to the same nested
form; runtime equality confirms zero macro overhead.")))

(define-bench macroexpand-compile-time
  (:category :syntax)
  (:sizes (1))
  (:setup (n)
    (declare (ignore n))
    (list (copy-tree
            '(bind ((((a b) (c d)) (list (list 1 2) (list 3 4))))
               (+ a b c d)))
          (copy-tree '(-> 16 (1+) sqrt (1+) sqrt (1+)))))
  (:call (forms)
    (list (macroexpand-1 (first forms))
          (macroexpand-1 (second forms))))
  (:note "COMPILE-TIME: one MACROEXPAND-1 step of a representative BIND
form and a representative -> form, the expansion cost the compiler pays
once per source form. This is expansion cost, not runtime; it has no
baseline and is absolute. COPY-TREE keeps each rep's forms fresh, outside
the timed region."))
