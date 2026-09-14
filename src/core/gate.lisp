;;;; src/core/gate.lisp -- one scan per barcode presented, not per frame.
;;;;
;;;; The capture output reports every code in view on every frame it can read
;;;; it, many times a second.  Logging each report would bump the count for as
;;;; long as the label is held up.  So a code is admitted once, and not again
;;;; until it has been out of view for QUIET-MS -- the reader stops reporting it
;;;; when it leaves, and the gap is what "taken away and shown again" looks like.
;;;;
;;;; Kept per code, not just for the last one: two labels in the frame at once
;;;; alternate in the reports, and a gate that remembered only the latest would
;;;; admit both on every frame.

(in-package #:upc-logger)

(defstruct (scan-gate (:constructor make-scan-gate (&key (quiet-ms 1500))))
  (quiet-ms 1500 :type (integer 0))
  (last-seen (make-hash-table :test 'equal)))

(defun admit-scan (gate code now-ms)
  "True if CODE, reported at NOW-MS milliseconds, is a new presentation to log.
Every report counts as a sighting, admitted or not."
  (let* ((seen (scan-gate-last-seen gate))
         (previous (gethash code seen))
         (admit (or (null previous)
                    (> (- now-ms previous) (scan-gate-quiet-ms gate)))))
    (setf (gethash code seen) now-ms)
    ;; Forget codes long gone, so a day of scanning doesn't grow the table.
    (when (> (hash-table-count seen) 64)
      (maphash (lambda (key time)
                 (when (> (- now-ms time) (scan-gate-quiet-ms gate))
                   (remhash key seen)))
               seen))
    admit))
