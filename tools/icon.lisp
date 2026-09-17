;;;; tools/icon.lisp -- the application icon: a barcode, stylised.
;;;;
;;;; A build tool, run on the Mac by `make icon' with SBCL, objc and AppKit;
;;;; never part of the app.  The artwork is code, so changing it is an edit.
;;;;
;;;; The mark is the bars themselves, filling a square block with an even
;;;; margin, rather than a picture of a label lying on a table.  Real UPC-A is
;;;; 95 modules; at the size an icon is actually seen -- 60 points, often less
;;;; -- that is a grey smear, so the rhythm is kept and the density is not.
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

(defmacro with-saved-state (&body body)
  `(progn
     (objc:invoke "NSGraphicsContext" "saveGraphicsState")
     (unwind-protect (progn ,@body)
       (objc:invoke "NSGraphicsContext" "restoreGraphicsState"))))

(defun gradient (from to)
  (objc:invoke (objc:invoke (objc:invoke "NSGradient" "alloc")
                            "initWithStartingColor:endingColor:" from to)
               "autorelease"))

(defun fill-bar (x y width height colour)
  "A bar with its ends rounded to a half-width, which is a pill for a thin one."
  (objc:invoke colour "set")
  (objc:invoke (objc:invoke "NSBezierPath" "bezierPathWithRoundedRect:xRadius:yRadius:"
                            (rect x y width height) (d (/ width 2)) (d (/ width 2)))
               "fill"))

;;; The bars ---------------------------------------------------------------------

(defparameter +pattern+
  ;; Module widths, alternating bar and space, beginning and ending on a bar.
  ;; Eight bars of two, three and four modules. Fifty modules of one-module
  ;; bars came out a comb of hairlines at 120 pixels -- striped wallpaper;
  ;; answering with five-module bars overshot the other way and read as two
  ;; stripes. Eight is few enough to be a mark rather than a texture, and the
  ;; widths stay varied enough to scan as a barcode.
  '(3 2 2 1 4 2 2 2 3 1 2 2 4 1 3)
  "Odd length, so the first and last entries are both bars.")

(defparameter +accents+ '(4)
  "Which bars are amber, counting bars only.  One, a little right of centre: at
eight bars a second accent is a quarter of the mark, which is a colour scheme
rather than an accent.")

(defun draw-bars (size)
  (let* ((margin (* size 0.16))
         (span (- size (* 2 margin)))
         (module (/ span (reduce #'+ +pattern+)))
         (ink (color 0.97 0.97 0.94))
         (amber (color 0.99 0.76 0.33)))
    (loop with x = margin
          with bar-index = 0
          for width in +pattern+
          for bar = t then (not bar)
          do (when bar
               (fill-bar x margin (* width module) span
                         (if (member bar-index +accents+) amber ink))
               (incf bar-index))
             (incf x (* width module)))))

;;; The icon ---------------------------------------------------------------------

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
        (draw-bars size))
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
