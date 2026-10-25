// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 CloudCoder Limited

import AppKit
import Charts
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class HealthModel: ObservableObject {
    enum Range: String, CaseIterable, Identifiable {
        case hour = "1 h", day = "24 h", week = "7 d", month = "30 d"
        var id: String { rawValue }
        var seconds: TimeInterval {
            switch self { case .hour: 3600; case .day: 86400; case .week: 7 * 86400; case .month: 30 * 86400 }
        }
    }

    enum Metric: String, CaseIterable, Identifiable {
        case temp = "Temp", power = "Power", fans = "Fans", limit = "CPU limit", battery = "Battery"
        var id: String { rawValue }
    }

    @Published var findings: [HealthFinding] = []
    @Published var samples: [HistorySample] = []
    @Published var range: Range = .day { didSet { load() } }
    @Published var metric: Metric = .temp
    @Published var total = 0
    private var condition: String?

    func load() {
        let since = Date().addingTimeInterval(-range.seconds)
        let r = range
        Task.detached {
            let store = HistoryStore.shared
            let rows = store.samples(since: since)
            let day = r == .day ? rows : store.samples(since: Date().addingTimeInterval(-86400))
            let count = store.count()
            await MainActor.run {
                self.samples = Self.thin(rows, max: 400)
                self.total = count
                self.findings = HealthChecks.run(battery: BatteryInfo.read(), condition: self.condition, day: day)
            }
        }
        if condition == nil {
            Task.detached {
                let c = BatteryInfo.condition()
                await MainActor.run { self.condition = c; self.load() }
            }
        }
    }

    /// Keeps charts light: at most `max` evenly spaced points.
    nonisolated static func thin(_ rows: [HistorySample], max: Int) -> [HistorySample] {
        guard rows.count > max else { return rows }
        let step = Double(rows.count) / Double(max)
        return (0..<max).map { rows[Int(Double($0) * step)] }
    }

    func value(_ s: HistorySample) -> Double? {
        switch metric {
        case .temp: return s.cpu
        case .power: return s.watts
        case .fans: return s.fan
        case .limit: return Double(s.throttle)
        case .battery: return s.battery.map(Double.init)
        }
    }

    var unit: String {
        switch metric { case .temp: "°C"; case .power: "W"; case .fans: "rpm"; case .limit, .battery: "%" }
    }

    func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "TurboFan history.csv"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = HistoryStore.shared.csv(since: Date().addingTimeInterval(-HistoryStore.retention))
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}

struct HealthView: View {
    @StateObject private var model = HealthModel()

    private var summary: (String, Color) {
        let problems = model.findings.filter { $0.level >= .warning }.count
        if problems == 0 { return ("Your Mac looks healthy", .green) }
        return ("\(problems) thing\(problems == 1 ? "" : "s") to look at", problems > 1 ? .orange : .yellow)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "stethoscope").foregroundStyle(summary.1)
                Text(summary.0).font(.headline)
                Spacer()
                Button { model.load() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).help("Refresh")
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.findings) { f in FindingRow(finding: f) }
            }
            Divider()
            history
        }
        .onAppear { model.load() }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("History").font(.headline)
                Spacer()
                Picker("", selection: $model.range) {
                    ForEach(HealthModel.Range.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 170)
            }
            Picker("", selection: $model.metric) {
                ForEach(HealthModel.Metric.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            Chart(model.samples) { s in
                if let v = model.value(s) {
                    LineMark(x: .value("Time", s.date), y: .value(model.unit, v))
                        .foregroundStyle(Color(red: 0.31, green: 0.72, blue: 1.0))
                        .interpolationMethod(.monotone)
                }
            }
            .chartYAxisLabel(model.unit)
            .frame(height: 110)
            .overlay {
                if model.samples.isEmpty {
                    Text("No history yet for this range").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("\(model.total) samples, one a minute, kept 90 days").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Export CSV…") { model.exportCSV() }.controlSize(.small)
            }
        }
    }
}

struct FindingRow: View {
    let finding: HealthFinding

    private var icon: (String, Color) {
        switch finding.level {
        case .good: ("checkmark.circle.fill", .green)
        case .info: ("info.circle.fill", .blue)
        case .warning: ("exclamationmark.triangle.fill", .orange)
        case .problem: ("xmark.octagon.fill", .red)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon.0).foregroundStyle(icon.1)
            VStack(alignment: .leading, spacing: 2) {
                Text(finding.title).font(.callout.bold())
                Text(finding.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let a = finding.advice {
                    Text(a).font(.caption).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
