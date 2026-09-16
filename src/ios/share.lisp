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

;;; One item, two formats.
;;;
;;; The share sheet opens straight away rather than behind a list of formats.
;;; The item it carries is registered twice, as CSV and as PDF, and the
;;; destination takes the representation it can use: Numbers and Sheets ask for
;;; the CSV, Books and Print for the PDF, AirDrop and Files take the first one
;;; registered -- which is why CSV is registered first.
;;;
;;; Apple's own "Options" panel, the one offering lossless or most-compatible
;;; for a photo, is not public: UIActivityItemsConfigurationReading carries a
;;; title, a message body, link metadata and previews, and nothing that names a
;;; format. This is the mechanism underneath it that third-party code may use.

(objc:define-objc-block-type file-load-handler
    objc:objc-object-pointer (objc:objc-at-question-mark))

(defvar *load-handlers* '()
  "Kept: NSItemProvider calls these once something asks for a representation,
long after the sheet went up.")

(defun register-representation (provider type path)
  "Offer the file at PATH as TYPE, one representation of the shared item."
  (let ((handler (objc:make-objc-block
                  'file-load-handler
                  (lambda (completion)
                    (handler-case
                        (objc:call-objc-block
                         '(:void (objc:objc-object-pointer objc:objc-bool objc:objc-object-pointer))
                         completion
                         (objc:invoke "NSURL" "fileURLWithPath:" path)
                         nil                        ; no file coordination needed
                         (cffi:null-pointer))
                      (serious-condition (condition)
                        (note "handing over ~a: ~a" type condition)))
                    ;; No NSProgress: the file was written before the sheet opened.
                    (cffi:null-pointer)))))
    (push handler *load-handlers*)
    (objc:invoke provider
                 "registerFileRepresentationForTypeIdentifier:fileOptions:visibility:loadHandler:"
                 type
                 0                                  ; not open in place
                 0                                  ; visible to every process
                 handler)))

(defun export-item-provider ()
  (let ((provider (objc:alloc-init-object "NSItemProvider")))
    (objc:invoke provider "setSuggestedName:" (export-basename (current-window)))
    (register-representation provider "public.comma-separated-values-text" (write-csv))
    (register-representation provider "com.adobe.pdf" (write-pdf))
    provider))

(objc:define-objc-block-type file-loaded :void
  (objc:objc-object-pointer objc:objc-object-pointer))

(defvar *load-probes* '())

(defun probe-representations ()
  "Ask our own provider for both formats, the way a destination does.

The load handlers only run when something asks, which on a simulator means a
tap nobody is there to make; this drives the same path from code so that a
block the bridge cannot carry shows up on the console instead of under a finger."
  (let ((provider (export-item-provider)))
    (dolist (type '("public.comma-separated-values-text" "com.adobe.pdf"))
      (let* ((wanted type)
             (block (objc:make-objc-block
                     'file-loaded
                     (lambda (url error)
                       (handler-case
                           (if (cffi:null-pointer-p url)
                               (note "probe ~a: no file (~a)" wanted
                                     (if (cffi:null-pointer-p error)
                                         "no error either"
                                         (objc:ns-string-to-string
                                          (objc:invoke error "localizedDescription"))))
                               (note "probe ~a: ~a" wanted
                                     (objc:ns-string-to-string (objc:invoke url "lastPathComponent"))))
                         (serious-condition (condition)
                           (note "probe ~a failed: ~a" wanted condition)))))))
        (push block *load-probes*)
        (objc:invoke provider "loadFileRepresentationForTypeIdentifier:completionHandler:"
                     type block)))))

(defun share-export (sender)
  (handler-case
      (let* ((configuration (ui:keep (objc:invoke (objc:invoke "UIActivityItemsConfiguration" "alloc")
                                                  "initWithItemProviders:"
                                                  (vector (export-item-provider)))))
             (sheet (objc:invoke (objc:invoke (objc:invoke "UIActivityViewController" "alloc")
                                              "initWithActivityItemsConfiguration:" configuration)
                                 "autorelease")))
        (anchor-popover sheet sender)
        (objc:invoke (ui:root-controller) "presentViewController:animated:completion:" sheet t nil)
        (note "sharing ~a, CSV and PDF" (export-basename (current-window))))
    (serious-condition (condition)
      (note "share: ~a" condition))))
