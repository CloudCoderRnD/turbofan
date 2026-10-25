#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 CloudCoder Limited
# Builds everything and writes dist/TurboFan-<version>.zip (prebuilt files + install scripts + docs).
set -euo pipefail
cd "${0:A:h}/.."
VERSION=$(cat VERSION)
NAME=TurboFan-$VERSION

TF_CHANNEL=release scripts/build-app.sh
rm -rf "dist/$NAME" "dist/$NAME.zip"
mkdir -p "dist/$NAME/build" "dist/$NAME/scripts"
cp -R build/TurboFan.app build/turbofan build/turbofand build/TurboFanMSR.kext "dist/$NAME/build/"
cp scripts/install.sh scripts/install-privileged.sh scripts/uninstall.sh scripts/test-fan-safety.sh "dist/$NAME/scripts/"
cp README.md LICENSE SECURITY.md CHANGELOG.md VERSION "dist/$NAME/"
mkdir -p "dist/$NAME/assets" && cp assets/AppIcon.png "dist/$NAME/assets/"
(cd dist && ditto -c -k --norsrc --noextattr --keepParent "$NAME" "$NAME.zip")
(cd dist && shasum -a 256 "$NAME.zip" | tee "$NAME.zip.sha256")
echo "wrote dist/$NAME.zip"
