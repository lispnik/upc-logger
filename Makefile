# Makefile for UPC Logger.
#
#   make test       run the FiveAM suite on the host, in ECL
#   make sim        build the simulator .app
#   make run-sim    build, install and launch it on the booted simulator
#   make demo-sim   the same, launched with UPC_LOGGER_DEMO=1 (scripted scans)
#   make device     build for iphoneos, install on a connected iPhone and launch
#   make icon       redraw the icon (SBCL + objc + AppKit)
#   make deps       restore ocicl dependencies, here and in objc
#   make clean
#
# `make device' needs signing, which is personal and so lives in local.mk
# (not committed):
#
#   IOS_SIGNING_IDENTITY = Apple Development: Your Name (XXXXXXXXXX)
#   IOS_PROVISIONING_PROFILE = /path/to/profile.mobileprovision

-include local.mk

OBJC_DIR ?= $(HOME)/Projects/common-lisp/objc
IOS_APP_DIR ?= $(HOME)/Projects/common-lisp/asdf-ios-app
SBCL ?= sbcl
BUNDLE_ID = com.lispnik.upc-logger

# A matched host ECL and iOS prefixes.  If they are not where ECL_DIR says,
# nothing is exported and asdf-ios-app falls back to what
# (asdf-ios-app:bootstrap-ecl) recorded.
ECL_DIR ?= $(HOME)/Projects/ecl
ifneq ($(wildcard $(ECL_DIR)/ecl-iOS-sim/bin/ecl-config),)
export ECL_HOST ?= $(ECL_DIR)/ecl-native/bin/ecl
export ECL_IOS_PREFIX ?= $(ECL_DIR)/ecl-iOS
export ECL_IOS_SIM_PREFIX ?= $(ECL_DIR)/ecl-iOS-sim
endif
ECL ?= $(or $(wildcard $(ECL_HOST)),ecl)

# :IGNORE-INHERITED-CONFIGURATION so a missing dependency fails here rather
# than resolving to whatever a personal init file happens to point at.  Each
# tree's ocicl/ directory is inside it, so :TREE finds those too.
REGISTRY = (asdf:initialize-source-registry \
              (list :source-registry \
                    (list :tree (truename "./")) \
                    (list :tree (truename "$(OBJC_DIR)")) \
                    (list :tree (truename "$(IOS_APP_DIR)")) \
                    :ignore-inherited-configuration))

# ECL in batch: any unhandled error exits 1 instead of waiting at a debugger
# prompt that nobody is there to answer.
define ecl
$(ECL) --norc \
  --eval '(require :asdf)' \
  --eval '$(REGISTRY)' \
  --eval '(handler-bind ((serious-condition (lambda (c) (format *error-output* "~&error: ~a~%" c) (finish-output *error-output*) (ext:quit 1)))) $(1))' \
  --eval '(ext:quit 0)'
endef

# Built for the simulator only unless a signing identity is in the
# environment -- see :BUNDLE-PLATFORMS in upc-logger-app.asd.
SIM_ENV = IOS_SIGNING_IDENTITY= IOS_PROVISIONING_PROFILE=
DEVICE_ENV = IOS_SIGNING_IDENTITY="$(IOS_SIGNING_IDENTITY)" \
             IOS_PROVISIONING_PROFILE="$(IOS_PROVISIONING_PROFILE)"

BUILD_AND_INSTALL_SIM = \
  (asdf:load-system "asdf-ios-app") \
  (uiop:symbol-call :asdf-ios-app "INSTALL-IN-SIMULATOR" \
    (first (uiop:symbol-call :asdf-ios-app "MAKE-APP" "upc-logger-app" :platforms (list :simulator))))

.PHONY: all test sim run-sim demo-sim device icon deps clean

all: test sim

test:
	$(call ecl,(asdf:load-system :upc-logger/tests) (unless (uiop:symbol-call :upc-logger/tests :run-tests) (ext:quit 1)))

sim:
	$(SIM_ENV) $(call ecl,(asdf:make "upc-logger-app"))

run-sim:
	$(SIM_ENV) $(call ecl,$(BUILD_AND_INSTALL_SIM))
	-xcrun simctl terminate booted $(BUNDLE_ID)
	xcrun simctl launch booted $(BUNDLE_ID)

demo-sim:
	$(SIM_ENV) $(call ecl,$(BUILD_AND_INSTALL_SIM))
	-xcrun simctl terminate booted $(BUNDLE_ID)
	SIMCTL_CHILD_UPC_LOGGER_DEMO=1 xcrun simctl launch booted $(BUNDLE_ID)

device:
	@test -n "$(IOS_SIGNING_IDENTITY)" || { echo "error: set IOS_SIGNING_IDENTITY and IOS_PROVISIONING_PROFILE in local.mk" >&2; exit 1; }
	$(DEVICE_ENV) $(call ecl,\
	  (asdf:load-system "asdf-ios-app") \
	  (let* ((app (first (uiop:symbol-call :asdf-ios-app "MAKE-APP" "upc-logger-app" :platforms (list :device)))) \
	         (device (uiop:symbol-call :asdf-ios-app "INSTALL-ON-DEVICE" app))) \
	    (uiop:run-program (list "xcrun" "devicectl" "device" "process" "launch" "--device" device "$(BUNDLE_ID)") \
	                      :output t :error-output t :ignore-error-status t)))

# The icon is drawn by tools/icon.lisp; the PNG is committed so that building
# the app needs neither SBCL nor AppKit.  ImageMagick drops the alpha channel,
# which an App Store icon may not have.
ICON = res/Icon.xcassets/AppIcon.appiconset/icon-1024.png

icon: $(ICON)

$(ICON): tools/icon.lisp
	$(SBCL) --non-interactive --no-userinit --no-sysinit \
	  --eval '(require :asdf)' \
	  --eval '$(REGISTRY)' \
	  --eval '(asdf:load-system :objc)' \
	  --load tools/icon.lisp \
	  --eval '(upc-logger-icon:render-icon "$(ICON)")'
	magick "$(ICON)" -alpha off "$(ICON)"
	@echo "drew $(ICON)"

deps:
	ocicl install
	cd "$(OBJC_DIR)" && ocicl install

clean:
	rm -rf build
	find . -name '*.fasl' -o -name '*.fas' -o -name '*.fasc' | xargs rm -f
