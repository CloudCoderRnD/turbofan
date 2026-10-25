// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 CloudCoder Limited

import Foundation
import TurboCore

/// One finding of the Mac health check.
struct HealthFinding: Identifiable, Equatable {
    enum Level: Int, Comparable {
        case good, info, warning, problem
        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    var id: String
    var level: Level
    var title: String
    var detail: String
    var advice: String?
}

/// Turns live readings and the last day of history into plain-language findings.
enum HealthChecks {
    static func run(battery: BatteryInfo, condition: String?, day: [HistorySample]) -> [HealthFinding] {
        var out: [HealthFinding] = []

        // Charger
        if let w = battery.adapterWatts, let need = MacModel.recommendedAdapterWatts {
            if w < need {
                out.append(.init(id: "charger", level: .problem, title: "Charger too small: \(w) W",
                                 detail: "This Mac needs a \(need) W charger. With \(w) W, macOS slows the CPU under load and the battery can drain while plugged in.",
                                 advice: "Use a \(need) W (or bigger) USB-C charger and cable."))
            } else {
                out.append(.init(id: "charger", level: .good, title: "Charger OK: \(w) W", detail: "Enough power for this Mac (\(need) W recommended)."))
            }
        }

        // Battery wear
        if let h = battery.healthPercent {
            let cycles = battery.cycles.map { ", \($0) cycles" } ?? ""
            let bad = h < 80 || condition?.lowercased().contains("service") == true
            out.append(.init(id: "battery", level: bad ? .warning : .good,
                             title: "Battery health \(h)%\(cycles)",
                             detail: condition.map { "macOS rates the battery: \($0)." } ?? "Capacity compared with new.",
                             advice: bad ? "Expect shorter battery life. A charge limit of 80% slows further wear; replacement restores full life." : nil))
        }
        if let t = battery.temperature, t > 40 {
            out.append(.init(id: "battery-heat", level: .warning, title: String(format: "Battery warm: %.0f °C", t),
                             detail: "Heat ages batteries fastest.", advice: "Keep vents clear and avoid charging on soft surfaces."))
        }

        guard day.count >= 10 else {
            out.append(.init(id: "history", level: .info, title: "Collecting history",
                             detail: "TurboFan records once a minute. Daily checks appear after about 10 minutes."))
            return out.sorted { $0.level > $1.level }
        }
        let n = Double(day.count)

        // Throttling
        let throttled = day.filter { $0.throttle < 100 }
        let tShare = Double(throttled.count) / n
        if tShare > 0.05 {
            let lowest = throttled.map(\.throttle).min() ?? 100
            let onAC = throttled.filter(\.onAC).count
            out.append(.init(id: "throttle", level: tShare > 0.25 ? .problem : .warning,
                             title: "CPU slowed \(Int(tShare * 100))% of the last day",
                             detail: "macOS limited the CPU, down to \(lowest)% speed\(onAC > throttled.count / 2 ? ", mostly while on the charger" : "").",
                             advice: "Common causes: a charger that is too small, heat, or dust in the fans."))
        } else {
            out.append(.init(id: "throttle", level: .good, title: "No significant throttling", detail: "CPU ran at full allowed speed in the last day."))
        }

        // Heat
        let temps = day.compactMap(\.cpu)
        if let maxT = temps.max() {
            let hot = Double(temps.filter { $0 >= 90 }.count) / Double(max(1, temps.count))
            out.append(.init(id: "heat", level: hot > 0.1 ? .warning : .good,
                             title: hot > 0.1 ? "CPU often very hot" : "Temperatures normal",
                             detail: String(format: "Peak %.0f °C; above 90 °C %d%% of the time.", maxT, Int(hot * 100)),
                             advice: hot > 0.1 ? "Try the Silent or Balanced profile, or turbo off for light work." : nil))
        }

        // Fans working hard at moderate temperatures: dust or blocked vents.
        let busyCool = day.filter { ($0.fanFraction ?? 0) > 0.85 && ($0.cpu ?? 100) < 70 }
        if Double(busyCool.count) / n > 0.3 {
            out.append(.init(id: "fans", level: .warning, title: "Fans working hard while cool",
                             detail: "Fans ran near full speed while the CPU stayed under 70 °C for much of the day.",
                             advice: "Often dust or blocked vents. Also check that no other fan app is forcing them."))
        }

        return out.sorted { $0.level > $1.level }
    }
}
