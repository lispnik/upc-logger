;;;; tools/icon.lisp -- the application icon: barcode bars with a log over them.
;;;;
;;;; A build tool, run on the Mac by `make icon' with SBCL, objc and AppKit;
;;;; never part of the app.  The artwork is code, so changing it is an edit.
;;;;
;;;; iOS masks the corners itself and wants a full-bleed, opaque square, so
;;;; nothing here is rounded at the outside.  Coordinates are Cocoa's: y up.

(defpackage #:upc-logger-icon
  (:use #:common-lisp)
  (:export #:render-icon))

(in-package #:upc-logger-icon)

(defparameter +appkit+ "/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit")

(defun d (x) (float x 1d0))

(defun color (red green blue &optional (alpha 1))
  (objc:invoke "NSColor" "colorWithSRGBRed:green:blue:alpha:" (d red) (d green) (d blue) (d alpha)))

(defun rect (x y width height)
  (vector (d x) (d y) (d width) (d height)))

(defun fill-path (path colour)
  (objc:invoke colour "set")
  (objc:invoke path "fill"))

(defun rounded (x y width height radius)
  (objc:invoke "NSBezierPath" "bezierPathWithRoundedRect:xRadius:yRadius:"
               (rect x y width height) (d radius) (d radius)))

(defun oval (cx cy rx ry)
  (objc:invoke "NSBezierPath" "bezierPathWithOvalInRect:"
               (rect (- cx rx) (- cy ry) (* 2 rx) (* 2 ry))))

(defmacro with-saved-state (&body body)
  `(progn
     (objc:invoke "NSGraphicsContext" "saveGraphicsState")
     (unwind-protect (progn ,@body)
       (objc:invoke "NSGraphicsContext" "restoreGraphicsState"))))

(defun gradient (from to)
  (objc:invoke (objc:invoke (objc:invoke "NSGradient" "alloc")
                            "initWithStartingColor:endingColor:" from to)
               "autorelease"))

;;; The barcode -----------------------------------------------------------------

(defparameter +bar-pattern+
  ;; Module widths, alternating bar and space: guard, digits, centre guard,
  ;; digits, guard.  Not a real encoding -- just the rhythm of one.
  '(1 1 1  3 2 1 1  2 2 2 1  1 4 1 1  1 1 3 2  2 1 1 3
    1 1 1 1 1
    1 3 1 2  2 2 1 2  1 1 4 1  3 1 1 2  1 2 3 1
    1 1 1))

(defun draw-barcode (size)
  (let* ((card-x (* size 0.14)) (card-w (* size 0.72))
         (card-y (* size 0.30)) (card-h (* size 0.52))
         (modules (reduce #'+ +bar-pattern+))
         (left (+ card-x (* size 0.07)))
         (module (/ (- card-w (* size 0.14)) modules))
         (top (+ card-y card-h (* size -0.07)))
         (bottom (+ card-y (* size 0.10))))
    (with-saved-state
      (let ((shadow (objc:alloc-init-object "NSShadow")))
        (objc:invoke shadow "setShadowOffset:" (vector 0d0 (d (* size -0.012))))
        (objc:invoke shadow "setShadowBlurRadius:" (d (* size 0.03)))
        (objc:invoke shadow "setShadowColor:" (color 0 0 0 0.35))
        (objc:invoke shadow "set"))
      (fill-path (rounded card-x card-y card-w card-h (* size 0.045)) (color 0.98 0.98 0.96)))
    (objc:invoke (color 0.08 0.09 0.10) "set")
    (loop with x = left
          for width in +bar-pattern+
          for bar = t then (not bar)
          for index from 0
          do (when bar
               ;; Guard bars run longer, as on a real label.
               (let ((guard (or (< index 3) (> index 46) (<= 23 index 27))))
                 (objc:invoke "NSBezierPath" "fillRect:"
                              (rect x (if guard (- bottom (* size 0.035)) bottom)
                                    (* width module)
                                    (- top (if guard (- bottom (* size 0.035)) bottom))))))
             (incf x (* width module)))))

;;; The log ---------------------------------------------------------------------

(defun stroke-curve (points width colour)
  "A round-capped cubic through four POINTS, each (x . y)."
  (let ((path (objc:invoke "NSBezierPath" "bezierPath")))
    (flet ((pt (p) (vector (d (car p)) (d (cdr p)))))
      (objc:invoke path "moveToPoint:" (pt (first points)))
      (objc:invoke path "curveToPoint:controlPoint1:controlPoint2:"
                   (pt (fourth points)) (pt (second points)) (pt (third points))))
    (objc:invoke path "setLineWidth:" (d width))
    (objc:invoke path "setLineCapStyle:" 1)
    (objc:invoke colour "set")
    (objc:invoke path "stroke")))

(defun draw-log (size)
  "A log lying level across the middle of the barcode, its cut end showing the
rings.  Drawn about its own centre, which sits on the centre of the bars.

Shorter than the card is wide: the cut end sticks out past the body by its own
radius, and at the card's full width that overhang ran off the artwork."
  (let* ((s size)
         (half-length (* s 0.32))
         (radius (* s 0.095))
         (end-rx (* radius 0.62))
         (bark-light (color 0.60 0.38 0.19))
         (bark-dark (color 0.36 0.21 0.10))
         (grain (color 0.28 0.16 0.07 0.85)))
    (with-saved-state
      ;; The centre of the card is (0.50, 0.56) and the bars sit a little above
      ;; it; 0.57 puts the log across their middle.  No rotation: level.
      (let ((transform (objc:invoke "NSAffineTransform" "transform")))
        (objc:invoke transform "translateXBy:yBy:" (d (* s 0.50)) (d (* s 0.57)))
        (objc:invoke transform "concat"))
      ;; Shadow under the whole log.
      (with-saved-state
        (let ((shadow (objc:alloc-init-object "NSShadow")))
          (objc:invoke shadow "setShadowOffset:" (vector (d (* s 0.004)) (d (* s -0.022))))
          (objc:invoke shadow "setShadowBlurRadius:" (d (* s 0.035)))
          (objc:invoke shadow "setShadowColor:" (color 0 0 0 0.5))
          (objc:invoke shadow "set"))
        (fill-path (oval (- half-length) 0 end-rx radius) bark-dark)
        (objc:invoke "NSBezierPath" "fillRect:"
                     (rect (- half-length) (- radius) (* 2 half-length) (* 2 radius))))
      ;; Bark: a gradient across the log's width, rounded at the far end.
      (fill-path (oval (- half-length) 0 end-rx radius) bark-dark)
      (objc:invoke (gradient bark-dark bark-light) "drawInRect:angle:"
                   (rect (- half-length) (- radius) (* 2 half-length) (* 2 radius)) 90d0)
      (objc:invoke (gradient bark-light bark-dark) "drawInRect:angle:"
                   (rect (- half-length) (* radius 0.15) (* 2 half-length) (* radius 0.85)) 90d0)
      ;; Grain.
      (loop for (y wobble) in `((,(* radius 0.55) ,(* radius 0.12))
                                (,(* radius 0.05) ,(* radius -0.10))
                                (,(* radius -0.50) ,(* radius 0.08)))
            do (stroke-curve (list (cons (* half-length -0.85) y)
                                   (cons (* half-length -0.3) (+ y wobble))
                                   (cons (* half-length 0.2) (- y wobble))
                                   (cons (* half-length 0.8) y))
                             (* s 0.011) grain))
      ;; A knot.
      (fill-path (oval (* half-length -0.25) (* radius -0.28) (* s 0.022) (* s 0.014)) grain)
      ;; The cut end: pale wood, rings, a bark rim.
      (fill-path (oval half-length 0 end-rx radius) (color 0.90 0.74 0.50))
      (dolist (k '(0.72 0.46 0.22))
        (let ((ring (oval half-length 0 (* end-rx k) (* radius k))))
          (objc:invoke ring "setLineWidth:" (d (* s 0.008)))
          (objc:invoke (color 0.70 0.50 0.28) "set")
          (objc:invoke ring "stroke")))
      (let ((rim (oval half-length 0 end-rx radius)))
        (objc:invoke rim "setLineWidth:" (d (* s 0.016)))
        (objc:invoke bark-dark "set")
        (objc:invoke rim "stroke")))))

;;; The icon --------------------------------------------------------------------

(defun render-icon (path &key (size 1024))
  "Draw the icon at SIZE x SIZE and write it to PATH as a PNG.  Returns PATH."
  (objc:ensure-objc-initialized :modules (list +appkit+))
  (objc:with-autorelease-pool ()
    (let ((rep (objc:invoke (objc:invoke "NSBitmapImageRep" "alloc")
                            "initWithBitmapDataPlanes:pixelsWide:pixelsHigh:bitsPerSample:samplesPerPixel:hasAlpha:isPlanar:colorSpaceName:bytesPerRow:bitsPerPixel:"
                            (cffi:null-pointer) size size 8 4 t nil
                            "NSCalibratedRGBColorSpace" 0 0)))
      (with-saved-state
        (objc:invoke "NSGraphicsContext" "setCurrentContext:"
                     (objc:invoke "NSGraphicsContext" "graphicsContextWithBitmapImageRep:" rep))
        (objc:invoke (gradient (color 0.03 0.22 0.27) (color 0.07 0.43 0.47))
                     "drawInRect:angle:" (rect 0 0 size size) 90d0)
        (draw-barcode size)
        (draw-log size))
      (let* ((data (objc:invoke rep "representationUsingType:properties:"
                                4 (objc:invoke "NSDictionary" "dictionary"))) ; PNG
             (length (objc:invoke data "length"))
             (bytes (objc:invoke data "bytes"))
             (octets (make-array length :element-type '(unsigned-byte 8))))
        (dotimes (i length)
          (setf (aref octets i) (cffi:mem-aref bytes :unsigned-char i)))
        (ensure-directories-exist path)
        (with-open-file (out path :direction :output :element-type '(unsigned-byte 8)
                                  :if-exists :supersede)
          (write-sequence octets out))
        (objc:invoke rep "release"))))
  path)
