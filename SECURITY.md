# Security

TurboFan needs a few privileged pieces to do its job. This page lists exactly what they are, so you
can judge them before installing.

## What runs with privileges

**Fan and readings helper** — `/Library/PrivilegedHelperTools/com.cloudcoder.turbofan.helper`,
started by `/Library/LaunchDaemons/com.cloudcoder.turbofan.helper.plist`, runs as root.

- Writes only the SMC fan keys `F<n>Md` (mode) and `F<n>Tg` (target speed), always clamped to the
  fan's own range.
- Runs `/usr/bin/powermetrics --samplers cpu_power` while the app asks for readings, stopped ~30 s
  after the last request.
- Listens on the UNIX socket `/var/run/turbofan.sock`. Every connection is checked with
  `getpeereid`: only root and the user ID that installed TurboFan are answered.
- Accepts four JSON commands: status, set one fan's mode, all fans auto, raw readings. Modes are
  validated (sensor keys must exist, curve points in range).
- Saves fan settings to `/Library/Application Support/TurboFan/fans.json` (root-owned).

**Password-free switching rule** — `/etc/sudoers.d/turbofan` lets the installing user run exactly
these commands without a password, and nothing else:

```text
/usr/bin/pmset -a lowpowermode 0
/usr/bin/pmset -a lowpowermode 1
/usr/sbin/sysctl -w debug.turbofan_turbo=0
/usr/sbin/sysctl -w debug.turbofan_turbo=1
/usr/bin/kmutil load -b com.cloudcoder.TurboFanMSR
/usr/bin/kmutil load -p /Library/Application Support/TurboFan/TurboFanMSR.kext
/usr/bin/kmutil unload -b com.cloudcoder.TurboFanMSR
```

The rule is checked with `visudo -c` before it is installed.

**Kernel extension** — `TurboFanMSR.kext`, root-owned. It only reads and writes MSR `0x1A0` bit 38
and exposes one sysctl. It is ad-hoc signed and cannot load unless you relax kext protection in
Recovery (`csrutil enable --without kext`). That lowers your Mac's security; TurboFan works without
it using Low Power Mode.

## Network use

TurboFan makes one kind of request: every 6 hours it reads the CloudCoder message feed
(`https://turbo.cloud-coder.com/messages.json`) for update notices and news. The request carries
only the app version and edition (`?v=1.0.1&edition=free`); no device ID, account, or readings.
Turn it off in the About window ("Show news and update messages from CloudCoder").

TurboFan has no telemetry or analytics, and your readings and settings never leave your Mac.

## Reporting a vulnerability

Please report security problems privately through GitHub:
[Report a vulnerability](https://github.com/CloudCoderRnD/turbofan/security/advisories/new).
Do not open a public issue for security problems. We aim to reply within a week.
