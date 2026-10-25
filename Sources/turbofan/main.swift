// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 CloudCoder Limited

import Foundation
import TurboCore

let usage = """
usage: turbofan <command>
  status   show turbo state, backend, temperature, fans
  version  show the TurboFan version
  on       enable Turbo Boost
  off      disable Turbo Boost
  watch    print temperature, fans and load every second
  sensors  list all temperature sensors
  metrics  CPU clock, package power, thermal limit (--raw: powermetrics sample)
  fans     show fans and their modes
  fans auto                      give all fans back to macOS
  fans preset quiet|balanced|cool|full|auto
  fan <n> auto                   fan n (1-based) back to macOS
  fan <n> <rpm>                  fixed speed
  fan <n> sensor <KEY> <from> <to>  min speed at <from> °C, max at <to> °C
"""

func printStatus() {
    let s = Turbo.status()
    print("turbo:      \(s.turboOn ? "ON" : "OFF")")
    print("backend:    \(s.backend.rawValue)\(Turbo.kextInstalled ? "" : " (kext not installed)")")
    print("low power:  \(s.lowPowerMode ? "on" : "off")")
    if let t = SMC.shared.cpuTemperature() { print(String(format: "cpu temp:   %.1f °C", t)) }
    let fans = SMC.shared.fanSpeeds()
    if !fans.isEmpty { print("fans:       " + fans.map { "\(Int($0)) rpm" }.joined(separator: ", ")) }
    print("power:      \(Power.onBattery() ? "battery" : "AC")\(Power.batteryPercent().map { " (\($0)%)" } ?? "")")
}

let args = CommandLine.arguments.dropFirst()
switch args.first {
case "version", "--version", "-v":
    print("turbofan \(TurboFanVersion.string)")
case "status", nil:
    printStatus()
case "on", "off":
    do {
        let backend = try Turbo.set(on: args.first == "on")
        print("turbo \(args.first!) via \(backend.rawValue)")
    } catch {
        FileHandle.standardError.write("error: \(error)\nRun scripts/install.sh once to allow password-free switching.\n".data(using: .utf8)!)
        exit(1)
    }
case "sensors":
    for s in SMC.shared.temperatureSensors() {
        print("\(s.key)  \(s.name.padding(toLength: 22, withPad: " ", startingAt: 0))" + String(format: "%5.1f °C", s.value))
    }
case "fans", "fan":
    let rest = Array(args.dropFirst())
    func describe(_ m: FanMode) -> String {
        switch m {
        case .auto: return "auto"
        case let .constant(rpm): return "constant \(Int(rpm)) rpm"
        case let .sensor(key, from, to): return "\(SMC.sensorName(key)) (\(key)) \(Int(from))–\(Int(to)) °C"
        case let .curve(key, points):
            let preset = FanPreset.matching(m).map { "\($0.rawValue) preset, " } ?? ""
            return preset + "curve on \(SMC.sensorName(key)): " + points.map { "\(Int($0.temp))°→\(Int($0.percent))%" }.joined(separator: " ")
        }
    }
    do {
        var fans: [FanInfo]
        if rest == ["auto"] {
            fans = try FanClient.autoAll()
        } else if rest.first == "preset", rest.count == 2,
                  let preset = FanPreset.allCases.first(where: { $0.rawValue.lowercased().hasPrefix(rest[1].lowercased()) }) {
            fans = try FanClient.apply(preset: preset, fanCount: try FanClient.status().count)
        } else if let n = rest.first.flatMap(Int.init), rest.count >= 2 {
            let mode: FanMode
            if rest[1] == "auto" {
                mode = .auto
            } else if rest[1] == "sensor", rest.count == 5, let from = Double(rest[3]), let to = Double(rest[4]) {
                mode = .sensor(key: rest[2], from: from, to: to)
            } else if let rpm = Double(rest[1]) {
                mode = .constant(rpm: rpm)
            } else {
                print(usage); exit(2)
            }
            fans = try FanClient.set(fan: n - 1, mode: mode)
        } else if rest.isEmpty {
            fans = try FanClient.status()
        } else {
            print(usage); exit(2)
        }
        for f in fans {
            print("\(f.name): \(Int(f.actual)) rpm (range \(Int(f.min))–\(Int(f.max)))  mode: \(describe(f.mode))")
        }
    } catch {
        FileHandle.standardError.write("error: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
case "metrics":
    do {
        if args.dropFirst().first == "--raw" {
            _ = try FanClient.snapshot()
            Thread.sleep(forTimeInterval: 5)
            print(try FanClient.rawMetrics())
        } else {
            var m = try FanClient.snapshot().metrics
            for _ in 0..<10 where m == nil { // sampler needs a few seconds after it starts
                Thread.sleep(forTimeInterval: 1)
                m = try FanClient.snapshot().metrics
            }
            print("cpu clock:  \(m?.cpuMHz.map { "\(Int($0)) MHz" } ?? "-")\(m?.nominalPercent.map { String(format: " (%.0f%% of nominal)", $0) } ?? "")")
            print("package:    \(m?.packageWatts.map { String(format: "%.1f W", $0) } ?? "-")")
        }
        let t = Thermal.read()
        print("cpu limit:  \(t.speedLimit)%\(t.throttled ? "  (THROTTLED)" : "")")
    } catch {
        FileHandle.standardError.write("error: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
case "smc":
    // Debug: dump all SMC keys whose name starts with the given prefixes (default: fans + temps).
    let prefixes = args.count > 1 ? Array(args.dropFirst()) : ["F", "T"]
    for key in SMC.shared.allKeys() where prefixes.contains(where: { key.hasPrefix($0) }) {
        let t = SMC.shared.type(of: key) ?? "?"
        let v = SMC.shared.value(key).map { String(format: "%.2f", $0) } ?? (SMC.shared.read(key)?.bytes.map { String(format: "%02x", $0) }.joined() ?? "-")
        print("\(key)  [\(t)]  \(v)")
    }
case "watch":
    let load = CPULoad()
    while true {
        Thread.sleep(forTimeInterval: 1)
        let t = SMC.shared.cpuTemperature().map { String(format: "%.1f°C", $0) } ?? "-"
        let f = SMC.shared.fanSpeeds().map { "\(Int($0))" }.joined(separator: "/")
        print(String(format: "%@  temp %@  fans %@ rpm  load %3.0f%%  turbo %@",
                     DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium),
                     t, f, load.sample() * 100, Turbo.status().turboOn ? "on" : "off"))
    }
default:
    print(usage)
    exit(2)
}
