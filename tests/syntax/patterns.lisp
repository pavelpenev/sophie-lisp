;;;; Public-pattern acceptance. Pattern compiler internals are deliberately not
;;;; exercised here; public behavior is covered through SL:BIND and SL:FN.
(in-package #:sophie-lisp.tests)

(defvar *xpat-events* nil)

;; A keyed object with only a direct REF method: no incomplete seq/dict protocol.
(defclass xpat-access ()
  ((name :initarg :name :reader xpat-name)
   (items :initarg :items :reader xpat-items)))

(defmethod sl:ref ((object xpat-access) key &optional (default nil supplied-p))
  (push (list (xpat-name object) key supplied-p) *xpat-events*)
  (let ((pair (assoc key (xpat-items object))))
    (if pair (values (cdr pair) t) (values default nil))))

(parachute:define-test patterns.public-pattern-semantics
  ;; A nested vector is data. A list inside it is a pattern, not a call.
  (parachute:is equal '(1 2 3)
                (multiple-value-list
                 (sl:bind ((#((a b) c) (vector '(1 2) 3)))
                   (values a b c))))
  ;; Entry fields are processed left-to-right through the public binding macro.
  (let ((*xpat-events* nil))
    (parachute:is equal '((:key :value) ((:key 0 nil) (:value 0 nil)))
                  (multiple-value-list
                   (sl:bind (((:entry #(key) #(value))
                              (sl:map-entry
                               (make-instance 'xpat-access :name :key
                                :items '((0 . :key)))
                               (make-instance 'xpat-access :name :value
                                :items '((0 . :value))))))
                     (values (list key value) (reverse *xpat-events*))))))
  ;; Vector projections are processed left-to-right through the public FN macro.
  (let ((*xpat-events* nil))
    (parachute:is equal '((:zero :one) ((:direct 0 nil) (:direct 1 nil)))
                  (multiple-value-list
                   (funcall
                    (sl:fn (#(a b))
                      (values (list a b) (reverse *xpat-events*)))
                    (make-instance 'xpat-access :name :direct
                     :items '((0 . :zero) (1 . :one) (2 . :extra))))))))
