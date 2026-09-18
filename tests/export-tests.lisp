;;;; tests/export-tests.lisp

(in-package #:upc-logger/tests)

(def-suite export :in all-tests :description "What the share button sends.")
(in-suite export)

(defun one-group (&rest arguments)
  (first (group-entries (list (apply #'event arguments)) t)))

(test fields-are-quoted-only-when-they-have-to-be
  (is (string= "036000291452" (csv-field "036000291452")))
  (is (string= "\"a,b\"" (csv-field "a,b")))
  (is (string= "\"say \"\"hi\"\"\"" (csv-field "say \"hi\"")))
  (is (string= "\"two
lines\"" (csv-field (format nil "two~%lines"))))
  (is (string= "8" (csv-field 8))))

(test a-csv-line-joins-fields-with-commas
  (is (string= "a,b,c" (csv-line '("a" "b" "c"))))
  (is (string= "\"a,1\",b" (csv-line '("a,1" "b")))))

(test the-csv-has-a-header-and-a-row-for-each-group
  (let* ((at (encode-universal-time 22 3 14 16 9 2026 0))
         (groups (list (one-group "036000291452" at :count 8)))
         (csv (log-csv groups 0))
         (lines (remove "" (uiop:split-string csv :separator '(#\Newline))
                        :test #'string= :key (lambda (line) (string-trim '(#\Return) line)))))
    (is (= 2 (length lines)))
    (is (string= "Code,Name,Count,Scans,First scanned,Last scanned,Note,Photo,Set photo,Universal time"
                 (string-trim '(#\Return) (first lines))))
    ;; CRLF, as RFC 4180 says.
    (is-true (every (lambda (line) (eql #\Return (char line (1- (length line))))) lines))
    ;; The universal time is computed, not copied in: a literal would only
    ;; test that two numbers were typed alike.
    (is (string= (format nil "036000291452,,8,1,2026-09-16 14:03:22,,,,,~d" at)
                 (string-trim '(#\Return) (second lines))))))

(test the-set-photo-has-its-own-column
  (let* ((at (encode-universal-time 0 0 14 16 9 2026 0))
         (row (export-row (one-group "036000291452" at
                                     :photo "mine.jpg" :shared-photo "set.jpg")
                          0)))
    (is (string= "mine.jpg" (eighth row)))
    (is (string= "set.jpg" (ninth row)))))

(test a-merged-row-reports-its-scans-and-both-times
  (let* ((first-at (encode-universal-time 0 0 14 16 9 2026 0))
         (last-at (encode-universal-time 30 5 14 16 9 2026 0))
         (group (first (group-entries (list (event "036000291452" last-at)
                                            (event "036000291452" first-at :count 2))
                                      t)))
         (row (export-row group 0)))
    (is (string= "3" (third row)))                       ; items
    (is (string= "2" (fourth row)))                      ; scans
    (is (string= "2026-09-16 14:00:00" (fifth row)))
    (is (string= "2026-09-16 14:05:30" (sixth row)))))

(test a-single-scan-does-not-print-its-time-twice
  (let ((row (export-row (one-group "036000291452"
                                    (encode-universal-time 0 0 14 16 9 2026 0))
                         0)))
    (is (string= "2026-09-16 14:00:00" (fifth row)))
    (is (string= "" (sixth row)))))

(test a-name-a-note-and-a-photo-reach-the-csv
  (let* ((at (encode-universal-time 0 0 14 16 9 2026 0))
         (group (one-group "036000291452" at :count 2
                           :name "Blue paint, 1L"        ; a comma, so it is quoted
                           :note "damaged box"
                           :photo "20260917-140322.jpg"))
         (row (export-row group 0)))
    (is (string= "Blue paint, 1L" (second row)))
    (is (string= "damaged box" (seventh row)))
    (is (string= "20260917-140322.jpg" (eighth row)))
    (is (string= (format nil "036000291452,\"Blue paint, 1L\",2,1,2026-09-16 14:00:00,,damaged box,20260917-140322.jpg,,~d" at)
                 (csv-line row)))))

(test the-summary-counts-scans-and-items
  (let ((groups (group-entries (list (event "a" 300 :count 8)
                                     (event "a" 200)
                                     (event "b" 100))
                               t)))
    (is (string= "3 scans, 10 items" (export-summary groups)))
    (is (string= "0 scans, 0 items" (export-summary '())))
    (is (string= "1 scan, 1 item"
                 (export-summary (group-entries (list (event "a" 100)) t))))))

(test the-file-is-named-after-the-window
  (is (string= "upc-scans-20260916-1403"
               (export-basename (make-time-window (encode-universal-time 0 3 14 16 9 2026 0)
                                                  (encode-universal-time 0 3 15 16 9 2026 0))
                                0))))
