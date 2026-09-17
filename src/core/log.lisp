;;;; src/core/log.lisp -- every scan, kept as its own event.
;;;;
;;;; A scan is an event with the time it happened.  Nothing is merged on the
;;;; way in: merging is a way of LOOKING at the log (see aggregate.lisp), and a
;;;; log that merged as it wrote could not be unmerged afterwards.  The first
;;;; version of this file did merge, and the cost was exactly that -- a row of
;;;; eight kept two timestamps out of eight, and the histogram put all eight
;;;; items in the first one's bin.
;;;;
;;;; COUNT is on the event because a person scans one of a case and says there
;;;; are eight: that is one scan reporting eight items, not eight scans, and
;;;; recording it as eight would invent seven times that never happened.
;;;;
;;;; A NAME belongs to the CODE -- naming one event names every event with that
;;;; code, and a later scan inherits it.  A NOTE and a PHOTO describe the one
;;;; scan and stay on their own event.
;;;;
;;;; The photo is a file beside the log; only its name is here.

(in-package #:upc-logger)

(defstruct (entry (:constructor make-entry (&key code (count 1) at name note photo
                                                 ;; Accepted so a v1 plist reads
                                                 ;; without special-casing.
                                                 scanned-at)))
  (code "" :type string)
  (count 1 :type (integer 1))
  (at (or scanned-at 0) :type integer)
  (name nil :type (or null string))
  (note nil :type (or null string))
  (photo nil :type (or null string)))

(defun annotated-p (entry)
  "True when ENTRY carries something of its own: a note or a photo.

Such an event never merges with its neighbours, because what it carries
belongs to that scan and would be hidden inside a run."
  (and (or (entry-note entry) (entry-photo entry)) t))

(defstruct (scan-log (:constructor make-scan-log (&optional entries)))
  "The log.  ENTRIES is a list of events, newest first."
  (entries '() :type list))

(defun log-length (log)
  (length (scan-log-entries log)))

(defun log-entry (log index)
  (nth index (scan-log-entries log)))

(defun total-items (log)
  (reduce #'+ (scan-log-entries log) :key #'entry-count :initial-value 0))

(defun code-name (log code)
  "What CODE has been called, from the newest event that names it, or NIL."
  (let ((named (find-if (lambda (entry)
                          (and (string= code (entry-code entry))
                               (entry-name entry)))
                        (scan-log-entries log))))
    (and named (entry-name named))))

(defun record-scan (log code now)
  "Log a scan of CODE at universal time NOW as its own event.

Always a new event: two scans of the same thing are two scans, and the
display is where they are drawn as one.  Returns the event and :NEW, the
second value kept so callers written against the merging version still work."
  (let ((entry (make-entry :code code :at now :name (code-name log code))))
    (push entry (scan-log-entries log))
    (values entry :new)))

(defun delete-entry (log index)
  "Remove event INDEX.  Returns it, or NIL if there was none."
  (let ((entry (log-entry log index)))
    (when entry
      (setf (scan-log-entries log)
            (append (subseq (scan-log-entries log) 0 index)
                    (nthcdr (1+ index) (scan-log-entries log)))))
    entry))

(defun set-count (log index count)
  "Make event INDEX report COUNT items.  Zero deletes it."
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
  "Call event INDEX's code NAME, and every other event with that code too."
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
  "Attach NOTE to event INDEX alone.  Blank clears it."
  (let ((entry (log-entry log index)))
    (if (null entry)
        (values nil nil)
        (progn (setf (entry-note entry) (blank-to-nil note))
               (values entry :updated)))))

(defun set-photo (log index photo)
  "Attach the photo file named PHOTO to event INDEX alone.  NIL clears it."
  (let ((entry (log-entry log index)))
    (if (null entry)
        (values nil nil)
        (progn (setf (entry-photo entry) (blank-to-nil photo))
               (values entry :updated)))))

;;; The file ------------------------------------------------------------------

(defconstant +log-format-version+ 2
  "2 keeps every scan as its own event.  1 kept merged rows with a first and a
last time, and is still read.")

(defun entry-plist (entry)
  "ENTRY as a plist, leaving out what it does not have."
  (append (list :code (entry-code entry)
                :count (entry-count entry)
                :at (entry-at entry))
          (when (entry-name entry) (list :name (entry-name entry)))
          (when (entry-note entry) (list :note (entry-note entry)))
          (when (entry-photo entry) (list :photo (entry-photo entry)))))

(defun plist-entry (plist)
  "An event from PLIST, in either format.

Version 1 wrote :SCANNED-AT and :UPDATED-AT for a merged row.  Its count is
kept as one event reporting that many items: the scans between the first time
and the last were never written down, and inventing them would be a lie the
file cannot support."
  (make-entry :code (getf plist :code)
              :count (getf plist :count)
              :at (or (getf plist :at) (getf plist :scanned-at) 0)
              :name (getf plist :name)
              :note (getf plist :note)
              :photo (getf plist :photo)))

(defun save-log (log path)
  "Write LOG to PATH, by way of a temporary file renamed over it."
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

Either version reads; the next save writes the current one."
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
