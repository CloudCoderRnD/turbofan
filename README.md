<p align="center">
  <img src="assets/AppIcon.png" width="128" alt="TurboFan icon">
</p>

<h1 align="center">TurboFan</h1>

<p align="center">
  Turbo Boost and fan control for Intel Macs, in one menu bar app.<br>
  Free and open source, made by <a href="https://cloud-coder.com">CloudCoder Limited</a>.
</p>

---

Intel MacBooks run hot. TurboFan lets you turn Turbo Boost off when you want a cool, quiet,
longer-lasting laptop, and take control of the fans when you want the opposite. Profiles switch both
for you based on what you are doing.

## Features

**Turbo Boost**
- Turn Turbo Boost on or off from the menu bar or the `turbofan` command.
- Auto rules: turbo off on battery, above a temperature, or while chosen apps run.
- Re-applies your choice after sleep.

**Fans**
- Per fan: Auto (macOS), Fixed speed, Linear (min speed at one temperature, max at another), or
  Curve (drag points on a chart).
- One-click presets for all fans: Auto, Quiet, Balanced, Cool, Full speed.
- Settings survive reboots. Fans go back to macOS control if TurboFan stops.

**Profiles**
- Silent, Balanced, Performance and Max combine a turbo setting and a fan preset; each is editable.
- Automatic switching by situation: meeting apps running, external display, battery or AC.

**Readings**
- CPU clock speed and package power (watts), CPU temperature, load and a 10-minute chart.
- Every temperature sensor the SMC exposes, with readable names.
- Warning when macOS throttles the CPU for heat; the menu bar icon turns into a thermometer.

**From CloudCoder**
- Update notices and news appear as a card in the panel (and optionally a macOS notification).
  Checked every 6 hours; can be turned off. See [SECURITY.md](SECURITY.md#network-use).

Measured on a MacBook Pro 15" (2019, Core i9-9980HK) with all cores busy: **turbo on 4.11 GHz at
67 W, turbo off 2.60 GHz at 20 W.**

## Requirements

- An **Intel** Mac. Apple silicon Macs have no Turbo Boost and are not supported.
- macOS 14 Sonoma or later.
- Admin password once, at install.
- To build from source: Xcode or the Command Line Tools (Swift 5.10+).

Tested on: MacBook Pro 15" 2019 (MacBookPro15,1, i9-9980HK, T2), macOS 15.7. Reports from other models are welcome.

## Install

### From a release

1. Download `TurboFan-<version>.zip` from [Releases](https://github.com/CloudCoderRnD/turbofan/releases) and unzip it.
2. In Terminal, in the unzipped folder:

   ```bash
   ./scripts/install.sh
   ```

The app is not notarized by Apple yet. The installer removes the download quarantine flag so macOS
will open it.

### From source

```bash
git clone https://github.com/CloudCoderRnD/turbofan.git
cd turbofan
./scripts/install.sh
```

The installer puts:

| What | Where |
|---|---|
| App | `~/Applications/TurboFan.app` |
| CLI | `/usr/local/bin/turbofan` |
| Fan and readings helper (root) | `/Library/PrivilegedHelperTools/com.cloudcoder.turbofan.helper` + LaunchDaemon |
| Turbo kext | `/Library/Application Support/TurboFan/TurboFanMSR.kext` |
| Password-free switching rule | `/etc/sudoers.d/turbofan` (exact commands only, see [SECURITY.md](SECURITY.md)) |

`./scripts/install.sh --no-kext` skips the kext.

## How turbo off works: kext or Low Power Mode

Real Turbo Boost control means writing an Intel CPU register (MSR `0x1A0`, bit 38), which only the
kernel can do. TurboFan ships a tiny kernel extension, `TurboFanMSR`, for that.

Apple only lets kexts signed with a special Apple certificate load with full security. TurboFan's
kext is not signed that way, so out of the box **TurboFan uses Low Power Mode** for "turbo off".
That works with full security and gives a similar result (lower clocks, less heat), but it is not
an exact turbo switch.

### Enable the kext (optional, lowers security)

> **Warning:** this relaxes System Integrity Protection for kernel extensions on your Mac.
> Only do it if you understand the trade-off.

1. Shut down. On an Intel Mac, hold **Cmd+R** at power on to start Recovery.
2. Open Utilities > Terminal and run `csrutil enable --without kext`.
3. Restart and run `turbofan off`.
4. If macOS shows "System Extension Blocked", open System Settings > Privacy & Security, click
   Allow, and restart.
5. `turbofan status` should now show `backend: Kext`.

To undo: run `./scripts/uninstall.sh`, then `csrutil enable` in Recovery.

## Command line

```text
turbofan status                     turbo state, backend, temperature, fans
turbofan version                    TurboFan version
turbofan on | off                   switch Turbo Boost
turbofan watch                      temperature, fans and load every second
turbofan sensors                    all temperature sensors
turbofan metrics [--raw]            CPU clock, package power, thermal limit (--raw: powermetrics sample)
turbofan fans                       fans and their modes
turbofan fans auto                  all fans back to macOS
turbofan fans preset quiet|balanced|cool|full|auto
turbofan fan <n> auto | <rpm>       one fan (1-based)
turbofan fan <n> sensor <KEY> <from> <to>
turbofan smc [prefixes]             dump SMC keys (default: fans F and temperatures T)
```

Example: `turbofan fan 1 sensor TCXC 50 85` runs fan 1 at minimum speed at 50 °C and full speed at 85 °C.

`turbofan smc` is useful for Mac model reports: it lists every fan and temperature key with its type and value.

## How it works

| Part | Path | Role |
|---|---|---|
| App | `Sources/TurboFanApp` | Entry point of the menu bar app. |
| UI | `Sources/TurboFanUI` | SwiftUI menu bar UI: Turbo, Fans, Profiles, Sensors tabs, in-app messages, and the plug-in hook for other editions. |
| Core | `Sources/TurboCore` | SMC reader/writer, sensors, fan types, turbo control, power and thermal readings. |
| Helper | `Sources/turbofand` | Root LaunchDaemon. Owns fan writes (`F<n>Md`, `F<n>Tg`) and runs `powermetrics` on demand. Local socket, only root and the installing user may connect. |
| CLI | `Sources/turbofan` | `turbofan` command. |
| Pro | `Sources/TurboFanPro`, `Sources/TurboFanProApp` | Pro edition: Battery and Health tabs, 90-day history (SQLite), licence and trial, Sparkle auto-updates, self-installing helpers. Plugs into `TurboFanUI` through its `EditionPlugin` hook. |
| Pro helper | `Sources/turbofanpro-helper` | Root LaunchDaemon for the battery charge limit (SMC `BCLM`); limit back to 100 % when it stops. |
| Licences | `Sources/ProShared`, `Sources/turbofan-license` | Ed25519-signed licence keys, checked offline; `turbofan-license` issues them. |
| Kext | `kext/TurboFanMSR.c` | Sets bit 38 of MSR `0x1A0` on all cores. Load = turbo off, unload = turbo on. `sysctl debug.turbofan_turbo` reads or sets it. |

### Fan safety

- Target speeds are clamped to each fan's own minimum and maximum.
- A sensor-driven fan whose sensor cannot be read runs at full speed.
- Every fan goes back to Auto if the CPU reaches 100 °C.
- When the helper stops, fans go back to Auto. After a crash, fans left in manual mode with no saved
  setting are reset on restart. The app warns if a fan is stuck in manual while the helper is down.

`sudo ./scripts/test-fan-safety.sh` checks all of this on your Mac.

Do not run another fan control app at the same time; they write the same SMC keys.

## Building TurboFan Pro

```bash
./scripts/build-pro.sh        # build/TurboFan Pro.app (Sparkle and all helpers bundled inside)
./scripts/release-pro.sh      # zip, update signature and appcast (needs the update-signing key)
```

Open `TurboFan Pro.app` and click **Install helpers**; it installs the fan, turbo and battery helpers
with one password prompt.

To use your own keys in a self-built Pro:

```bash
swift run turbofan-license keygen ~/my-licence.key        # prints a public key
# put that public key in Sources/TurboFanPro/LicenseManager.swift (publicKey), rebuild, then:
swift run turbofan-license issue ~/my-licence.key --name "Me" --email me@example.com
```

For your own update feed, generate a Sparkle key pair (`.build/artifacts/sparkle/Sparkle/bin/generate_keys`)
and set `SPARKLE_PUBLIC_KEY` and `FEED_URL` when running `build-pro.sh`.

## Uninstall

```bash
./scripts/uninstall.sh
```

Fans return to macOS control and turbo goes back on. Low Power Mode is left as it is.

## Editions

Everything here is open source under GPL-3.0, including the Pro features. Build it yourself for free,
or buy the official TurboFan Pro build from CloudCoder to support the project.

| | Free | Pro |
|---|---|---|
| Turbo Boost control, fan control, profiles, sensors, readings | ✓ | ✓ |
| Battery charge limit (50–100 %) | | ✓ |
| Mac health report with advice, 90-day history, CSV export | | ✓ |
| Automatic updates (signed by CloudCoder) | | ✓ official build |
| Drag-and-drop install, helpers install themselves | | ✓ |
| Priority email support | | ✓ official build |
| Source code | GPL-3.0, this repository | GPL-3.0, this repository |

The official Pro build is sold at the [CloudCoder Store](https://store.cloud-coder.com/turbofan) with a
14-day free trial. Licence keys and updates are signed with CloudCoder's private keys, which are not in
this repository; a Pro build you make yourself works, but uses your own keys (see below).

## Contributing

Bug reports, Mac model test results and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).
Security issues: see [SECURITY.md](SECURITY.md).

## License

Copyright © 2026 CloudCoder Limited.

TurboFan is free software: you can redistribute it and/or modify it under the terms of the
[GNU General Public License](LICENSE) as published by the Free Software Foundation, either version 3
of the License, or (at your option) any later version. It is distributed WITHOUT ANY WARRANTY.

Changing fan speeds and CPU settings is at your own risk. Mac, macOS and Apple silicon are trademarks
of Apple Inc. Intel and Turbo Boost are trademarks of Intel Corporation. TurboFan is not affiliated
with Apple or Intel.

<p align="center"><a href="https://cloud-coder.com">cloud-coder.com</a></p>
