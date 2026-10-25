#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 CloudCoder Limited
# Builds build/TurboFan.app, build/turbofan (CLI), build/turbofand (helper) and build/TurboFanMSR.kext.
set -euo pipefail
cd "${0:A:h}/.."
VERSION=$(cat VERSION)

# The CLI's version constant must match the VERSION file.
CODE_VERSION=$(sed -n 's/.*static let string = "\(.*\)".*/\1/p' Sources/TurboCore/Version.swift)
if [[ "$CODE_VERSION" != "$(cat VERSION)" ]]; then
  echo "error: VERSION is $(cat VERSION) but Sources/TurboCore/Version.swift says $CODE_VERSION" >&2
  exit 1
fi

swift build -c release
BIN=$(swift build -c release --show-bin-path)

APP=build/TurboFan.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/TurboFanApp" "$APP/Contents/MacOS/TurboFanApp"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp "$BIN/turbofan" build/turbofan
cp "$BIN/turbofand" build/turbofand

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>TurboFanApp</string>
	<key>CFBundleIdentifier</key><string>com.cloudcoder.TurboFan</string>
	<key>CFBundleName</key><string>TurboFan</string>
	<key>CFBundleDisplayName</key><string>TurboFan</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>$VERSION</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>NSHumanReadableCopyright</key><string>© 2026 CloudCoder Limited. GPL-3.0-or-later.</string>
	<key>LSUIElement</key><true/>
	<key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
codesign --force --sign - build/turbofan
codesign --force --sign - build/turbofand
kext/build.sh
echo "built $APP, build/turbofan"
