// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 CloudCoder Limited

import Foundation
import SwiftUI
import TurboFanUI

/// Plugs TurboFan Pro into the shared app: Battery and Health tabs, updates, licence.
@MainActor
public final class ProPlugin: EditionPlugin {
    public static func install() {
        // `TurboFanProApp --health-report` prints the health check as text and exits.
        if CommandLine.arguments.contains("--health-report") {
            let day = HistoryStore.shared.samples(since: Date().addingTimeInterval(-86400))
            print("Mac health (\(day.count) samples in the last 24 h, \(HistoryStore.shared.count()) total)")
            for f in HealthChecks.run(battery: BatteryInfo.read(), condition: BatteryInfo.condition(), day: day) {
                print("[\(f.level)] \(f.title)\n    \(f.detail)" + (f.advice.map { "\n    → \($0)" } ?? ""))
            }
            exit(0)
        }
        Extensions.edition = ProPlugin()
        _ = LicenseManager.shared // starts the trial clock on first launch
        Recorder.shared.start()
        HelperInstaller.shared.check()
        Updater.shared.start()
    }

    public var editionName: String { LicenseManager.shared.editionLabel }

    public var tabs: [ExtraTab] {
        [
            ExtraTab(title: "Battery", symbol: "battery.75percent") { AnyView(VStack(spacing: 10) { HelperSetupCard(); ProGate { BatteryView() } }) },
            ExtraTab(title: "Health", symbol: "stethoscope") { AnyView(VStack(spacing: 10) { HelperSetupCard(); ProGate { HealthView() } }) },
        ]
    }

    public var actions: [ExtraAction] {
        Updater.shared.available ? [ExtraAction(title: "Updates") { Updater.shared.check() }] : []
    }

    public var aboutSection: AnyView? { AnyView(LicenseView()) }
}
