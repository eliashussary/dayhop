APP := build/Dayhop.app
DEST := /Applications/Dayhop.app
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# Version comes from the latest git tag (v1.2.3 → 1.2.3) unless given: make dmg VERSION=1.2.3
VERSION ?= $(patsubst v%,%,$(shell git describe --tags --abbrev=0 2>/dev/null))
VERSION := $(or $(VERSION),0.1.0)
BUILD_NUMBER ?= $(shell git rev-list --count HEAD 2>/dev/null || echo 1)
DMG := build/Dayhop-$(VERSION).dmg

# UNIVERSAL=1 builds for both Apple Silicon and Intel.
ARCH_FLAGS := $(if $(UNIVERSAL),--arch arm64 --arch x86_64,)
SWIFT_BUILD := swift build -c release $(ARCH_FLAGS)

# "-" is ad-hoc signing. Set to a "Developer ID Application: …" identity for a distributable build.
SIGN_ID ?= -
SIGN_FLAGS := $(if $(filter -,$(SIGN_ID)),,--options runtime --timestamp --entitlements Resources/Dayhop.entitlements)

.PHONY: build bundle install dmg icon check screenshots clean

build:
	$(SWIFT_BUILD)

bundle: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp "$$($(SWIFT_BUILD) --show-bin-path)/Dayhop" $(APP)/Contents/MacOS/
	cp Resources/Info.plist $(APP)/Contents/
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" $(APP)/Contents/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(BUILD_NUMBER)" $(APP)/Contents/Info.plist
	codesign --force $(SIGN_FLAGS) --sign "$(SIGN_ID)" $(APP)

# Drag-to-install disk image: Dayhop.app next to an Applications shortcut.
dmg: bundle
	rm -rf build/dmg $(DMG)
	mkdir -p build/dmg
	cp -R $(APP) build/dmg/
	ln -s /Applications build/dmg/Applications
	hdiutil create -volname "Dayhop $(VERSION)" -srcfolder build/dmg -fs HFS+ -format UDZO -ov $(DMG)
	$(if $(filter -,$(SIGN_ID)),,codesign --force --timestamp --sign "$(SIGN_ID)" $(DMG))
	@echo "→ $(DMG)"

# Build, install to /Applications, register with LaunchServices, and (re)start.
install: bundle
	-pkill -x Dayhop
	rm -rf $(DEST)
	cp -R $(APP) $(DEST)
	touch $(DEST)
	$(LSREGISTER) -f $(DEST)
	open $(DEST) --args --background

# Regenerate the app icon (and the README copy) from scripts/make-icon.swift.
icon:
	swift scripts/make-icon.swift build/AppIcon.iconset
	iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
	mkdir -p .github/assets
	cp build/AppIcon.iconset/icon_128x128@2x.png .github/assets/icon.png

# Self-check for the date, countdown, time zone and meeting-link logic.
check:
	mkdir -p build
	swiftc -swift-version 5 -o build/check Sources/Dayhop/Logic.swift scripts/check/main.swift
	./build/check

# Render the README images from the real popover, reminder and settings views (see scripts/screenshots).
# English (US) with a 12-hour clock, whatever this Mac's locale.
screenshots:
	mkdir -p build
	swiftc -swift-version 5 -o build/screenshots $(filter-out Sources/Dayhop/main.swift Sources/Dayhop/AppDelegate.swift,$(wildcard Sources/Dayhop/*.swift)) scripts/screenshots/main.swift
	./build/screenshots .github/assets -AppleLocale en_US -AppleLanguages '(en)' -AppleICUForce24HourTime NO

clean:
	rm -rf .build build
