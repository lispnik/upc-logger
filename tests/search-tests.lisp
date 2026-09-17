;;;; tests/search-tests.lisp

(in-package #:upc-logger/tests)

(def-suite searching :in all-tests :description "Finding a scan again.")
(in-suite searching)

(defun sample-entries ()
  (list (make-entry :code "036000291452" :at 3998500000
                    :name "Blue paint 1L" :note "damaged box")
        (make-entry :code "845121047035" :at 3998400000
                    :name "White spirit")
        (make-entry :code "111111111117" :at 3998300000)))

(test a-substring-of-the-code-finds-it
  (let ((entries (sample-entries)))
    ;; Not anchored at the start: 00029 sits in the middle of 036000291452.
    (is (= 1 (length (search-entries entries "00029"))))
    (is (= 1 (length (search-entries entries "036000291452"))))
    (is (= 3 (length (search-entries entries "1"))))          ; all three contain a 1
    (is (= 0 (length (search-entries entries "999"))))))

(test the-name-and-the-note-are-searched-too
  (let ((entries (sample-entries)))
    (is (= 1 (length (search-entries entries "paint"))))
    (is (= 1 (length (search-entries entries "damaged"))))
    (is (string= "845121047035" (entry-code (first (search-entries entries "spirit")))))))

(test case-does-not-matter
  (let ((entries (sample-entries)))
    (is (= 1 (length (search-entries entries "BLUE PAINT"))))
    (is (= 1 (length (search-entries entries "Damaged Box"))))))

(test a-blank-search-matches-everything
  (let ((entries (sample-entries)))
    (is (= 3 (length (search-entries entries ""))))
    (is (= 3 (length (search-entries entries "   "))))
    (is (= 3 (length (search-entries entries nil))))
    (is-true (entry-matches-p (first entries) ""))))

(test an-entry-with-no-name-or-note-is-not-a-problem
  (let ((bare (make-entry :code "111111111117" :at 1)))
    (is-false (entry-matches-p bare "paint"))
    (is-true (entry-matches-p bare "1111"))))

(test the-window-covers-every-match
  (let* ((entries (sample-entries))
         (window (window-for-entries entries)))
    (is-true (<= (time-window-start window) 3998300000))
    (is-true (> (time-window-end window) 3998500000))
    ;; Every entry falls inside it, which is the point.
    (is (= 3 (length (entries-in-window (make-scan-log entries) window))))))

(test one-match-still-gets-a-window-with-width
  (let* ((entry (make-entry :code "036000291452" :at 3998500000))
         (window (window-for-entries (list entry))))
    (is-true (>= (window-span window) +minimum-span+))
    (is (= 1 (length (entries-in-window (make-scan-log (list entry)) window))))))

(test no-matches-means-no-window
  (is (null (window-for-entries '())))
  (is (null (entries-time-span '()))))

(test the-span-of-a-set-of-entries
  (multiple-value-bind (earliest latest) (entries-time-span (sample-entries))
    (is (= 3998300000 earliest))
    (is (= 3998500000 latest))))
