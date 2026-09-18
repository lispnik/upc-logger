;;;; tests/log-tests.lisp

(in-package #:upc-logger/tests)

(def-suite scan-log :in all-tests :description "The log: events, counts, saving.")
(in-suite scan-log)

(defun codes (log)
  (mapcar #'entry-code (scan-log-entries log)))

(test new-scans-go-on-top
  (let ((log (make-scan-log)))
    (record-scan log "111111111117" 100)
    (record-scan log "222222222224" 200)
    (is (equal '("222222222224" "111111111117") (codes log)))))

(test every-scan-is-its-own-event
  ;; The whole point of the format: two scans of the same thing are two
  ;; events, each with its own time. Merging is a way of looking at them.
  (let ((log (make-scan-log)))
    (record-scan log "111111111117" 100)
    (record-scan log "111111111117" 160)
    (is (= 2 (log-length log)))
    (is (= 160 (entry-at (log-entry log 0))))
    (is (= 100 (entry-at (log-entry log 1))))
    (is (= 2 (total-items log)))))

(test a-count-reports-items-not-scans
  ;; One scan of a case of eight is one scan reporting eight items; recording
  ;; eight events would invent seven times that never happened.
  (let ((log (make-scan-log)))
    (record-scan log "111111111117" 100)
    (set-count log 0 8)
    (is (= 1 (log-length log)))
    (is (= 8 (total-items log)))))

(test setting-a-count
  (let ((log (make-scan-log)))
    (record-scan log "111111111117" 100)
    (multiple-value-bind (entry how) (set-count log 0 8)
      (is (eq :updated how))
      (is (= 8 (entry-count entry))))))

(test a-count-of-zero-deletes
  (let ((log (make-scan-log)))
    (record-scan log "111111111117" 100)
    (record-scan log "222222222224" 200)
    (is (eq :deleted (nth-value 1 (set-count log 0 0))))
    (is (equal '("111111111117") (codes log)))))

(test nonsense-counts-change-nothing
  (let ((log (make-scan-log)))
    (record-scan log "111111111117" 100)
    (is (null (nth-value 1 (set-count log 0 -3))))
    (is (null (nth-value 1 (set-count log 5 2))))
    (is (null (nth-value 1 (set-count log 0 "7"))))
    (is (= 1 (entry-count (log-entry log 0))))))

(test deleting-from-the-middle
  (let ((log (make-scan-log)))
    (dolist (code '("111111111117" "222222222224" "333333333331"))
      (record-scan log code 1))
    (is (string= "222222222224" (entry-code (delete-entry log 1))))
    (is (equal '("333333333331" "111111111117") (codes log)))
    (is (null (delete-entry log 7)))))

(test naming-a-row-names-the-code-everywhere
  (let ((log (make-scan-log)))
    (record-scan log "111111111117" 100)
    (record-scan log "222222222224" 200)
    (record-scan log "111111111117" 300)
    (is (eq :updated (nth-value 1 (set-name log 0 "Blue paint 1L"))))
    (is (string= "Blue paint 1L" (entry-name (log-entry log 0))))
    (is (string= "Blue paint 1L" (entry-name (log-entry log 2))))
    (is (null (entry-name (log-entry log 1))))
    (is (string= "Blue paint 1L" (code-name log "111111111117")))))

(test a-later-scan-inherits-the-name
  (let ((log (make-scan-log)))
    (record-scan log "111111111117" 100)
    (set-name log 0 "Blue paint 1L")
    (record-scan log "111111111117" 300)
    (is (string= "Blue paint 1L" (entry-name (log-entry log 0))))))

(test a-blank-name-clears-it
  (let ((log (make-scan-log)))
    (record-scan log "111111111117" 100)
    (set-name log 0 "Blue paint")
    (set-name log 0 "   ")
    (is (null (entry-name (log-entry log 0))))
    (is (null (code-name log "111111111117")))))

(test notes-and-photos-stay-on-their-own-event
  (let ((log (make-scan-log)))
    (record-scan log "111111111117" 100)
    (record-scan log "111111111117" 200)
    (set-note log 0 "damaged box")
    (set-photo log 0 "20260917-140322.jpg")
    (is (string= "damaged box" (entry-note (log-entry log 0))))
    (is (null (entry-note (log-entry log 1))))
    (is-true (annotated-p (log-entry log 0)))
    (is-false (annotated-p (log-entry log 1)))
    (set-note log 0 "")
    (set-photo log 0 nil)
    (is-false (annotated-p (log-entry log 0)))))

(test setting-anything-on-an-event-that-is-not-there
  (let ((log (make-scan-log)))
    (is (null (nth-value 1 (set-name log 3 "x"))))
    (is (null (nth-value 1 (set-note log 3 "x"))))
    (is (null (nth-value 1 (set-photo log 3 "x.jpg"))))))

(defun scratch-file (name)
  (merge-pathnames (format nil "upc-logger-test-~a-~d.sexp" name (random 1000000))
                   (uiop:temporary-directory)))

(test saving-and-loading-round-trips
  (let ((log (make-scan-log))
        (path (scratch-file "round-trip")))
    (unwind-protect
         (progn
           (record-scan log "111111111117" 3966000000)
           (record-scan log "222222222224" 3966000100)
           (record-scan log "222222222224" 3966000200)
           (set-count log 1 5)
           (set-note log 0 "damaged box")
           (set-photo log 0 "20260917-140322.jpg")
           (set-name log 2 "Blue paint 1L")
           (save-log log path)
           (save-log log path)                       ; over an existing file
           (multiple-value-bind (loaded status) (load-log path)
             (is (eq :loaded status))
             (is (equalp (scan-log-entries log) (scan-log-entries loaded)))))
      (ignore-errors (delete-file path)))))

(test a-version-1-log-still-reads
  ;; Version 1 merged as it wrote: a row with a count and two timestamps. Its
  ;; count survives as one event reporting that many items, because the scans
  ;; between those two times were never written down.
  (let ((path (scratch-file "v1")))
    (unwind-protect
         (progn
           (with-open-file (out path :direction :output :if-exists :supersede)
             (write-string "(:upc-logger 1 :entries ((:code \"036000291452\" :count 8 :scanned-at 3966000000 :updated-at 3966000900 :name \"Blue paint 1L\")))" out))
           (multiple-value-bind (log status) (load-log path)
             (is (eq :loaded status))
             (is (= 1 (log-length log)))
             (let ((entry (log-entry log 0)))
               (is (= 8 (entry-count entry)))
               (is (= 3966000000 (entry-at entry)))   ; the first time it was seen
               (is (string= "Blue paint 1L" (entry-name entry))))))
      (ignore-errors (delete-file path)))))

(test a-missing-file-is-an-empty-log
  (multiple-value-bind (log status) (load-log (scratch-file "missing"))
    (is (eq :missing status))
    (is (zerop (log-length log)))))

(test a-corrupt-file-is-moved-aside
  (let* ((path (scratch-file "corrupt"))
         (aside (make-pathname :type "corrupt" :defaults path)))
    (unwind-protect
         (progn
           (with-open-file (out path :direction :output :if-exists :supersede)
             (write-string "(:upc-logger 2 :entries ((:code " out))
           (multiple-value-bind (log status) (load-log path)
             (is (eq :corrupt status))
             (is (zerop (log-length log))))
           (is-false (probe-file path))
           (is-true (probe-file aside)))
      (ignore-errors (delete-file path))
      (ignore-errors (delete-file aside)))))

(test reading-does-not-evaluate
  (let ((path (scratch-file "eval")))
    (unwind-protect
         (progn
           (with-open-file (out path :direction :output :if-exists :supersede)
             (write-string "(:upc-logger 2 :entries #.(error \"evaluated\"))" out))
           (is (eq :corrupt (nth-value 1 (load-log path)))))
      (ignore-errors (delete-file path))
      (ignore-errors (delete-file (make-pathname :type "corrupt" :defaults path))))))
