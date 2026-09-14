;;;; tests/upc-tests.lisp

(in-package #:upc-logger/tests)

(def-suite codes :in all-tests :description "Reading what the camera reports.")
(in-suite codes)

(test metadata-types
  (is (eq :ean-13 (metadata-type "org.gs1.EAN-13")))
  (is (eq :ean-8 (metadata-type "org.gs1.EAN-8")))
  (is (eq :upc-e (metadata-type "org.gs1.UPC-E")))
  (is (null (metadata-type "org.iso.QRCode"))))

(test check-digits
  (is-true (check-digit-valid-p "036000291452"))    ; UPC-A
  (is-true (check-digit-valid-p "4006381333931"))   ; EAN-13
  (is-true (check-digit-valid-p "96385074"))        ; EAN-8
  (is-false (check-digit-valid-p "036000291453"))
  (is-false (check-digit-valid-p "03600029145"))    ; wrong length
  (is-false (check-digit-valid-p "03600029145x")))

(test upc-e-expands-to-upc-a
  (is (string= "042100005264" (expand-upc-e "04252614")))
  (is (string= "012300000413" (expand-upc-e "01234133")))  ; last digit 3
  (is (null (expand-upc-e "24252614")))                    ; number system 2
  (is-true (check-digit-valid-p (expand-upc-e "04252614"))))

(test adding-check-digits
  (is (string= "036000291452" (add-check-digit "03600029145")))
  (is (string= "4006381333931" (add-check-digit "400638133393")))
  (dotimes (i 50)
    (is-true (check-digit-valid-p
              (add-check-digit (format nil "~11,'0d" (random 100000000000)))))))

(test upc-a-loses-the-ean-13-zero
  (is (string= "036000291452" (scanned-code "0036000291452" "org.gs1.EAN-13")))
  (is (string= "4006381333931" (scanned-code "4006381333931" :ean-13))))

(test scanned-code-rejects-misreads
  (is (null (scanned-code "0036000291453" :ean-13)))
  (is (null (scanned-code "hello" :ean-13)))
  (is (null (scanned-code "036000291452" "org.iso.QRCode")))
  (is (string= "96385074" (scanned-code "96385074" :ean-8)))
  (is (string= "04252614" (scanned-code "04252614" :upc-e)))
  (is (null (scanned-code "04252615" :upc-e))))

(test entry-titles
  (is (string= "036000291452" (format-entry-title 1 "036000291452")))
  (is (string= "8 x 036000291452" (format-entry-title 8 "036000291452"))))

(test timestamps
  (is (string= "2026-09-14 14:03:22"
               (format-timestamp (encode-universal-time 22 3 14 14 9 2026 0) 0))))
