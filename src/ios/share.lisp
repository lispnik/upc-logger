;;;; src/ios/share.lisp -- the scans in the view, as a file to send on.
;;;;
;;;; Two formats: CSV, which is what a spreadsheet wants and so is offered
;;;; first, and PDF for something to read or print.  Both cover exactly what
;;;; the chart is showing, and both take their rows from the same core
;;;; function, so they cannot disagree.
;;;;
;;;; The PDF is drawn inside UIGraphicsPDFRenderer's block -- a Lisp closure --
;;;; and reuses DRAW-CHART, so the paper shows the same histogram as the glass.

(in-package #:upc-logger-ios)

(objc:define-objc-block-type pdf-actions :void (objc:objc-object-pointer))

(defparameter +page-width+ 612)
(defparameter +page-height+ 792)
(defparameter +margin+ 48)

(defun export-directory ()
  (objc:ns-string-to-string
   (objc:invoke (objc:invoke (objc:invoke "NSFileManager" "defaultManager") "temporaryDirectory")
                "path")))

(defun export-path (extension)
  (format nil "~a/~a.~a" (string-right-trim "/" (export-directory))
          (export-basename (current-window)) extension))

(defun write-csv ()
  (let ((path (export-path "csv")))
    (with-open-file (out path :direction :output :if-exists :supersede
                              :external-format :utf-8)
      (write-string (log-csv (visible-entries)) out))
    path))

(defun draw-pdf-rows (context entries top)
  "The table, from TOP, starting a new page when the foot of this one is reached."
  (let ((y top)
        (ink (ui:color 0.10 0.10 0.12))
        (faint (ui:color 0.45 0.45 0.50))
        (columns '(48 250 320 460)))
    (flet ((headings ()
             (loop for title in '("Code" "Count" "Scanned" "Last scanned")
                   for x in columns
                   do (draw-text title x y :size 10 :bold t :color faint))
             (incf y 18)))
      (headings)
      (dolist (row (export-rows entries))
        (when (> y (- +page-height+ +margin+))
          (objc:invoke context "beginPage")
          (setf y +margin+)
          (headings))
        (loop for field in row
              for x in columns
              for mono = t then nil
              do (draw-text field x y :size 10 :mono mono :color ink))
        (incf y 15)))))

(defun draw-pdf (context window entries)
  (handler-case
      (let ((y +margin+)
            (ink (ui:color 0.10 0.10 0.12))
            (faint (ui:color 0.45 0.45 0.50))
            (width (- +page-width+ (* 2 +margin+))))
        (objc:invoke context "beginPage")
        (draw-text "UPC Logger" +margin+ y :size 24 :bold t :color ink)
        (incf y 34)
        (draw-text (format-window window) +margin+ y :size 12 :color ink)
        (incf y 17)
        (draw-text (export-summary entries) +margin+ y :size 12 :color faint)
        (incf y 26)
        (draw-chart (vector +margin+ y width 150) window entries :pdf t)
        (incf y 172)
        (draw-pdf-rows context entries y))
    (serious-condition (condition)
      (note "pdf: ~a" condition))))

(defun write-pdf ()
  (let* ((path (export-path "pdf"))
         (window (current-window))
         (entries (visible-entries))
         (renderer (objc:invoke (objc:invoke (objc:invoke "UIGraphicsPDFRenderer" "alloc")
                                             "initWithBounds:"
                                             (vector 0d0 0d0
                                                     (float +page-width+ 1d0)
                                                     (float +page-height+ 1d0)))
                                "autorelease")))
    (objc:with-objc-block (actions 'pdf-actions
                                   (lambda (context) (draw-pdf context window entries)))
      (let ((data (objc:invoke renderer "PDFDataWithActions:" actions)))
        (objc:invoke data "writeToFile:atomically:" path t)))
    path))

;;; The share sheet ----------------------------------------------------------------

(defun anchor-popover (controller sender)
  "On an iPad a sheet is a popover, and a popover with no anchor is a crash."
  (let ((popover (objc:invoke controller "popoverPresentationController")))
    (unless (cffi:null-pointer-p popover)
      (objc:invoke popover "setSourceView:" sender)
      (objc:invoke popover "setSourceRect:" (objc:invoke sender "bounds")))))

(defun share-file (path sender)
  (let ((sheet (objc:invoke (objc:invoke (objc:invoke "UIActivityViewController" "alloc")
                                         "initWithActivityItems:applicationActivities:"
                                         (vector (objc:invoke "NSURL" "fileURLWithPath:" path))
                                         nil)
                            "autorelease")))
    (anchor-popover sheet sender)
    (objc:invoke (ui:root-controller) "presentViewController:animated:completion:" sheet t nil)
    (note "sharing ~a" path)))

(defun export-and-share (writer sender)
  (handler-case (share-file (funcall writer) sender)
    (serious-condition (condition)
      (note "export: ~a" condition))))

(defun share-export (sender)
  "Ask for a format, CSV first, then hand the file to the share sheet."
  (let ((sheet (objc:invoke "UIAlertController" "alertControllerWithTitle:message:preferredStyle:"
                            "Export this range"
                            (format nil "~a, ~a" (format-window (current-window))
                                    (export-summary (visible-entries)))
                            0)))                                  ; action sheet
    (objc:with-objc-block (on-csv 'alert-action-handler
                                  (lambda (action)
                                    (declare (ignore action))
                                    (export-and-share #'write-csv sender)))
      (objc:with-objc-block (on-pdf 'alert-action-handler
                                    (lambda (action)
                                      (declare (ignore action))
                                      (export-and-share #'write-pdf sender)))
        (let ((csv (objc:invoke "UIAlertAction" "actionWithTitle:style:handler:"
                                "CSV" 0 on-csv)))
          (objc:invoke sheet "addAction:" csv)
          (objc:invoke sheet "addAction:"
                       (objc:invoke "UIAlertAction" "actionWithTitle:style:handler:"
                                    "PDF" 0 on-pdf))
          (objc:invoke sheet "addAction:"
                       (objc:invoke "UIAlertAction" "actionWithTitle:style:handler:"
                                    "Cancel" 1 nil))
          (objc:invoke sheet "setPreferredAction:" csv))
        (anchor-popover sheet sender)
        (objc:invoke (ui:root-controller) "presentViewController:animated:completion:"
                     sheet t nil)))))
