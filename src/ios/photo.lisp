;;;; src/ios/photo.lisp -- a picture of what was scanned.
;;;;
;;;; The photo is a JPEG in Documents/photos/, and the log keeps only its file
;;;; name: the log stays a readable s-expression, and the pictures sit beside
;;;; it where Files can reach them.
;;;;
;;;; UIImagePickerController is the whole of the interface -- the camera on a
;;;; phone, the library where there is no camera -- and its delegate is a Lisp
;;;; class. The picker answers once, so the completion is held in a special
;;;; rather than threaded through Objective-C.

(in-package #:upc-logger-ios)

(defvar *picker-delegate* nil "Kept: UIKit holds a delegate weakly.")
(defvar *photo-completion* nil
  "What to do with the file name the picker produces, or NIL for a cancel.")

(defun photos-directory ()
  (let ((path (merge-pathnames "photos/" (documents-directory))))
    (ensure-directories-exist path)
    path))

(defun photo-file-path (name)
  (namestring (merge-pathnames name (photos-directory))))

(defun photo-exists-p (name)
  (and name (probe-file (photo-file-path name))))

(defun new-photo-name ()
  (multiple-value-bind (second minute hour day month year)
      (decode-universal-time (get-universal-time))
    (format nil "~4,'0d~2,'0d~2,'0d-~2,'0d~2,'0d~2,'0d.jpg"
            year month day hour minute second)))

(defun jpeg-data (image &optional (quality 0.6d0))
  "IMAGE as JPEG bytes.  UIImageJPEGRepresentation is a C function, not a
method, and its quality is a CGFloat -- a double on arm64."
  (let ((function (cffi:foreign-symbol-pointer "UIImageJPEGRepresentation")))
    (when function
      (si:call-cfun function :pointer-void '(:pointer-void :double)
                    (list image (float quality 1d0))))))

(defun write-photo (image)
  "IMAGE as a JPEG beside the log.  Returns its file name, or NIL."
  (let ((data (jpeg-data image))
        (name (new-photo-name)))
    (when (and data (not (cffi:null-pointer-p data))
               (objc:invoke-bool data "writeToFile:atomically:" (photo-file-path name) t))
      (note "wrote ~a, ~:d bytes" name (objc:invoke data "length"))
      name)))

(defun finish-photo (name)
  (let ((completion *photo-completion*))
    (setf *photo-completion* nil)
    (when completion
      (funcall completion name))))

(objc:define-objc-class photo-picker-delegate () ()
  (:objc-class-name "UPCPhotoPickerDelegate"))

(objc:define-objc-method ("imagePickerController:didFinishPickingMediaWithInfo:" :void)
    ((self photo-picker-delegate) (picker objc:objc-object-pointer)
     (info objc:objc-object-pointer))
  (handler-case
      (let* ((image (objc:invoke info "objectForKey:" "UIImagePickerControllerOriginalImage"))
             (name (unless (cffi:null-pointer-p image) (write-photo image))))
        (objc:invoke picker "dismissViewControllerAnimated:completion:" t nil)
        (finish-photo name))
    (serious-condition (condition)
      (note "photo: ~a" condition)
      (finish-photo nil))))

(objc:define-objc-method ("imagePickerControllerDidCancel:" :void)
    ((self photo-picker-delegate) (picker objc:objc-object-pointer))
  (handler-case
      (progn (objc:invoke picker "dismissViewControllerAnimated:completion:" t nil)
             (finish-photo nil))
    (serious-condition (condition)
      (note "cancel: ~a" condition))))

(defun delete-photo-file (name)
  "Remove the JPEG called NAME, if it is there.  A photo replaced or deleted
leaves no file behind: the pictures would otherwise pile up unreferenced."
  (when name
    (let ((path (photo-file-path name)))
      (when (probe-file path)
        (handler-case (progn (delete-file path) (note "removed ~a" name))
          (error (condition) (note "could not remove ~a: ~a" name condition)))))))

(defun pick-photo (completion &optional presenter)
  "Take or choose a photo, then call COMPLETION with its file name, or NIL.

PRESENTER is what puts the picker on screen; the root controller cannot, while
something else is presented over it."
  (handler-case
      (let ((camera (objc:invoke-bool "UIImagePickerController" "isSourceTypeAvailable:" 1))
            (picker (objc:alloc-init-object "UIImagePickerController")))
        (setf *photo-completion* completion)
        (unless *picker-delegate*
          (setf *picker-delegate* (ui:keep (make-instance 'photo-picker-delegate))))
        ;; 1 is the camera, 0 the library: the simulator has only the second.
        (objc:invoke picker "setSourceType:" (if camera 1 0))
        (objc:invoke picker "setDelegate:" (objc:objc-object-pointer *picker-delegate*))
        (objc:invoke (or presenter (ui:root-controller))
                     "presentViewController:animated:completion:" picker t nil))
    (serious-condition (condition)
      (note "picker: ~a" condition)
      (finish-photo nil))))

;;; Without a camera or a library -------------------------------------------------

(objc:define-objc-block-type image-actions :void (objc:objc-object-pointer))

(defun synthetic-photo ()
  "An image drawn here rather than taken, so the write-and-show path can be
exercised on a simulator, where there is no camera and the library is empty."
  (let ((renderer (objc:invoke (objc:invoke (objc:invoke "UIGraphicsImageRenderer" "alloc")
                                            "initWithSize:" (vector 240d0 240d0))
                               "autorelease")))
    (objc:with-objc-block (actions 'image-actions
                                   (lambda (context)
                                     (declare (ignore context))
                                     (objc:invoke (ui:color 0.06 0.42 0.47) "setFill")
                                     (objc:invoke (objc:invoke "UIBezierPath" "bezierPathWithRect:"
                                                               (vector 0d0 0d0 240d0 240d0))
                                                  "fill")
                                     (objc:invoke (ui:color 0.99 0.76 0.33) "setFill")
                                     (objc:invoke (objc:invoke "UIBezierPath" "bezierPathWithOvalInRect:"
                                                               (vector 60d0 60d0 120d0 120d0))
                                                  "fill")))
      (objc:invoke renderer "imageWithActions:" actions))))
