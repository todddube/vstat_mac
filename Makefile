# Vibe Stats for macOS
#
# The Xcode project is GENERATED from project.yml. Never hand-edit the
# .xcodeproj — regenerate it. That is what keeps the build reviewable.

DEVELOPER_DIR := /Applications/Xcode-beta.app/Contents/Developer
export DEVELOPER_DIR

PROJECT := VibeStats.xcodeproj
SCHEME  := VibeStats
# DerivedData lives OUTSIDE the repo on purpose: this checkout sits in an
# iCloud-synced folder, and the fileprovider/FinderInfo xattrs it stamps on
# directories make codesign fail with "resource fork ... not allowed".
DERIVED := $(HOME)/Library/Developer/Xcode/DerivedData/VibeStats-build
APP     := $(DERIVED)/Build/Products/Debug/VibeStats.app

.PHONY: all generate build test run clean distclean fixtures release icon dmg notarize

all: build

# This checkout lives in ~/Documents, which iCloud Drive syncs. When XcodeGen
# rewrites the .xcodeproj directory mid-sync, iCloud resolves the race by
# leaving a conflict copy named "VibeStats 2.xcodeproj". It is always stale and
# always safe to delete — the project is generated, never authored.
generate:
	@rm -rf "VibeStats [0-9]*.xcodeproj" "project [0-9]*.yml"
	xcodegen generate --spec project.yml

build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-derivedDataPath $(DERIVED) build

test: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-derivedDataPath $(DERIVED) test

run: build
	@pkill -x VibeStats || true
	open $(APP)

release: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-derivedDataPath $(DERIVED) archive \
		-archivePath build/VibeStats.xcarchive

# Redraw the app icon at every size the asset catalogue needs. The artwork is
# drawn per size, never downscaled — a 1024 hub reduced to 16 px is mush.
icon:
	swift Scripts/make-appicon.swift VibeStats/Resources/Assets.xcassets/AppIcon.appiconset

# Re-capture live vendor payloads so schema drift shows up as a diff.
fixtures:
	@./Scripts/capture-fixtures.sh

# Developer ID signed, notarized, stapled — the only distribution that opens on
# a clean machine without a Gatekeeper fight.
notarize: release
	xcodebuild -exportArchive -archivePath build/VibeStats.xcarchive \
		-exportPath build/export -exportOptionsPlist Scripts/ExportOptions.plist
	ditto -c -k --keepParent build/export/VibeStats.app build/VibeStats.zip
	xcrun notarytool submit build/VibeStats.zip --keychain-profile "AC_PASSWORD" --wait
	xcrun stapler staple build/export/VibeStats.app

dmg:
	@./Scripts/make-dmg.sh

# Deliberately does NOT delete $(PROJECT): the generated .xcodeproj is
# committed, so removing it here would leave the working tree with a deleted
# tracked file every time someone cleaned. Use `make distclean` for that.
clean:
	rm -rf build $(DERIVED)

# The full nuke, including the committed project. `make generate` puts it back
# byte-for-byte, so this is recoverable — it is just not what `clean` should do.
distclean: clean
	rm -rf $(PROJECT)
