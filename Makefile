THEOS_DEVICE_IP = 192.168.1.15

TARGET := iphone:clang:16.5:14.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AutoPickUp
AutoPickUp_FILES = Tweak.xm
AutoPickUp_CFLAGS = -fobjc-arc
AutoPickUp_PRIVATE_FRAMEWORKS = TelephonyUtilities

# make AA_DEBUG=1 to log the tweak's decisions to Console.app
ifeq ($(AA_DEBUG),1)
AutoPickUp_CFLAGS += -DAA_DEBUG=1
endif

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
