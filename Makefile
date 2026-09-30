TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
DEBUG = 0
FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = CrashAnalyzerPrefs
CrashAnalyzerPrefs_FILES = CAPRootListController.m CALogStore.m CAReportViewController.m
CrashAnalyzerPrefs_FRAMEWORKS = UIKit Foundation
CrashAnalyzerPrefs_PRIVATE_FRAMEWORKS = Preferences
CrashAnalyzerPrefs_INSTALL_PATH = /Library/PreferenceBundles
CrashAnalyzerPrefs_CFLAGS = -fobjc-arc
CrashAnalyzerPrefs_RESOURCE_DIRS = Resources

include $(THEOS_MAKE_PATH)/bundle.mk

after-install::
	install.exec "sbreload"
