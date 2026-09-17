;;;; upc-logger.asd -- the scan log, independent of any phone.
;;;;
;;;; The iOS application is upc-logger-app.asd, a separate file on purpose:
;;;; :DEFSYSTEM-DEPENDS-ON is resolved when an .asd is READ, so keeping the
;;;; bundle out of this file lets the core and its tests load on a Mac with
;;;; nothing but a Lisp and FiveAM.

(asdf:defsystem #:upc-logger
  :description "UPC codes, scan counts and timestamps: the model behind UPC Logger."
  :author "Matthew Kennedy <burnsidemk@gmail.com>"
  :license "MIT"
  :version "0.1.0"
  :serial t
  :components ((:module "core"
                :pathname "src/core"
                :serial t
                :components ((:file "package")
                             (:file "upc")
                             (:file "log")
                             (:file "aggregate")
                             (:file "window")
                             (:file "search")
                             (:file "export")
                             (:file "gate")))))

(asdf:defsystem #:upc-logger/tests
  :description "FiveAM tests for the upc-logger core."
  :depends-on (#:upc-logger #:fiveam)
  :serial t
  :components ((:module "tests"
                :serial t
                :components ((:file "package")
                             (:file "upc-tests")
                             (:file "log-tests")
                             (:file "aggregate-tests")
                             (:file "window-tests")
                             (:file "search-tests")
                             (:file "export-tests")
                             (:file "gate-tests"))))
  ;; FIVEAM:RUN! prints failures but returns NIL, and ASDF discards what a
  ;; TEST-OP returns -- which is how a suite goes green with failing tests.
  :perform (asdf:test-op (o c)
             (unless (uiop:symbol-call :upc-logger/tests :run-tests)
               (error "The test suite failed."))))
