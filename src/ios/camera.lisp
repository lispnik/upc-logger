;;;; src/ios/camera.lisp -- the top third: a live preview that reads barcodes.
;;;;
;;;; AVFoundation does the reading.  A capture session runs the back camera
;;;; into an AVCaptureMetadataOutput asked for EAN-13 (which is how UPC-A
;;;; arrives), EAN-8 and UPC-E, and the output calls a Lisp-defined delegate
;;;; with whatever codes are in the frame -- on the main queue, because that is
;;;; the queue it is given, so the delegate can touch UIKit directly.
;;;;
;;;; The preview is a CALayer, and layers take no part in Auto Layout, so the
;;;; view it sits in is a UIView subclass whose layoutSubviews keeps the layer
;;;; the size of the view.
;;;;
;;;; A simulator has no camera.  There the preview area offers a button that
;;;; feeds a made-up code through the same path a real scan takes.

(in-package #:upc-logger-ios)

(defvar *scanner* nil "The view the preview is shown in.")
(defvar *preview* nil "The AVCaptureVideoPreviewLayer.")
(defvar *flash* nil "A green view over the preview, shown for a moment on each scan.")
(defvar *aim* nil "The red aiming line, meaningless without a camera.")
(defvar *session* nil)
(defvar *output* nil)
(defvar *camera-queue* nil)
(defvar *scan-delegate* nil)
(defvar *access-reply* nil "Kept: the reply arrives after the call returns.")
(defvar *gate* (make-scan-gate))

(defparameter +media-type-video+ "vide" "AVMediaTypeVideo")

(objc:define-objc-block-type thunk-block :void ())
(objc:define-objc-block-type access-reply :void (objc:objc-c++-bool))

;;; The view --------------------------------------------------------------------

(objc:define-objc-class scanner-view () ()
  (:objc-class-name "UPCScannerView")
  (:objc-superclass-name "UIView"))

(objc:define-objc-method ("layoutSubviews" :void) ((self scanner-view))
  (objc:invoke (objc:current-super) "layoutSubviews")
  (handler-case
      (when *preview*
        (objc:invoke *preview* "setFrame:" (objc:invoke (objc:objc-object-pointer self) "bounds")))
    (serious-condition (condition)
      (note "layout: ~a" condition))))

(defun scanner-label (text &key (offset 0))
  (let ((label (ui:new "UILabel")))
    (objc:invoke label "setText:" text)
    (objc:invoke label "setNumberOfLines:" 0)
    (objc:invoke label "setTextAlignment:" 1)
    (objc:invoke label "setTextColor:" (ui:color 1 1 1 0.9))
    (objc:invoke label "setFont:" (ui:font 15 0.2))
    (objc:invoke *scanner* "addSubview:" label)
    (ui:pin label "leadingAnchor" *scanner* "leadingAnchor" 24)
    (ui:pin label "trailingAnchor" *scanner* "trailingAnchor" -24)
    (ui:pin label "centerYAnchor" *scanner* "centerYAnchor" offset)
    label))

;;; Feedback --------------------------------------------------------------------

(defun beep ()
  (let ((play (cffi:foreign-symbol-pointer "AudioServicesPlaySystemSound")))
    (when play
      (si:call-cfun play :void '(:unsigned-int) (list 1057)))))

(defun buzz ()
  (let ((generator (objc:invoke (objc:invoke (objc:invoke "UIImpactFeedbackGenerator" "alloc")
                                             "initWithStyle:" 1) ; medium
                                "autorelease")))
    (objc:invoke generator "impactOccurred")))

(defun flash ()
  (when *flash*
    (objc:invoke *flash* "setAlpha:" 0.45d0)
    (objc:with-objc-block (fade 'thunk-block
                                (lambda () (objc:invoke *flash* "setAlpha:" 0d0)))
      (objc:invoke "UIView" "animateWithDuration:animations:" 0.45d0 fade))))

;;; A scan ----------------------------------------------------------------------

(defun log-scan (code)
  (multiple-value-bind (entry how) (record-scan *log* code (get-universal-time))
    (save)
    (show-scan how)
    (buzz)
    (beep)
    (flash)
    (note "~(~a~) ~a" how (format-entry-title (entry-count entry) (entry-code entry)))))

(defun now-ms ()
  (floor (* 1000 (get-internal-real-time)) internal-time-units-per-second))

(defun reading (value type)
  "The capture output saw VALUE, of AVMetadataObjectType TYPE."
  (let ((code (scanned-code value type)))
    (when (and code (admit-scan *gate* code (now-ms)))
      (log-scan code))))

(objc:define-objc-class scan-delegate () ()
  (:objc-class-name "UPCScanDelegate")
  (:objc-protocols "AVCaptureMetadataOutputObjectsDelegate"))

(objc:define-objc-method ("captureOutput:didOutputMetadataObjects:fromConnection:" :void)
    ((self scan-delegate) (output objc:objc-object-pointer)
     (objects objc:objc-object-pointer) (connection objc:objc-object-pointer))
  (declare (ignore output connection))
  (handler-case
      (dotimes (i (objc:invoke objects "count"))
        (let ((object (objc:invoke objects "objectAtIndex:" i)))
          (when (objc:can-invoke-p object "stringValue")
            (reading (objc:ns-string-to-string (objc:invoke object "stringValue"))
                     (objc:ns-string-to-string (objc:invoke object "type"))))))
    (serious-condition (condition)
      (note "scan: ~a" condition))))

;;; The session -----------------------------------------------------------------

(defun prefer-near-focus (device)
  "Barcodes are read close up; tell autofocus to start looking there."
  (when (and (objc:invoke-bool device "isAutoFocusRangeRestrictionSupported")
             (objc:invoke-bool device "lockForConfiguration:" (cffi:null-pointer)))
    (objc:invoke device "setAutoFocusRangeRestriction:" 1)          ; near
    (objc:invoke device "unlockForConfiguration")))

(defun narrow-to-preview ()
  "Only read codes inside the part of the frame the preview shows.  Must wait
until the session runs: before that the conversion answers an empty rectangle."
  (handler-case
      (let ((rect (objc:invoke *preview* "metadataOutputRectOfInterestForRect:"
                               (objc:invoke *scanner* "bounds"))))
        (when (and (plusp (aref rect 2)) (plusp (aref rect 3)))
          (objc:invoke *output* "setRectOfInterest:" rect)))
    (serious-condition (condition)
      (note "rect of interest: ~a" condition))))

(defun run-session ()
  (let* ((device (objc:invoke "AVCaptureDevice" "defaultDeviceWithMediaType:" +media-type-video+))
         (input (if (cffi:null-pointer-p device)
                    device
                    (objc:invoke "AVCaptureDeviceInput" "deviceInputWithDevice:error:"
                                 device (cffi:null-pointer))))
         (session (objc:alloc-init-object "AVCaptureSession"))
         (output (objc:alloc-init-object "AVCaptureMetadataOutput"))
         (main-queue (cffi:foreign-symbol-pointer "_dispatch_main_q")))
    ;; Owned, and never released: they last as long as the app.
    (setf *session* session
          *output* output)
    (cond ((or (cffi:null-pointer-p input)
               (not (objc:invoke-bool session "canAddInput:" input))
               (not (objc:invoke-bool session "canAddOutput:" output))
               (null main-queue))
           (scanner-label "The camera could not be opened."))
          (t
           (prefer-near-focus device)
           (objc:invoke session "addInput:" input)
           (objc:invoke session "addOutput:" output)
           ;; Types can only be asked for once the output is in a session.
           (let ((available (objc:invoke output "availableMetadataObjectTypes"))
                 (wanted (objc:invoke "NSMutableArray" "array")))
             (dolist (type '("org.gs1.EAN-13" "org.gs1.UPC-E" "org.gs1.EAN-8"))
               (when (objc:invoke-bool available "containsObject:" type)
                 (objc:invoke wanted "addObject:" type)))
             (objc:invoke output "setMetadataObjectTypes:" wanted))
           (setf *scan-delegate* (ui:keep (make-instance 'scan-delegate)))
           (objc:invoke output "setMetadataObjectsDelegate:queue:"
                        (objc:objc-object-pointer *scan-delegate*) main-queue)
           (setf *preview* (objc:invoke "AVCaptureVideoPreviewLayer" "layerWithSession:" session))
           (objc:invoke *preview* "setVideoGravity:" "AVLayerVideoGravityResizeAspectFill")
           (objc:invoke *preview* "setFrame:" (objc:invoke *scanner* "bounds"))
           (objc:invoke (objc:invoke *scanner* "layer") "insertSublayer:atIndex:" *preview* 0)
           ;; -startRunning blocks until the camera is up; not on the main thread.
           (setf *camera-queue* (objc:alloc-init-object "NSOperationQueue"))
           (objc:with-objc-block (begin 'thunk-block
                                        (lambda ()
                                          (handler-case
                                              (objc:with-autorelease-pool ()
                                                (objc:invoke session "startRunning"))
                                            (serious-condition (condition)
                                              (note "start: ~a" condition)))
                                          (ios-app-runtime:on-main #'narrow-to-preview)))
             (objc:invoke *camera-queue* "addOperationWithBlock:" begin))))))

;;; Without a camera ------------------------------------------------------------

(defvar *sample-codes* nil)

(defun sample-codes ()
  "Four made-up UPC-As, so repeated simulated scans sometimes match the top row."
  (or *sample-codes*
      (setf *sample-codes*
            (loop repeat 4
                  collect (add-check-digit (format nil "~11,'0d" (random 100000000000)))))))

(defun simulate-scan (&optional (which (random 4)))
  "A scan of sample code WHICH, arriving as the camera would report it: an
EAN-13 with a leading zero.  Past the gate, which is about a label held in view."
  (let ((code (scanned-code (concatenate 'string "0" (nth which (sample-codes)))
                            "org.gs1.EAN-13")))
    (when code
      (log-scan code))))

(defun show-simulator ()
  (when *aim*
    (objc:invoke *aim* "setHidden:" t))
  (scanner-label "No camera here." :offset -22)
  (let ((button (ui:system-button "Simulate scan")))
    (objc:invoke (objc:invoke button "titleLabel") "setFont:" (ui:font 17 0.3))
    (ui:on-tap button (lambda (sender)
                        (declare (ignore sender))
                        (simulate-scan)))
    (objc:invoke *scanner* "addSubview:" button)
    (ui:pin button "centerXAnchor" *scanner* "centerXAnchor")
    (ui:pin button "centerYAnchor" *scanner* "centerYAnchor" 18)))

(defun show-denied ()
  (scanner-label (format nil "Camera access is off.~%Turn it on in Settings, UPC Logger.")))

(defun start-camera ()
  (let ((device (objc:invoke "AVCaptureDevice" "defaultDeviceWithMediaType:" +media-type-video+)))
    (if (cffi:null-pointer-p device)
        (show-simulator)
        (case (objc:invoke "AVCaptureDevice" "authorizationStatusForMediaType:" +media-type-video+)
          (3 (run-session))                                         ; authorized
          (0                                                        ; not determined
           (setf *access-reply*
                 (objc:make-objc-block
                  'access-reply
                  (lambda (granted)
                    ;; Called on a queue of AVFoundation's choosing.
                    (ios-app-runtime:on-main
                     (lambda ()
                       (if (and granted (not (eql granted 0)))
                           (run-session)
                           (show-denied)))))))
           (objc:invoke "AVCaptureDevice" "requestAccessForMediaType:completionHandler:"
                        +media-type-video+ *access-reply*))
          (t (show-denied))))))

(defun scanner-overlay (color alpha)
  (let ((view (ui:new "UIView")))
    (objc:invoke view "setBackgroundColor:" color)
    (objc:invoke view "setAlpha:" alpha)
    (objc:invoke view "setUserInteractionEnabled:" nil)
    (objc:invoke *scanner* "addSubview:" view)
    view))

(defun build-scanner (root)
  (setf *scanner* (objc:alloc-init-object "UPCScannerView"))
  (objc:invoke *scanner* "setTranslatesAutoresizingMaskIntoConstraints:" nil)
  (objc:invoke *scanner* "setBackgroundColor:" (ui:color 0.06 0.08 0.10))
  (objc:invoke *scanner* "setClipsToBounds:" t)
  (objc:invoke root "addSubview:" *scanner*)
  (ui:pin *scanner* "topAnchor" root "topAnchor")
  (ui:pin *scanner* "leadingAnchor" root "leadingAnchor")
  (ui:pin *scanner* "trailingAnchor" root "trailingAnchor")
  (objc:invoke (objc:invoke (ui:anchor *scanner* "heightAnchor")
                            "constraintEqualToAnchor:multiplier:"
                            (ui:anchor root "heightAnchor") (/ 1d0 3))
               "setActive:" t)
  ;; The aiming line, a little below centre to clear the status bar.
  (let ((line (setf *aim* (scanner-overlay (ui:color 1 0.25 0.2) 0.8))))
    (ui:fix line "heightAnchor" 2)
    (ui:pin line "leadingAnchor" *scanner* "leadingAnchor" 36)
    (ui:pin line "trailingAnchor" *scanner* "trailingAnchor" -36)
    (ui:pin line "centerYAnchor" *scanner* "centerYAnchor" 20))
  (setf *flash* (scanner-overlay (ui:system-color "systemGreen") 0))
  (dolist (edge '("topAnchor" "bottomAnchor" "leadingAnchor" "trailingAnchor"))
    (ui:pin *flash* edge *scanner* edge))
  *scanner*)
