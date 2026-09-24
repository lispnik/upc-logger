;;;; upc-logger-app.asd -- the iOS application.
;;;;
;;;; Built with asdf-ios-app on ECL:  make sim, make run-sim, make device,
;;;; make testflight.  The platforms and signing are read from the environment
;;;; when this file is read, so one declaration serves the simulator (no
;;;; identity), a phone, and an App Store build (UPC_LOGGER_DISTRIBUTION=1).

(defsystem "upc-logger-app"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "upc-logger-ios:start"
  :description "Scan UPC barcodes with the camera and keep a timestamped, counted log."
  :author "Matthew Kennedy <burnsidemk@gmail.com>"
  :license "MIT"
  ;; CFBundleVersion: the build number, which every upload must raise.
  ;; tools/testflight.sh sets it from the commit count.
  :version #.(or (uiop:getenv "UPC_LOGGER_BUILD") "1.0.0")
  :serial t
  :depends-on ("upc-logger" "objc/uikit")
  :components ((:module "ios"
                :pathname "src/ios"
                :serial t
                :components ((:file "package")
                             (:file "store")
                             (:file "scan-table")
                             (:file "chart")
                             (:file "photo")
                             (:file "viewer")
                             (:file "list")
                             (:file "search")
                             (:file "share")
                             (:file "camera")
                             (:file "app"))))
  :bundle-identifier "com.burnsidemk.upclogger"
  :bundle-short-version "1.0"
  :bundle-name "UPC Logger"
  :bundle-executable "upc-logger"
  :bundle-icon "res/Icon.xcassets"
  ;; iPhone only: an iPad app must support every orientation to multitask,
  ;; and App Store validation refuses a portrait-only one.
  :bundle-device-family (:iphone)
  :bundle-orientations (:portrait)
  :bundle-frameworks ("UIKit" "Foundation" "CoreGraphics" "QuartzCore"
                      "AVFoundation" "AudioToolbox")
  :bundle-info-plist (("NSCameraUsageDescription"
                       . "UPC Logger reads barcodes with the camera, and takes a photo of a scan when you ask it to.")
                      ;; Where there is no camera the picker falls back to the
                      ;; library, and UIImagePickerController needs this to open it.
                      ("NSPhotoLibraryUsageDescription"
                       . "UPC Logger can attach a photo from your library to a scan.")
                      ;; The scan log is the app's Documents directory, and
                      ;; these two put it in Files under On My iPhone: the first
                      ;; shows the folder, the second lets what is in it be
                      ;; opened in place rather than copied out and edited in a
                      ;; copy nothing reads back.
                      ("UIFileSharingEnabled" . :true)
                      ("LSSupportsOpeningDocumentsInPlace" . :true)
                      ;; The top of the screen is the camera, so the status
                      ;; bar is light whatever the appearance.
                      ("UIViewControllerBasedStatusBarAppearance" . :false)
                      ("UIStatusBarStyle" . "UIStatusBarStyleLightContent")
                      ;; No encryption beyond what iOS itself provides, so no
                      ;; export-compliance question on every upload.
                      ("ITSAppUsesNonExemptEncryption" . :false))
  ;; Required of every app: what it collects (nothing) and which
  ;; required-reason APIs it uses (none).
  :bundle-resources (("res/PrivacyInfo.xcprivacy" . "PrivacyInfo.xcprivacy"))
  ;; A distribution build must not let a debugger attach.
  :get-task-allow #.(not (uiop:getenv "UPC_LOGGER_DISTRIBUTION"))
  :bundle-platforms #.(let ((identity (uiop:getenv "IOS_SIGNING_IDENTITY")))
                        (cond ((uiop:getenv "UPC_LOGGER_DISTRIBUTION") '(:device))
                              ((and identity (plusp (length identity)))
                               '(:simulator :device))
                              (t '(:simulator))))
  :code-signing-identity #.(let ((identity (uiop:getenv "IOS_SIGNING_IDENTITY")))
                             (if (and identity (plusp (length identity)))
                                 identity
                                 :automatic))
  :development-team #.(let ((team (uiop:getenv "IOS_DEVELOPMENT_TEAM")))
                        (and team (plusp (length team)) team))
  :provisioning-profile #.(let ((profile (uiop:getenv "IOS_PROVISIONING_PROFILE")))
                            (and profile (plusp (length profile)) profile)))
