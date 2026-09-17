;;;; src/core/export.lisp -- the scans in the view, as a file to send on.
;;;;
;;;; CSV is written here in full.  A PDF cannot be, since drawing it is UIKit's
;;;; job, but the rows it prints come from the same function, so the two
;;;; exports can never disagree about what was in the view.
;;;;
;;;; The photo travels as its file name rather than its bytes: a CSV cell full
;;;; of base64 is no use to a spreadsheet, and the name is enough to find the
;;;; file beside the log.

(in-package #:upc-logger)

(defparameter +export-columns+
  '("Code" "Name" "Count" "Scanned" "Last scanned" "Note" "Photo" "Universal time"))

(defun timestamp-for-export (universal-time &optional time-zone)
  "\"2026-09-16 14:03:22\": ISO order, a space instead of the T, and local
time, which is what a spreadsheet parses as a date without being asked."
  (format-timestamp universal-time time-zone))

(defun export-row (entry &optional time-zone)
  "ENTRY as the strings both exports print."
  (list (entry-code entry)
        (or (entry-name entry) "")
        (princ-to-string (entry-count entry))
        (timestamp-for-export (entry-scanned-at entry) time-zone)
        (if (entry-bumped-p entry)
            (timestamp-for-export (entry-updated-at entry) time-zone)
            "")
        (or (entry-note entry) "")
        (or (entry-photo entry) "")
        (princ-to-string (entry-scanned-at entry))))

(defun export-rows (entries &optional time-zone)
  (mapcar (lambda (entry) (export-row entry time-zone)) entries))

(defun csv-field (value)
  "VALUE quoted if it has to be: RFC 4180, where a quote is doubled."
  (let ((string (princ-to-string value)))
    (if (find-if (lambda (char) (member char '(#\, #\" #\Newline #\Return))) string)
        (with-output-to-string (out)
          (write-char #\" out)
          (loop for char across string
                do (when (char= char #\") (write-char #\" out))
                   (write-char char out))
          (write-char #\" out))
        string)))

(defun csv-line (fields)
  (format nil "~{~a~^,~}" (mapcar #'csv-field fields)))

(defun log-csv (entries &optional time-zone)
  "ENTRIES as a CSV document, header first.  Lines end CRLF, as the format says."
  (with-output-to-string (out)
    (format out "~a~c~c" (csv-line +export-columns+) #\Return #\Newline)
    (dolist (row (export-rows entries time-zone))
      (format out "~a~c~c" (csv-line row) #\Return #\Newline))))

(defun export-summary (entries)
  "The line both exports put under the title."
  (format nil "~d scan~:p, ~d item~:p"
          (length entries)
          (reduce #'+ entries :key #'entry-count :initial-value 0)))

(defun export-basename (window &optional time-zone)
  "A file name that says what is in it: upc-scans-20260916-1403."
  (multiple-value-bind (second minute hour day month year)
      (if time-zone
          (decode-universal-time (time-window-start window) time-zone)
          (decode-universal-time (time-window-start window)))
    (declare (ignore second))
    (format nil "upc-scans-~4,'0d~2,'0d~2,'0d-~2,'0d~2,'0d" year month day hour minute)))
