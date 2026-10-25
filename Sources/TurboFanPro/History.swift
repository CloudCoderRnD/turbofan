// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 CloudCoder Limited

import Foundation
import SQLite3
import TurboCore

/// One history row, recorded every minute while TurboFan runs.
struct HistorySample: Identifiable, Equatable {
    var id: Double { ts }
    var ts: Double
    var cpu: Double?
    var watts: Double?
    var mhz: Double?
    var fan: Double? // average fan speed, rpm
    var fanFraction: Double? // average fan speed as a fraction of max (0...1)
    var throttle: Int // CPU speed limit percent (100 = none)
    var battery: Int?
    var onAC: Bool
    var adapterWatts: Int?
    var load: Double

    var date: Date { Date(timeIntervalSince1970: ts) }
}

/// SQLite store at ~/Library/Application Support/TurboFan Pro/history.sqlite. Keeps 90 days.
final class HistoryStore: @unchecked Sendable {
    static let shared = HistoryStore()
    static let retention: TimeInterval = 90 * 86400

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "turbofanpro.history")

    let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TurboFan Pro", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.sqlite")
    }()

    private init() {
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { db = nil; return }
        exec("""
        CREATE TABLE IF NOT EXISTS samples (
          ts REAL PRIMARY KEY, cpu REAL, watts REAL, mhz REAL, fan REAL, fan_frac REAL,
          throttle INTEGER, battery INTEGER, on_ac INTEGER, adapter INTEGER, load REAL)
        """)
    }

    private func exec(_ sql: String) {
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    func insert(_ s: HistorySample) {
        queue.async { [self] in
            var stmt: OpaquePointer?
            let sql = "INSERT OR REPLACE INTO samples VALUES (?,?,?,?,?,?,?,?,?,?,?)"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            func bind(_ i: Int32, _ v: Double?) { if let v { sqlite3_bind_double(stmt, i, v) } else { sqlite3_bind_null(stmt, i) } }
            func bindInt(_ i: Int32, _ v: Int?) { if let v { sqlite3_bind_int64(stmt, i, Int64(v)) } else { sqlite3_bind_null(stmt, i) } }
            bind(1, s.ts); bind(2, s.cpu); bind(3, s.watts); bind(4, s.mhz); bind(5, s.fan); bind(6, s.fanFraction)
            bindInt(7, s.throttle); bindInt(8, s.battery); bindInt(9, s.onAC ? 1 : 0); bindInt(10, s.adapterWatts); bind(11, s.load)
            sqlite3_step(stmt)
            let cutoff = Date().timeIntervalSince1970 - Self.retention
            exec("DELETE FROM samples WHERE ts < \(cutoff)")
        }
    }

    /// Samples since a date, oldest first.
    func samples(since: Date) -> [HistorySample] {
        queue.sync { [self] in
            var stmt: OpaquePointer?
            let sql = "SELECT ts,cpu,watts,mhz,fan,fan_frac,throttle,battery,on_ac,adapter,load FROM samples WHERE ts >= ? ORDER BY ts"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_double(stmt, 1, since.timeIntervalSince1970)
            var rows: [HistorySample] = []
            func d(_ i: Int32) -> Double? { sqlite3_column_type(stmt, i) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, i) }
            func n(_ i: Int32) -> Int? { sqlite3_column_type(stmt, i) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(stmt, i)) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(HistorySample(ts: sqlite3_column_double(stmt, 0), cpu: d(1), watts: d(2), mhz: d(3), fan: d(4),
                                          fanFraction: d(5), throttle: n(6) ?? 100, battery: n(7), onAC: n(8) == 1,
                                          adapterWatts: n(9), load: d(10) ?? 0))
            }
            return rows
        }
    }

    func count() -> Int {
        queue.sync { [self] in
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM samples", -1, &stmt, nil) == SQLITE_OK else { return 0 }
            defer { sqlite3_finalize(stmt) }
            return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int64(stmt, 0)) : 0
        }
    }

    func csv(since: Date) -> String {
        let f = ISO8601DateFormatter()
        var out = "time,cpu_c,package_w,clock_mhz,fan_rpm,fan_pct,cpu_limit_pct,battery_pct,on_ac,adapter_w,load_pct\n"
        func s(_ v: Double?, _ fmt: String = "%.1f") -> String { v.map { String(format: fmt, $0) } ?? "" }
        for r in samples(since: since) {
            out += [f.string(from: r.date), s(r.cpu), s(r.watts), s(r.mhz, "%.0f"), s(r.fan, "%.0f"),
                    s(r.fanFraction.map { $0 * 100 }, "%.0f"), String(r.throttle), r.battery.map(String.init) ?? "",
                    r.onAC ? "1" : "0", r.adapterWatts.map(String.init) ?? "", String(format: "%.0f", r.load * 100)]
                .joined(separator: ",") + "\n"
        }
        return out
    }
}

/// Records one sample a minute while the app runs.
@MainActor
final class Recorder {
    static let shared = Recorder()
    private var timer: Timer?
    private let cpu = CPULoad()

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in Recorder.shared.record() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { Recorder.shared.record() }
    }

    func record() {
        let load = cpu.sample()
        Task.detached {
            let smc = SMC.shared
            let count = Int(smc.value("FNum") ?? 0)
            let speeds = (0..<count).compactMap { smc.value("F\($0)Ac") }
            let fractions = (0..<count).compactMap { i -> Double? in
                guard let a = smc.value("F\(i)Ac"), let lo = smc.value("F\(i)Mn"), let hi = smc.value("F\(i)Mx"), hi > lo else { return nil }
                return min(1, max(0, (a - lo) / (hi - lo)))
            }
            // The helper runs powermetrics only while asked (30 s idle stop): wake it, then read.
            var metrics = (try? FanClient.snapshot())?.metrics
            if metrics == nil {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                metrics = (try? FanClient.snapshot())?.metrics
            }
            let battery = BatteryInfo.read()
            let sample = HistorySample(
                ts: Date().timeIntervalSince1970.rounded(),
                cpu: smc.cpuTemperature(),
                watts: metrics?.packageWatts,
                mhz: metrics?.cpuMHz,
                fan: speeds.isEmpty ? nil : speeds.reduce(0, +) / Double(speeds.count),
                fanFraction: fractions.isEmpty ? nil : fractions.reduce(0, +) / Double(fractions.count),
                throttle: Thermal.read().speedLimit,
                battery: battery.percent,
                onAC: battery.onAC,
                adapterWatts: battery.adapterWatts,
                load: load)
            HistoryStore.shared.insert(sample)
        }
    }
}
