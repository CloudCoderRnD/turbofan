// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 CloudCoder Limited

import ProShared
import SwiftUI

@MainActor
final class BatteryModel: ObservableObject {
    @Published var info = BatteryInfo.read()
    @Published var helper: BatteryStatus?
    @Published var error: String?
    @Published var condition: String?
    @Published var limit: Double = 100
    private var timer: Timer?
    private var synced = false

    func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        Task.detached { let c = BatteryInfo.condition(); await MainActor.run { self.condition = c } }
    }

    func stop() { timer?.invalidate(); timer = nil }

    func refresh() {
        info = BatteryInfo.read()
        Task.detached {
            let result = Result { try BatteryClient.status() }
            await MainActor.run { self.publish(result) }
        }
    }

    func apply(_ value: Int) {
        Task.detached {
            let result = Result { try BatteryClient.setLimit(value) }
            await MainActor.run { self.publish(result) }
        }
    }

    private func publish(_ result: Result<BatteryStatus, Error>) {
        switch result {
        case let .success(s):
            helper = s
            error = nil
            if !synced { limit = Double(s.limit); synced = true }
        case let .failure(e):
            error = "\(e)"
        }
    }
}

struct BatteryView: View {
    @StateObject private var model = BatteryModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Battery").font(.headline)
                Spacer()
                Text(model.info.percent.map { "\($0)%" } ?? "–").font(.system(.title2, design: .rounded).bold())
            }
            Text(stateLine).font(.caption).foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    fact("Health", model.info.healthPercent.map { "\($0)%" } ?? "–")
                    fact("Cycles", model.info.cycles.map(String.init) ?? "–")
                }
                GridRow {
                    fact("Condition", model.condition ?? "…")
                    fact("Charger", model.info.adapterWatts.map { "\($0) W" } ?? (model.info.onAC ? "?" : "none"))
                }
            }

            Divider()

            Text("Charge limit").font(.headline)
            Text("Keeping the battery at 80% while plugged in slows battery wear. Above the limit, the Mac runs from the charger.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Slider(value: $model.limit, in: 50...100, step: 5) { editing in
                    if !editing { model.apply(Int(model.limit)) }
                }
                Text("\(Int(model.limit))%").monospacedDigit().frame(width: 44, alignment: .trailing)
            }
            .disabled(model.helper == nil)
            HStack {
                Button("80% (recommended)") { model.limit = 80; model.apply(80) }
                Button("No limit") { model.limit = 100; model.apply(100) }
            }
            .controlSize(.small)
            .disabled(model.helper == nil)
            if let s = model.helper, let smc = s.smcLimit {
                Text(smc == s.limit ? "Active: charging stops at \(s.limit)%." : "Applying \(s.limit)%…")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let e = model.error { Text(e).font(.caption).foregroundStyle(.red) }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private var stateLine: String {
        if !model.info.onAC { return "On battery" }
        if model.info.charging { return "Charging" }
        if let s = model.helper, s.limit < 100, let p = model.info.percent, p >= s.limit - 1 { return "Holding at limit (on charger)" }
        return "On charger, not charging"
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.body, design: .rounded).monospacedDigit())
        }
    }
}
