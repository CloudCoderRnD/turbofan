#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 CloudCoder Limited
# Fan daemon safety test. Run as root (sudo scripts/test-fan-safety.sh).
#   1. clean stop (bootout)  -> fans back to Auto
#   2. start again           -> saved fan setting comes back
#   3. crash (SIGKILL) with the saved setting gone -> stale manual fan reset to Auto
# Ends with all fans on Auto, also when interrupted. Exits non-zero if any check fails.
set -u
L=com.cloudcoder.turbofan.helper
T=/usr/local/bin/turbofan
CONFIG="/Library/Application Support/TurboFan/fans.json"
[[ $EUID -eq 0 ]] || { echo "must run as root"; exit 1; }

md() { $T smc F0Md | awk '{print $NF}'; }
md2() { $T smc F1Md | awk '{print $NF}'; }
wait_daemon() { for _ in {1..25}; do $T fans >/dev/null 2>&1 && return 0; sleep 1; done; return 1; }
# Ctrl-C mid-test must not leave a fan fixed or the daemon stopped.
cleanup() {
  launchctl print system/$L >/dev/null 2>&1 || launchctl bootstrap system /Library/LaunchDaemons/$L.plist
  wait_daemon && $T fans auto >/dev/null
}
trap 'echo; echo "interrupted: putting fans back on auto"; cleanup; exit 130' INT TERM
check() { [[ "$2" == "$3" ]] && echo "   PASS  $1 ($2)" || { echo "   FAIL  $1 (got $2, want $3)"; FAILED=1; }; }
FAILED=0

wait_daemon || { echo "daemon not running"; exit 1; }
FANS=$($T smc FNum | awk '{print int($NF)}')
echo "1. fan 1 fixed at 3000, then stop daemon (bootout, no restart)"
$T fan 1 3000 >/dev/null; sleep 3
check "manual before stop" "$(md)" "1.00"
launchctl bootout system/$L; sleep 1
check "auto after stop" "$(md)" "0.00"

echo "2. start daemon again"
launchctl bootstrap system /Library/LaunchDaemons/$L.plist
wait_daemon && sleep 3
check "manual again after restart" "$(md)" "1.00"
check "saved mode restored" "$($T fans | head -1 | sed 's/.*mode: //')" "constant 3000 rpm"

echo "3. crash (SIGKILL) with saved settings deleted"
rm -f "$CONFIG"
launchctl kill SIGKILL system/$L; sleep 0.5
check "still manual after crash (expected)" "$(md)" "1.00"
(( FANS > 1 )) && echo "   (fan 2 mode before restart: $(md2))"
wait_daemon && sleep 3
check "stale manual fan reset on start" "$(md)" "0.00"
(( FANS > 1 )) && check "fan 2 on auto" "$(md2)" "0.00"

$T fans auto >/dev/null
echo "done: all fans on auto. $([[ $FAILED == 0 ]] && echo 'ALL PASSED' || echo 'SOME FAILED')"
tail -8 /var/log/turbofan.log
exit $FAILED
