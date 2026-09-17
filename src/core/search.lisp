;;;; src/core/search.lisp -- finding a scan again.
;;;;
;;;; A substring of the code, the name or the note, ignoring case: three
;;;; fields, because a person looking for something remembers whichever of
;;;; them they happened to write down.
;;;;
;;;; The window a search wants is not the window a chart was showing -- the
;;;; matches may be spread over a week, or be one scan from Tuesday -- so
;;;; WINDOW-FOR-ENTRIES answers with the span the matches actually occupy.

(in-package #:upc-logger)

(defun contains-p (needle haystack)
  "True when HAYSTACK has NEEDLE in it somewhere, ignoring case."
  (and (stringp haystack)
       (search needle haystack :test #'char-equal)
       t))

(defun entry-matches-p (entry query)
  "True when ENTRY answers to QUERY.  A blank query matches everything, which
is what an empty search field should do."
  (let ((query (blank-to-nil query)))
    (or (null query)
        (contains-p query (entry-code entry))
        (contains-p query (entry-name entry))
        (contains-p query (entry-note entry)))))

(defun search-entries (entries query)
  (if (null (blank-to-nil query))
      entries
      (remove-if-not (lambda (entry) (entry-matches-p entry query)) entries)))

(defun entries-time-span (entries)
  "The earliest and latest scan times in ENTRIES, or NIL for none."
  (when entries
    (let ((times (mapcar #'entry-scanned-at entries)))
      (values (reduce #'min times) (reduce #'max times)))))

(defun window-for-entries (entries &optional (padding 1/20))
  "A window showing every one of ENTRIES, or NIL when there are none.

Padded, so the first and last bars are not flush against the edges, and never
narrower than +MINIMUM-SPAN+: a search that finds one scan would otherwise ask
for a window of no width at all."
  (multiple-value-bind (earliest latest) (entries-time-span entries)
    (when earliest
      ;; 1+ the latest because the window is half-open and the newest match
      ;; must fall inside it.
      (let* ((span (max +minimum-span+ (- (1+ latest) earliest)))
             (pad (round (* padding span)))
             (start (- earliest pad)))
        (make-time-window start (+ start span (* 2 pad)))))))
