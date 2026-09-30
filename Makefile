TARGET := iphone:clang:latest:15.0
ARCHS ?= arm64 arm64e
DEBUG = 0
FINALPACKAGE = 1
THEOS_PACKAGE_SCHEME ?= rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = CrashAnalyzerPrefs
CrashAnalyzerPrefs_FILES = CAPRootListController.m CALogStore.m CAReportViewController.m
CrashAnalyzerPrefs_FRAMEWORKS = UIKit Foundation
# Preferences.framework is private and is not shipped in the public SDK.
# Preference classes are resolved by Settings at runtime; do not link it here.
CrashAnalyzerPrefs_LDFLAGS = -Wl,-undefined,dynamic_lookup
CrashAnalyzerPrefs_RESOURCE_DIRS = Resources
CrashAnalyzerPrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk

after-install::
	install.exec "sbreload"
