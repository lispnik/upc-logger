;;;; src/ios/search.lisp -- the search bar along the bottom.
;;;;
;;;; Typing filters the table as the letters arrive, and moves the chart to the
;;;; span the matches occupy: searching for a name is asking "when did I scan
;;;; these", and a chart still showing the last day would answer a question
;;;; nobody asked.
;;;;
;;;; Clearing the field puts both back: the last day, following new scans.
;;;;
;;;; The keyboard covers the bottom of the screen, which is where the bar is,
;;;; so the bar's bottom constraint follows the keyboard up and down.  Without
;;;; that the field is hidden by the thing typing into it.

(in-package #:upc-logger-ios)

(defvar *search-bar* nil)
(defvar *search-delegate* nil "Kept: UIKit holds a delegate weakly.")
(defvar *search-bottom* nil "The bar's bottom constraint, moved by the keyboard.")
(defvar *keyboard-observer* nil "Kept: the notification centre holds it weakly.")

(defun apply-query (text)
  "Filter by TEXT, and put the chart over whatever it matches."
  (let ((query (blank-to-nil text)))
    (setf *query* query)
    (if (null query)
        ;; Cleared: back to the last day, following new scans again.
        (setf *window* (default-window (get-universal-time))
              *follow* t)
        (let ((window (window-for-entries (search-entries (scan-log-entries *log*) query))))
          ;; No matches: leave the window alone rather than jump somewhere empty.
          (when window
            (setf *window* window
                  *follow* nil))))
    (notify-window-change)))

(objc:define-objc-class search-delegate () ()
  (:objc-class-name "UPCSearchDelegate"))

(objc:define-objc-method ("searchBar:textDidChange:" :void)
    ((self search-delegate) (bar objc:objc-object-pointer) (text objc:objc-object-pointer))
  (declare (ignore bar))
  (handler-case (apply-query (objc:ns-string-to-string text))
    (serious-condition (condition)
      (note "search: ~a" condition))))

(objc:define-objc-method ("searchBarSearchButtonClicked:" :void)
    ((self search-delegate) (bar objc:objc-object-pointer))
  (handler-case (objc:invoke bar "resignFirstResponder")
    (serious-condition (condition) (note "search done: ~a" condition))))

(objc:define-objc-method ("searchBarCancelButtonClicked:" :void)
    ((self search-delegate) (bar objc:objc-object-pointer))
  (handler-case
      (progn
        (objc:invoke bar "setText:" "")
        (objc:invoke bar "resignFirstResponder")
        (apply-query nil))
    (serious-condition (condition) (note "search cancel: ~a" condition))))

(objc:define-objc-method ("searchBarTextDidBeginEditing:" :void)
    ((self search-delegate) (bar objc:objc-object-pointer))
  (handler-case (objc:invoke bar "setShowsCancelButton:animated:" t t)
    (serious-condition (condition) (note "search begin: ~a" condition))))

(objc:define-objc-method ("searchBarTextDidEndEditing:" :void)
    ((self search-delegate) (bar objc:objc-object-pointer))
  (handler-case (objc:invoke bar "setShowsCancelButton:animated:" nil t)
    (serious-condition (condition) (note "search end: ~a" condition))))

(objc:define-objc-method ("searchBar:selectedScopeButtonIndexDidChange:" :void)
    ((self search-delegate) (bar objc:objc-object-pointer) (index (:signed :long-long)))
  (declare (ignore bar))
  ;; 0 groups runs of a code into one row; 1 shows every scan.
  (handler-case
      (progn (setf *aggregated* (zerop index))
             (notify-window-change))
    (serious-condition (condition)
      (note "scope: ~a" condition))))

;;; The keyboard ------------------------------------------------------------------

(defun keyboard-height (notification)
  "How much of the screen the keyboard is about to cover, in points."
  (let* ((info (objc:invoke notification "userInfo"))
         (value (objc:invoke info "objectForKey:" "UIKeyboardFrameEndUserInfoKey")))
    (if (cffi:null-pointer-p value)
        0
        (let* ((frame (objc:invoke value "CGRectValue"))
               (screen (objc:invoke (objc:invoke "UIScreen" "mainScreen") "bounds"))
               ;; The frame is in screen coordinates: what it covers is whatever
               ;; of it lies above the bottom of the screen.
               (covered (- (aref screen 3) (aref frame 1))))
          (max 0 covered)))))

(defun follow-keyboard (notification)
  (handler-case
      (when *search-bottom*
        (let ((height (keyboard-height notification)))
          (objc:invoke *search-bottom* "setConstant:" (float (- height) 1d0))
          (objc:invoke (ui:root-view) "layoutIfNeeded")))
    (serious-condition (condition)
      (note "keyboard: ~a" condition))))

(defun watch-keyboard ()
  (let ((centre (objc:invoke "NSNotificationCenter" "defaultCenter")))
    (setf *keyboard-observer* (ui:action-target #'follow-keyboard))
    (dolist (name '("UIKeyboardWillChangeFrameNotification"
                    "UIKeyboardWillHideNotification"))
      (objc:invoke centre "addObserver:selector:name:object:"
                   *keyboard-observer* "fire:" name nil))))

;;; The bar ------------------------------------------------------------------------

(defun build-search (root)
  "The search bar, along the bottom.  Returns it."
  (setf *search-bar* (ui:new "UISearchBar"))
  (objc:invoke *search-bar* "setPlaceholder:" "Search code, name or note")
  (objc:invoke *search-bar* "setSearchBarStyle:" 2)          ; minimal
  (objc:invoke *search-bar* "setAutocapitalizationType:" 0)
  (objc:invoke *search-bar* "setAutocorrectionType:" 1)      ; no
  ;; The Search key is how the keyboard goes away, so it stays live on an empty
  ;; field; by default UIKit greys it out until something has been typed.
  (objc:invoke *search-bar* "setEnablesReturnKeyAutomatically:" nil)
  ;; The scope strip carries the one control that has nowhere else to go: the
  ;; row above is already holding the range, Reset and Share.
  ;; A Lisp vector, which INVOKE turns into a temporary NSArray.  Not
  ;; -arrayWithObjects:, which is variadic: on Apple silicon the variable
  ;; arguments go on the stack, so calling it plainly reads garbage, and the
  ;; bridge refuses rather than pretend otherwise.
  (objc:invoke *search-bar* "setScopeButtonTitles:" (vector "Grouped" "Every scan"))
  (objc:invoke *search-bar* "setShowsScopeBar:" t)
  (objc:invoke *search-bar* "setSelectedScopeButtonIndex:" (if *aggregated* 0 1))
  (setf *search-delegate* (ui:keep (make-instance 'search-delegate)))
  (objc:invoke *search-bar* "setDelegate:" (objc:objc-object-pointer *search-delegate*))
  (objc:invoke root "addSubview:" *search-bar*)
  (ui:pin *search-bar* "leadingAnchor" root "leadingAnchor")
  (ui:pin *search-bar* "trailingAnchor" root "trailingAnchor")
  ;; Kept, not autoreleased: -constraintEqualToAnchor:constant: already returns
  ;; an autoreleased constraint, so a second -autorelease over-releases it, and
  ;; this one has to outlive the pool anyway -- the keyboard moves it.
  (let ((bottom (ui:keep (objc:invoke (ui:anchor *search-bar* "bottomAnchor")
                                      "constraintEqualToAnchor:constant:"
                                      (ui:anchor (objc:invoke (ui:root-controller)
                                                              "safeAreaLayoutGuide")
                                                 "bottomAnchor")
                                      0d0))))
    (setf *search-bottom* bottom)
    (objc:invoke bottom "setActive:" t))
  (watch-keyboard)
  *search-bar*)
