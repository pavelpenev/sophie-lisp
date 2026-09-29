;;;; Equivalence of internal eager traversal with the retained-view path.

(in-package #:sophie-lisp.tests)

(defvar *eager-traversal-callbacks* 0)
(defvar *eager-traversal-callback-ordinal* 0)
(defvar *eager-traversal-indices* nil)

(defun eager-traversal-corpus ()
  "Return named fresh sources; the improper tail is demanded at index three."
  (list (cons :empty-list nil)
        (cons :single-list '(7))
        (cons :mixed-list '(1 :two nil "four" 1))
        (cons :long-list (loop for index below 128 collect (mod index 11)))
        (cons :dotted (list* 1 2 3 :improper))
        (cons :empty-vector #())
        (cons :single-vector #(7))
        (cons :mixed-vector #(1 :two nil "four" 1))
        (cons :typed-vector (make-array 6 :element-type 'fixnum
                                             :initial-contents '(2 1 2 3 2 1)))
        (cons :string "abcba")
        (cons :fill-pointer (make-array 5 :initial-contents '(1 2 3 4 5)
                                       :fill-pointer 3))
        (cons :lazy (sl:lazy-cons 1 (sl:lazy-cons 2 nil)))
        (cons :hash (let ((table (make-hash-table)))
                      (setf (gethash :one table) 1
                            (gethash :two table) 2)
                      table))))

(defun eager-traversal-observe (operation source generic-p)
  "Capture a unary operation's value or condition, plus demand-side callbacks."
  (let ((sophie-lisp.internal::*force-generic-traversal* generic-p)
        (*eager-traversal-callbacks* 0)
        (*eager-traversal-indices* nil))
    (let ((outcome (handler-case
                       (let ((value (funcall operation source)))
                         (list :value (if (typep value 'sl:lazy-seq)
                                          (sl:seq-into 'list value)
                                          value)))
                     (error (condition) (list :error (type-of condition))))))
      (list outcome *eager-traversal-callbacks*
            (nreverse *eager-traversal-indices*)))))

(defun eager-traversal-normalize (value)
  (typecase value
    (sl:map-entry
     (list :map-entry (eager-traversal-normalize (sl:entry-key value))
           (eager-traversal-normalize (sl:entry-value value))))
    (sl:ordered-dict
     (list :ordered-dict (eager-traversal-normalize (sl:seq-into 'list value))))
    (cons (cons (eager-traversal-normalize (car value))
                (eager-traversal-normalize (cdr value))))
    (t value)))

(defun eager-traversal-check-corpus (operation &key (expected-dotted-callbacks 3))
  "Compare fast and generic observations on independent named corpus inputs.
EXPECTED-DOTTED-CALLBACKS, when non-NIL, is an exact callback count."
  (loop for fast-entry in (eager-traversal-corpus)
        for generic-entry in (eager-traversal-corpus)
        do (let* ((name (car fast-entry))
                  (fast (eager-traversal-observe operation (cdr fast-entry) nil))
                  (generic (eager-traversal-observe operation (cdr generic-entry) t)))
          (parachute:is equalp (list name (eager-traversal-normalize generic))
                        (list name (eager-traversal-normalize fast)))
          (when (and expected-dotted-callbacks (eq name :dotted))
            (parachute:is = expected-dotted-callbacks (second fast))
            (parachute:is eq :error (first (first fast)))
            (parachute:is eq 'type-error (second (first fast)))))))

(defun eager-traversal-record (index)
  (incf *eager-traversal-callbacks*)
  (push index *eager-traversal-indices*))

(parachute:define-test eager-traversal.corpus-equivalence
  (eager-traversal-check-corpus
   (lambda (source)
     (let ((elements nil))
       (sophie-lisp.internal::do-view-elements
           (element source :index index :result (nreverse elements))
         (eager-traversal-record index)
         (push element elements)))))
  (eager-traversal-check-corpus
   (lambda (source)
     (let ((count 0))
       (sophie-lisp.internal::do-view-elements
           (element source :index index :result count)
         (declare (ignore element))
         (eager-traversal-record index)
         (incf count)))))
  (eager-traversal-check-corpus
   (lambda (source)
     (let ((sum 0))
       (sophie-lisp.internal::do-view-elements
           (element source :index index :result sum)
         (eager-traversal-record index)
         (when (numberp element) (incf sum element))
         (when (>= index 3) (return sum)))))
   :expected-dotted-callbacks 3)
  (eager-traversal-check-corpus
   (lambda (source)
     (let ((elements nil))
       (sophie-lisp.internal::do-view-elements
           (element source :index index :result (nreverse elements))
         (eager-traversal-record index)
         (push element elements)
         (when (= index 1) (return (nreverse elements))))))
   :expected-dotted-callbacks nil))

(parachute:define-test eager-traversal.region-equivalence
  (dolist (bounds '((0 0) (0 2) (1 3) (2 2) (2 nil) (3 3) (4 4) (5 nil)))
    (eager-traversal-check-corpus
     (lambda (source)
       (let ((elements nil))
         (sophie-lisp.internal::do-view-elements
             (element source :index index :start (first bounds)
                             :end (second bounds) :result (nreverse elements))
           (eager-traversal-record index)
           (push (cons index element) elements))))
     :expected-dotted-callbacks nil)))

(parachute:define-test eager-traversal.no-prefetch-and-captured-tail
  (dolist (generic-p '(nil t))
    (let ((source (list* :first :second :bad)))
      (let ((result (eager-traversal-observe
                     (lambda (items)
                       (sophie-lisp.internal::do-view-elements
                           (element items :index index)
                         (declare (ignore element))
                         (eager-traversal-record index)
                         (when (= index 1) (return :stopped))))
                     source generic-p)))
        (parachute:is equal '(:value :stopped) (first result))
        (parachute:is = 2 (second result))
        (parachute:is equal '(0 1) (third result))))
    (let* ((source (list :first :second))
           (outcome (eager-traversal-observe
                     (lambda (items)
                       (sophie-lisp.internal::do-view-elements
                           (element items :index index :result :done)
                         (declare (ignore element))
                         (eager-traversal-record index)
                         (when (zerop index) (setf (cdr source) nil))))
                     source generic-p)))
      (parachute:is equal '(:value :done) (first outcome))
      (parachute:is equal '(0 1) (third outcome)))))

(defun eager-traversal-query-record (kind &rest arguments)
  (eager-traversal-record (cons kind arguments)))

(parachute:define-test eager-traversal.scalar-query-equivalence
  ;; Record both key and predicate/test calls with their full argument lists.
  ;; No selected item satisfies the FIND/COUNT tests, so the dotted tail is
  ;; reached after exactly three elements and six callbacks.
  (dolist (operation
           (list (lambda (source)
                   (sl:seq-find :absent source
                                :key (lambda (value)
                                       (eager-traversal-query-record :key value)
                                       value)
                                :test (lambda (item value)
                                        (eager-traversal-query-record :test item value)
                                        nil)))
                 (lambda (source)
                   (sl:seq-position :absent source
                                    :key (lambda (value)
                                           (eager-traversal-query-record :key value)
                                           value)
                                    :test (lambda (item value)
                                            (eager-traversal-query-record :test item value)
                                            nil)))
                 (lambda (source)
                   (sl:seq-find-if (lambda (value)
                                     (eager-traversal-query-record :predicate value)
                                     nil)
                                   source :key (lambda (value)
                                                 (eager-traversal-query-record :key value)
                                                 value)))
                 (lambda (source)
                   (sl:seq-position-if (lambda (value)
                                         (eager-traversal-query-record :predicate value)
                                         nil)
                                       source :key (lambda (value)
                                                     (eager-traversal-query-record :key value)
                                                     value)))
                 (lambda (source)
                   (sl:seq-count :absent source
                                 :key (lambda (value)
                                        (eager-traversal-query-record :key value)
                                        value)
                                 :test (lambda (item value)
                                         (eager-traversal-query-record :test item value)
                                         nil)))
                 (lambda (source)
                   (sl:seq-count-if (lambda (value)
                                      (eager-traversal-query-record :predicate value)
                                      nil)
                                    source :key (lambda (value)
                                                  (eager-traversal-query-record :key value)
                                                  value)))))
    (eager-traversal-check-corpus operation :expected-dotted-callbacks 6))
  (dolist (operation
           (list (lambda (source)
                   (sl:seq-find :absent source :from-end t
                                :test (lambda (item value)
                                        (eager-traversal-query-record :test item value)
                                        nil)))
                 (lambda (source)
                   (sl:seq-find-if
                    (lambda (value)
                      (eager-traversal-query-record :predicate value)
                      nil)
                    source :from-end t))
                 (lambda (source)
                   (sl:seq-position :absent source :from-end t
                                    :test (lambda (item value)
                                            (eager-traversal-query-record :test item value)
                                            nil)))
                 (lambda (source)
                   (sl:seq-position-if
                    (lambda (value)
                      (eager-traversal-query-record :predicate value)
                      nil)
                    source :from-end t))
                 (lambda (source)
                   (sl:seq-count :absent source :from-end t
                                 :test (lambda (item value)
                                         (eager-traversal-query-record :test item value)
                                         nil)))
                 (lambda (source)
                   (sl:seq-count-if
                    (lambda (value)
                      (eager-traversal-query-record :predicate value)
                      nil)
                    source :from-end t))))
    (eager-traversal-check-corpus operation :expected-dotted-callbacks 0))
  (eager-traversal-check-corpus (lambda (source) (sl:seq-last source))
                                :expected-dotted-callbacks 0)
  (dolist (operation
           (list (lambda (source)
                   (sl:seq-every (lambda (value)
                                   (eager-traversal-query-record :predicate value)
                                   t)
                                 source))
                 (lambda (source)
                   (sl:seq-some (lambda (value)
                                  (eager-traversal-query-record :predicate value)
                                  nil)
                                source))
                 (lambda (source)
                   (sl:seq-notevery (lambda (value)
                                      (eager-traversal-query-record :predicate value)
                                      t)
                                    source))
                 (lambda (source)
                   (sl:seq-notany (lambda (value)
                                    (eager-traversal-query-record :predicate value)
                                    nil)
                                  source))
                 (lambda (source)
                   (sl:seq-min source :default :empty
                               :key (lambda (value)
                                      (eager-traversal-query-record :key value)
                                      0)))
                 (lambda (source)
                   (sl:seq-max source :default :empty
                               :key (lambda (value)
                                      (eager-traversal-query-record :key value)
                                      0)))))
    (eager-traversal-check-corpus operation))
  ;; The region must validate its START without observing the node at END.
  (dolist (operation
           (list (lambda (source)
                   (sl:seq-find :absent source :start 2 :end 2))
                 (lambda (source)
                   (sl:seq-count :absent source :start 2 :end 2))))
    (eager-traversal-check-corpus operation :expected-dotted-callbacks nil))
  (dolist (operation
           (list (lambda (source)
                   (sl:seq-find-if #'identity source :start 4 :end 4))
                 (lambda (source)
                   (sl:seq-count-if #'identity source :start 4 :end 4))))
    (eager-traversal-check-corpus operation :expected-dotted-callbacks 0))
  (dolist (operation
           (list (lambda (source)
                   (sl:seq-find 3 source
                                :test (lambda (item value)
                                        (eager-traversal-query-record :test item value)
                                        (eql item value))))
                 (lambda (source)
                   (sl:seq-position-if
                    (lambda (value)
                      (eager-traversal-query-record :predicate value)
                      (eql value 3))
                    source))
                 (lambda (source)
                   (sl:seq-some (lambda (value)
                                  (eager-traversal-query-record :predicate value)
                                  (and (eql value 3) :found))
                                source))
                 (lambda (source)
                   (sl:seq-every (lambda (value)
                                   (eager-traversal-query-record :predicate value)
                                   (not (eql value 3)))
                                 source))
                 (lambda (source)
                   (sl:seq-notevery (lambda (value)
                                      (eager-traversal-query-record :predicate value)
                                      (not (eql value 3)))
                                    source))
                 (lambda (source)
                   (sl:seq-notany (lambda (value)
                                    (eager-traversal-query-record :predicate value)
                                    (eql value 3))
                                  source))))
    (let* ((source '(0 1 2 3 4 5))
           (generic (eager-traversal-observe operation source t))
           (fast (eager-traversal-observe operation source nil)))
      (parachute:is equal generic fast)
      (parachute:is = 4 (second generic))
      (parachute:is = 4 (second fast)))))

(parachute:define-test eager-traversal.map-materialize-equivalence
  ;; Both materialization branches and unary mapping share the eager drain.
  (dolist (operation
           (list (lambda (source)
                   (sl:seq-map (lambda (value)
                                 (eager-traversal-query-record :map value)
                                 value)
                               source))
                 (lambda (source)
                   (sl:seq-map-indexed
                    (lambda (index value)
                      (eager-traversal-query-record :indexed index value)
                      value)
                    source))
                 (lambda (source)
                   (sl:seq-keep (lambda (value)
                                  (eager-traversal-query-record :keep value)
                                  value)
                                source))
                 (lambda (source)
                   (sl:seq-mapcat (lambda (value)
                                    (eager-traversal-query-record :cat value)
                                    (list value))
                                  source))
                 (lambda (source)
                   (sl:seq-map (lambda (value)
                                 (eager-traversal-query-record :mixed value)
                                 value)
                               source #()))))
    (eager-traversal-check-corpus operation :expected-dotted-callbacks nil)))

(parachute:define-test eager-traversal.selection-finish-equivalence
  (dolist (operation
           (list (lambda (source)
                   (sl:seq-filter
                    (lambda (value)
                      (eager-traversal-query-record :predicate value)
                      t)
                    source :key (lambda (value)
                                  (eager-traversal-query-record :key value)
                                  value)))
                 (lambda (source)
                   (sl:seq-remove :absent source
                                  :test (lambda (item value)
                                          (eager-traversal-query-record :test item value)
                                          nil)))
                 (lambda (source)
                   (sl:seq-remove-if
                    (lambda (value)
                      (eager-traversal-query-record :predicate value)
                      nil)
                    source))
                 (lambda (source) (sl:seq-take 2 source))
                 (lambda (source) (sl:seq-drop 1 source))
                 (lambda (source)
                   (sl:seq-take-while
                    (lambda (value)
                      (eager-traversal-query-record :predicate value)
                      t)
                    source))
                 (lambda (source)
                   (sl:seq-drop-while
                    (lambda (value)
                      (eager-traversal-query-record :predicate value)
                      nil)
                    source))
                 (lambda (source) (sl:seq-take-nth 2 source))))
    (eager-traversal-check-corpus operation :expected-dotted-callbacks nil))
  ;; Finite region, empty region, and unreachable start on each source type.
  (dolist (bounds '((0 0) (0 2) (1 3) (2 2) (4 4)))
    (eager-traversal-check-corpus
     (lambda (source)
       (sl:seq-filter (lambda (value)
                        (eager-traversal-query-record :predicate value)
                        t)
                      source :start (first bounds) :end (second bounds)))
     :expected-dotted-callbacks nil)
    (eager-traversal-check-corpus
     (lambda (source)
       (sl:seq-remove-if (lambda (value)
                           (eager-traversal-query-record :predicate value)
                           nil)
                         source :start (first bounds) :end (second bounds)))
     :expected-dotted-callbacks nil))
  (dolist (operation
           (list (lambda (source)
                   (sl:seq-filter (lambda (value)
                                    (eager-traversal-query-record :predicate value)
                                    t)
                                  source :from-end t :count 1))
                 (lambda (source)
                   (sl:seq-remove-if
                    (lambda (value)
                      (eager-traversal-query-record :predicate value)
                      t)
                    source :from-end t :count 1))))
    (eager-traversal-check-corpus operation :expected-dotted-callbacks nil)))

(defun eager-traversal-lazy-observe (operation source generic-p)
  (let ((sophie-lisp.internal::*force-generic-traversal* generic-p)
        (*eager-traversal-callbacks* 0)
        (*eager-traversal-indices* nil))
    (let* ((result (funcall operation source))
           (before (list *eager-traversal-callbacks*
                         (reverse *eager-traversal-indices*)))
           (first (handler-case (list :value (sl:seq-into 'list result))
                    (error (condition) (list :error (type-of condition)))))
           (middle (list *eager-traversal-callbacks*
                         (reverse *eager-traversal-indices*)))
           (second (handler-case (list :value (sl:seq-into 'list result))
                     (error (condition) (list :error (type-of condition))))))
      (list before first middle second *eager-traversal-callbacks*
            (reverse *eager-traversal-indices*)))))

(parachute:define-test eager-traversal.lazy-selection-and-map-forcing
  ;; Results remain deferred, and repeat forcing preserves memoized nodes.
  (dolist (operation
           (list (lambda (source)
                   (sl:seq-map (lambda (value)
                                 (eager-traversal-query-record :map value)
                                 value)
                               source))
                 (lambda (source)
                   (sl:seq-map-indexed
                    (lambda (index value)
                      (eager-traversal-query-record :indexed index value)
                      value)
                    source))
                 (lambda (source)
                   (sl:seq-filter
                    (lambda (value)
                      (eager-traversal-query-record :predicate value)
                      t)
                    source))
                 (lambda (source)
                   (sl:seq-remove-if
                    (lambda (value)
                      (eager-traversal-query-record :predicate value)
                      nil)
                    source))))
    (dolist (source (list (sl:lazy-cons 1 (sl:lazy-cons 2 nil))
                          (sl:lazy-cons 1
                                        (sl:make-lazy-seq
                                         (lambda () (error 'type-error
                                                           :datum :bad
                                                           :expected-type 'list))))))
      (let ((fast (eager-traversal-lazy-observe operation source nil))
            (generic (eager-traversal-lazy-observe operation source t)))
        (parachute:is equalp generic fast)
        (parachute:is equal '(0 nil) (first fast))
        (parachute:is equal (second fast) (fourth fast))
        (parachute:is equal (third fast)
                      (list (fifth fast) (sixth fast)))))))

(parachute:define-test eager-traversal.eager-result-types-and-freshness
  (dolist (source (list '(1 2 3 4) #(1 2 3 4)))
    (dolist (operation
             (list (lambda (items) (sl:seq-map #'1+ items))
                   (lambda (items) (sl:seq-map-indexed
                                    (lambda (index item) (+ index item)) items))
                   (lambda (items) (sl:seq-keep #'identity items))
                   (lambda (items) (sl:seq-mapcat #'list items))
                   (lambda (items) (sl:seq-filter #'evenp items))
                   (lambda (items) (sl:seq-remove-if #'evenp items))))
      (dolist (generic-p '(nil t))
        (let* ((sophie-lisp.internal::*force-generic-traversal* generic-p)
               (first (funcall operation source))
               (second (funcall operation source)))
          (parachute:is equal (type-of first) (type-of second))
          (parachute:is equalp first second)
          (parachute:false (eq first second))
          (parachute:false (eq first source))))))
  (dolist (generic-p '(nil t))
    (let* ((sophie-lisp.internal::*force-generic-traversal* generic-p)
           (source '(1 2))
           (first (sl:seq-map (lambda (a b) (declare (ignore b)) (1+ a))
                              source #(3 4)))
           (second (sl:seq-map (lambda (a b) (declare (ignore b)) (1+ a))
                               source #(3 4))))
      (parachute:true (typep first 'sl:lazy-seq))
      (parachute:false (eq first second))
      (parachute:is equal '(2 3) (sl:seq-into 'list first)))))

(parachute:define-test eager-traversal.eager-drain-dotted-position
  (dolist (generic-p '(nil t))
    (dolist (entry
             (list (cons :map
                         (lambda (source)
                           (sl:seq-map (lambda (value)
                                         (eager-traversal-query-record :map value)
                                         value)
                                       source)))
                   (cons :predicate
                         (lambda (source)
                           (sl:seq-filter
                            (lambda (value)
                              (eager-traversal-query-record :predicate value)
                              t)
                            source)))))
      (let ((outcome (eager-traversal-observe
                      (cdr entry) (list* 1 2 3 :bad) generic-p)))
        (parachute:is eq :error (first (first outcome)))
        (parachute:is eq 'type-error (second (first outcome)))
        (parachute:is = 3 (second outcome))
        (parachute:is equal (list (list (car entry) 1)
                                  (list (car entry) 2)
                                  (list (car entry) 3))
                      (third outcome))))))

(parachute:define-test eager-traversal.cursor-single-source-corpus
  (dolist (operation
           (list (lambda (source)
                   (sl:seq-map-indexed
                    (lambda (index value)
                      (eager-traversal-query-record :indexed index value)
                      value) source))
                 (lambda (source)
                   (sl:seq-keep (lambda (value)
                                  (eager-traversal-query-record :keep value)
                                  value) source))
                 (lambda (source)
                   (sl:seq-mapcat (lambda (value)
                                    (eager-traversal-query-record :cat value)
                                    (list value)) source))
                 (lambda (source)
                   (sl:seq-remove :absent source
                                  :test (lambda (item value)
                                          (eager-traversal-query-record :test item value)
                                          nil)))
                 (lambda (source)
                   (sl:seq-remove-if
                    (lambda (value)
                      (eager-traversal-query-record :predicate value)
                      nil) source))))
    (eager-traversal-check-corpus operation :expected-dotted-callbacks nil)))

(parachute:define-test eager-traversal.cursor-demand-and-retry
  (dolist (generic-p '(nil t))
    (dolist (operation
             (list (lambda (callback source) (sl:seq-map callback source))
                   (lambda (callback source)
                     (sl:seq-map-indexed
                      (lambda (index value)
                        (declare (ignore index))
                        (funcall callback value)) source))
                   (lambda (callback source) (sl:seq-keep callback source))
                   (lambda (callback source)
                     (sl:seq-mapcat (lambda (value)
                                      (funcall callback value)
                                      (list value)) source))
                   (lambda (callback source) (sl:seq-filter callback source))
                   (lambda (callback source)
                     (sl:seq-remove-if (lambda (value)
                                         (funcall callback value)
                                         nil) source))
                   (lambda (callback source) (sl:seq-remove :absent source
                                                            :test (lambda (item value)
                                                                    (declare (ignore item))
                                                                    (funcall callback value)
                                                                    nil)))))
      (let* ((sophie-lisp.internal::*force-generic-traversal* generic-p)
             (seen nil)
             (source (sl:lazy-cons 1 (sl:lazy-cons 2 (sl:lazy-cons 3 nil))))
             (result (funcall operation (lambda (value)
                                          (push value seen)
                                          value) source)))
        (parachute:is equal nil seen)
        (parachute:is eql 1 (sl:seq-first result))
        (parachute:is equal '(1) seen)
        (parachute:is eql 1 (sl:seq-first result))
        (parachute:is equal '(1) seen)
        (let ((second (sl:seq-rest result)))
          (parachute:true (eq second (sl:seq-rest result)))
          (parachute:is equal '(1) seen)
          (parachute:is eql 2 (sl:seq-first second))
          (parachute:is equal '(2 1) seen)
          (parachute:is eql 3 (sl:seq-first (sl:seq-rest second)))
          (parachute:is equal '(3 2 1) seen))))
    (let* ((sophie-lisp.internal::*force-generic-traversal* generic-p)
           (calls 0)
           (source (list* 1 2 :bad))
           (cursor (sophie-lisp.internal::make-view-cursor source)))
      (multiple-value-bind (empty element rest)
          (sophie-lisp.internal::view-cursor-step cursor)
        (parachute:false empty)
        (parachute:is eql 1 element)
        (sophie-lisp.internal::view-cursor-advance cursor rest))
      (multiple-value-bind (empty element rest)
          (sophie-lisp.internal::view-cursor-step cursor)
        (parachute:false empty)
        (parachute:is eql 2 element)
        (sophie-lisp.internal::view-cursor-advance cursor rest))
      (dotimes (attempt 2)
        (declare (ignore attempt))
        (handler-case (sophie-lisp.internal::view-cursor-step cursor)
          (type-error (condition)
            (parachute:is eql :bad (type-error-datum condition))
            (incf calls))))
      (parachute:is = 2 calls))))

(parachute:define-test eager-traversal.cursor-dotted-lazy-force-position
  (dolist (operation
           (list (lambda (callback source) (sl:seq-map callback source))
                 (lambda (callback source)
                   (sl:seq-map-indexed (lambda (index value)
                                         (declare (ignore index))
                                         (funcall callback value)) source))
                 (lambda (callback source) (sl:seq-keep callback source))
                 (lambda (callback source)
                   (sl:seq-mapcat (lambda (value)
                                    (funcall callback value)
                                    (list value)) source))
                 (lambda (callback source)
                   (sl:seq-filter (lambda (value)
                                    (funcall callback value)
                                    t) source))
                 (lambda (callback source)
                   (sl:seq-remove-if (lambda (value)
                                       (funcall callback value)
                                       nil) source))
                 (lambda (callback source)
                   (sl:seq-remove :absent source
                                  :test (lambda (item value)
                                          (declare (ignore item))
                                          (funcall callback value)
                                          nil)))))
    (dolist (generic-p '(nil t))
      (let* ((sophie-lisp.internal::*force-generic-traversal* generic-p)
             (seen nil)
             (source (sophie-lisp.internal::open-view (list* 1 2 3 :bad)))
             (result (funcall operation (lambda (value) (push value seen) value) source)))
        (parachute:is equal nil seen)
        (dotimes (position 3)
          (parachute:is eql (1+ position) (sl:seq-first result))
          (parachute:is = (1+ position) (length seen))
          (setf result (sl:seq-rest result)))
        (parachute:is equal '(3 2 1) seen)
        (dotimes (retry 2)
          (declare (ignore retry))
          (handler-case (sl:seq-first result)
            (type-error (condition)
              (parachute:is eql :bad (type-error-datum condition)))))
        (parachute:is equal '(3 2 1) seen)))))

(defun eager-traversal-direct-observe (operation source generic-p)
  (let ((sophie-lisp.internal::*force-generic-traversal* generic-p)
        (*eager-traversal-indices* nil))
    (let ((outcome (handler-case
                       (let ((value (funcall operation source)))
                         (list :value (type-of value)
                               (and (vectorp value) (array-element-type value))
                               (eager-traversal-normalize (if (typep value 'sl:lazy-seq)
                                                              (sl:seq-into 'list value)
                                                              value))
                               (and (or (consp value) (vectorp value))
                                    (eq source value))))
                     (error (condition)
                       (list :error (type-of condition)
                             (and (typep condition 'type-error)
                                  (type-error-datum condition)))))))
      (list outcome (nreverse *eager-traversal-indices*)))))

(parachute:define-test eager-traversal.direct-build-corpus-equivalence
  (dolist (operation
           (list (lambda (source)
                   (sl:seq-map (lambda (value)
                                 (eager-traversal-query-record :map value)
                                 value) source))
                 (lambda (source)
                   (sl:seq-map-indexed
                    (lambda (index value)
                      (eager-traversal-query-record :indexed index value)
                      value) source))
                 (lambda (source)
                   (sl:seq-keep (lambda (value)
                                  (eager-traversal-query-record :keep value)
                                  value) source))
                 (lambda (source)
                   (sl:seq-filter (lambda (value)
                                    (eager-traversal-query-record :predicate value)
                                    t) source
                                  :key (lambda (value)
                                         (eager-traversal-query-record :key value)
                                         value)))
                 (lambda (source)
                   (sl:seq-remove :absent source
                                  :key (lambda (value)
                                         (eager-traversal-query-record :key value)
                                         value)
                                  :test (lambda (item value)
                                          (eager-traversal-query-record :test item value)
                                          nil)))
                 (lambda (source)
                   (sl:seq-remove-if
                    (lambda (value)
                      (eager-traversal-query-record :predicate value)
                      nil) source))))
    (loop for fast-entry in (eager-traversal-corpus)
          for generic-entry in (eager-traversal-corpus)
          do (let ((name (car fast-entry)))
               (parachute:is equalp
                             (list name (eager-traversal-direct-observe
                                         operation (cdr generic-entry) t))
                             (list name (eager-traversal-direct-observe
                                         operation (cdr fast-entry) nil)))))))

(parachute:define-test eager-traversal.direct-build-region-and-errors
  (dolist (bounds '((0 0) (0 2) (1 3) (2 2) (2 nil) (3 3) (4 4) (5 nil)))
    (dolist (operation
             (list (lambda (source)
                     (sl:seq-filter
                      (lambda (value)
                        (eager-traversal-query-record :predicate value)
                        t) source :start (first bounds) :end (second bounds)))
                   (lambda (source)
                     (sl:seq-remove-if
                      (lambda (value)
                        (eager-traversal-query-record :predicate value)
                        nil) source :start (first bounds) :end (second bounds)))))
      (loop for fast-entry in (eager-traversal-corpus)
            for generic-entry in (eager-traversal-corpus)
            do (let ((name (car fast-entry)))
                 (parachute:is equalp
                               (list name (eager-traversal-direct-observe
                                           operation (cdr generic-entry) t))
                               (list name (eager-traversal-direct-observe
                                           operation (cdr fast-entry) nil)))))))
  (dolist (operation
           (list (lambda (source)
                   (sl:seq-map (lambda (value)
                                 (eager-traversal-query-record :map value)
                                 (when (eql value 2) (error 'simple-error))
                                 value) source))
                 (lambda (source)
                   (sl:seq-map-indexed
                    (lambda (index value)
                      (eager-traversal-query-record :indexed index value)
                      (when (eql value 2) (error 'simple-error))
                      value) source))
                 (lambda (source)
                   (sl:seq-keep (lambda (value)
                                  (eager-traversal-query-record :keep value)
                                  (when (eql value 2) (error 'simple-error))
                                  value) source))
                 (lambda (source)
                   (sl:seq-filter
                    (lambda (value)
                      (eager-traversal-query-record :predicate value)
                      (when (eql value 2) (error 'simple-error))
                      t) source))
                 (lambda (source)
                   (sl:seq-remove-if
                    (lambda (value)
                      (eager-traversal-query-record :predicate value)
                      (when (eql value 2) (error 'simple-error))
                      nil) source))
                 (lambda (source)
                   (sl:seq-remove :absent source
                                  :test (lambda (item value)
                                          (declare (ignore item))
                                          (eager-traversal-query-record :test value)
                                          (when (eql value 2) (error 'simple-error))
                                          nil)))))
    (dolist (source (list '(1 2 3) #(1 2 3) (list* 1 2 3 :bad)))
      (parachute:is equalp
                    (eager-traversal-direct-observe operation source t)
                    (eager-traversal-direct-observe operation source nil)))))

(parachute:define-test eager-traversal.direct-build-typed-vectors-and-freshness
  (dolist (source (list (make-array 3 :element-type 'fixnum
                                       :initial-contents '(1 2 3))
                        (make-array 4 :element-type 'base-char
                                       :initial-contents '(#\a #\b #\c #\d))
                        (make-array 4 :fill-pointer 3
                                       :initial-contents '(1 2 3 4))))
    (dolist (operation
             (list (lambda (items) (sl:seq-map #'identity items))
                   (lambda (items) (sl:seq-map-indexed
                                    (lambda (index value)
                                      (declare (ignore index)) value) items))
                   (lambda (items) (sl:seq-keep #'identity items))
                   (lambda (items) (sl:seq-filter (constantly t) items))
                   (lambda (items) (sl:seq-remove-if (constantly nil) items))
                   (lambda (items) (sl:seq-remove :absent items
                                                    :test (constantly nil)))))
      (parachute:is equalp
                    (eager-traversal-direct-observe operation source t)
                    (eager-traversal-direct-observe operation source nil))
      (let ((sophie-lisp.internal::*force-generic-traversal* nil))
        (let ((first (funcall operation source))
              (second (funcall operation source)))
          (parachute:false (eq first source))
          (parachute:false (eq first second)))))))

(defun eager-traversal-construction-value (value)
  (typecase value
    (hash-table
     (let ((entries nil))
       (maphash (lambda (key item) (push (list key item) entries)) value)
       (list :hash-table (hash-table-test value) (nreverse entries))))
    (sl:dict
     (list :dict (sl:seq-into 'list value)))
    (sl:ordered-dict
     (list :ordered-dict (sl:seq-into 'list value)))
    (sl:hash-set
     (list :hash-set (sl:seq-into 'list value)))
    (t (list (type-of value) value))))

(defun eager-traversal-construction-observe (operation source generic-p)
  (let ((sophie-lisp.internal::*force-generic-traversal* generic-p)
        (*eager-traversal-callbacks* 0)
        (*eager-traversal-callback-ordinal* 0)
        (*eager-traversal-indices* nil))
    (let ((outcome (handler-case
                       (let ((value (funcall operation source)))
                         (list :value (eager-traversal-construction-value value)
                               (and (or (listp source) (vectorp source))
                                    (not (eq value source)))))
                     (error (condition) (list :error (type-of condition))))))
      (list outcome *eager-traversal-callbacks*
            (nreverse *eager-traversal-indices*)))))

(defun eager-traversal-entry-corpus ()
  (let ((entries (list (sl:map-entry :a 1) (sl:map-entry :b 2)
                       (sl:map-entry :a 3))))
    (list (cons :empty nil)
          (cons :list entries)
          (cons :vector (coerce entries 'vector))
          (cons :fill-pointer
                (make-array 5 :initial-contents
                            (append entries (subseq entries 0 2))
                            :fill-pointer 3))
          (cons :lazy (sl:lazy-cons (first entries)
                                    (sl:lazy-cons (second entries)
                                                  (sl:lazy-cons (third entries) nil))))
          (cons :dotted (list* (first entries) (second entries)
                               (third entries) :bad)))))

(defun eager-traversal-wrong-entry-corpus ()
  (let ((wrong (list (sl:map-entry :a 1) :bad (sl:map-entry :b 2))))
    (list (cons :wrong-list wrong)
          (cons :wrong-vector (coerce wrong 'vector)))))

(defun eager-traversal-check-construction (operation sources &optional dotted-count)
  (loop for fast-entry in (funcall sources)
        for generic-entry in (funcall sources)
        do (let* ((name (car fast-entry))
                  (source (cdr fast-entry))
                  (fast (eager-traversal-construction-observe operation source nil))
                  (generic (eager-traversal-construction-observe
                            operation (cdr generic-entry) t)))
             (parachute:is equalp
                           (list name (eager-traversal-normalize generic))
                           (list name (eager-traversal-normalize fast)))
             (when (and dotted-count (consp source) (not (list-length-safe source)))
               (parachute:is = dotted-count (second fast))
               (parachute:is equal '(0 1 2) (third fast))
               (parachute:is eq :error (first (first fast)))
               (parachute:is eq 'type-error (second (first fast)))))))

(defun list-length-safe (source)
  (handler-case (length source)
    (type-error () nil)))

(parachute:define-test eager-traversal.construction-equivalence
  (dolist (target '(list vector string hash-table dict ordered-dict hash-set))
    (eager-traversal-check-construction
     (lambda (source) (sl:seq-into target source)) #'eager-traversal-corpus))
  (eager-traversal-check-construction
   (lambda (source)
     (sl:dict-group-by
      (lambda (value)
        (eager-traversal-record *eager-traversal-callback-ordinal*)
        (incf *eager-traversal-callback-ordinal*)
        value)
      source))
   #'eager-traversal-corpus)
  (dolist (operation
           (list (lambda (source) (sl:seq-into 'dict source))
                 (lambda (source) (sl:seq-into 'ordered-dict source))
                 (lambda (source) (sl:seq-into 'hash-table source))
                 (lambda (source) (sl:dict-collect (sl:dict) source))
                 (lambda (source) (sl:dict-collect (make-hash-table) source))
                 (lambda (source)
                   (sophie-lisp.internal::ordered-from-entries 'sl:ordered-dict source))))
    (eager-traversal-check-construction operation #'eager-traversal-entry-corpus))
  (eager-traversal-check-construction
   (lambda (items) (sl:seq-into 'dict items))
   #'eager-traversal-wrong-entry-corpus)
  (dolist (operation (list (lambda (source) (sl:set-size source))
                           (lambda (source) (sl:dict-frequencies source))
                           (lambda (source) (sl:dict-count-by #'identity source))))
    (eager-traversal-check-construction operation #'eager-traversal-corpus)))

(parachute:define-test eager-traversal.member-corpus-equivalence
  ;; Each run uses independent sources, and the observation realizes the tail.
  (eager-traversal-check-corpus
   (lambda (source)
     (sl:seq-member :absent source
                    :key (lambda (value)
                           (eager-traversal-query-record :key value)
                           value)
                    :test (lambda (item value)
                            (eager-traversal-query-record :test item value)
                            nil)))
   :expected-dotted-callbacks 6)
  (dolist (item '(1 2 3 :absent))
    (eager-traversal-check-corpus
     (lambda (source)
       (sl:seq-member item source
                      :key (lambda (value)
                             (eager-traversal-query-record :key value)
                             value)
                      :test (lambda (target value)
                              (eager-traversal-query-record :test target value)
                              (eql target value))))
     :expected-dotted-callbacks (if (eql item :absent) 6 nil))))

(parachute:define-test eager-traversal.member-call-time-and-lazy-tail
  (dolist (generic-p '(nil t))
    (let* ((sophie-lisp.internal::*force-generic-traversal* generic-p)
           (forces nil)
           (callbacks nil)
           (source (sl:lazy-cons 1
                     (sl:make-lazy-seq
                      (lambda ()
                        (push 2 forces)
                        (sl:lazy-cons 2
                          (sl:make-lazy-seq
                           (lambda ()
                             (push 3 forces)
                             (sl:lazy-cons 3 nil))))))))
           (tail (sl:seq-member 2 source
                   :key (lambda (value) (push (list :key value) callbacks) value)
                   :test (lambda (item value)
                           (push (list :test item value) callbacks)
                           (eql item value)))))
      (parachute:is equal '(2) forces)
      (parachute:is equal '((:key 1) (:test 2 1) (:key 2) (:test 2 2))
                    (reverse callbacks))
      (parachute:is eql 2 (sl:seq-first tail))
      (parachute:is equal '(2) forces)
      (parachute:is eql 3 (sl:seq-first (sl:seq-rest tail)))
      (parachute:is equal '(3 2) forces)
      (parachute:is = 4 (length callbacks)))
    (let* ((sophie-lisp.internal::*force-generic-traversal* generic-p)
           (source (list* 1 2 :bad))
           (tail (sl:seq-member 2 source)))
      (parachute:is eql 2 (sl:seq-first tail))
      (loop repeat 2 do
        (parachute:is eql :bad
          (handler-case (sl:seq-first (sl:seq-rest tail))
            (type-error (condition) (type-error-datum condition))))))
    (let* ((sophie-lisp.internal::*force-generic-traversal* generic-p)
           (source (make-array 4 :fill-pointer 3
                                 :initial-contents '(1 2 3 4)))
           (tail (sl:seq-member 2 source
                   :test (lambda (item value)
                           (when (= value 2) (setf (fill-pointer source) 4))
                           (= item value)))))
      ;; The view's end is fixed on opening, not on later tail demand.
      (parachute:is equal '(2 3) (sl:seq-into 'list tail)))))

(parachute:define-test eager-traversal.mapcat-inner-corpus
  ;; Fresh independent sources for fast and forced-generic modes, including
  ;; empty and lazy inner pieces.
  (dolist (piece
           (list (lambda (value) (list value value))
                 (lambda (value) (declare (ignore value)) nil)
                 (lambda (value) (vector value value))
                 (lambda (value)
                   (sl:lazy-cons value (sl:lazy-cons value nil)))))
    (eager-traversal-check-corpus
     (lambda (source)
       (sl:seq-mapcat (lambda (value)
                        (eager-traversal-query-record :cat value)
                        (funcall piece value)) source))
     :expected-dotted-callbacks nil)))

(parachute:define-test eager-traversal.mapcat-staged-open-and-demand
  (dolist (generic-p '(nil t))
    ;; A failed opening must not replay the successful callback, even after
    ;; a preceding result has already been delivered.
    (let* ((sophie-lisp.internal::*force-generic-traversal* generic-p)
           (calls nil)
           (piece (make-instance 'map03-validating :items '(8 9)))
           (result (sl:seq-mapcat
                    (lambda (value)
                      (push value calls)
                      (if (= value 1) (list :first) piece))
                    (sl:lazy-cons 1 (sl:lazy-cons 2 nil)))))
      (parachute:false calls)
      (parachute:is eq :first (sl:seq-first result))
      (parachute:is equal '(1) calls)
      (let ((tail (sl:seq-rest result)))
        (parachute:fail (sl:seq-first tail) map03-validation-retry)
        (parachute:is equal '(2 1) calls)
        (parachute:is = 8 (sl:seq-first tail))
        (parachute:is equal '(2 1) calls)
        (parachute:is equal '(:first 8 9) (sl:seq-into 'list result))
        (parachute:is equal '(2 1) calls)))
    (let* ((sophie-lisp.internal::*force-generic-traversal* generic-p)
           (calls nil)
           (forces nil)
           (result (sl:seq-mapcat
                    (lambda (value)
                      (push value calls)
                      (if (= value 1) nil
                          (sl:make-lazy-seq
                           (lambda ()
                             (push value forces)
                             (sl:lazy-cons value nil)))))
                    (sl:lazy-cons 1 (sl:lazy-cons 2 nil)))))
      (parachute:false calls)
      (parachute:false forces)
      (parachute:is = 2 (sl:seq-first result))
      (parachute:is equal '(2 1) calls)
      (parachute:is equal '(2) forces)
      (parachute:is = 2 (sl:seq-first result))
      (parachute:is equal '(2) forces))))

(parachute:define-test eager-traversal.search-mismatch-corpus
  ;; Each observation receives an independent source from the corpus.
  (dolist (operation
           (list (lambda (source)
                   (sl:seq-search '(1 :two) source
                                  :key (lambda (value)
                                         (eager-traversal-query-record :key value)
                                         value)
                                  :test (lambda (left right)
                                          (eager-traversal-query-record :test left right)
                                          (equal left right))))
                 (lambda (source)
                   (sl:seq-search #(1) source :from-end t
                                  :test (lambda (left right)
                                          (eager-traversal-query-record :test left right)
                                          (equal left right))))
                 (lambda (source)
                   (sl:seq-search nil source :from-end t))
                 (lambda (source)
                   (sl:seq-search nil source :start2 2 :end2 2))
                 (lambda (source)
                   (sl:seq-mismatch '(1 :two nil) source
                                    :key (lambda (value)
                                           (eager-traversal-query-record :key value)
                                           value)
                                    :test (lambda (left right)
                                            (eager-traversal-query-record :test left right)
                                            (equal left right))))
                 (lambda (source)
                   (sl:seq-mismatch #(1 :two nil) source :from-end t
                                    :test (lambda (left right)
                                            (eager-traversal-query-record :test left right)
                                            (equal left right))))
                 (lambda (source)
                   (sl:seq-mismatch nil source :start1 0 :end1 0))
                 (lambda (source)
                   (sl:seq-mismatch #(1 2) source :start1 1 :end1 2
                                    :start2 1 :end2 3 :from-end t))))
    (eager-traversal-check-corpus operation :expected-dotted-callbacks nil)))

(parachute:define-test eager-traversal.search-mismatch-boundary-traces
  (dolist (generic-p '(nil t))
    (let ((sophie-lisp.internal::*force-generic-traversal* generic-p)
          (calls nil))
      (flet ((key (value) (push (list :key value) calls) value)
             (compare (left right)
               (push (list :test left right) calls)
               (eql left right)))
        (parachute:is = 2 (sl:seq-search '(2 3) #(0 1 2 3 2 3 8)
                                         :start2 1 :end2 4
                                         :key #'key :test #'compare))
        (parachute:is equal '((:key 2) (:key 3) (:key 1) (:key 2)
                              (:test 2 1) (:key 3) (:test 2 2)
                              (:test 3 3))
                      (reverse calls))
        (setf calls nil)
        (parachute:is = 4 (sl:seq-search #(2 3) '(0 1 2 3 2 3 8)
                                         :from-end t :key #'key
                                         :test #'compare))
        (parachute:is = 9 (count :key calls :key #'first))
        (setf calls nil)
        (parachute:is = 2 (sl:seq-mismatch '(9 1 2 3) #(0 1 7 3)
                                           :start1 1 :start2 1
                                           :key #'key :test #'compare))
        (parachute:is equal '((:key 1) (:key 1) (:test 1 1)
                              (:key 2) (:key 7) (:test 2 7))
                      (reverse calls))
        (setf calls nil)
        (parachute:is = 4 (sl:seq-mismatch '(9 1 2 3) #(0 1 2 7)
                                           :start1 1 :start2 1
                                           :from-end t :key #'key :test #'compare))
        (parachute:is equal '((:key 3) (:key 7) (:test 3 7))
                      (reverse calls))
        (setf calls nil)
        (parachute:is eq nil (sl:seq-mismatch '(1 2) #(1 2)
                                             :key #'key :test #'compare))
        (parachute:is = 4 (count :key calls :key #'first))
        (parachute:is = 1 (sl:seq-mismatch '(1) #(1 2)
                                           :from-end t))))))

(defun eager-traversal-lockstep-corpus ()
  "Fresh multi-source fixtures for both direct and forced-generic traversals."
  (list (cons :empty-first (list nil #(10 20)))
        (cons :empty-last (list #(1 2) nil))
        (cons :two-lists (list '(1 2) '(10 20)))
        (cons :short-first (list '(1) #(10 20)))
        (cons :short-last (list #(1 2) '(10)))
        (cons :short-middle (list '(1 2) #(10) '(100 200)))
        (cons :fill-pointer (list '(1 2 3) (make-array 3 :fill-pointer 2
                                                      :initial-contents '(10 20 30))))
        (cons :string (list "ab" '(1 2 3)))
        (cons :lazy (list '(1 2) (sl:lazy-cons 10 (sl:lazy-cons 20 nil))))
        (cons :extension (list '(1 2) (make-instance 'map03-source
                                                    :items '(10 20))))
        (cons :dotted (list (list* 1 2 :bad) #(10 20 30)))))

(defun eager-traversal-lockstep-observe (sources generic-p operation)
  (let ((sophie-lisp.internal::*force-generic-traversal* generic-p)
        (events nil))
    (let ((result
            (handler-case
                (let ((value (apply operation
                                    (lambda (&rest values)
                                      (push values events)
                                      (apply #'+ values))
                                    sources)))
                  (list :value (sl:seq-into 'list value)))
              (error (condition) (list :error (type-of condition))))))
      (list result (nreverse events)))))

(parachute:define-test eager-traversal.lockstep-corpus-equivalence
  (loop for fast in (eager-traversal-lockstep-corpus)
        for generic in (eager-traversal-lockstep-corpus)
        do (parachute:is eq (car fast) (car generic))
           (parachute:is equalp
                         (eager-traversal-lockstep-observe
                          (cdr generic) t #'sl:seq-map)
                         (eager-traversal-lockstep-observe
                          (cdr fast) nil #'sl:seq-map)))
  (loop for fast in (eager-traversal-lockstep-corpus)
        for generic in (eager-traversal-lockstep-corpus)
        do (let ((fast-value
                  (let ((sophie-lisp.internal::*force-generic-traversal* nil))
                    (handler-case
                        (list :value
                              (sl:seq-into 'list
                                           (apply #'sl:seq-interleave (cdr fast))))
                      (error (condition) (list :error (type-of condition))))))
                 (generic-value
                  (let ((sophie-lisp.internal::*force-generic-traversal* t))
                    (handler-case
                        (list :value
                              (sl:seq-into 'list
                                           (apply #'sl:seq-interleave (cdr generic))))
                      (error (condition) (list :error (type-of condition)))))))
             (parachute:is equalp generic-value fast-value))))

(parachute:define-test eager-traversal.lockstep-order-and-retry
  (dolist (generic-p '(nil t))
    (let* ((sophie-lisp.internal::*force-generic-traversal* generic-p)
           (events nil)
           (first (map03-stream '(1 2) (lambda (index)
                                            (push (list :first index) events))))
           (middle (map03-stream '(10) (lambda (index)
                                            (push (list :middle index) events))))
           (last (map03-stream '(100 200) (lambda (index)
                                             (push (list :last index) events))))
           (result (sl:seq-map (lambda (&rest values)
                                 (push (cons :callback values) events)
                                 (apply #'+ values))
                               first middle last)))
      (parachute:is eq nil events)
      (parachute:is equal '(111) (sl:seq-into 'list result))
      (parachute:is equal '((:first 0) (:middle 0) (:last 0)
                            (:callback 1 10 100) (:first 1) (:middle 1))
                    (nreverse events)))
    (let* ((sophie-lisp.internal::*force-generic-traversal* generic-p)
           (events nil)
           (calls 0)
           (result (sl:seq-map (lambda (x y)
                                 (incf calls)
                                 (push (list :callback x y) events)
                                 (when (= calls 2) (error "retry"))
                                 (+ x y))
                               (map03-stream '(1 2 3)
                                             (lambda (i) (push (list :left i) events)))
                               (map03-stream '(10 20 30)
                                             (lambda (i) (push (list :right i) events))))))
      (parachute:is = 11 (sl:seq-first result))
      (parachute:fail (sl:seq-first (sl:seq-rest result)) simple-error)
      (parachute:is = 22 (sl:seq-first (sl:seq-rest result)))
      (parachute:is = 3 calls)
      (parachute:is equal '((:left 0) (:right 0) (:callback 1 10)
                            (:left 1) (:right 1) (:callback 2 20)
                            (:callback 2 20))
                    (nreverse events)))))

(parachute:define-test eager-traversal.split-family-equivalence
  ;; Rebuild inputs for each route: lazy memoization must never cross runs.
  (dolist (factory (list (lambda () '(1 2 0 3 4 0 5))
                         (lambda () #(1 2 0 3 4 0 5))
                         (lambda () (sl:seq-into 'lazy-seq '(1 2 0 3 4 0 5)))
                         (lambda () (make-array 9 :initial-contents
                                                '(1 2 0 3 4 0 5 99 99)
                                                :fill-pointer 7))))
    (dolist (operation (list (lambda (source callback)
                               (declare (ignore callback))
                               (sl:seq-split-at 3 source))
                             (lambda (source callback)
                               (sl:seq-split-with
                                (lambda (value)
                                  (funcall callback value)
                                  (plusp value)) source))
                             (lambda (source callback)
                               (sl:seq-split source :delimiter '(0 3)
                                             :test (lambda (a b)
                                                     (funcall callback a)
                                                     (= a b))))
                             (lambda (source callback)
                               (sl:seq-split source :predicate
                                             (lambda (value)
                                               (funcall callback value)
                                               (zerop value))))))
      (let ((observations nil))
        (dolist (generic-p '(nil t))
          (let ((sophie-lisp.internal::*force-generic-traversal* generic-p)
                (calls nil))
            (let* ((result (funcall operation (funcall factory)
                                    (lambda (value) (push value calls))))
                   (outer-type (type-of result))
                   (pieces (sl:seq-into 'list result))
                   (piece-types (mapcar #'type-of pieces))
                   (values (mapcar (lambda (piece) (sl:seq-into 'list piece)) pieces)))
              (push (list outer-type piece-types values (nreverse calls))
                    observations))))
        (parachute:is equalp (first observations) (second observations))))))

(parachute:define-test eager-traversal.split-deferred-and-retry
  (dolist (generic-p '(nil t))
    (let ((sophie-lisp.internal::*force-generic-traversal* generic-p)
          (calls 0))
      (let ((pieces (sl:seq-split-with
                     (lambda (value)
                       (incf calls)
                       (when (= calls 2) (error "retry split boundary"))
                       (< value 2))
                     (sl:seq-into 'lazy-seq '(1 2 3)))))
        (parachute:is = 0 calls)
        (let ((prefix (sl:seq-first pieces)))
          (parachute:fail (sl:seq-into 'list prefix) simple-error)
          (parachute:is equal '(1) (sl:seq-into 'list prefix)))
        (parachute:is equal '(2 3)
                      (sl:seq-into 'list (sl:seq-first (sl:seq-rest pieces))))
        (parachute:is = 3 calls)))
    (let ((sophie-lisp.internal::*force-generic-traversal* generic-p)
          (calls 0))
      (let ((pieces (sl:seq-split #(1 0 2) :predicate
                                  (lambda (value)
                                    (incf calls)
                                    (zerop value)))))
        (parachute:is = 0 calls)
        (parachute:is equalp #(1) (sl:seq-first pieces))
        (parachute:is = 2 calls)
        (parachute:is equalp #(2) (sl:seq-first (sl:seq-rest pieces)))))))

(parachute:define-test eager-traversal.partition-family-equivalence
  (dolist (factory (list (lambda () '(1 2 3 4 5 6 7))
                         (lambda () #(1 2 3 4 5 6 7))
                         (lambda () (sl:seq-into 'lazy-seq '(1 2 3 4 5 6 7)))))
    (dolist (operation (list (lambda (source callback)
                               (declare (ignore callback))
                               (sl:seq-partition 3 source :step 2))
                             (lambda (source callback)
                               (declare (ignore callback))
                               (sl:seq-partition 2 source :step 4))
                             (lambda (source callback)
                               (declare (ignore callback))
                               (sl:seq-partition 3 source :step 2 :pad '(8 9)))
                             (lambda (source callback)
                               (sl:seq-partition-by
                                (lambda (value)
                                  (funcall callback value)
                                  (floor value 3)) source))))
      (let ((observations nil))
        (dolist (generic-p '(nil t))
          (let ((sophie-lisp.internal::*force-generic-traversal* generic-p)
                (calls nil))
            (let* ((result (funcall operation (funcall factory)
                                    (lambda (value) (push value calls))))
                   (before (copy-list calls))
                   (first (sl:seq-first result))
                   (partial (sl:seq-into 'list first))
                   (pieces (sl:seq-into 'list result)))
              (push (list (type-of result) before partial
                          (mapcar #'type-of pieces)
                          (mapcar (lambda (piece) (sl:seq-into 'list piece)) pieces)
                          (nreverse calls)) observations))))
        (parachute:is equalp (first observations) (second observations))))))

(parachute:define-test eager-traversal.partition-padding-and-retry
  (dolist (generic-p '(nil t))
    (let ((sophie-lisp.internal::*force-generic-traversal* generic-p)
          (reads 0))
      (let ((result (sl:seq-partition 4 #(1 2 3 4 5) :step 4
                                      :pad (sl:seq-map
                                            (lambda (value)
                                              (incf reads)
                                              (when (= reads 2) (error "retry padding"))
                                              value)
                                            (sl:seq-into 'lazy-seq '(8 9 10))))))
        (parachute:is = 0 reads)
        (parachute:is equalp #(1 2 3 4) (sl:seq-first result))
        (parachute:fail (sl:seq-first (sl:seq-rest result)) simple-error)
        (parachute:is equalp #(5 8 9 10)
                      (sl:seq-first (sl:seq-rest result)))
        (parachute:is = 4 reads)))
    (let ((sophie-lisp.internal::*force-generic-traversal* generic-p)
          (keys 0))
      (let ((result (sl:seq-partition-by
                     (lambda (value)
                       (incf keys)
                       (when (= keys 2) (error "retry key"))
                       value)
                     #(1 1 2))))
        (parachute:is = 0 keys)
        (parachute:fail (sl:seq-first result) simple-error)
        (parachute:is equalp #(1 1) (sl:seq-first result))
        (parachute:is equalp #(2) (sl:seq-first (sl:seq-rest result)))
        (parachute:is = 4 keys)))))

(defvar *eager-seqable-openings* nil)

(parachute:define-test eager-traversal.concrete-opening-dispatch
  (s-collect-with-methods
      '((defmethod sl:seqablep :around ((source t))
          (push source *eager-seqable-openings*)
          (call-next-method)))
    (dolist (factory (list (lambda () (list 1 2 3 4))
                           (lambda () (vector 1 2 3 4))))
      (loop for operation in
               (list (lambda (source) (sl:seq-member 2 source))
                     (lambda (source) (sl:seq-search (subseq source 1 3) source))
                     (lambda (source) (sl:seq-mismatch source source))
                     (lambda (source) (sl:seq-map #'+ source source))
                     (lambda (source) (sl:seq-interleave source source))
                     (lambda (source) (sl:seq-split source :predicate #'evenp))
                     (lambda (source) (sl:seq-split-at 2 source))
                     (lambda (source) (sl:seq-split-with #'oddp source))
                     (lambda (source) (sl:seq-partition 2 source))
                     (lambda (source) (sl:seq-partition-by #'oddp source))
                     (lambda (source) (sl:seq-find 2 source))
                     (lambda (source) (sl:seq-last source))
                     (lambda (source) (sl:seq-map-indexed
                                       (lambda (index element)
                                         (+ index element)) source))
                     (lambda (source) (sl:seq-keep #'identity source))
                     (lambda (source) (sl:seq-filter #'oddp source))
                     (lambda (source) (sl:seq-remove 2 source))
                     (lambda (source) (sl:seq-remove-if #'oddp source))
                     (lambda (source) (sl:seq-mapcat #'list source)))
            for openings in '(1 1 2 2 2 1 1 1 1 1 1 1 1 1 1 1 1 1)
            do (let ((source (funcall factory))
                     (*eager-seqable-openings* nil))
                 (funcall operation source)
                 (parachute:is = openings
                               (count source *eager-seqable-openings* :test #'eq))))
    (dolist (generic-p '(nil t))
      (let ((sophie-lisp.internal::*force-generic-traversal* generic-p))
        (parachute:fail (sl:seq-member 2 42) type-error)
        (parachute:fail (sl:seq-split-at 2 42) type-error))))))
