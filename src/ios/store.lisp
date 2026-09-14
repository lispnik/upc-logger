;;;; src/ios/store.lisp -- where the log lives on the phone.
;;;;
;;;; The app's Documents directory, which is backed up, survives updates, and
;;;; is where a later spreadsheet export will want to write beside it.

(in-package #:upc-logger-ios)

(defvar *log* (make-scan-log))
(defvar *log-path* nil)

(defun note (format &rest arguments)
  "A line on the console, for simctl launch --console-pty and Console.app."
  (format t "~&UPC-LOGGER: ~?~%" format arguments)
  (finish-output))

(defun documents-directory ()
  (let* ((manager (objc:invoke "NSFileManager" "defaultManager"))
         ;; NSDocumentDirectory, NSUserDomainMask
         (urls (objc:invoke manager "URLsForDirectory:inDomains:" 9 1))
         (path (objc:ns-string-to-string
                (objc:invoke (objc:invoke urls "firstObject") "path"))))
    (pathname (concatenate 'string (string-right-trim "/" path) "/"))))

(defun open-log ()
  (setf *log-path* (merge-pathnames "scans.sexp" (documents-directory)))
  (multiple-value-bind (log status) (load-log *log-path*)
    (setf *log* log)
    (note "log ~(~a~), ~d entries, at ~a" status (log-length log) *log-path*)))

(defun save ()
  (handler-case (save-log *log* *log-path*)
    (error (condition)
      (note "could not save: ~a" condition))))
