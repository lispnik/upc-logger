;;;; src/core/upc.lisp -- what a barcode reader hands over, made into a code.
;;;;
;;;; AVFoundation does not report UPC-A as such.  A UPC-A symbol is an EAN-13
;;;; with an implied leading zero, and that is what the metadata output says it
;;;; saw: "org.gs1.EAN-13", thirteen digits, the first a 0.  The zero is dropped
;;;; here so the log shows the twelve digits printed under the bars.

(in-package #:upc-logger)

(defun metadata-type (type)
  "A keyword for an AVMetadataObjectType string, or NIL for one we don't log."
  (cond ((string= type "org.gs1.EAN-13") :ean-13)
        ((string= type "org.gs1.EAN-8") :ean-8)
        ((string= type "org.gs1.UPC-E") :upc-e)
        (t nil)))

(defun digits-p (string)
  (and (stringp string)
       (plusp (length string))
       (every #'digit-char-p string)))

(defun check-digit-valid-p (code)
  "True when CODE, a GTIN of 8, 12, 13 or 14 digits, ends in its mod-10 check digit.

Weights run 3, 1, 3, ... leftward from the digit before the check digit, which
is what makes one rule serve every length."
  (and (digits-p code)
       (member (length code) '(8 12 13 14))
       (let ((sum 0))
         (loop for i from (- (length code) 2) downto 0
               for weight = 3 then (- 4 weight)
               do (incf sum (* weight (digit-char-p (char code i)))))
         (= (mod (- 10 (mod sum 10)) 10)
            (digit-char-p (char code (1- (length code))))))))

(defun add-check-digit (digits)
  "DIGITS with its GTIN check digit appended: eleven digits make a UPC-A."
  (let ((sum 0))
    (loop for i from (1- (length digits)) downto 0
          for weight = 3 then (- 4 weight)
          do (incf sum (* weight (digit-char-p (char digits i)))))
    (format nil "~a~d" digits (mod (- 10 (mod sum 10)) 10))))

(defun expand-upc-e (code)
  "The twelve-digit UPC-A that an eight-digit UPC-E CODE abbreviates, or NIL."
  (when (and (digits-p code) (= (length code) 8)
             (member (char code 0) '(#\0 #\1)))
    (let ((system (char code 0))
          (d (subseq code 1 7))
          (check (char code 7)))
      (flet ((d (i) (char d (1- i))))
        (let ((body
                (case (d 6)
                  ((#\0 #\1 #\2)
                   (format nil "~c~c~c0000~c~c~c" (d 1) (d 2) (d 6) (d 3) (d 4) (d 5)))
                  (#\3
                   (format nil "~c~c~c00000~c~c" (d 1) (d 2) (d 3) (d 4) (d 5)))
                  (#\4
                   (format nil "~c~c~c~c00000~c" (d 1) (d 2) (d 3) (d 4) (d 5)))
                  (t
                   (format nil "~c~c~c~c~c0000~c" (d 1) (d 2) (d 3) (d 4) (d 5) (d 6))))))
          (format nil "~c~a~c" system body check))))))

(defun normalize-code (value type)
  "VALUE as it should be logged: digits only, a UPC-A without EAN-13's leading zero."
  (let ((code (string-trim '(#\Space #\Tab #\Newline #\Return) value)))
    (if (and (eq type :ean-13) (= (length code) 13) (char= (char code 0) #\0))
        (subseq code 1)
        code)))

(defun scanned-code (value type)
  "The code to log for a barcode read as VALUE of TYPE (a keyword or an
AVMetadataObjectType string), or NIL when it is not a well-formed product code.

A misread that happens to keep the right length is caught by the check digit,
so a smudged label doesn't put a phantom product in the log."
  (let ((type (if (stringp type) (metadata-type type) type)))
    (when (and type (stringp value))
      (let ((code (normalize-code value type)))
        (when (digits-p code)
          (case type
            (:upc-e (let ((expanded (expand-upc-e code)))
                      (and expanded (check-digit-valid-p expanded) code)))
            ((:ean-13 :ean-8) (and (check-digit-valid-p code) code))))))))

;;; Presentation --------------------------------------------------------------

(defun format-entry-title (count code)
  "\"8 x 012345678905\" for a count of eight; just the code for one."
  (if (= count 1)
      code
      (format nil "~d x ~a" count code)))

(defun format-timestamp (universal-time &optional time-zone)
  "UNIVERSAL-TIME as \"2026-09-14 14:03:22\", in local time unless TIME-ZONE is given."
  (multiple-value-bind (second minute hour day month year)
      (if time-zone
          (decode-universal-time universal-time time-zone)
          (decode-universal-time universal-time))
    (format nil "~4,'0d-~2,'0d-~2,'0d ~2,'0d:~2,'0d:~2,'0d"
            year month day hour minute second)))
