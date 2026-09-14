;;;; src/ios/app.lisp -- the entry point: camera on top, scans below.

(in-package #:upc-logger-ios)

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
    (objc:invoke root "setBackgroundColor:" (ui:system-color "systemBackground"))
    (build-list root (build-scanner root))
    (start-camera)
    (when demo
      (demo)))
  (values))
