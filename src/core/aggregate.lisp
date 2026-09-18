;;;; src/core/aggregate.lisp -- drawing a run of scans as one row, or not.
;;;;
;;;; The log keeps every scan.  A list of eleven identical codes is a true
;;;; record and a poor thing to read, so the table shows runs of the same code
;;;; as one row -- unless the scan carries something of its own.
;;;;
;;;; An event with a note or a photo is always its own row.  Merging it would
;;;; hide the very thing that made it worth marking: "damaged box" belongs to
;;;; one tin in the run, not to the run.  The plain events on either side of it
;;;; still merge among themselves.
;;;;
;;;; Both views produce GROUPs, so the table, the exports and everything else
;;;; take one kind of thing and never have to ask which view is on.

(in-package #:upc-logger)

(defstruct (group (:constructor %make-group (events)))
  "One row: the events behind it, newest first."
  (events '() :type list))

(defun group-first-event (group)
  "The newest event in GROUP, which is the one an edit acts on."
  (first (group-events group)))

(defun group-code (group)
  (entry-code (group-first-event group)))

(defun group-name (group)
  (entry-name (group-first-event group)))

(defun group-note (group)
  (entry-note (group-first-event group)))

(defun group-photo (group)
  (entry-photo (group-first-event group)))

(defun group-count (group)
  "Items reported by every event in GROUP."
  (reduce #'+ (group-events group) :key #'entry-count :initial-value 0))

(defun group-scans (group)
  "How many scans are behind this row."
  (length (group-events group)))

(defun group-latest (group)
  (reduce #'max (group-events group) :key #'entry-at))

(defun group-earliest (group)
  (reduce #'min (group-events group) :key #'entry-at))

(defun group-merged-p (group)
  (> (group-scans group) 1))

(defun group-entries (events aggregate)
  "EVENTS, newest first, as the rows to show.

With AGGREGATE false every event is its own row.  With it true, adjacent
events of the same code merge, except that an event with a note or a photo
stands alone."
  (if (null aggregate)
      (mapcar (lambda (event) (%make-group (list event))) events)
      (let ((groups '())
            (run '()))
        (flet ((flush ()
                 (when run
                   (push (%make-group (nreverse run)) groups)
                   (setf run '()))))
          (dolist (event events)
            (cond ((annotated-p event)
                   ;; Its own row, and it breaks the run around it.
                   (flush)
                   (push (%make-group (list event)) groups))
                  ((and run (string= (entry-code (first run)) (entry-code event)))
                   (push event run))
                  (t
                   (flush)
                   (setf run (list event)))))
          (flush))
        (nreverse groups))))

(defun groups-total-items (groups)
  (reduce #'+ groups :key #'group-count :initial-value 0))

(defun groups-total-scans (groups)
  (reduce #'+ groups :key #'group-scans :initial-value 0))
