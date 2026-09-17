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
   #:entry-name #:entry-note #:entry-photo
   #:scan-log #:make-scan-log #:scan-log-entries
   #:log-length #:log-entry #:total-items #:code-name
   #:record-scan #:set-count #:delete-entry
   #:set-name #:set-note #:set-photo #:blank-to-nil
   #:save-log #:load-log #:+log-format-version+
   ;; debouncing the camera
   #:scan-gate #:make-scan-gate #:admit-scan
   ;; the window the chart shows
   #:time-window #:make-time-window #:time-window-start #:time-window-end
   #:window-span #:default-window #:zoom-window #:pan-window #:window-following-p
   #:clamp-span #:+day+ #:+minimum-span+ #:+maximum-span+
   #:choose-bin-seconds #:bin-start #:histogram #:tick-interval #:axis-ticks
   #:format-window #:format-clock #:format-day #:entries-in-window
   ;; searching
   #:contains-p #:entry-matches-p #:search-entries
   #:entries-time-span #:window-for-entries
   ;; exports
   #:+export-columns+ #:export-row #:export-rows #:export-summary #:export-basename
   #:csv-field #:csv-line #:log-csv #:timestamp-for-export))
