;;;; src/ios/chart.lisp -- scans over time, drawn in Lisp.
;;;;
;;;; A UIView subclass whose drawRect: is a Lisp method, over a window of time
;;;; that a pinch zooms and a drag scrolls.  The drawing is a function of a
;;;; rectangle, so the same code fills the chart on screen and the chart in the
;;;; exported PDF.
;;;;
;;;; The window starts as the last day and follows new scans.  Touching the
;;;; chart stops it following, because a chart that jumps while it is being
;;;; read is worse than one that is briefly out of date; Reset, or a double
;;;; tap, puts it back.

(in-package #:upc-logger-ios)

(defvar *chart* nil)
(defvar *window* nil)
(defvar *follow* t "True while the window still tracks the newest scan.")
(defvar *range-label* nil)
(defvar *on-window-change* nil
  "Called after the window moves, by whatever is showing it.")

(defun current-window ()
  (or *window* (setf *window* (default-window (get-universal-time)))))

(defvar *query* nil
  "What the search bar holds, or NIL.  One rule decides what is on screen:
inside the window, and matching this -- so the table, the bars and an export
can never disagree about what \"showing\" means.")

(defvar *aggregated* nil
  "True while a run of scans of one code is drawn as a single row.

Off to begin with: a row per scan is the log as it was actually recorded, and
grouping is the interpretation laid over it.  The strip above the search bar
turns it on.")

(defun visible-entries ()
  "The scans on screen, one event each.  The bars are drawn from these however
the table is grouped: the times are the reason every scan is kept."
  (search-entries (entries-in-window *log* (current-window)) *query*))

(defun visible-groups ()
  "The rows on screen: merged runs, or one row per scan."
  (group-entries (visible-entries) *aggregated*))

(defun notify-window-change ()
  (when *on-window-change*
    (funcall *on-window-change*)))

(defun update-range-label ()
  (when *range-label*
    (objc:invoke *range-label* "setText:" (format-window (current-window)))))

(defun redraw-chart ()
  (when *chart*
    (objc:invoke *chart* "setNeedsDisplay")))

;;; Drawing ---------------------------------------------------------------------

(defun text-attributes (size &key bold mono color)
  (let ((attributes (objc:invoke "NSMutableDictionary" "dictionary")))
    (objc:invoke attributes "setObject:forKey:"
                 (cond (mono (ui:mono-font size))
                       (bold (ui:bold-font size))
                       (t (ui:font size)))
                 "NSFont")
    (objc:invoke attributes "setObject:forKey:"
                 (or color (ui:system-color "label"))
                 "NSColor")
    attributes))

(defun draw-text (text x y &key (size 11) bold mono color center)
  "TEXT at X, Y in the current context; with CENTER, X is its middle."
  (let* ((string (objc:invoke "NSString" "stringWithString:" text))
         (attributes (text-attributes size :bold bold :mono mono :color color))
         (x (if center
                (- x (/ (aref (objc:invoke-into 'vector string "sizeWithAttributes:" attributes) 0)
                        2))
                x)))
    (objc:invoke string "drawAtPoint:withAttributes:"
                 (vector (float x 1d0) (float y 1d0)) attributes)))

(defun fill-rect (x y width height color &optional (radius 0))
  (let ((rect (vector (float x 1d0) (float y 1d0)
                      (float (max 0 width) 1d0) (float (max 0 height) 1d0))))
    (objc:invoke color "setFill")
    (objc:invoke (if (plusp radius)
                     (objc:invoke "UIBezierPath" "bezierPathWithRoundedRect:cornerRadius:"
                                  rect (float radius 1d0))
                     (objc:invoke "UIBezierPath" "bezierPathWithRect:" rect))
                 "fill")))

(defun draw-chart (rect window entries &key pdf)
  "The histogram of ENTRIES over WINDOW, inside RECT of the current context.

PDF picks ink that is dark on white paper; on screen the system colours follow
light and dark appearance."
  (let* ((x (aref rect 0)) (y (aref rect 1))
         (width (aref rect 2)) (height (aref rect 3))
         (axis 16)                              ; room under the bars for labels
         (plot (max 10 (- height axis)))
         (span (window-span window))
         (bin (choose-bin-seconds span))
         (counts (histogram entries (time-window-start window) (time-window-end window) bin))
         (bars (length counts))
         (bar-width (/ width bars))
         (peak (max 1 (reduce #'max counts)))
         (faint (if pdf (ui:color 0.55 0.55 0.58) (ui:system-color "secondaryLabel")))
         (grid (if pdf (ui:color 0.85 0.85 0.87) (ui:system-color "separator")))
         (ink (if pdf (ui:color 0.10 0.42 0.50) (ui:system-color "systemTeal"))))
    (dolist (tick (axis-ticks window))
      (let* ((tick-x (+ x (* width (/ (- (car tick) (time-window-start window)) span))))
             ;; The label is centred on its tick, so one at either end hangs
             ;; over the edge and is cut off -- "15:10" came out "15:1".  Held
             ;; inside the plot it reads whole, a little off its own tick.
             (label-x (max (+ x 17) (min tick-x (- (+ x width) 17)))))
        (fill-rect tick-x y 1 plot grid)
        (draw-text (cdr tick) label-x (+ y plot 2) :size 9 :color faint :center t)))
    (fill-rect x (+ y plot) width 1 grid)
    (loop for i below bars
          for count = (aref counts i)
          do (when (plusp count)
               (let ((bar (max 2 (* (- plot 12) (/ count peak)))))
                 (fill-rect (+ x (* i bar-width) 0.5) (- (+ y plot) bar)
                            (max 1 (- bar-width 1)) bar ink 1))))
    (if (zerop (reduce #'+ counts))
        (draw-text "No scans in this range" (+ x (/ width 2)) (+ y (/ plot 2) -8)
                   :size 13 :color faint :center t)
        (draw-text (format nil "peak ~d in ~a" peak (bin-name bin)) x y :size 9 :color faint))))

(defun bin-name (seconds)
  (cond ((< seconds 3600) (format nil "~d min" (floor seconds 60)))
        ((< seconds +day+) (format nil "~d h" (floor seconds 3600)))
        ((= seconds +day+) "a day")
        (t (format nil "~d days" (floor seconds +day+)))))

(objc:define-objc-class chart-view () ()
  (:objc-class-name "UPCChartView")
  (:objc-superclass-name "UIView"))

(objc:define-objc-method ("drawRect:" :void)
    ((self chart-view) (dirty cocoa:ns-rect))
  (declare (ignore dirty))
  ;; Nothing may unwind into UIKit.
  (handler-case
      (let ((bounds (objc:invoke (objc:objc-object-pointer self) "bounds")))
        (draw-chart (vector 0d0 0d0 (aref bounds 2) (aref bounds 3))
                    (current-window) (visible-entries)))
    (serious-condition (condition)
      (note "chart: ~a" condition))))

;;; Gestures --------------------------------------------------------------------

(defun chart-width ()
  (max 1 (aref (objc:invoke *chart* "bounds") 2)))

(defun on-pinch (recognizer)
  "Pinch to zoom the time axis, keeping the moment under the fingers still."
  (handler-case
      (let* ((scale (objc:invoke recognizer "scale"))
             (point (objc:invoke recognizer "locationInView:" *chart*))
             (focus (max 0 (min 1 (/ (aref point 0) (chart-width))))))
        (objc:invoke recognizer "setScale:" 1d0)
        (when (and (> scale 0.05) (/= scale 1))
          (setf *window* (zoom-window (current-window) (/ 1d0 scale) focus)
                *follow* nil)
          (notify-window-change)))
    (serious-condition (condition)
      (note "pinch: ~a" condition))))

(defun on-pan (recognizer)
  "Drag to scroll through time. The translation is zeroed so each call is a delta."
  (handler-case
      (let ((delta (objc:invoke recognizer "translationInView:" *chart*)))
        (objc:invoke recognizer "setTranslation:inView:" #(0 0) *chart*)
        (let ((seconds (- (* (window-span (current-window))
                             (/ (aref delta 0) (chart-width))))))
          (unless (zerop seconds)
            (setf *window* (pan-window (current-window) seconds)
                  *follow* nil)
            (notify-window-change))))
    (serious-condition (condition)
      (note "pan: ~a" condition))))

(defun reset-window ()
  "Back to the last day, following new scans again."
  (setf *window* (default-window (get-universal-time))
        *follow* t)
  (notify-window-change))

(defun follow-new-scan ()
  "Slide the window up to now, unless the chart has been panned or zoomed."
  (when *follow*
    (setf *window* (default-window (get-universal-time)
                                   (window-span (current-window))))))

(defun install-chart-gestures (view)
  (loop for (class-name function taps)
          in (list (list "UIPanGestureRecognizer" #'on-pan nil)
                   (list "UIPinchGestureRecognizer" #'on-pinch nil)
                   (list "UITapGestureRecognizer"
                         (lambda (sender) (declare (ignore sender)) (reset-window))
                         2))
        do (let ((recognizer (ui:keep (objc:invoke (objc:invoke class-name "alloc")
                                                   "initWithTarget:action:"
                                                   (ui:action-target function) "fire:"))))
             (when taps
               (objc:invoke recognizer "setNumberOfTapsRequired:" taps))
             (objc:invoke view "addGestureRecognizer:" recognizer))))

(defun build-chart (root above)
  (setf *chart* (objc:alloc-init-object "UPCChartView"))
  (objc:invoke *chart* "setTranslatesAutoresizingMaskIntoConstraints:" nil)
  (objc:invoke *chart* "setBackgroundColor:" (ui:system-color "systemBackground"))
  (objc:invoke root "addSubview:" *chart*)
  (ui:pin *chart* "topAnchor" above "bottomAnchor" 8)
  (ui:pin *chart* "leadingAnchor" root "leadingAnchor" 14)
  (ui:pin *chart* "trailingAnchor" root "trailingAnchor" -14)
  (ui:fix *chart* "heightAnchor" 150)
  (install-chart-gestures *chart*)
  *chart*)
