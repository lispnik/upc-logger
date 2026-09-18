;;;; src/core/export.lisp -- the rows in the view, as a file to send on.
;;;;
;;;; A row is a GROUP, so an export says what the table says: grouped while the
;;;; table is grouped, a line per scan while it is not.  The Scans column is
;;;; what tells the two apart -- a merged row reports how many scans are behind
;;;; it, and its first and last times.
;;;;
;;;; CSV is written here in full.  A PDF cannot be, since drawing it is UIKit's
;;;; job, but its rows come from the same function, so the two exports can
;;;; never disagree.
;;;;
;;;; The photo travels as its file name rather than its bytes: a spreadsheet
;;;; cell full of base64 is no use, and the name finds the file beside the log.

(in-package #:upc-logger)

(defparameter +export-columns+
  '("Code" "Name" "Count" "Scans" "First scanned" "Last scanned"
    "Note" "Photo" "Set photo" "Universal time"))

(defun timestamp-for-export (universal-time &optional time-zone)
  "\"2026-09-16 14:03:22\": ISO order, a space instead of the T, and local
time, which is what a spreadsheet parses as a date without being asked."
  (format-timestamp universal-time time-zone))

(defun export-row (group &optional time-zone)
  "GROUP as the strings both exports print."
  (let ((earliest (group-earliest group))
        (latest (group-latest group)))
    (list (group-code group)
          (or (group-name group) "")
          (princ-to-string (group-count group))
          (princ-to-string (group-scans group))
          (timestamp-for-export earliest time-zone)
          ;; Only when it differs: a row of one scan has one time, and
          ;; printing it twice reads as though something happened twice.
          (if (= earliest latest) "" (timestamp-for-export latest time-zone))
          (or (group-note group) "")
          (or (group-photo group) "")
          (or (group-shared-photo group) "")
          (princ-to-string earliest))))

(defun export-rows (groups &optional time-zone)
  (mapcar (lambda (group) (export-row group time-zone)) groups))

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

(defun log-csv (groups &optional time-zone)
  "GROUPS as a CSV document, header first.  Lines end CRLF, as the format says."
  (with-output-to-string (out)
    (format out "~a~c~c" (csv-line +export-columns+) #\Return #\Newline)
    (dolist (row (export-rows groups time-zone))
      (format out "~a~c~c" (csv-line row) #\Return #\Newline))))

(defun export-summary (groups)
  "The line both exports put under the title, and the table puts above itself.

Scans as well as items when they differ: eleven items over three scans is a
different fact from eleven scans, and the merged view hides which."
  (let ((items (groups-total-items groups))
        (scans (groups-total-scans groups)))
    (if (= items scans)
        (format nil "~d scan~:p, ~d item~:p" scans items)
        (format nil "~d scan~:p, ~d item~:p" scans items))))

(defun export-basename (window &optional time-zone)
  "A file name that says what is in it: upc-scans-20260916-1403."
  (multiple-value-bind (second minute hour day month year)
      (if time-zone
          (decode-universal-time (time-window-start window) time-zone)
          (decode-universal-time (time-window-start window)))
    (declare (ignore second))
    (format nil "upc-scans-~4,'0d~2,'0d~2,'0d-~2,'0d~2,'0d" year month day hour minute)))
