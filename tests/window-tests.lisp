;;;; tests/window-tests.lisp

(in-package #:upc-logger/tests)

(def-suite window :in all-tests :description "The stretch of time the chart shows.")
(in-suite window)

(defparameter +midnight+ (encode-universal-time 0 0 0 16 9 2026 0)
  "2026-09-16 00:00 UTC, which is a whole number of six-hour ticks.")

(test the-default-window-is-the-last-day
  (let ((window (default-window +midnight+)))
    (is (= +day+ (window-span window)))
    ;; A second past now, so that now itself is inside a half-open window.
    (is (= (1+ +midnight+) (time-window-end window)))
    (is (< +midnight+ (time-window-end window)))))

(test zooming-in-halves-the-span-around-the-finger
  (let* ((window (default-window +midnight+))
         (zoomed (zoom-window window 1/2 0)))          ; pinch at the left edge
    (is (= (/ +day+ 2) (window-span zoomed)))
    (is (= (time-window-start window) (time-window-start zoomed))))
  (let* ((window (default-window +midnight+))
         (zoomed (zoom-window window 1/2 1)))          ; and at the right
    (is (= (time-window-end window) (time-window-end zoomed)))))

(test the-time-under-the-finger-does-not-move
  (let* ((window (default-window +midnight+))
         (focus 1/4)
         (before (+ (time-window-start window) (* focus (window-span window))))
         (zoomed (zoom-window window 1/3 focus))
         (after (+ (time-window-start zoomed) (* focus (window-span zoomed)))))
    (is (= before after))))

(test zooming-out-then-in-returns-where-it-started
  (let* ((window (default-window +midnight+))
         (round-trip (zoom-window (zoom-window window 4 1/3) 1/4 1/3)))
    (is (= (time-window-start window) (time-window-start round-trip)))
    (is (= (time-window-end window) (time-window-end round-trip)))))

(test the-span-is-clamped-at-both-ends
  (let ((window (default-window +midnight+)))
    (is (= +minimum-span+ (window-span (zoom-window window 1/100000))))
    (is (= +maximum-span+ (window-span (zoom-window window 100000))))
    ;; Clamped is not drifting: a zoom that cannot happen leaves the window be.
    (let ((pinned (zoom-window (make-time-window 0 +minimum-span+) 1/2)))
      (is (= 0 (time-window-start pinned))))))

(test panning-keeps-the-span
  (let* ((window (default-window +midnight+))
         (moved (pan-window window (- +day+))))
    (is (= (window-span window) (window-span moved)))
    (is (= (- (time-window-start window) +day+) (time-window-start moved)))))

(test a-window-panned-into-the-past-stops-following
  (is-true (window-following-p (default-window +midnight+) +midnight+))
  (is-false (window-following-p (pan-window (default-window +midnight+) (- +day+))
                                +midnight+)))

(test bins-are-round-amounts-of-time
  (is (= 1800 (choose-bin-seconds +day+)))             ; a day in half hours
  (is (= 60 (choose-bin-seconds 3600)))
  (is (= 604800 (choose-bin-seconds (* 3650 +day+))))  ; nothing wider than a week
  (is (= (* 3 3600) (bin-start (+ (* 3 3600) 900) 3600))))

(defun scan-at (time &key (code "036000291452") (count 1))
  (make-entry :code code :count count :scanned-at time))

(test the-histogram-counts-items-in-their-bins
  (let* ((entries (list (scan-at +midnight+)
                        (scan-at (+ +midnight+ 60) :count 8)
                        (scan-at (+ +midnight+ 3600))
                        (scan-at (- +midnight+ 60))              ; before the window
                        (scan-at (+ +midnight+ +day+))))         ; after it
         (counts (histogram entries +midnight+ (+ +midnight+ +day+) 3600)))
    (is (= 24 (length counts)))
    (is (= 9 (aref counts 0)))                          ; 1 + 8 items, one bin
    (is (= 1 (aref counts 1)))
    (is (= 10 (reduce #'+ counts)))))

(test the-window-is-half-open
  (let* ((window (make-time-window +midnight+ (+ +midnight+ 3600)))
         (log (make-scan-log (list (scan-at (+ +midnight+ 3600))    ; the end, excluded
                                   (scan-at (+ +midnight+ 1800))
                                   (scan-at +midnight+)             ; the start, included
                                   (scan-at (- +midnight+ 1))))))
    (is (= 2 (length (entries-in-window log window))))))

(test a-scan-made-this-second-is-in-the-live-window
  ;; The chart follows new scans by ending its window at the moment of the
  ;; scan.  Ending it AT that moment hid every scan for the second it was
  ;; made: the table and the bars stayed one scan behind.
  (let* ((window (default-window +midnight+))
         (log (make-scan-log (list (scan-at +midnight+)))))
    (is (= 1 (length (entries-in-window log window))))
    (is (= 1 (reduce #'+ (histogram (scan-log-entries log)
                                    (time-window-start window)
                                    (time-window-end window)
                                    3600))))))

(test ticks-land-on-round-times-and-say-the-clock-or-the-date
  (let ((ticks (axis-ticks (make-time-window +midnight+ (+ +midnight+ +day+)) 0)))
    (is (= 4 (length ticks)))                           ; every six hours
    (is (equal '("00:00" "06:00" "12:00" "18:00") (mapcar #'cdr ticks)))
    (is (= +midnight+ (car (first ticks)))))
  (let ((ticks (axis-ticks (make-time-window +midnight+ (+ +midnight+ (* 30 +day+))) 0)))
    (is-true (every (lambda (tick) (find #\Space (cdr tick))) ticks))))

(test the-visible-range-is-written-out
  (is (string= "Sep 16 to Sep 17"
               (format-window (make-time-window +midnight+ (+ +midnight+ +day+)) 0)))
  (is (string= "Sep 16 00:00 to 06:00"
               (format-window (make-time-window +midnight+ (+ +midnight+ 21600)) 0))))
