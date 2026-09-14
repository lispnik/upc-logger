;;;; tests/package.lisp

(defpackage #:upc-logger/tests
  (:use #:common-lisp #:fiveam #:upc-logger)
  (:export #:all-tests #:run-tests))

(in-package #:upc-logger/tests)

(def-suite all-tests :description "Everything.")

(defun run-tests ()
  "Run the suite and return true only if it passed.  Not RUN!, whose NIL on
failure is indistinguishable from its NIL on success."
  (let ((results (run 'all-tests)))
    (explain! results)
    (results-status results)))
