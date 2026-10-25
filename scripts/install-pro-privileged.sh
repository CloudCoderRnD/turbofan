#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 CloudCoder Limited
#
# Root part of the Pro install: the shared helpers (fan helper, kext, CLI, sudoers rule) via
# install-privileged.sh, then the Pro battery helper. Run as root: install-pro-privileged.sh <user>
# The app runs this from its bundle through the macOS password dialog.
set -euo pipefail
cd "${0:A:h}/.."
USER_NAME=$1
[[ $EUID -eq 0 ]] || { echo "must run as root"; exit 1; }
[[ "$USER_NAME" =~ ^[a-z_][a-z0-9_.-]*$ ]] || { echo "bad user name"; exit 1; }

# launchd stops services asynchronously; wait, and retry the start, or bootstrap fails with error 5.
stop_service() {
  launchctl bootout "system/$1" 2>/dev/null || true
  for _ in {1..20}; do launchctl print "system/$1" >/dev/null 2>&1 || return 0; sleep 0.5; done
}
start_service() {
  for _ in {1..5}; do launchctl bootstrap system "$1" 2>/dev/null && return 0; sleep 1; done
  launchctl bootstrap system "$1"
}

scripts/install-privileged.sh "$USER_NAME" 1

LABEL=com.cloudcoder.turbofanpro.helper
BIN=/Library/PrivilegedHelperTools/$LABEL
PLIST=/Library/LaunchDaemons/$LABEL.plist
echo "==> Installing Pro battery helper ($LABEL)"
stop_service $LABEL
install -m 755 -o root -g wheel build/turbofanpro-helper "$BIN"
cat > "$PLIST" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>$LABEL</string>
	<key>ProgramArguments</key>
	<array><string>$BIN</string><string>--allow-uid</string><string>$(id -u "$USER_NAME")</string></array>
	<key>RunAtLoad</key><true/>
	<key>KeepAlive</key><true/>
	<key>StandardOutPath</key><string>/var/log/turbofanpro.log</string>
	<key>StandardErrorPath</key><string>/var/log/turbofanpro.log</string>
</dict>
</plist>
XML
chown root:wheel "$PLIST"; chmod 644 "$PLIST"
start_service "$PLIST"

# Only one TurboFan app should run: Pro replaces Free.
pkill -x TurboFanApp 2>/dev/null || true
rm -rf "/Users/$USER_NAME/Applications/TurboFan.app"
echo "==> Pro install done"
