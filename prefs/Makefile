TARGET := iphone:clang:16.5:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = AutoPickUpPrefs

AutoPickUpPrefs_FILES = APURootListController.m APUAppListController.m
AutoPickUpPrefs_FRAMEWORKS = UIKit Contacts ContactsUI
AutoPickUpPrefs_PRIVATE_FRAMEWORKS = Preferences
AutoPickUpPrefs_INSTALL_PATH = /Library/PreferenceBundles
AutoPickUpPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
