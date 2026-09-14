;;;; src/ios/package.lisp

(defpackage #:upc-logger-ios
  (:use #:common-lisp #:upc-logger)
  (:local-nicknames (#:ui #:uikit))
  (:export #:start #:simulate-scan #:edit-count))
