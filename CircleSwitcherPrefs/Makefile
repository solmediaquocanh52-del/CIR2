TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = CircleSwitcherPrefs

CircleSwitcherPrefs_FILES = \
	CSCircleSwitcherRootListController.mm \
	CSCircleSwitcherLogoCell.mm \
	CSCircleSwitcherPreviewHeader.mm \
	CSCircleSwitcherEasterEgg.mm \
	CSCircleSwitcherColorCell.mm \
	CSCircleSwitcherLabeledSliderCell.mm

CircleSwitcherPrefs_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore
CircleSwitcherPrefs_CFLAGS = -fobjc-arc -Wno-error
CircleSwitcherPrefs_LDFLAGS = -Wl,-undefined,dynamic_lookup
CircleSwitcherPrefs_INSTALL_PATH = /Library/PreferenceBundles
CircleSwitcherPrefs_RESOURCE_DIRS = Resources

include $(THEOS_MAKE_PATH)/bundle.mk
