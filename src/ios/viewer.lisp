;;;; src/ios/viewer.lisp -- a scan's photo, full screen.
;;;;
;;;; Tapping the thumbnail on a row opens the picture over everything, with
;;;; the two things worth doing to it: replace, or delete.
;;;;
;;;; It takes what to do as closures rather than calling back into the list,
;;;; so this file loads before that one and neither has to know the other.

(in-package #:upc-logger-ios)

(defvar *viewer* nil "The photo controller while it is up.")
(defvar *viewer-image* nil)
(defvar *viewer-blocks* '()
  "Handlers for the open confirmation.  UIKit copies what it keeps.")

(objc:define-objc-block-type viewer-action-handler :void (objc:objc-object-pointer))

(defun dismiss-viewer ()
  (let ((controller *viewer*))
    (setf *viewer* nil
          *viewer-image* nil)
    (when controller
      (objc:invoke controller "dismissViewControllerAnimated:completion:" t nil)
      (ui:unkeep controller))))

(defun confirm-delete (controller on-delete)
  (dolist (block *viewer-blocks*)
    (ignore-errors (objc:free-objc-block block)))
  (setf *viewer-blocks* '())
  (let ((alert (objc:invoke "UIAlertController" "alertControllerWithTitle:message:preferredStyle:"
                            "Delete this photo?"
                            "It goes from the scan and from the phone."
                            0)))                                  ; action sheet
    (let ((block (objc:make-objc-block
                  'viewer-action-handler
                  (lambda (action)
                    (declare (ignore action))
                    (handler-case
                        (progn (dismiss-viewer)
                               (when on-delete (funcall on-delete)))
                      (serious-condition (condition)
                        (note "delete photo: ~a" condition)))))))
      (push block *viewer-blocks*)
      (objc:invoke alert "addAction:"
                   (objc:invoke "UIAlertAction" "actionWithTitle:style:handler:"
                                "Delete" 2 block)))              ; destructive
    (objc:invoke alert "addAction:"
                 (objc:invoke "UIAlertAction" "actionWithTitle:style:handler:"
                              "Cancel" 1 nil))
    ;; On an iPad a sheet is a popover, and a popover with no anchor is a crash.
    (let ((popover (objc:invoke alert "popoverPresentationController")))
      (unless (cffi:null-pointer-p popover)
        (let ((view (objc:invoke controller "view")))
          (objc:invoke popover "setSourceView:" view)
          (objc:invoke popover "setSourceRect:" (objc:invoke view "bounds")))))
    (objc:invoke controller "presentViewController:animated:completion:" alert t nil)))

(defun viewer-button (title &key destructive)
  (let ((button (ui:system-button title)))
    (objc:invoke button "setTintColor:"
                 (if destructive
                     (ui:system-color "systemRed")
                     (objc:invoke "UIColor" "whiteColor")))
    (objc:invoke (objc:invoke button "titleLabel") "setFont:" (ui:font 17 0.3))
    button))

(defun show-photo (file &key on-replace on-delete)
  "FILE, full screen, over whatever is showing.

ON-REPLACE is called with this controller, so a picker can be presented from
it -- presenting from the root while this is up would have nowhere to go.
ON-DELETE is called after the viewer has gone, and after a confirmation."
  (handler-case
      (let* ((controller (ui:keep (objc:alloc-init-object "UIViewController")))
             (view (objc:invoke controller "view"))
             (safe (objc:invoke view "safeAreaLayoutGuide"))
             (image (ui:new "UIImageView"))
             (row (ui:new "UIStackView")))
        (setf *viewer* controller
              *viewer-image* image)
        (objc:invoke controller "setModalPresentationStyle:" 0)   ; full screen
        (objc:invoke view "setBackgroundColor:" (ui:color 0 0 0))
        (objc:invoke image "setContentMode:" 1)                   ; aspect fit
        (objc:invoke image "setImage:"
                     (objc:invoke "UIImage" "imageWithContentsOfFile:" file))
        (objc:invoke view "addSubview:" image)
        (ui:pin image "topAnchor" view "topAnchor")
        (ui:pin image "leadingAnchor" view "leadingAnchor")
        (ui:pin image "trailingAnchor" view "trailingAnchor")
        (ui:pin image "bottomAnchor" view "bottomAnchor")
        (objc:invoke row "setAxis:" 0)
        (objc:invoke row "setDistribution:" 1)                    ; fill equally
        (objc:invoke view "addSubview:" row)
        (ui:pin row "leadingAnchor" safe "leadingAnchor" 24)
        (ui:pin row "trailingAnchor" safe "trailingAnchor" -24)
        (ui:pin row "bottomAnchor" safe "bottomAnchor" -12)
        (let ((close (viewer-button "Close"))
              (replace (viewer-button "Replace"))
              (remove (viewer-button "Delete" :destructive t)))
          (ui:on-tap close (lambda (sender)
                             (declare (ignore sender))
                             (dismiss-viewer)))
          (ui:on-tap replace (lambda (sender)
                               (declare (ignore sender))
                               (when on-replace (funcall on-replace controller))))
          (ui:on-tap remove (lambda (sender)
                              (declare (ignore sender))
                              (confirm-delete controller on-delete)))
          (objc:invoke row "addArrangedSubview:" close)
          (objc:invoke row "addArrangedSubview:" replace)
          (objc:invoke row "addArrangedSubview:" remove))
        (objc:invoke (ui:root-controller) "presentViewController:animated:completion:"
                     controller t nil))
    (serious-condition (condition)
      (note "photo viewer: ~a" condition))))

(defun viewer-show-file (file)
  "Put FILE in the open viewer, after a replacement."
  (when *viewer-image*
    (objc:invoke *viewer-image* "setImage:"
                 (objc:invoke "UIImage" "imageWithContentsOfFile:" file))))
