;;;; tests/gate-tests.lisp

(in-package #:upc-logger/tests)

(def-suite gate :in all-tests :description "One scan per presentation, not per frame.")
(in-suite gate)

(test a-held-label-is-admitted-once
  (let ((gate (make-scan-gate :quiet-ms 1500)))
    (is-true (admit-scan gate "111111111117" 0))
    ;; Reported every frame for five seconds.
    (is (notany #'identity
                (loop for ms from 33 to 5000 by 33
                      collect (admit-scan gate "111111111117" ms))))))

(test a-label-shown-again-after-a-pause-is-admitted
  (let ((gate (make-scan-gate :quiet-ms 1500)))
    (admit-scan gate "111111111117" 0)
    (is-false (admit-scan gate "111111111117" 1000))
    (is-true (admit-scan gate "111111111117" 3000))))

(test two-labels-in-view-are-each-admitted-once
  (let ((gate (make-scan-gate :quiet-ms 1500))
        (admitted '()))
    (loop for ms from 0 to 3000 by 33
          do (dolist (code '("111111111117" "222222222224"))
               (when (admit-scan gate code ms)
                 (push code admitted))))
    (is (equal '("222222222224" "111111111117") admitted))))

(test the-table-of-sightings-is-pruned
  (let ((gate (make-scan-gate :quiet-ms 10)))
    (dotimes (i 200)
      (admit-scan gate (format nil "~12,'0d" i) (* i 100)))
    (is (<= (hash-table-count (upc-logger::scan-gate-last-seen gate)) 65))))
