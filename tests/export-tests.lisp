;;;; tests/export-tests.lisp

(in-package #:upc-logger/tests)

(def-suite export :in all-tests :description "What the share button sends.")
(in-suite export)

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

(test the-csv-has-a-header-and-a-row-for-each-scan
  (let* ((scanned-at (encode-universal-time 22 3 14 16 9 2026 0))
         (entry (make-entry :code "036000291452" :count 8 :scanned-at scanned-at))
         (csv (log-csv (list entry) 0))
         (lines (remove "" (uiop:split-string csv :separator '(#\Newline))
                        :test #'string= :key (lambda (line) (string-trim '(#\Return) line)))))
    (is (= 2 (length lines)))
    (is (string= "Code,Count,Scanned,Last scanned,Universal time"
                 (string-trim '(#\Return) (first lines))))
    ;; CRLF, as RFC 4180 says.
    (is-true (every (lambda (line) (eql #\Return (char line (1- (length line))))) lines))
    ;; The last column is the universal time itself, computed rather than
    ;; copied in: a literal here only tests that two numbers were typed alike.
    (is (string= (format nil "036000291452,8,2026-09-16 14:03:22,,~d" scanned-at)
                 (string-trim '(#\Return) (second lines))))))

(test a-bumped-row-carries-the-time-it-was-last-scanned
  (let ((entry (make-entry :code "036000291452" :count 2
                           :scanned-at (encode-universal-time 0 0 14 16 9 2026 0)
                           :updated-at (encode-universal-time 30 5 14 16 9 2026 0))))
    (is (string= "2026-09-16 14:05:30" (fourth (export-row entry 0))))
    (is (string= "" (fourth (export-row (make-entry :code "x" :scanned-at 1) 0))))))

(test the-summary-counts-rows-and-items
  (let ((entries (list (make-entry :code "a" :count 8 :scanned-at 1)
                       (make-entry :code "b" :count 1 :scanned-at 2))))
    (is (string= "2 scans, 9 items" (export-summary entries)))
    (is (string= "0 scans, 0 items" (export-summary '())))
    (is (string= "1 scan, 1 item" (export-summary (list (make-entry :code "a" :scanned-at 1)))))))

(test the-file-is-named-after-the-window
  (is (string= "upc-scans-20260916-1403"
               (export-basename (make-time-window (encode-universal-time 0 3 14 16 9 2026 0)
                                                  (encode-universal-time 0 3 15 16 9 2026 0))
                                0))))
