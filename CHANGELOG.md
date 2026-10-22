# Changelog

## 1.0.2 — unreleased

- Messages now come from turbo.cloud-coder.com; "Get Pro" opens the CloudCoder Store.

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
