;;;; src/ios/scan-table.lisp -- a table of scans, told where its rows come from.
;;;;
;;;; A row is a GROUP: one scan, or a run of them drawn as one.  The source is
;;;; given a function returning the rows and, optionally, what to do when one
;;;; is tapped, swiped away, or has its detail button pressed -- so a second
;;;; table of scans is a call rather than another data source.
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
   (info :initarg :info :initform nil :reader source-info)
   (image-tap :initarg :image-tap :initform nil :reader source-image-tap)
   (view :initform nil :accessor source-view)
   (changed :initarg :changed :initform nil :reader source-changed))
  (:objc-class-name "UPCScanTableSource"))

(defun thumbnail-tapped (source recognizer)
  "Which row's picture was tapped.  Asked of the table by where the touch
landed, because cells are reused and a recognizer cannot hold a row number."
  (handler-case
      (let* ((table (source-view source))
             (point (objc:invoke recognizer "locationInView:" table))
             (path (objc:invoke table "indexPathForRowAtPoint:" point)))
        (unless (cffi:null-pointer-p path)
          (let ((group (source-group source (objc:invoke path "row"))))
            (when (and group (source-image-tap source))
              (funcall (source-image-tap source) group)))))
    (serious-condition (condition)
      (note "thumbnail: ~a" condition))))

(defun source-group (source row)
  (nth row (source-cache source)))

(objc:define-objc-method ("tableView:numberOfRowsInSection:" (:signed :long-long))
    ((self scan-table-source) (table objc:objc-object-pointer) (section (:signed :long-long)))
  (declare (ignore table section))
  (handler-case (length (source-cache self))
    (serious-condition () 0)))

(defun group-subtitle (group)
  "The name, the note, and when it happened -- a span when the row is a run."
  (let ((when (if (group-merged-p group)
                  (format nil "~d scans, ~a to ~a"
                          (group-scans group)
                          (format-timestamp (group-earliest group))
                          (subseq (format-timestamp (group-latest group)) 11))
                  (format-timestamp (group-earliest group)))))
    (format nil "~@[~a~%~]~@[~a. ~]~a" (group-name group) (group-note group) when)))

(defun configure-cell (cell group)
  (objc:invoke (objc:invoke cell "textLabel") "setText:"
               (format-entry-title (group-count group) (group-code group)))
  (objc:invoke (objc:invoke cell "detailTextLabel") "setText:" (group-subtitle group))
  ;; The thumbnail has to be cleared as well as set: cells are reused, and a
  ;; row with no photo would otherwise show the last one's.
  ;; Its own picture if it has one, otherwise the set's -- which every scan of
  ;; a photographed run carries, so each row shows it when rows are per scan.
  (let ((view (objc:invoke cell "imageView"))
        (photo (group-display-photo group)))
    (if (photo-exists-p photo)
        (objc:invoke view "setImage:"
                     (objc:invoke "UIImage" "imageWithContentsOfFile:" (photo-file-path photo)))
        (objc:invoke view "setImage:" nil))
    (objc:invoke view "setClipsToBounds:" t)
    (objc:invoke view "setContentMode:" 2)              ; scale aspect fill
    (objc:invoke (objc:invoke view "layer") "setCornerRadius:" 6d0)))

(objc:define-objc-method ("tableView:cellForRowAtIndexPath:" objc:objc-object-pointer)
    ((self scan-table-source) (table objc:objc-object-pointer) (path objc:objc-object-pointer))
  (handler-case
      (let ((cell (objc:invoke table "dequeueReusableCellWithIdentifier:" "scan"))
            (group (source-group self (objc:invoke path "row"))))
        (when (cffi:null-pointer-p cell)
          (setf cell (objc:invoke (objc:invoke (objc:invoke "UITableViewCell" "alloc")
                                               "initWithStyle:reuseIdentifier:" 3 "scan") ; subtitle
                                  "autorelease"))
          (objc:invoke (objc:invoke cell "textLabel") "setFont:" (ui:mono-font 19 0.3))
          (let ((detail (objc:invoke cell "detailTextLabel")))
            (objc:invoke detail "setFont:" (ui:font 12))
            (objc:invoke detail "setNumberOfLines:" 2)
            (objc:invoke detail "setTextColor:" (ui:system-color "secondaryLabel")))
          ;; 4 is the detail button. 3 is a checkmark, which is not a button at
          ;; all: the row showed a tick and the menu could not be reached.
          (when (source-info self)
            (objc:invoke cell "setAccessoryType:" 4))
          ;; The picture opens itself; the rest of the row still sets the count.
          (when (source-image-tap self)
            (let ((thumbnail (objc:invoke cell "imageView"))
                  (source self))
              (objc:invoke thumbnail "setUserInteractionEnabled:" t)
              (objc:invoke thumbnail "addGestureRecognizer:"
                           (ui:keep (objc:invoke (objc:invoke "UITapGestureRecognizer" "alloc")
                                                 "initWithTarget:action:"
                                                 (ui:action-target
                                                  (lambda (recognizer)
                                                    (thumbnail-tapped source recognizer)))
                                                 "fire:"))))))
        (when group
          (configure-cell cell group))
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
      (let ((group (source-group self (objc:invoke path "row")))
            (select (source-select self)))
        (objc:invoke table "deselectRowAtIndexPath:animated:" path t)
        (when (and group select)
          (funcall select group)))
    (serious-condition (condition)
      (note "select: ~a" condition))))

(objc:define-objc-method ("tableView:accessoryButtonTappedForRowWithIndexPath:" :void)
    ((self scan-table-source) (table objc:objc-object-pointer) (path objc:objc-object-pointer))
  (declare (ignore table))
  (handler-case
      (let ((group (source-group self (objc:invoke path "row")))
            (info (source-info self)))
        (when (and group info)
          (funcall info group)))
    (serious-condition (condition)
      (note "detail: ~a" condition))))

(objc:define-objc-method ("tableView:canEditRowAtIndexPath:" objc:objc-bool)
    ((self scan-table-source) (table objc:objc-object-pointer) (path objc:objc-object-pointer))
  (declare (ignore table path))
  ;; A BOOL is 1 or 0 across the bridge, never T.
  (if (source-remove self) 1 0))

(objc:define-objc-method ("tableView:commitEditingStyle:forRowAtIndexPath:" :void)
    ((self scan-table-source) (table objc:objc-object-pointer) (style (:signed :long-long))
     (path objc:objc-object-pointer))
  (handler-case
      (let ((group (source-group self (objc:invoke path "row")))
            (remove-row (source-remove self)))
        (when (and (= style 1) group remove-row (funcall remove-row group))
          ;; The cache has to lose the row before UIKit animates it away, or
          ;; the count it reads back will not match what it just removed.
          (setf (source-cache self) (remove group (source-cache self)))
          (objc:invoke table "deleteRowsAtIndexPaths:withRowAnimation:"
                       (objc:invoke "NSArray" "arrayWithObject:" path) 100)
          (when (source-changed self)
            (funcall (source-changed self)))))
    (serious-condition (condition)
      (note "delete: ~a" condition))))

;;; The component ---------------------------------------------------------------

(defun make-scan-table (&key rows select remove info image-tap changed)
  "A table view showing whatever ROWS returns, a list of groups.

SELECT is called with the group that was tapped.  INFO, if given, puts a
detail button on every row and is called with that row's group.  REMOVE turns
on swipe to delete and is called with the group; returning true lets the row
go.  CHANGED is called after the table has changed itself, for whatever is
showing totals elsewhere."
  (let* ((view (objc:invoke (objc:invoke (objc:invoke "UITableView" "alloc")
                                         "initWithFrame:style:" (vector 0d0 0d0 0d0 0d0) 0)
                            "autorelease"))
         ;; A table view holds its source and delegate weakly.
         (source (ui:keep (make-instance 'scan-table-source
                                         :rows rows :select select :remove remove
                                         :info info :image-tap image-tap
                                         :changed changed)))
         (table (%make-scan-table view source)))
    (setf (source-view source) view)
    (objc:invoke view "setTranslatesAutoresizingMaskIntoConstraints:" nil)
    (objc:invoke view "setRowHeight:" 62d0)
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
