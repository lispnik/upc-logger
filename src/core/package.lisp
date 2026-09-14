;;;; src/core/package.lisp

(defpackage #:upc-logger
  (:use #:common-lisp)
  (:export
   ;; codes
   #:metadata-type #:digits-p #:check-digit-valid-p #:add-check-digit #:expand-upc-e
   #:normalize-code #:scanned-code
   ;; presentation
   #:format-entry-title #:format-timestamp
   ;; entries and the log
   #:entry #:make-entry #:entry-p #:entry-code #:entry-count
   #:entry-scanned-at #:entry-updated-at #:entry-bumped-p
   #:scan-log #:make-scan-log #:scan-log-entries
   #:log-length #:log-entry #:total-items
   #:record-scan #:set-count #:delete-entry
   #:save-log #:load-log #:+log-format-version+
   ;; debouncing the camera
   #:scan-gate #:make-scan-gate #:admit-scan))
