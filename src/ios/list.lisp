;;;; src/ios/list.lisp -- the scans, and changing how many.
;;;;
;;;; A UITableView whose data source and delegate are one Lisp-defined class.
;;;; Row I is entry I of the log, which is newest first, so a new scan is an
;;;; insert at row 0 and a bump is a reload of row 0.
;;;;
;;;; Tapping a row asks for a count in an alert with a number pad.  The field
;;;; starts empty with the current count as its placeholder, so typing 8 means
;;;; 8 -- not 18, which is what a prefilled "1" would give.

(in-package #:upc-logger-ios)

(defvar *table* nil)
(defvar *summary* nil)
(defvar *list-source* nil)

(objc:define-objc-block-type text-field-setup :void (objc:objc-object-pointer))
(objc:define-objc-block-type alert-action-handler :void (objc:objc-object-pointer))

(defun index-path (row)
  (objc:invoke "NSIndexPath" "indexPathForRow:inSection:" row 0))

(defun update-summary ()
  (let ((rows (log-length *log*)))
    (objc:invoke *summary* "setText:"
                 (if (zerop rows)
                     "Point the camera at a barcode"
                     (format nil "~d scan~:p, ~d item~:p" rows (total-items *log*))))))

(defun subtitle (entry)
  (let ((scanned (format-timestamp (entry-scanned-at entry))))
    (if (entry-bumped-p entry)
        (format nil "~a, last ~a" scanned
                (subseq (format-timestamp (entry-updated-at entry)) 11))
        scanned)))

;;; The data source and delegate ----------------------------------------------

(objc:define-objc-class list-source () ()
  (:objc-class-name "UPCListSource"))

(objc:define-objc-method ("tableView:numberOfRowsInSection:" (:signed :long-long))
    ((self list-source) (table objc:objc-object-pointer) (section (:signed :long-long)))
  (declare (ignore table section))
  (handler-case (log-length *log*)
    (serious-condition () 0)))

(objc:define-objc-method ("tableView:cellForRowAtIndexPath:" objc:objc-object-pointer)
    ((self list-source) (table objc:objc-object-pointer) (path objc:objc-object-pointer))
  (handler-case
      (let ((cell (objc:invoke table "dequeueReusableCellWithIdentifier:" "scan"))
            (entry (log-entry *log* (objc:invoke path "row"))))
        (when (cffi:null-pointer-p cell)
          (setf cell (objc:invoke (objc:invoke (objc:invoke "UITableViewCell" "alloc")
                                               "initWithStyle:reuseIdentifier:" 3 "scan") ; subtitle
                                  "autorelease"))
          (objc:invoke (objc:invoke cell "textLabel") "setFont:" (ui:mono-font 19 0.3))
          (objc:invoke (objc:invoke cell "detailTextLabel") "setFont:" (ui:font 12))
          (objc:invoke (objc:invoke cell "detailTextLabel") "setTextColor:"
                       (ui:system-color "secondaryLabel")))
        (when entry
          (objc:invoke (objc:invoke cell "textLabel") "setText:"
                       (format-entry-title (entry-count entry) (entry-code entry)))
          (objc:invoke (objc:invoke cell "detailTextLabel") "setText:" (subtitle entry)))
        cell)
    (serious-condition (condition)
      ;; An empty cell is a bad row; no cell at all is a crash.
      (note "cell: ~a" condition)
      (objc:invoke (objc:invoke (objc:invoke "UITableViewCell" "alloc")
                                "initWithStyle:reuseIdentifier:" 0 "scan")
                   "autorelease"))))

(objc:define-objc-method ("tableView:didSelectRowAtIndexPath:" :void)
    ((self list-source) (table objc:objc-object-pointer) (path objc:objc-object-pointer))
  (handler-case
      (let ((entry (log-entry *log* (objc:invoke path "row"))))
        (objc:invoke table "deselectRowAtIndexPath:animated:" path t)
        (when entry
          (edit-count entry)))
    (serious-condition (condition)
      (note "select: ~a" condition))))

(objc:define-objc-method ("tableView:commitEditingStyle:forRowAtIndexPath:" :void)
    ((self list-source) (table objc:objc-object-pointer) (style (:signed :long-long))
     (path objc:objc-object-pointer))
  ;; Implementing this is what turns on swipe-to-delete.
  (handler-case
      (when (and (= style 1)                               ; UITableViewCellEditingStyleDelete
                 (delete-entry *log* (objc:invoke path "row")))
        (save)
        (objc:invoke table "deleteRowsAtIndexPaths:withRowAnimation:"
                     (objc:invoke "NSArray" "arrayWithObject:" path) 100) ; automatic
        (update-summary))
    (serious-condition (condition)
      (note "delete: ~a" condition))))

(defun install-list-source (table)
  ;; A table view holds both of these weakly.
  (setf *list-source* (ui:keep (make-instance 'list-source)))
  (let ((pointer (objc:objc-object-pointer *list-source*)))
    (objc:invoke table "setDataSource:" pointer)
    (objc:invoke table "setDelegate:" pointer)))

;;; After a scan ----------------------------------------------------------------

(defun show-scan (how)
  "Bring the table up to date with a scan RECORD-SCAN reported as HOW."
  (let ((top (objc:invoke "NSArray" "arrayWithObject:" (index-path 0))))
    (ecase how
      (:new (objc:invoke *table* "insertRowsAtIndexPaths:withRowAnimation:" top 3))     ; top
      (:bumped (objc:invoke *table* "reloadRowsAtIndexPaths:withRowAnimation:" top 0))) ; fade
    (objc:invoke *table* "scrollToRowAtIndexPath:atScrollPosition:animated:"
                 (index-path 0) 1 t)                                                    ; top
    (update-summary)))

;;; Editing a count -------------------------------------------------------------

(defun apply-count (entry text)
  "Set ENTRY's count from TEXT as typed.  Blank or not a number: no change.

ENTRY rather than a row number, because a scan can arrive while the alert is
up and push every row down one."
  (let ((index (position entry (scan-log-entries *log*)))
        (count (and text (ignore-errors (parse-integer (string-trim " " text))))))
    (when (and index count (nth-value 1 (set-count *log* index count)))
      (save)
      (objc:invoke *table* "reloadData")
      (update-summary))))

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
                                         (objc:invoke field "setKeyboardType:" 4) ; UIKeyboardTypeNumberPad
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
                                  "Cancel" 1 nil))                  ; UIAlertActionStyleCancel
        (objc:invoke alert "addAction:" set-action)
        (objc:invoke alert "setPreferredAction:" set-action)))
    (objc:invoke (ui:root-controller) "presentViewController:animated:completion:" alert t nil)))

(defun build-list (root scanner)
  (setf *summary* (ui:new "UILabel"))
  (objc:invoke *summary* "setFont:" (ui:font 13 0.3))
  (objc:invoke *summary* "setTextColor:" (ui:system-color "secondaryLabel"))
  (objc:invoke root "addSubview:" *summary*)
  (ui:pin *summary* "topAnchor" scanner "bottomAnchor" 10)
  (ui:pin *summary* "leadingAnchor" root "leadingAnchor" 20)
  (ui:pin *summary* "trailingAnchor" root "trailingAnchor" -20)
  (setf *table* (objc:invoke (objc:invoke (objc:invoke "UITableView" "alloc")
                                          "initWithFrame:style:" (vector 0d0 0d0 0d0 0d0) 0)
                             "autorelease"))
  (objc:invoke *table* "setTranslatesAutoresizingMaskIntoConstraints:" nil)
  (objc:invoke root "addSubview:" *table*)
  (ui:pin *table* "topAnchor" *summary* "bottomAnchor" 6)
  (ui:pin *table* "leadingAnchor" root "leadingAnchor")
  (ui:pin *table* "trailingAnchor" root "trailingAnchor")
  (ui:pin *table* "bottomAnchor" root "bottomAnchor")
  (install-list-source *table*)
  (update-summary))
