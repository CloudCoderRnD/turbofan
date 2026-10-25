#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 CloudCoder Limited
#
# Builds, (optionally) notarizes, zips and signs a TurboFan Pro release, and writes the Sparkle appcast.
#   DEVELOPER_ID   "Developer ID Application: CloudCoder Limited (TEAMID)"  -> Developer ID signing
#   NOTARY_PROFILE notarytool keychain profile (xcrun notarytool store-credentials) -> notarize + staple
#   DOWNLOAD_BASE  where the zip will be served (default https://turbo.cloud-coder.com/pro)
# Output: dist/TurboFanPro-<version>.zip, dist/appcast.xml
set -euo pipefail
cd "${0:A:h}/.."
VERSION=$(cat VERSION)
BASE=${DOWNLOAD_BASE:-https://turbo.cloud-coder.com/pro}
SPARKLE_BIN=.build/artifacts/sparkle/Sparkle/bin
SPARKLE_KEY=${SPARKLE_KEY_FILE:-$HOME/Documents/ccode/turbofan-pro/sparkle-private.key}
APP="build/TurboFan Pro.app"
ZIP="dist/TurboFanPro-$VERSION.zip"

scripts/build-pro.sh
mkdir -p dist
rm -f "$ZIP"

if [[ -n "${NOTARY_PROFILE:-}" && -n "${DEVELOPER_ID:-}" ]]; then
  echo "==> Notarizing"
  ditto -c -k --norsrc --noextattr --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
else
  echo "==> Skipping notarization (needs DEVELOPER_ID and NOTARY_PROFILE)"
fi

ditto -c -k --norsrc --noextattr --keepParent "$APP" "$ZIP"
SIG=$($SPARKLE_BIN/sign_update --ed-key-file "$SPARKLE_KEY" "$ZIP")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")
DATE=$(LC_ALL=en_US.UTF-8 date -u "+%a, %d %b %Y %H:%M:%S +0000")
cat > dist/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>TurboFan Pro</title>
    <item>
      <title>TurboFan Pro $VERSION</title>
      <pubDate>$DATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>$BASE/notes/$VERSION.html</sparkle:releaseNotesLink>
      <enclosure url="$BASE/TurboFanPro-$VERSION.zip" $SIG type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML
echo "wrote $ZIP and dist/appcast.xml"
