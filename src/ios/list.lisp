;;;; src/ios/list.lisp -- the rows in the visible range, and what they carry.
;;;;
;;;; The table is the reusable one from scan-table.lisp, and a row is a GROUP:
;;;; one scan, or a run of them drawn as one.  Tapping a row asks for a count,
;;;; which is done most often and so keeps the plain tap; the detail button
;;;; opens everything else -- a name, a note, a photo -- and a swipe deletes.
;;;;
;;;; Every edit acts on the group's newest event, and the prompts say so.  A
;;;; count typed onto a run of three would otherwise have to invent how to
;;;; spread itself over three scans, and any answer to that is a guess.

(in-package #:upc-logger-ios)

(defvar *table* nil "The SCAN-TABLE below the chart.")
(defvar *summary* nil)
(defvar *menu-blocks* '()
  "The open menu's handler blocks.  UIKit copies what it keeps, so the
originals are needed only until the next menu replaces them.")

(objc:define-objc-block-type text-field-setup :void (objc:objc-object-pointer))
(objc:define-objc-block-type alert-action-handler :void (objc:objc-object-pointer))

(defun update-summary ()
  (let ((groups (visible-groups)))
    (objc:invoke *summary* "setText:"
                 (cond ((and (null groups) *query*)
                        (format nil "Nothing matches ~s" *query*))
                       ((null groups) "No scans in this range")
                       (*query* (format nil "~a matching ~s" (export-summary groups) *query*))
                       (t (export-summary groups))))))

(defun refresh-list ()
  (when *table*
    (scan-table-reload *table*))
  (update-summary))

(defun event-index (event)
  (position event (scan-log-entries *log*)))

(defun remove-group (group)
  "Take every scan behind GROUP out of the log.  True if any went."
  (let ((removed nil))
    (dolist (event (group-events group) removed)
      (let ((index (event-index event)))
        (when index
          (delete-entry *log* index)
          (setf removed t))))
    (when removed
      (save))
    removed))

(defun change-event (event function)
  "Apply FUNCTION to EVENT's current index, then save and show the result."
  (let ((index (event-index event)))
    (when index
      (funcall function index)
      (save)
      (refresh-list)
      (redraw-chart))))

(defun change-group (group function)
  (change-event (group-first-event group) function))

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

(defun apply-count (group text)
  "Set the newest scan in GROUP to TEXT items.  Blank or not a number: nothing."
  (let ((count (and text (ignore-errors (parse-integer (string-trim " " text))))))
    (when count
      (change-group group (lambda (index) (set-count *log* index count))))))

(defun edit-count (group)
  (let* ((event (group-first-event group))
         (alert (objc:invoke "UIAlertController" "alertControllerWithTitle:message:preferredStyle:"
                             (group-code group)
                             (if (group-merged-p group)
                                 (format nil "~d scans here. How many items on the last one, at ~a? 0 removes it."
                                         (group-scans group)
                                         (subseq (format-timestamp (entry-at event)) 11))
                                 (format nil "Scanned ~a.~%How many? 0 removes it."
                                         (format-timestamp (entry-at event))))
                             1)))
    (objc:with-objc-block (setup 'text-field-setup
                                 (lambda (field)
                                   (handler-case
                                       (progn
                                         (objc:invoke field "setKeyboardType:" 4) ; number pad
                                         ;; Placeholder, not text: typing 8 must mean 8, not 18.
                                         (objc:invoke field "setPlaceholder:"
                                                      (princ-to-string (entry-count event)))
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
                                          (apply-count group (objc:ns-string-to-string
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

(defun edit-name (group)
  (text-prompt (group-code group)
               "What is this? The name sticks to the code, so every scan of it
shows the same name."
               (group-name group)
               (lambda (text)
                 (change-group group (lambda (index) (set-name *log* index text))))))

(defun edit-note (group)
  (text-prompt (or (group-name group) (group-code group))
               (if (group-merged-p group)
                   "A note about the last scan in this run. It will show as its own row."
                   "A note about this scan.")
               (group-note group)
               (lambda (text)
                 (change-group group (lambda (index) (set-note *log* index text))))))

(defun attach-photo (group)
  (pick-photo (lambda (name)
                (when name
                  (change-group group (lambda (index) (set-photo *log* index name)))))))

(defun clear-photo (group)
  (let ((old (group-photo group)))
    (change-group group (lambda (index) (set-photo *log* index nil)))
    (delete-photo-file old)))

(defun photo-tapped (group)
  "The picture on a row, full screen, with the two things worth doing to it."
  (let ((old (group-photo group)))
    (when (photo-exists-p old)
      (show-photo (photo-file-path old)
                  :on-replace
                  (lambda (presenter)
                    ;; Presented from the viewer: the root controller has the
                    ;; viewer over it and cannot present anything itself.
                    (pick-photo (lambda (name)
                                  (when name
                                    (change-group group
                                                  (lambda (index) (set-photo *log* index name)))
                                    (delete-photo-file old)
                                    (viewer-show-file (photo-file-path name))))
                                presenter))
                  :on-delete
                  (lambda ()
                    (change-group group (lambda (index) (set-photo *log* index nil)))
                    (delete-photo-file old))))))

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

(defun row-menu (group)
  "The detail button: everything a row carries besides its count."
  ;; The last menu's blocks are done with; only one sheet is ever open.
  (dolist (block *menu-blocks*)
    (ignore-errors (objc:free-objc-block block)))
  (setf *menu-blocks* '())
  (let ((sheet (objc:invoke "UIAlertController" "alertControllerWithTitle:message:preferredStyle:"
                            (or (group-name group) (group-code group))
                            (format nil "~a~@[~%~a~]~@[~%~a~]"
                                    (format-entry-title (group-count group) (group-code group))
                                    (when (group-merged-p group)
                                      (format nil "~d scans; a note or a photo goes on the last one and gives it its own row."
                                              (group-scans group)))
                                    (group-note group))
                            0)))                                  ; action sheet
    (menu-action sheet "Set count" (lambda () (edit-count group)))
    (menu-action sheet (if (group-name group) "Rename" "Name this code")
                 (lambda () (edit-name group)))
    (menu-action sheet (if (group-note group) "Edit note" "Add a note")
                 (lambda () (edit-note group)))
    (menu-action sheet (if (photo-exists-p (group-photo group)) "Replace photo" "Add a photo")
                 (lambda () (attach-photo group)))
    (when (group-photo group)
      (menu-action sheet "Remove photo" (lambda () (clear-photo group)) 2)) ; destructive
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

(defun build-list (root above below)
  "The summary and the table, filling what is left between ABOVE and BELOW."
  (setf *summary* (ui:new "UILabel"))
  (objc:invoke *summary* "setFont:" (ui:font 13 0.3))
  (objc:invoke *summary* "setTextColor:" (ui:system-color "secondaryLabel"))
  (objc:invoke root "addSubview:" *summary*)
  (ui:pin *summary* "topAnchor" above "bottomAnchor" 8)
  (ui:pin *summary* "leadingAnchor" root "leadingAnchor" 20)
  (ui:pin *summary* "trailingAnchor" root "trailingAnchor" -20)
  (setf *table* (make-scan-table :rows #'visible-groups
                                 :select #'edit-count
                                 :info #'row-menu
                                 :image-tap #'photo-tapped
                                 :remove #'remove-group
                                 :changed (lambda ()
                                            (update-summary)
                                            (redraw-chart))))
  (let ((view (scan-table-view *table*)))
    (objc:invoke root "addSubview:" view)
    (ui:pin view "topAnchor" *summary* "bottomAnchor" 6)
    (ui:pin view "leadingAnchor" root "leadingAnchor")
    (ui:pin view "trailingAnchor" root "trailingAnchor")
    ;; The search bar, not the bottom of the screen: the table stops where it
    ;; begins, and the bar rides up with the keyboard.
    (ui:pin view "bottomAnchor" below "topAnchor"))
  (update-summary))
