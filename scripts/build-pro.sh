#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 CloudCoder Limited
#
# Builds "build/TurboFan Pro.app" with Sparkle and every helper bundled inside
# (Contents/Resources/Installer), so the app can install or update its root helpers itself.
#
# Signing: with DEVELOPER_ID="Developer ID Application: CloudCoder Limited (TEAMID)" it signs with
# hardened runtime and a timestamp (ready for notarization); without it, ad-hoc.
set -euo pipefail
cd "${0:A:h}/.."
VERSION=$(cat VERSION)
BUILD=$(date +%Y%m%d%H%M)
# Public half of the CloudCoder update-signing key (the private half never leaves CloudCoder).
SPARKLE_PUBLIC=${SPARKLE_PUBLIC_KEY:-$(cat assets/sparkle-public-key.txt)}
FEED=${FEED_URL:-https://turbo.cloud-coder.com/pro/appcast.xml}

echo "==> Free app, helpers, CLI and kext"
scripts/build-app.sh >/dev/null

echo "==> Pro app and battery helper"
swift build -c release
BIN=$(swift build -c release --show-bin-path)

APP="build/TurboFan Pro.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources/Installer/build" "$APP/Contents/Resources/Installer/scripts"
cp "$BIN/TurboFanProApp" "$APP/Contents/MacOS/TurboFanProApp"
ditto "$BIN/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
cp assets/AppIconPro.icns "$APP/Contents/Resources/AppIcon.icns"

INST="$APP/Contents/Resources/Installer"
cp build/turbofan build/turbofand "$BIN/turbofanpro-helper" "$INST/build/"
ditto build/TurboFanMSR.kext "$INST/build/TurboFanMSR.kext"
cp scripts/install-privileged.sh scripts/install-pro-privileged.sh "$INST/scripts/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>TurboFanProApp</string>
	<key>CFBundleIdentifier</key><string>com.cloudcoder.TurboFanPro</string>
	<key>CFBundleName</key><string>TurboFan Pro</string>
	<key>CFBundleDisplayName</key><string>TurboFan Pro</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>$VERSION</string>
	<key>CFBundleVersion</key><string>$BUILD</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>NSHumanReadableCopyright</key><string>© 2026 CloudCoder Limited. GPL-3.0-or-later.</string>
	<key>LSUIElement</key><true/>
	<key>NSHighResolutionCapable</key><true/>
	<key>SUFeedURL</key><string>$FEED</string>
	<key>SUPublicEDKey</key><string>$SPARKLE_PUBLIC</string>
	<key>SUEnableAutomaticChecks</key><true/>
	<key>SUScheduledCheckInterval</key><integer>86400</integer>
</dict>
</plist>
PLIST

echo "==> Signing"
if [[ -n "${DEVELOPER_ID:-}" ]]; then
  SIGN=(codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID")
  FW="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
  # Inside out: Sparkle's helpers, the framework, our helpers, then the app.
  for item in "$FW/XPCServices/Installer.xpc" "$FW/XPCServices/Downloader.xpc" "$FW/Autoupdate" "$FW/Updater.app"; do
    [[ -e "$item" ]] && "${SIGN[@]}" "$item"
  done
  "${SIGN[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
  for b in turbofan turbofand turbofanpro-helper; do "${SIGN[@]}" "$INST/build/$b"; done
  "${SIGN[@]}" "$APP"
  echo "signed with $DEVELOPER_ID"
else
  codesign --force --deep --sign - "$APP"
  echo "ad-hoc signed (set DEVELOPER_ID for a Developer ID build)"
fi
codesign --verify --deep --strict "$APP" && echo "built $APP $VERSION ($BUILD)"
