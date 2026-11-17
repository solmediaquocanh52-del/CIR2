ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CircleSwitcher
CircleSwitcher_FILES = Tweak.x
CircleSwitcher_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-function -Wno-absolute-value
CircleSwitcher_FRAMEWORKS = UIKit QuartzCore CoreGraphics Metal

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += CircleSwitcherPrefs
include $(THEOS_MAKE_PATH)/aggregate.mk
