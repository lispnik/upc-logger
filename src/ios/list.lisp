;;;; src/ios/list.lisp -- the scans in the visible range, and changing a count.
;;;;
;;;; The table is the reusable one from scan-table.lisp; what is app-specific
;;;; is here: the rows are the log filtered to the chart's window, a tap asks
;;;; for a count on a number pad, and a swipe deletes.
;;;;
;;;; The alert works on the entry rather than the row number, because a scan
;;;; can arrive while it is open and push every row down one.

(in-package #:upc-logger-ios)

(defvar *table* nil "The SCAN-TABLE below the chart.")
(defvar *summary* nil)

(objc:define-objc-block-type text-field-setup :void (objc:objc-object-pointer))
(objc:define-objc-block-type alert-action-handler :void (objc:objc-object-pointer))

(defun update-summary ()
  (let ((entries (visible-entries)))
    (objc:invoke *summary* "setText:"
                 (if (null entries)
                     "No scans in this range"
                     (export-summary entries)))))

(defun refresh-list ()
  (when *table*
    (scan-table-reload *table*))
  (update-summary))

(defun remove-entry (entry)
  "Take ENTRY out of the log wherever it now sits.  True if it was there."
  (let ((index (position entry (scan-log-entries *log*))))
    (when index
      (delete-entry *log* index)
      (save)
      t)))

;;; Setting a count ---------------------------------------------------------------

(defun apply-count (entry text)
  "Set ENTRY's count from TEXT as typed.  Blank or not a number: no change."
  (let ((index (position entry (scan-log-entries *log*)))
        (count (and text (ignore-errors (parse-integer (string-trim " " text))))))
    (when (and index count (nth-value 1 (set-count *log* index count)))
      (save)
      (refresh-list)
      (redraw-chart))))

(defun edit-count (entry)
  (let ((alert (objc:invoke "UIAlertController" "alertControllerWithTitle:message:preferredStyle:"
                            (entry-code entry)
                            (format nil "Scanned ~a.~%How many? 0 removes it."
                                    (format-timestamp (entry-scanned-at entry)))
                            1)))                                    ; UIAlertControllerStyleAlert
    (objc:with-objc-block (setup 'text-field-setup
                                 (lambda (field)
                                   (handler-case
                                       (progn
                                         (objc:invoke field "setKeyboardType:" 4) ; number pad
                                         (objc:invoke field "setPlaceholder:"
                                                      (princ-to-string (entry-count entry)))
                                         (objc:invoke field "setTextAlignment:" 1)
                                         (objc:invoke field "setFont:" (ui:mono-font 22)))
                                     (serious-condition (condition)
                                       (note "count field: ~a" condition)))))
      (objc:invoke alert "addTextFieldWithConfigurationHandler:" setup))
    (objc:with-objc-block (on-set 'alert-action-handler
                                  (lambda (action)
                                    (declare (ignore action))
                                    (handler-case
                                        (let ((field (objc:invoke (objc:invoke alert "textFields")
                                                                  "firstObject")))
                                          (apply-count entry (objc:ns-string-to-string
                                                              (objc:invoke field "text"))))
                                      (serious-condition (condition)
                                        (note "set count: ~a" condition)))))
      (let ((set-action (objc:invoke "UIAlertAction" "actionWithTitle:style:handler:"
                                     "Set" 0 on-set)))
        (objc:invoke alert "addAction:"
                     (objc:invoke "UIAlertAction" "actionWithTitle:style:handler:"
                                  "Cancel" 1 nil))
        (objc:invoke alert "addAction:" set-action)
        (objc:invoke alert "setPreferredAction:" set-action)))
    (objc:invoke (ui:root-controller) "presentViewController:animated:completion:" alert t nil)))

;;; After a scan -------------------------------------------------------------------

(defun show-scan (how)
  "Bring the chart and the table up to date with a scan reported as HOW."
  (declare (ignore how))
  (follow-new-scan)
  (notify-window-change)
  (when *table*
    (scan-table-scroll-to-top *table*)))

(defun build-list (root above)
  (setf *summary* (ui:new "UILabel"))
  (objc:invoke *summary* "setFont:" (ui:font 13 0.3))
  (objc:invoke *summary* "setTextColor:" (ui:system-color "secondaryLabel"))
  (objc:invoke root "addSubview:" *summary*)
  (ui:pin *summary* "topAnchor" above "bottomAnchor" 8)
  (ui:pin *summary* "leadingAnchor" root "leadingAnchor" 20)
  (ui:pin *summary* "trailingAnchor" root "trailingAnchor" -20)
  (setf *table* (make-scan-table :rows #'visible-entries
                                 :select #'edit-count
                                 :remove #'remove-entry
                                 :changed (lambda ()
                                            (update-summary)
                                            (redraw-chart))))
  (let ((view (scan-table-view *table*)))
    (objc:invoke root "addSubview:" view)
    (ui:pin view "topAnchor" *summary* "bottomAnchor" 6)
    (ui:pin view "leadingAnchor" root "leadingAnchor")
    (ui:pin view "trailingAnchor" root "trailingAnchor")
    (ui:pin view "bottomAnchor" root "bottomAnchor"))
  (update-summary))
