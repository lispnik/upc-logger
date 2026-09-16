;;;; src/ios/app.lisp -- the entry point, and the screen it builds.
;;;;
;;;; Camera on top, then the chart with its controls, then the scans that fall
;;;; inside the chart's window.  Everything that moves the window goes through
;;;; REFRESH-VIEW, so the three of them never disagree about what is on screen.

(in-package #:upc-logger-ios)

(defun refresh-view ()
  (update-range-label)
  (redraw-chart)
  (refresh-list))

(defun build-controls (root above)
  "The line under the chart: what it is showing, and what to do with it."
  (let ((row (ui:new "UIStackView")))
    (objc:invoke row "setAxis:" 0)
    (objc:invoke row "setSpacing:" 12)
    (objc:invoke row "setAlignment:" 3)                 ; centre
    (objc:invoke root "addSubview:" row)
    (ui:pin row "topAnchor" above "bottomAnchor" 6)
    (ui:pin row "leadingAnchor" root "leadingAnchor" 16)
    (ui:pin row "trailingAnchor" root "trailingAnchor" -16)
    (setf *range-label* (ui:new "UILabel"))
    (objc:invoke *range-label* "setFont:" (ui:font 12))
    (objc:invoke *range-label* "setTextColor:" (ui:system-color "secondaryLabel"))
    (objc:invoke row "addArrangedSubview:" *range-label*)
    ;; A spacer, so the buttons sit at the right end.
    (let ((spacer (ui:new "UIView")))
      (objc:invoke row "addArrangedSubview:" spacer)
      (objc:invoke spacer "setContentHuggingPriority:forAxis:" 1d0 0))
    (let ((reset (ui:system-button "Reset"))
          (share (ui:system-button "Share")))
      (ui:on-tap reset (lambda (sender) (declare (ignore sender)) (reset-window)))
      (ui:on-tap share (lambda (sender) (share-export sender)))
      (objc:invoke row "addArrangedSubview:" reset)
      (objc:invoke row "addArrangedSubview:" share))
    (update-range-label)
    row))

(defun demo ()
  "UPC_LOGGER_DEMO=1: a few simulated scans, a count set to 8, then the count
prompt -- so a simulator shows every part of the app without a finger."
  (let ((steps (list (lambda () (simulate-scan 0))
                     (lambda () (simulate-scan 0))
                     (lambda () (simulate-scan 1))
                     (lambda () (simulate-scan 2))
                     (lambda () (let ((entry (log-entry *log* 1)))
                                  (when entry (apply-count entry "8"))))
                     (lambda () (note "demo: scripted scans done")))))
    (when (ext:getenv "UPC_LOGGER_DEMO_PROMPT")
      (setf steps (append steps (list (lambda () (edit-count (log-entry *log* 0)))))))
    (when (ext:getenv "UPC_LOGGER_DEMO_SHARE")
      ;; Write both files before offering them, so that a PDF that cannot be
      ;; drawn says so on the console instead of waiting for a finger.
      (setf steps (append steps
                          (list (lambda ()
                                  (dolist (writer (list #'write-csv #'write-pdf))
                                    (handler-case
                                        (let ((path (funcall writer)))
                                          (note "wrote ~a, ~:d bytes" path
                                                (or (ignore-errors
                                                     (with-open-file (in path :element-type '(unsigned-byte 8))
                                                       (file-length in)))
                                                    0)))
                                      (serious-condition (condition)
                                        (note "export failed: ~a" condition)))))
                                (lambda () (share-export *chart*))))))
    (ui:after-every 0.8 (lambda (timer)
                          (if steps
                              (funcall (pop steps))
                              (objc:invoke timer "invalidate"))))))

(defun start ()
  (objc:ensure-objc-initialized)
  (setf *random-state* (make-random-state t))
  (open-log)
  (let ((demo (ext:getenv "UPC_LOGGER_DEMO"))
        (root (ui:root-view)))
    (when demo
      (setf *log* (make-scan-log)))
    (setf *window* (default-window (get-universal-time))
          *follow* t
          *on-window-change* #'refresh-view)
    (objc:invoke root "setBackgroundColor:" (ui:system-color "systemBackground"))
    (let* ((scanner (build-scanner root))
           (chart (build-chart root scanner))
           (controls (build-controls root chart)))
      (build-list root controls))
    (start-camera)
    (when demo
      (demo)))
  (values))
