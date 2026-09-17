;;;; tests/aggregate-tests.lisp

(in-package #:upc-logger/tests)

(def-suite aggregating :in all-tests
  :description "Runs of scans drawn as one row, or every scan on its own.")
(in-suite aggregating)

(defun event (code at &key (count 1) note photo name)
  (make-entry :code code :at at :count count :note note :photo photo :name name))

(defun run-of (codes)
  "Events newest first, one per code, a second apart."
  (loop for code in codes
        for at downfrom 1000
        collect (event code at)))

(test ungrouped-is-one-row-per-scan
  (let ((groups (group-entries (run-of '("a" "a" "a")) nil)))
    (is (= 3 (length groups)))
    (is-true (every (lambda (g) (= 1 (group-scans g))) groups))))

(test adjacent-scans-of-the-same-code-merge
  (let ((groups (group-entries (run-of '("a" "a" "a")) t)))
    (is (= 1 (length groups)))
    (is (= 3 (group-scans (first groups))))
    (is (= 3 (group-count (first groups))))
    (is-true (group-merged-p (first groups)))))

(test a-different-code-breaks-the-run
  (let ((groups (group-entries (run-of '("a" "a" "b" "a")) t)))
    (is (= 3 (length groups)))
    (is (equal '("a" "b" "a") (mapcar #'group-code groups)))
    (is (equal '(2 1 1) (mapcar #'group-scans groups)))))

(test counts-add-up-across-a-run
  (let ((groups (group-entries (list (event "a" 300 :count 8)
                                     (event "a" 200)
                                     (event "a" 100 :count 2))
                               t)))
    (is (= 1 (length groups)))
    (is (= 11 (group-count (first groups))))
    (is (= 3 (group-scans (first groups))))))

(test a-scan-with-a-photo-stands-alone
  ;; Merging it would hide the very thing that made it worth marking.
  (let ((groups (group-entries (list (event "a" 400)
                                     (event "a" 300 :photo "shelf.jpg")
                                     (event "a" 200)
                                     (event "a" 100))
                               t)))
    (is (= 3 (length groups)))
    (is (equal '(1 1 2) (mapcar #'group-scans groups)))
    (is (string= "shelf.jpg" (group-photo (second groups))))
    ;; The plain scans on either side still merge among themselves.
    (is (= 2 (group-scans (third groups))))))

(test a-scan-with-a-note-stands-alone
  (let ((groups (group-entries (list (event "a" 300)
                                     (event "a" 200 :note "damaged box")
                                     (event "a" 100))
                               t)))
    (is (= 3 (length groups)))
    (is (string= "damaged box" (group-note (second groups))))))

(test an-annotated-scan-is-alone-even-among-its-own-kind
  (let ((groups (group-entries (list (event "a" 200 :note "one")
                                     (event "a" 100 :note "two"))
                               t)))
    (is (= 2 (length groups)))))

(test a-group-knows-when-it-began-and-ended
  (let ((group (first (group-entries (run-of '("a" "a" "a")) t))))
    (is (= 1000 (group-latest group)))        ; newest first
    (is (= 998 (group-earliest group)))
    ;; The newest event is the one an edit acts on.
    (is (= 1000 (entry-at (group-first-event group))))))

(test a-single-scan-is-not-merged
  (let ((group (first (group-entries (list (event "a" 100)) t))))
    (is-false (group-merged-p group))
    (is (= 100 (group-earliest group)))
    (is (= 100 (group-latest group)))))

(test the-name-comes-through-a-group
  (let ((groups (group-entries (list (event "a" 200 :name "Blue paint 1L")
                                     (event "a" 100 :name "Blue paint 1L"))
                               t)))
    (is (string= "Blue paint 1L" (group-name (first groups))))))

(test totals-over-groups
  (let ((groups (group-entries (list (event "a" 300 :count 8)
                                     (event "a" 200)
                                     (event "b" 100 :count 2))
                               t)))
    (is (= 11 (groups-total-items groups)))
    (is (= 3 (groups-total-scans groups)))))

(test nothing-to-group
  (is (null (group-entries '() t)))
  (is (null (group-entries '() nil))))
