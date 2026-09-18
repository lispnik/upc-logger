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
  ;; A run of one code, then others: enough for the grouped view to have
  ;; something to group and the ungrouped view something to spread out.
  (let ((steps (list (lambda () (simulate-scan 0))
                     (lambda () (simulate-scan 0))
                     (lambda () (simulate-scan 0))
                     (lambda () (simulate-scan 1))
                     (lambda () (simulate-scan 2))
                     (lambda () (let ((group (first (visible-groups))))
                                  (when group (apply-count group "8"))))
                     (lambda () (note "demo: scripted scans done")))))
    (when (ext:getenv "UPC_LOGGER_DEMO_ROW")
      ;; A name, a note and a photo on the top row, so the three of them can be
      ;; seen on a simulator: no camera, and a library with nothing in it.
      (setf steps (append steps
                          (list (lambda ()
                                  (let ((group (first (visible-groups))))
                                    (when group
                                      (change-group group
                                                    (lambda (index)
                                                      (set-name *log* index "Blue paint 1L")
                                                      (set-note *log* index "damaged box"))))))
                                (lambda ()
                                  (let ((group (first (visible-groups))))
                                    (when group
                                      (handler-case
                                          (let ((name (write-photo (synthetic-photo))))
                                            (if name
                                                (change-group group
                                                              (lambda (index)
                                                                (set-photo *log* index name)))
                                                (note "demo: no photo written")))
                                        (serious-condition (condition)
                                          (note "demo photo: ~a" condition))))))
                                (lambda ()
                                  (let ((group (first (visible-groups))))
                                    (when group (row-menu group))))))))
    (when (ext:getenv "UPC_LOGGER_DEMO_VIEWER")
      ;; The photo full screen: a thumbnail cannot be tapped on a simulator.
      (setf steps (append steps
                          (list (lambda ()
                                  (let ((group (first (visible-groups))))
                                    (when group
                                      (handler-case
                                          (let ((name (write-photo (synthetic-photo))))
                                            (when name
                                              (change-group group
                                                            (lambda (index)
                                                              (set-photo *log* index name)))))
                                        (serious-condition (condition)
                                          (note "demo photo: ~a" condition))))))
                                (lambda ()
                                  (let ((group (first (visible-groups))))
                                    (note "demo: opening the photo full screen")
                                    (when group (photo-tapped group))))))))
    (when (ext:getenv "UPC_LOGGER_DEMO_GROUPS")
      ;; Both views, and the rule that an annotated scan leaves its run: the
      ;; scope strip cannot be tapped on a simulator.
      (setf steps (append steps
                          (list (lambda ()
                                  (note "demo: grouped, ~d row~:p over ~d scan~:p"
                                        (length (visible-groups))
                                        (groups-total-scans (visible-groups))))
                                (lambda ()
                                  ;; The MIDDLE OF THE RUN, not the second event
                                  ;; overall: newest first the events are
                                  ;; [other, other, run, run, run], so the run's
                                  ;; middle is index 3.  Noting index 1 marked a
                                  ;; scan that was already its own row and
                                  ;; proved nothing.
                                  (let ((middle (nth 3 (visible-entries))))
                                    (when middle
                                      (change-event middle
                                                    (lambda (index)
                                                      (set-note *log* index "damaged box")))
                                      (note "demo: noted the middle of the run (~a); ~d rows now"
                                            (entry-code middle)
                                            (length (visible-groups))))))
                                ;; Held a beat so the grouped result can be seen.
                                (lambda () (note "demo: grouped, ~d rows over ~d scans"
                                                 (length (visible-groups))
                                                 (groups-total-scans (visible-groups))))
                                (lambda ()
                                  (setf *aggregated* nil)
                                  (when *search-bar*
                                    (objc:invoke *search-bar* "setSelectedScopeButtonIndex:" 1))
                                  (notify-window-change)
                                  (note "demo: every scan, ~d rows" (length (visible-groups))))))))
    (when (ext:getenv "UPC_LOGGER_DEMO_SEARCH")
      ;; A search typed from code: the field cannot be tapped on a simulator,
      ;; and live filtering is the whole of what wants showing.
      (setf steps (append steps
                          (list (lambda ()
                                  (let ((entry (log-entry *log* 1)))
                                    (when entry
                                      (change-entry entry
                                                    (lambda (index)
                                                      (set-name *log* index "Blue paint 1L"))))))
                                (lambda ()
                                  (let ((code (let ((entry (log-entry *log* 0)))
                                                (and entry (subseq (entry-code entry) 0 5)))))
                                    (note "demo: searching ~s" code)
                                    (when *search-bar*
                                      (objc:invoke *search-bar* "setText:" code))
                                    (apply-query code)))
                                (lambda ()
                                  (note "demo: searching \"paint\"")
                                  (when *search-bar*
                                    (objc:invoke *search-bar* "setText:" "paint"))
                                  (apply-query "paint"))))))
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
                                (lambda () (probe-representations))
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
           (controls (build-controls root chart))
           (search (build-search root)))
      ;; The table fills what is left between the controls and the search bar.
      (build-list root controls search))
    (start-camera)
    (when demo
      (demo)))
  (values))
