;;;; upc-logger-app.asd -- the iOS application.
;;;;
;;;; Built with asdf-ios-app on ECL:  make sim, make run-sim, make device.
;;;; The platforms and signing are read from the environment when this file is
;;;; read, so one declaration serves the simulator (no identity) and a phone.

(defsystem "upc-logger-app"
  :defsystem-depends-on ("asdf-ios-app")
  :class :ios-app-system
  :build-operation "ios-app-op"
  :entry-point "upc-logger-ios:start"
  :description "Scan UPC barcodes with the camera and keep a timestamped, counted log."
  :author "Matthew Kennedy <burnsidemk@gmail.com>"
  :license "MIT"
  :version "0.1.0"
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
                             (:file "list")
                             (:file "share")
                             (:file "camera")
                             (:file "app"))))
  :bundle-identifier "com.lispnik.upc-logger"
  :bundle-name "UPC Logger"
  :bundle-executable "upc-logger"
  :bundle-icon "res/Icon.xcassets"
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
                      ("UIStatusBarStyle" . "UIStatusBarStyleLightContent"))
  :bundle-platforms #.(let ((identity (uiop:getenv "IOS_SIGNING_IDENTITY")))
                        (if (and identity (plusp (length identity)))
                            '(:simulator :device)
                            '(:simulator)))
  :code-signing-identity #.(let ((identity (uiop:getenv "IOS_SIGNING_IDENTITY")))
                             (if (and identity (plusp (length identity)))
                                 identity
                                 :automatic))
  :provisioning-profile #.(let ((profile (uiop:getenv "IOS_PROVISIONING_PROFILE")))
                            (and profile (plusp (length profile)) profile)))
