ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = CircleSwitcherPrefs
CircleSwitcherPrefs_FILES = CSCircleSwitcherRootListController.mm CSCircleSwitcherLogoCell.mm CSCircleSwitcherPreviewHeader.mm CSCircleSwitcherEasterEgg.mm CSCircleSwitcherColorCell.mm CSCircleSwitcherLabeledSliderCell.mm
CircleSwitcherPrefs_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-function -Wno-absolute-value
CircleSwitcherPrefs_FRAMEWORKS = UIKit QuartzCore CoreGraphics Metal
CircleSwitcherPrefs_PRIVATE_FRAMEWORKS = Preferences
CircleSwitcherPrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)$(THEOS_PACKAGE_BASE_PATH)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)$(THEOS_PACKAGE_BASE_PATH)/Library/PreferenceLoader/Preferences/CircleSwitcher.plist$(ECHO_END)
