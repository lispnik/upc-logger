;;;; src/ios/scan-table.lisp -- a table of scans, told where its rows come from.
;;;;
;;;; One Objective-C class serves every table of entries in the app: it is
;;;; given a function returning the rows, and optionally what to do when one is
;;;; tapped or swiped away.  A second table -- a session, a single code's
;;;; history -- is then a call rather than another data source.
;;;;
;;;; The rows are cached rather than asked for per cell.  UIKit asks for the
;;;; count once and then for each cell, and a source that recomputed in between
;;;; could answer from two different lists; that mismatch is an exception
;;;; inside UIKit, where nothing can catch it.

(in-package #:upc-logger-ios)

(defstruct (scan-table (:constructor %make-scan-table (view source)))
  view
  source)

(objc:define-objc-class scan-table-source ()
  ((rows-function :initarg :rows :reader source-rows-function)
   (cache :initform '() :accessor source-cache)
   (select :initarg :select :initform nil :reader source-select)
   (remove-row :initarg :remove :initform nil :reader source-remove)
   (changed :initarg :changed :initform nil :reader source-changed))
  (:objc-class-name "UPCScanTableSource"))

(defun source-entry (source row)
  (nth row (source-cache source)))

(objc:define-objc-method ("tableView:numberOfRowsInSection:" (:signed :long-long))
    ((self scan-table-source) (table objc:objc-object-pointer) (section (:signed :long-long)))
  (declare (ignore table section))
  (handler-case (length (source-cache self))
    (serious-condition () 0)))

(defun configure-cell (cell entry)
  (objc:invoke (objc:invoke cell "textLabel") "setText:"
               (format-entry-title (entry-count entry) (entry-code entry)))
  (objc:invoke (objc:invoke cell "detailTextLabel") "setText:" (scan-subtitle entry)))

(defun scan-subtitle (entry)
  (let ((scanned (format-timestamp (entry-scanned-at entry))))
    (if (entry-bumped-p entry)
        (format nil "~a, last ~a" scanned
                (subseq (format-timestamp (entry-updated-at entry)) 11))
        scanned)))

(objc:define-objc-method ("tableView:cellForRowAtIndexPath:" objc:objc-object-pointer)
    ((self scan-table-source) (table objc:objc-object-pointer) (path objc:objc-object-pointer))
  (handler-case
      (let ((cell (objc:invoke table "dequeueReusableCellWithIdentifier:" "scan"))
            (entry (source-entry self (objc:invoke path "row"))))
        (when (cffi:null-pointer-p cell)
          (setf cell (objc:invoke (objc:invoke (objc:invoke "UITableViewCell" "alloc")
                                               "initWithStyle:reuseIdentifier:" 3 "scan") ; subtitle
                                  "autorelease"))
          (objc:invoke (objc:invoke cell "textLabel") "setFont:" (ui:mono-font 19 0.3))
          (objc:invoke (objc:invoke cell "detailTextLabel") "setFont:" (ui:font 12))
          (objc:invoke (objc:invoke cell "detailTextLabel") "setTextColor:"
                       (ui:system-color "secondaryLabel")))
        (when entry
          (configure-cell cell entry))
        cell)
    (serious-condition (condition)
      (note "cell: ~a" condition)
      ;; An empty cell is a bad row; no cell at all is a crash.
      (objc:invoke (objc:invoke (objc:invoke "UITableViewCell" "alloc")
                                "initWithStyle:reuseIdentifier:" 0 "scan")
                   "autorelease"))))

(objc:define-objc-method ("tableView:didSelectRowAtIndexPath:" :void)
    ((self scan-table-source) (table objc:objc-object-pointer) (path objc:objc-object-pointer))
  (handler-case
      (let ((entry (source-entry self (objc:invoke path "row")))
            (select (source-select self)))
        (objc:invoke table "deselectRowAtIndexPath:animated:" path t)
        (when (and entry select)
          (funcall select entry)))
    (serious-condition (condition)
      (note "select: ~a" condition))))

(objc:define-objc-method ("tableView:canEditRowAtIndexPath:" objc:objc-bool)
    ((self scan-table-source) (table objc:objc-object-pointer) (path objc:objc-object-pointer))
  (declare (ignore table path))
  ;; A BOOL is 1 or 0 across the bridge, never T.
  (if (source-remove self) 1 0))

(objc:define-objc-method ("tableView:commitEditingStyle:forRowAtIndexPath:" :void)
    ((self scan-table-source) (table objc:objc-object-pointer) (style (:signed :long-long))
     (path objc:objc-object-pointer))
  (handler-case
      (let ((entry (source-entry self (objc:invoke path "row")))
            (remove-row (source-remove self)))
        (when (and (= style 1) entry remove-row (funcall remove-row entry))
          ;; The cache has to lose the row before UIKit animates it away, or
          ;; the count it reads back will not match what it just removed.
          (setf (source-cache self) (remove entry (source-cache self)))
          (objc:invoke table "deleteRowsAtIndexPaths:withRowAnimation:"
                       (objc:invoke "NSArray" "arrayWithObject:" path) 100)
          (when (source-changed self)
            (funcall (source-changed self)))))
    (serious-condition (condition)
      (note "delete: ~a" condition))))

;;; The component ---------------------------------------------------------------

(defun make-scan-table (&key rows select remove changed)
  "A table view showing whatever ROWS returns, a list of entries.

SELECT is called with the entry that was tapped.  REMOVE, if given, turns on
swipe to delete and is called with the entry; returning true lets the row go.
CHANGED is called after the table has changed itself, for whatever is showing
totals elsewhere."
  (let* ((view (objc:invoke (objc:invoke (objc:invoke "UITableView" "alloc")
                                         "initWithFrame:style:" (vector 0d0 0d0 0d0 0d0) 0)
                            "autorelease"))
         ;; A table view holds its source and delegate weakly.
         (source (ui:keep (make-instance 'scan-table-source
                                         :rows rows :select select
                                         :remove remove :changed changed)))
         (table (%make-scan-table view source)))
    (objc:invoke view "setTranslatesAutoresizingMaskIntoConstraints:" nil)
    (let ((pointer (objc:objc-object-pointer source)))
      (objc:invoke view "setDataSource:" pointer)
      (objc:invoke view "setDelegate:" pointer))
    (scan-table-reload table)
    table))

(defun scan-table-reload (table)
  (let ((source (scan-table-source table)))
    (setf (source-cache source) (funcall (source-rows-function source)))
    (objc:invoke (scan-table-view table) "reloadData")))

(defun scan-table-scroll-to-top (table)
  (when (plusp (length (source-cache (scan-table-source table))))
    (objc:invoke (scan-table-view table) "scrollToRowAtIndexPath:atScrollPosition:animated:"
                 (objc:invoke "NSIndexPath" "indexPathForRow:inSection:" 0 0) 1 t)))
