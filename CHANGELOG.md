# Changelog

## 1.1.0 — 2026-10-25

- **TurboFan Pro is now open source** in this repository (GPL-3.0): battery charge limit, Mac health
  report with 90-day history and CSV export, licence keys and trial, Sparkle auto-updates,
  self-installing helpers. CloudCoder sells the official signed build.
- Messages now come from turbo.cloud-coder.com; "Get Pro" opens the CloudCoder Store.
- Throttle warning says "heat or power" (macOS also limits the CPU on a too-small charger).
- `--shots <dir>` saves real screenshots of every tab.
- From contributors (thanks, Mossaddique Ahsan): helper no longer dies on SIGPIPE; CI token is
  read-only except for releases; docs synced; fan safety test exit code, one-fan Macs and Ctrl-C
  cleanup; message links and images must be https; VoiceOver labels; first unit tests.

## 1.0.1 — 2026-10-22

- **Fix:** the root helper could spin at high CPU and memory after it stopped sampling CPU power
  (powermetrics end-of-file was read in a loop). Everyone on 1.0.0 should update.
- Installer waits for the old helper to stop before starting the new one (fixes "Bootstrap failed: 5").
- Panel footer shows cloud-coder.com and the edition (Free / Pro), with a link to TurboFan Pro.
- About window shows the edition and the CloudCoder website.
- App code split into the `TurboFanUI` library with a plug-in hook for other editions.
- In-app messages from CloudCoder (update notices, news) with image cards; can be turned off.

## 1.0.0 — 2026-10-22

First public release.

- Turbo Boost on/off via the TurboFanMSR kext, with Low Power Mode fallback; auto rules for battery,
  temperature and apps; re-applied after sleep.
- Fan control: Auto, Fixed, Linear and Curve modes per fan; Quiet, Balanced, Cool and Full speed presets.
- Profiles (Silent, Balanced, Performance, Max) with automatic switching by apps, external display,
  battery or AC.
- Readings: CPU clock and package power, all SMC temperature sensors, thermal throttling warning.
- Root helper with fan safety: clamped speeds, full speed on lost sensor, auto at 100 °C, auto on
  stop, crash cleanup. `scripts/test-fan-safety.sh`.
- `turbofan` command-line tool.
