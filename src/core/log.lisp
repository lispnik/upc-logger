;;;; src/core/log.lisp -- the scans, newest first, and the file they live in.
;;;;
;;;; Every entry keeps when it was first scanned and when it was last bumped,
;;;; as universal times.  Nothing here needs them yet beyond the list's
;;;; subtitle, but a histogram over a date range and a spreadsheet export both
;;;; will, and a timestamp not recorded now cannot be recovered later.
;;;;
;;;; An entry may also carry a name, a note and a photo.  The name belongs to
;;;; the CODE -- naming one row names every row with that code, and a later
;;;; scan of it inherits the name -- because a name is what the product is
;;;; called, and typing it again per scan would defeat the point.  A note and a
;;;; photo describe one scan and stay on their own row.
;;;;
;;;; The photo is a file beside the log, not in it: only its name is here, so
;;;; the log stays a readable s-expression rather than a wall of base64.
;;;;
;;;; The file is a readable s-expression rather than a database: it is small,
;;;; it can be looked at, and reading it back is READ.

(in-package #:upc-logger)

(defstruct (entry (:constructor make-entry (&key code (count 1) scanned-at
                                                 (updated-at scanned-at)
                                                 name note photo)))
  (code "" :type string)
  (count 1 :type (integer 1))
  (scanned-at 0 :type integer)
  (updated-at 0 :type integer)
  (name nil :type (or null string))
  (note nil :type (or null string))
  (photo nil :type (or null string)))

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
  (reduce #'+ (scan-log-entries log) :key #'entry-count :initial-value 0))

(defun code-name (log code)
  "What CODE has been called, from the newest entry that names it, or NIL."
  (let ((named (find-if (lambda (entry)
                          (and (string= code (entry-code entry))
                               (entry-name entry)))
                        (scan-log-entries log))))
    (and named (entry-name named))))

(defun record-scan (log code now)
  "Log a scan of CODE at universal time NOW.

The same code as the newest entry bumps that entry's count, so a run of
identical items scanned one after another stays one row; anything else is a
new row on top, carrying whatever this code has been named before.  Returns
the entry and :BUMPED or :NEW."
  (let ((newest (first (scan-log-entries log))))
    (if (and newest (string= code (entry-code newest)))
        (progn
          (incf (entry-count newest))
          (setf (entry-updated-at newest) now)
          (values newest :bumped))
        (let ((entry (make-entry :code code :scanned-at now
                                 :name (code-name log code))))
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

(defun blank-to-nil (text)
  "TEXT trimmed, or NIL if nothing is left: an empty field clears a value."
  (when (stringp text)
    (let ((trimmed (string-trim '(#\Space #\Tab #\Newline #\Return) text)))
      (unless (zerop (length trimmed)) trimmed))))

(defun set-name (log index name)
  "Call row INDEX's code NAME, and every other row with that code too.

Returns the entry and :UPDATED, or NIL and NIL for a row that isn't there.
Blank clears the name, on all of them."
  (let ((entry (log-entry log index)))
    (if (null entry)
        (values nil nil)
        (let ((name (blank-to-nil name))
              (code (entry-code entry)))
          (dolist (other (scan-log-entries log))
            (when (string= code (entry-code other))
              (setf (entry-name other) name)))
          (values entry :updated)))))

(defun set-note (log index note)
  "Attach NOTE to row INDEX alone.  Blank clears it."
  (let ((entry (log-entry log index)))
    (if (null entry)
        (values nil nil)
        (progn (setf (entry-note entry) (blank-to-nil note))
               (values entry :updated)))))

(defun set-photo (log index photo)
  "Attach the photo file named PHOTO to row INDEX alone.  NIL clears it."
  (let ((entry (log-entry log index)))
    (if (null entry)
        (values nil nil)
        (progn (setf (entry-photo entry) (blank-to-nil photo))
               (values entry :updated)))))

;;; The file ------------------------------------------------------------------

(defconstant +log-format-version+ 1)

(defun entry-plist (entry)
  "ENTRY as a plist, leaving out what it does not have: a log of plain scans
reads the same as it did before names, notes and photos existed."
  (append (list :code (entry-code entry)
                :count (entry-count entry)
                :scanned-at (entry-scanned-at entry)
                :updated-at (entry-updated-at entry))
          (when (entry-name entry) (list :name (entry-name entry)))
          (when (entry-note entry) (list :note (entry-note entry)))
          (when (entry-photo entry) (list :photo (entry-photo entry)))))

(defun plist-entry (plist)
  (make-entry :code (getf plist :code)
              :count (getf plist :count)
              :scanned-at (getf plist :scanned-at)
              :updated-at (getf plist :updated-at (getf plist :scanned-at))
              :name (getf plist :name)
              :note (getf plist :note)
              :photo (getf plist :photo)))

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
