;;;; src/core/window.lisp -- the stretch of time the chart is showing.
;;;;
;;;; All of it is arithmetic on universal times, so the zooming and panning a
;;;; finger does on the chart can be tested on a Mac with no chart in sight.
;;;;
;;;; A window is half-open, [start, end): a scan exactly on a bin boundary
;;;; belongs to the bin that starts there, and nothing is counted twice.

(in-package #:upc-logger)

(defconstant +day+ 86400)

(defconstant +minimum-span+ 300
  "Five minutes. Zooming further in shows one bar and no useful detail.")

(defconstant +maximum-span+ (* 3650 +day+)
  "Ten years. Past this the bins are wider than the data can fill.")

(defstruct (time-window (:constructor make-time-window (start end)))
  (start 0 :type integer)
  (end 0 :type integer))

(defun window-span (window)
  (- (time-window-end window) (time-window-start window)))

(defun default-window (now &optional (span +day+))
  "The last SPAN seconds, ending just after NOW: what the chart shows until it
is touched.

Just after, not at: the window is half-open, so a window ending exactly at NOW
leaves out a scan made in this very second -- and since the window is reset to
follow each new scan, that is every scan as it arrives.  It cost an afternoon
of a chart that stayed one scan behind itself."
  (let ((end (1+ now)))
    (make-time-window (- end span) end)))

(defun clamp-span (span)
  (min +maximum-span+ (max +minimum-span+ (round span))))

(defun zoom-window (window factor &optional (focus 1/2))
  "WINDOW zoomed by FACTOR, keeping the time at FOCUS where it is.

FACTOR below 1 zooms in. FOCUS is a fraction of the width, 0 at the left edge,
so the point under a pinch stays under it."
  (let* ((span (window-span window))
         (zoomed (clamp-span (* span factor)))
         (time (+ (time-window-start window) (* focus span)))
         (start (round (- time (* focus zoomed)))))
    (make-time-window start (+ start zoomed))))

(defun pan-window (window seconds)
  "WINDOW moved by SECONDS, which keeps its span."
  (make-time-window (round (+ (time-window-start window) seconds))
                    (round (+ (time-window-end window) seconds))))

(defun window-following-p (window now &optional (slack 60))
  "True when WINDOW still ends at about NOW, so a new scan belongs on its right
edge.  Panning into the past makes this false, and the chart stops following."
  (>= (time-window-end window) (- now slack)))

;;; Bars and ticks ---------------------------------------------------------------

(defparameter +bin-choices+
  '(60 300 900 1800 3600 10800 21600 43200 86400 604800)
  "Bin widths that read as round amounts of time: a minute up to a week.")

(defun choose-bin-seconds (span &optional (bars 48))
  "The bin width from +BIN-CHOICES+ that comes closest to BARS bars over SPAN.

Closest by ratio, not by difference, so being twice too coarse counts the same
as twice too fine.  Rounding up to the next choice instead was simpler and
wrong: an hour fell to five-minute bins, twelve fat bars where sixty thin ones
show when the scanning actually happened."
  (let ((target (max 1 bars)))
    (flet ((wrongness (choice)
             (let ((count (max 1 (/ span choice))))
               (max (/ count target) (/ target count)))))
      (first (sort (copy-list +bin-choices+) #'< :key #'wrongness)))))

(defun bin-start (time bin-seconds)
  "The start of the bin TIME falls in, so bars line up on round times."
  (* bin-seconds (floor time bin-seconds)))

(defun histogram (entries start end bin-seconds)
  "Items scanned per bin over [START, END), as a vector.

Counted by items rather than rows, so a row of eight stands eight high.  A
bumped row counts at the time it was first scanned: that is the only time an
entry keeps, and inventing the rest would be a lie the file cannot support."
  (let* ((bins (max 1 (ceiling (- end start) bin-seconds)))
         (counts (make-array bins :initial-element 0)))
    (dolist (entry entries counts)
      (let ((time (entry-at entry)))
        (when (and (<= start time) (< time end))
          (incf (aref counts (floor (- time start) bin-seconds))
                (entry-count entry)))))))

(defparameter +tick-choices+
  '(300 900 1800 3600 7200 21600 43200 86400 172800 604800 2592000))

(defun tick-interval (span &optional (most 6))
  "How far apart to put dated marks so that at most MOST of them fit in SPAN."
  (or (find-if (lambda (choice) (<= (/ span choice) most)) +tick-choices+)
      (first (last +tick-choices+))))

(defun month-name (month)
  (aref #("Jan" "Feb" "Mar" "Apr" "May" "Jun"
          "Jul" "Aug" "Sep" "Oct" "Nov" "Dec")
        (1- month)))

(defun format-clock (time &optional time-zone)
  (multiple-value-bind (second minute hour)
      (if time-zone (decode-universal-time time time-zone) (decode-universal-time time))
    (declare (ignore second))
    (format nil "~2,'0d:~2,'0d" hour minute)))

(defun format-day (time &optional time-zone)
  (multiple-value-bind (second minute hour day month)
      (if time-zone (decode-universal-time time time-zone) (decode-universal-time time))
    (declare (ignore second minute hour))
    (format nil "~a ~d" (month-name month) day)))

(defun axis-ticks (window &optional time-zone)
  "Marks along the bottom of the chart, as (time . label).

Labelled by the clock while a day or less is showing and by the date beyond
that, because \"14:00\" on a chart spanning a month says nothing."
  (let* ((interval (tick-interval (window-span window)))
         (clock (< interval +day+)))
    (loop for time = (let ((first (* interval (ceiling (time-window-start window) interval))))
                       first)
            then (+ time interval)
          while (< time (time-window-end window))
          collect (cons time (if clock
                                 (format-clock time time-zone)
                                 (format-day time time-zone))))))

(defun format-window (window &optional time-zone)
  "The visible range, as it is written under the chart."
  (let ((start (time-window-start window))
        (end (time-window-end window)))
    (if (< (window-span window) +day+)
        (format nil "~a ~a to ~a" (format-day start time-zone)
                (format-clock start time-zone) (format-clock end time-zone))
        (format nil "~a to ~a" (format-day start time-zone) (format-day end time-zone)))))

(defun entries-in-window (log window)
  "The log's entries scanned inside WINDOW, newest first, as the table shows them."
  (remove-if-not (lambda (entry)
                   (let ((time (entry-at entry)))
                     (and (<= (time-window-start window) time)
                          (< time (time-window-end window)))))
                 (scan-log-entries log)))
