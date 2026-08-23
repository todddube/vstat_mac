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

.PHONY: all generate build test run clean fixtures release

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

# Re-capture live vendor payloads so schema drift shows up as a diff.
fixtures:
	@./Scripts/capture-fixtures.sh

clean:
	rm -rf build $(PROJECT) $(DERIVED)
