# Contributing to TurboFan

Thanks for helping. TurboFan is small on purpose: one menu bar app, one CLI, one root helper and one
tiny kext.

## Most useful right now

- **Test reports from other Intel Macs.** Open an issue with your model, macOS version and the
  output of `turbofan status`, `turbofan fans` and `turbofan sensors`. Sensor and fan keys differ
  between models.
- **Sensor names** for keys that only show their four-letter code (`Sources/TurboCore/Fans.swift`).
- Bug reports with steps to reproduce.

## Building

```bash
swift build                 # debug build of everything (Free, Pro, CLI, helpers)
swift test                  # unit tests (fan curves, presets, powermetrics parser); needs Xcode
./scripts/build-app.sh      # Free release build: build/TurboFan.app, CLI, helper, kext
./scripts/build-pro.sh      # Pro release build: build/TurboFan Pro.app
./scripts/install.sh        # install Free on this Mac (asks for your password)
```

Command Line Tools are enough to build; `swift test` needs Xcode (CI runs it).

Screenshots of every tab with real controls and live data, no screen-recording permission needed:
`build/TurboFan.app/Contents/MacOS/TurboFanApp --shots out/` (Pro: `build/TurboFan\ Pro.app/Contents/MacOS/TurboFanProApp --shots out/`).

## Pull requests

- Keep changes focused, and match the surrounding style.
- Anything that writes to the SMC, runs as root or touches the kext must keep the safety rules in
  [README.md](README.md#fan-safety) and the limits in [SECURITY.md](SECURITY.md). Run
  `sudo ./scripts/test-fan-safety.sh` if you change the helper.
- New source files start with the SPDX header used in the existing files.
- By contributing you agree that your contribution is licensed under GPL-3.0-or-later, like the rest
  of TurboFan (Free and Pro).

## Code of conduct

Be kind and assume good faith. Harassment is not tolerated.
