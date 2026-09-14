;;;; src/core/log.lisp -- the scans, newest first, and the file they live in.
;;;;
;;;; Every entry keeps when it was first scanned and when it was last bumped,
;;;; as universal times.  Nothing here needs them yet beyond the list's
;;;; subtitle, but a histogram over a date range and a spreadsheet export both
;;;; will, and a timestamp not recorded now cannot be recovered later.
;;;;
;;;; The file is a readable s-expression rather than a database: it is small,
;;;; it can be looked at, and reading it back is READ.

(in-package #:upc-logger)

(defstruct (entry (:constructor make-entry (&key code (count 1) scanned-at
                                                 (updated-at scanned-at))))
  (code "" :type string)
  (count 1 :type (integer 1))
  (scanned-at 0 :type integer)
  (updated-at 0 :type integer))

(defun entry-bumped-p (entry)
  "True when ENTRY was scanned again after it was first logged."
  (/= (entry-scanned-at entry) (entry-updated-at entry)))

(defstruct (scan-log (:constructor make-scan-log (&optional entries)))
  "The log.  ENTRIES is a list, newest first: new scans go on the front, and
the table shows it in this order, so index I is row I."
  (entries '() :type list))

(defun log-length (log)
  (length (scan-log-entries log)))

(defun log-entry (log index)
  (nth index (scan-log-entries log)))

(defun total-items (log)
  "The sum of the counts: what was scanned, multiples included."
  (reduce #'+ (scan-log-entries log) :key #'entry-count))

(defun record-scan (log code now)
  "Log a scan of CODE at universal time NOW.

The same code as the newest entry bumps that entry's count, so a run of
identical items scanned one after another stays one row; anything else is a
new row on top.  Returns the entry and :BUMPED or :NEW."
  (let ((newest (first (scan-log-entries log))))
    (if (and newest (string= code (entry-code newest)))
        (progn
          (incf (entry-count newest))
          (setf (entry-updated-at newest) now)
          (values newest :bumped))
        (let ((entry (make-entry :code code :scanned-at now)))
          (push entry (scan-log-entries log))
          (values entry :new)))))

(defun delete-entry (log index)
  "Remove row INDEX.  Returns the removed entry, or NIL if there was none."
  (let ((entry (log-entry log index)))
    (when entry
      (setf (scan-log-entries log)
            (append (subseq (scan-log-entries log) 0 index)
                    (nthcdr (1+ index) (scan-log-entries log)))))
    entry))

(defun set-count (log index count)
  "Make row INDEX's count COUNT.  Zero deletes the row.

Returns the entry and :UPDATED, NIL and :DELETED, or NIL and NIL when INDEX is
out of range or COUNT is not a non-negative integer -- a keypad can't type a
negative, but a paste can put anything in the field."
  (let ((entry (log-entry log index)))
    (cond ((or (null entry) (not (typep count '(integer 0))))
           (values nil nil))
          ((zerop count)
           (delete-entry log index)
           (values nil :deleted))
          (t
           (setf (entry-count entry) count)
           (values entry :updated)))))

;;; The file ------------------------------------------------------------------

(defconstant +log-format-version+ 1)

(defun entry-plist (entry)
  (list :code (entry-code entry)
        :count (entry-count entry)
        :scanned-at (entry-scanned-at entry)
        :updated-at (entry-updated-at entry)))

(defun plist-entry (plist)
  (make-entry :code (getf plist :code)
              :count (getf plist :count)
              :scanned-at (getf plist :scanned-at)
              :updated-at (getf plist :updated-at (getf plist :scanned-at))))

(defun save-log (log path)
  "Write LOG to PATH, by way of a temporary file renamed over it.

The rename is what makes a save that is interrupted -- the app killed in the
background -- leave the previous log rather than half of a new one."
  (let ((temporary (make-pathname :type "tmp" :defaults path)))
    (ensure-directories-exist path)
    (with-open-file (out temporary :direction :output :if-exists :supersede
                                   :external-format :utf-8)
      (with-standard-io-syntax
        (let ((*print-readably* nil)
              (*print-pretty* nil))
          (format out ";;;; UPC Logger scans. Times are Common Lisp universal times.~%")
          (prin1 (list :upc-logger +log-format-version+
                       :entries (mapcar #'entry-plist (scan-log-entries log)))
                 out)
          (terpri out))))
    (rename-file temporary path #+ecl :if-exists #+ecl t)
    path))

(defun load-log (path)
  "The log saved at PATH.  Returns it and :LOADED, :MISSING or :CORRUPT.

A file that doesn't read is moved aside to a .corrupt file rather than left
where the next save would overwrite it: an empty log is a better start than a
crash, but the scans in the bad file may still be recoverable by hand."
  (if (not (probe-file path))
      (values (make-scan-log) :missing)
      (handler-case
          (let ((form (with-open-file (in path :external-format :utf-8)
                        (with-standard-io-syntax
                          (let ((*read-eval* nil))
                            (read in))))))
            (unless (and (consp form) (eq (first form) :upc-logger)
                         (integerp (second form)))
              (error "~a is not a UPC Logger file." path))
            (values (make-scan-log (mapcar #'plist-entry (getf (cddr form) :entries)))
                    :loaded))
        (error ()
          (ignore-errors
           (rename-file path (make-pathname :type "corrupt" :defaults path)
                        #+ecl :if-exists #+ecl t))
          (values (make-scan-log) :corrupt)))))
