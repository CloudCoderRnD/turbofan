// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 CloudCoder Limited

import Charts
import SwiftUI
import TurboCore

struct FansView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("menuBarShowsFans") private var menuBarShowsFans = false

    /// Preset every fan currently follows, if they all match one.
    private var currentPreset: FanPreset? {
        let presets = model.fanInfo.map { FanPreset.matching($0.mode) }
        guard let first = presets.first, presets.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = model.fanError, model.fanInfo.isEmpty {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            if !model.fanInfo.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Preset (all fans)").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        ForEach(FanPreset.allCases) { preset in
                            Button(preset.rawValue) { model.applyFanPreset(preset) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .tint(currentPreset == preset ? .accentColor : nil)
                        }
                    }
                }
                Divider()
            }
            ForEach(model.fanInfo, id: \.index) { fan in
                FanCard(fan: fan)
                Divider()
            }
            Toggle("Show fan speed in the menu bar", isOn: $menuBarShowsFans)
                .font(.caption)
            if !model.fanInfo.isEmpty {
                Text("Quit other fan control apps while using this.").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

struct FanCard: View {
    enum Kind: String, CaseIterable { case auto = "Auto", constant = "Fixed", sensor = "Linear", curve = "Curve" }

    @EnvironmentObject var model: AppModel
    let fan: FanInfo

    @State private var kind: Kind = .auto
    @State private var rpm: Double = 3000
    @State private var sensorKey = FanPreset.sensor
    @State private var from: Double = 50
    @State private var to: Double = 85
    @State private var points: [CurvePoint] = []
    @State private var synced = false

    private var sensorPicker: some View {
        Picker("Sensor", selection: $sensorKey) {
            ForEach(model.sensors) { s in
                Text("\(s.name)  \(Int(s.value))°").tag(s.key)
            }
        }
        .onChange(of: sensorKey) { send() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(fan.name).font(.headline)
                Text("\(Int(fan.min))–\(Int(fan.max)) rpm").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(fan.actual)) rpm").font(.system(.title3, design: .rounded).monospacedDigit().bold())
            }
            ProgressView(value: min(1, max(0, (fan.actual - fan.min) / max(1, fan.max - fan.min))))
                .tint(.teal)
                .accessibilityLabel("\(fan.name) speed")
                .accessibilityValue("\(Int(fan.actual)) rpm")

            Picker("\(fan.name) mode", selection: $kind) {
                ForEach(Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: kind) { send() }

            switch kind {
            case .auto:
                Text("macOS controls this fan.").font(.caption).foregroundStyle(.secondary)
            case .constant:
                HStack {
                    Slider(value: $rpm, in: fan.min...fan.max, step: 100) { editing in
                        if !editing { send() }
                    }
                    .accessibilityLabel("\(fan.name) fixed speed")
                    .accessibilityValue("\(Int(rpm)) rpm")
                    Text("\(Int(rpm))").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
            case .sensor:
                sensorPicker
                HStack {
                    Stepper(value: $from, in: 30...90, step: 5) { Text("Min at \(Int(from))°").monospacedDigit() }
                        .onChange(of: from) { if to <= from { to = from + 5 }; send() }
                    Stepper(value: $to, in: 35...100, step: 5) { Text("Max at \(Int(to))°").monospacedDigit() }
                        .onChange(of: to) { if from >= to { from = to - 5 }; send() }
                }
                .font(.caption)
            case .curve:
                sensorPicker
                CurveEditor(points: $points,
                            current: model.sensors.first { $0.key == sensorKey }?.value,
                            onCommit: send)
                Text("Drag points. Speed % of this fan's range.").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: syncFromFan)
        .onChange(of: fan.mode) { // changed elsewhere, e.g. a preset or the CLI
            synced = false
            syncFromFan()
        }
    }

    /// Load the daemon's current mode into the controls.
    private func syncFromFan() {
        guard !synced else { return }
        switch fan.mode {
        case .auto:
            kind = .auto
            rpm = fan.actual
        case let .constant(r):
            kind = .constant
            rpm = r
        case let .sensor(key, f, t):
            kind = .sensor
            sensorKey = key
            from = f
            to = t
        case let .curve(key, p):
            kind = .curve
            sensorKey = key
            points = p
        }
        if points.isEmpty, case let .curve(_, p) = FanPreset.balanced.mode { points = p }
        rpm = min(fan.max, max(fan.min, rpm))
        DispatchQueue.main.async { synced = true }
    }

    private func send() {
        guard synced else { return }
        let mode: FanMode
        switch kind {
        case .auto: mode = .auto
        case .constant: mode = .constant(rpm: rpm)
        case .sensor: mode = .sensor(key: sensorKey, from: from, to: to)
        case .curve: mode = .curve(key: sensorKey, points: points)
        }
        guard mode != fan.mode else { return }
        model.setFan(fan.index, mode)
    }
}

/// Draggable fan curve: x = temperature, y = speed percent.
struct CurveEditor: View {
    @Binding var points: [CurvePoint]
    let current: Double?
    let onCommit: () -> Void
    @State private var dragging: Int?

    var body: some View {
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                LineMark(x: .value("°C", p.temp), y: .value("%", p.percent))
                    .foregroundStyle(.teal)
                PointMark(x: .value("°C", p.temp), y: .value("%", p.percent))
                    .foregroundStyle(.teal)
                    .symbolSize(70)
            }
            if let t = current {
                RuleMark(x: .value("now", t)) // current temperature; the sensor picker shows the number
                    .foregroundStyle(.red.opacity(0.6))
            }
        }
        .chartXScale(domain: 30...100)
        .chartYScale(domain: 0...100)
        .chartXAxis { AxisMarks(values: [30, 50, 70, 90]) { v in
            AxisGridLine(); AxisValueLabel { Text("\(v.as(Int.self) ?? 0)°") }
        } }
        .chartYAxis { AxisMarks(values: [0, 50, 100]) { v in
            AxisGridLine(); AxisValueLabel { Text("\(v.as(Int.self) ?? 0)%") }
        } }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { g in drag(g.location, proxy, geo) }
                        .onEnded { _ in
                            dragging = nil
                            onCommit()
                        })
            }
        }
        .frame(height: 120)
    }

    private func drag(_ location: CGPoint, _ proxy: ChartProxy, _ geo: GeometryProxy) {
        guard let plot = proxy.plotFrame else { return }
        let origin = geo[plot].origin
        let x = location.x - origin.x, y = location.y - origin.y
        guard let temp: Double = proxy.value(atX: x), let percent: Double = proxy.value(atY: y) else { return }
        let sorted = points.indices.sorted { points[$0].temp < points[$1].temp }
        if dragging == nil {
            dragging = sorted.min { abs(points[$0].temp - temp) < abs(points[$1].temp - temp) }
        }
        guard let i = dragging, let rank = sorted.firstIndex(of: i) else { return }
        // Keep points in temperature order: stay between neighbours.
        let lo = rank > 0 ? points[sorted[rank - 1]].temp + 1 : 30
        let hi = rank < sorted.count - 1 ? points[sorted[rank + 1]].temp - 1 : 100
        points[i].temp = min(hi, max(lo, temp.rounded()))
        points[i].percent = min(100, max(0, percent.rounded()))
    }
}

struct SensorsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if isSnapshot { grid } else { ScrollView { grid }.frame(height: 360) }
    }

    private var grid: some View {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                ForEach(model.sensors) { s in
                    GridRow {
                        Text(s.name)
                        Text(s.key).font(.caption.monospaced()).foregroundStyle(.secondary)
                        Text(String(format: "%.0f °C", s.value))
                            .monospacedDigit()
                            .foregroundStyle(s.value >= 90 ? .red : s.value >= 75 ? .orange : .primary)
                            .gridColumnAlignment(.trailing)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// ImageRenderer cannot draw ScrollView, so snapshots render content inline.
let isSnapshot = CommandLine.arguments.contains("--snapshot")
