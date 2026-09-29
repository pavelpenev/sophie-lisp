;;;; Package definitions for the Sophie Lisp public API.
;;;;
;;;; Sophie names live in SOPHIE-LISP-EXTENSIONS.  SOPHIE-LISP explicitly
;;;; re-exports COMMON-LISP below because inherited symbols are not external
;;;; symbols of a package on all conforming implementations.

;;;; Within SOPHIE-LISP's DEFPACKAGE, :USE must precede :EXPORT so its
;;;; uninterned designators resolve to inherited SL-EXT symbols.

(defpackage #:sophie-lisp-extensions
  (:documentation
   "Extension symbols for Sophie Lisp — the namespace that defines all
   supplementary operations.")
  (:nicknames #:sl-ext)
  (:use)
  (:export
   #:*list-delimiter*
   #:->
   #:->>
   #:alist-dict
   #:as->
   #:bind
   #:collector-accumulate
   #:collector-result
   #:compare
   #:compose
   #:cycle
   #:dict
   #:dict-alist
   #:dict-collect
   #:dict-frequencies
   #:dict-group-by
   #:dict-count-by
   #:dict-reduce-kv
   #:dict-remove-keys
   #:dict-select-keys
   #:dict-keys
   #:dict-keys-map
   #:dict-member
   #:dict-merge
   #:dict-merge*
   #:dict-merge-with
   #:dict-plist
   #:dict-ref
   #:dict-ref-in
   #:dict-set
   #:dict-set-in
   #:dict-size
   #:dict-test
   #:dict-transform
   #:dict-update
   #:dict-update-in
   #:dict-vals
   #:dict-values-map
   #:dict-without
   #:dict-zipmap
   #:dictp
   #:doseq
   #:entry-key
   #:entry-value
   #:equals
   #:fbind
   #:fn
   #:gt
   #:gte
   #:hash-code
   #:hash-set
   #:hash-set-p
   #:if-bind
   #:iterate
   #:juxt
   #:lazy-cons
   #:lazy-seq
   #:lazy-seq-p
   #:lt
   #:lte
   #:make-collector-for
   #:make-lazy-seq
   #:map-entry
   #:op
   #:ordered-dict
   #:ordered-dict-p
   #:plist-dict
   #:plist-dict-view
   #:range
   #:ref
   #:repeatedly
   #:seq-concatenate
   #:seq-count
   #:seq-count-if
   #:seq-dedupe
   #:seq-drop
   #:seq-drop-last
   #:seq-drop-while
   #:seq-emptyp
   #:seq-every
   #:seq-filter
   #:seq-find
   #:seq-find-if
   #:seq-first
   #:seq-interleave
   #:seq-into
   #:seq-join
   #:seq-keep
   #:seq-last
   #:seq-length
   #:seq-map
   #:seq-map-indexed
   #:seq-mapcat
   #:seq-max
   #:seq-member
   #:seq-min
   #:seq-mismatch
   #:seq-notany
   #:seq-notevery
   #:seq-partition
   #:seq-partition-by
   #:seq-position
   #:seq-position-if
   #:seq-reduce
   #:seq-reductions
   #:seq-ref
   #:seq-remove
   #:seq-remove-duplicates
   #:seq-remove-if
   #:seq-rest
   #:seq-reverse
   #:seq-search
   #:seq-some
   #:seq-sort
   #:seq-split
   #:seq-split-at
   #:seq-split-with
   #:seq-stable-sort
   #:seq-subseq
   #:seq-substitute
   #:seq-substitute-if
   #:seq-take
   #:seq-take-last
   #:seq-take-nth
   #:seq-take-while
   #:seq-tree-seq
   #:seq-trim
   #:seq-trim-left
   #:seq-trim-right
   #:seqablep
   #:sl-core-syntax
   #:set-add
   #:set-intersection
   #:set-member
   #:set-minus
   #:set-remove
   #:set-size
   #:set-subset-p
   #:set-union
   "?"
   "@"
   "<>"
   #:when-bind
   #:~>))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (macrolet ((defpackage-with-common-lisp-exports (definition)
               (let* ((package (second definition))
                      (options (cddr definition))
                      (export-option (assoc :export options))
                      (common-lisp-export-names
                        (let ((names nil))
                          (do-external-symbols
                              (symbol (find-package :common-lisp))
                            (push (symbol-name symbol) names))
                          names)))
                 `(cl:defpackage ,package
                    ,@(remove export-option options :test #'eq)
                    (:export ,@(cdr export-option)
                             ,@common-lisp-export-names)))))
    ;; Declare CL exports in DEFPACKAGE so reloads do not create package variance.
    (defpackage-with-common-lisp-exports
      (defpackage #:sophie-lisp
        (:documentation
         "The combined Sophie Lisp facade, re-exporting Common Lisp and all
         extension symbols.")
        (:nicknames #:sl)
        (:use #:cl #:sl-ext)
        (:export
         #:*list-delimiter*
         #:->
         #:->>
         #:alist-dict
         #:as->
         #:bind
         #:collector-accumulate
         #:collector-result
         #:compare
         #:compose
         #:cycle
         #:dict
         #:dict-alist
         #:dict-collect
         #:dict-frequencies
         #:dict-group-by
         #:dict-count-by
         #:dict-reduce-kv
         #:dict-remove-keys
         #:dict-select-keys
         #:dict-keys
         #:dict-keys-map
         #:dict-member
         #:dict-merge
         #:dict-merge*
         #:dict-merge-with
         #:dict-plist
         #:dict-ref
         #:dict-ref-in
         #:dict-set
         #:dict-set-in
         #:dict-size
         #:dict-test
         #:dict-transform
         #:dict-update
         #:dict-update-in
         #:dict-vals
         #:dict-values-map
         #:dict-without
         #:dict-zipmap
         #:dictp
         #:doseq
         #:entry-key
         #:entry-value
         #:equals
         #:fbind
         #:fn
         #:gt
         #:gte
         #:hash-code
         #:hash-set
         #:hash-set-p
         #:if-bind
         #:iterate
         #:juxt
         #:lazy-cons
         #:lazy-seq
         #:lazy-seq-p
         #:lt
         #:lte
         #:make-collector-for
         #:make-lazy-seq
         #:map-entry
         #:op
         #:ordered-dict
         #:ordered-dict-p
         #:plist-dict
         #:plist-dict-view
         #:range
         #:ref
         #:repeatedly
         #:seq-concatenate
         #:seq-count
         #:seq-count-if
         #:seq-dedupe
         #:seq-drop
         #:seq-drop-last
         #:seq-drop-while
         #:seq-emptyp
         #:seq-every
         #:seq-filter
         #:seq-find
         #:seq-find-if
         #:seq-first
         #:seq-interleave
         #:seq-into
         #:seq-join
         #:seq-keep
         #:seq-last
         #:seq-length
         #:seq-map
         #:seq-map-indexed
         #:seq-mapcat
         #:seq-max
         #:seq-member
         #:seq-min
         #:seq-mismatch
         #:seq-notany
         #:seq-notevery
         #:seq-partition
         #:seq-partition-by
         #:seq-position
         #:seq-position-if
         #:seq-reduce
         #:seq-reductions
         #:seq-ref
         #:seq-remove
         #:seq-remove-duplicates
         #:seq-remove-if
         #:seq-rest
         #:seq-reverse
         #:seq-search
         #:seq-some
         #:seq-sort
         #:seq-split
         #:seq-split-at
         #:seq-split-with
         #:seq-stable-sort
         #:seq-subseq
         #:seq-substitute
         #:seq-substitute-if
         #:seq-take
         #:seq-take-last
         #:seq-take-nth
         #:seq-take-while
         #:seq-tree-seq
         #:seq-trim
         #:seq-trim-left
         #:seq-trim-right
         #:seqablep
         #:sl-core-syntax
         #:set-add
         #:set-intersection
         #:set-member
         #:set-minus
         #:set-remove
         #:set-size
         #:set-subset-p
         #:set-union
         "?"
         "@"
         "<>"
         #:when-bind
         #:~>)))))

(defpackage #:sl-user
  (:documentation "User package providing the full Sophie Lisp environment.")
  (:use #:sl))

(defpackage #:sophie-lisp.internal
  (:use #:cl #:sl-ext))
