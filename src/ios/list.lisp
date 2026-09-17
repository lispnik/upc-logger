;;;; src/ios/list.lisp -- the scans in the visible range, and what a row carries.
;;;;
;;;; The table is the reusable one from scan-table.lisp; what is app-specific
;;;; is here.  The rows are the log filtered to the chart's window; tapping a
;;;; row asks for a count, which is the thing done most often and so keeps the
;;;; plain tap; the detail button opens everything else -- a name, a note, a
;;;; photo -- and a swipe deletes.
;;;;
;;;; Every one of these works on the ENTRY rather than the row number, because
;;;; a scan can arrive while a prompt is open and push every row down one.

(in-package #:upc-logger-ios)

(defvar *table* nil "The SCAN-TABLE below the chart.")
(defvar *summary* nil)
(defvar *menu-blocks* '()
  "The open menu's handler blocks.  UIKit copies what it keeps, so the
originals are needed only until the next menu replaces them.")

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

(defun entry-index (entry)
  (position entry (scan-log-entries *log*)))

(defun remove-entry (entry)
  "Take ENTRY out of the log wherever it now sits.  True if it was there."
  (let ((index (entry-index entry)))
    (when index
      (delete-entry *log* index)
      (save)
      t)))

(defun change-entry (entry function)
  "Apply FUNCTION to ENTRY's current row, then save and show the result."
  (let ((index (entry-index entry)))
    (when index
      (funcall function index)
      (save)
      (refresh-list)
      (redraw-chart))))

;;; Prompts -----------------------------------------------------------------------

(defun text-prompt (title message initial setter)
  "An alert with one text field, holding INITIAL, whose text goes to SETTER."
  (let ((alert (objc:invoke "UIAlertController" "alertControllerWithTitle:message:preferredStyle:"
                            title message 1)))
    (objc:with-objc-block (setup 'text-field-setup
                                 (lambda (field)
                                   (handler-case
                                       (progn
                                         (objc:invoke field "setText:" (or initial ""))
                                         (objc:invoke field "setFont:" (ui:font 17))
                                         (objc:invoke field "setClearButtonMode:" 1)
                                         ;; Sentence case: a name or a note is prose.
                                         (objc:invoke field "setAutocapitalizationType:" 1))
                                     (serious-condition (condition)
                                       (note "prompt field: ~a" condition)))))
      (objc:invoke alert "addTextFieldWithConfigurationHandler:" setup))
    (objc:with-objc-block (on-save 'alert-action-handler
                                   (lambda (action)
                                     (declare (ignore action))
                                     (handler-case
                                         (let ((field (objc:invoke (objc:invoke alert "textFields")
                                                                   "firstObject")))
                                           (funcall setter (objc:ns-string-to-string
                                                            (objc:invoke field "text"))))
                                       (serious-condition (condition)
                                         (note "prompt: ~a" condition)))))
      (let ((save (objc:invoke "UIAlertAction" "actionWithTitle:style:handler:"
                               "Save" 0 on-save)))
        (objc:invoke alert "addAction:"
                     (objc:invoke "UIAlertAction" "actionWithTitle:style:handler:"
                                  "Cancel" 1 nil))
        (objc:invoke alert "addAction:" save)
        (objc:invoke alert "setPreferredAction:" save)))
    (objc:invoke (ui:root-controller) "presentViewController:animated:completion:" alert t nil)))

(defun apply-count (entry text)
  "Set ENTRY's count from TEXT as typed.  Blank or not a number: no change."
  (let ((count (and text (ignore-errors (parse-integer (string-trim " " text))))))
    (when count
      (change-entry entry (lambda (index) (set-count *log* index count))))))

(defun edit-count (entry)
  (let ((alert (objc:invoke "UIAlertController" "alertControllerWithTitle:message:preferredStyle:"
                            (entry-code entry)
                            (format nil "Scanned ~a.~%How many? 0 removes it."
                                    (format-timestamp (entry-scanned-at entry)))
                            1)))
    (objc:with-objc-block (setup 'text-field-setup
                                 (lambda (field)
                                   (handler-case
                                       (progn
                                         (objc:invoke field "setKeyboardType:" 4) ; number pad
                                         ;; Placeholder, not text: typing 8 must mean 8, not 18.
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

(defun edit-name (entry)
  (text-prompt (entry-code entry)
               "What is this? The name sticks to the code, so every scan of it
shows the same name."
               (entry-name entry)
               (lambda (text)
                 (change-entry entry (lambda (index) (set-name *log* index text))))))

(defun edit-note (entry)
  (text-prompt (or (entry-name entry) (entry-code entry))
               "A note about this scan."
               (entry-note entry)
               (lambda (text)
                 (change-entry entry (lambda (index) (set-note *log* index text))))))

(defun attach-photo (entry)
  (pick-photo (lambda (name)
                (when name
                  (change-entry entry (lambda (index) (set-photo *log* index name)))))))

(defun clear-photo (entry)
  (change-entry entry (lambda (index) (set-photo *log* index nil))))

;;; The row menu --------------------------------------------------------------------

(defun anchor-sheet (controller)
  "On an iPad a sheet is a popover, and a popover with no anchor is a crash."
  (let ((popover (objc:invoke controller "popoverPresentationController")))
    (unless (cffi:null-pointer-p popover)
      (let ((view (scan-table-view *table*)))
        (objc:invoke popover "setSourceView:" view)
        (objc:invoke popover "setSourceRect:" (objc:invoke view "bounds"))))))

(defun menu-action (sheet title function &optional (style 0))
  (let ((block (objc:make-objc-block
                'alert-action-handler
                (lambda (action)
                  (declare (ignore action))
                  (handler-case (funcall function)
                    (serious-condition (condition) (note "menu: ~a" condition)))))))
    (push block *menu-blocks*)
    (objc:invoke sheet "addAction:"
                 (objc:invoke "UIAlertAction" "actionWithTitle:style:handler:"
                              title style block))))

(defun row-menu (entry)
  "The detail button: everything a row carries besides its count."
  ;; The last menu's blocks are done with; only one sheet is ever open.
  (dolist (block *menu-blocks*)
    (ignore-errors (objc:free-objc-block block)))
  (setf *menu-blocks* '())
  (let ((sheet (objc:invoke "UIAlertController" "alertControllerWithTitle:message:preferredStyle:"
                            (or (entry-name entry) (entry-code entry))
                            (format nil "~a~@[~%~a~]"
                                    (format-entry-title (entry-count entry) (entry-code entry))
                                    (entry-note entry))
                            0)))                                  ; action sheet
    (menu-action sheet "Set count" (lambda () (edit-count entry)))
    (menu-action sheet (if (entry-name entry) "Rename" "Name this code")
                 (lambda () (edit-name entry)))
    (menu-action sheet (if (entry-note entry) "Edit note" "Add a note")
                 (lambda () (edit-note entry)))
    (menu-action sheet (if (photo-exists-p (entry-photo entry)) "Replace photo" "Add a photo")
                 (lambda () (attach-photo entry)))
    (when (entry-photo entry)
      (menu-action sheet "Remove photo" (lambda () (clear-photo entry)) 2)) ; destructive
    (menu-action sheet "Cancel" (lambda () nil) 1)
    (anchor-sheet sheet)
    (objc:invoke (ui:root-controller) "presentViewController:animated:completion:" sheet t nil)))

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
                                 :info #'row-menu
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
