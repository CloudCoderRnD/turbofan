// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 CloudCoder Limited

import Foundation
import Sparkle

/// Sparkle auto-updates. Updates are checked against SUFeedURL and must carry CloudCoder's
/// EdDSA signature (SUPublicEDKey in Info.plist).
@MainActor
final class Updater: NSObject, SPUUpdaterDelegate {
    static let shared = Updater()
    private var controller: SPUStandardUpdaterController?

    /// Only starts inside a real app bundle that has the Sparkle keys.
    func start() {
        guard Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        // `TurboFanProApp --update-now` checks, downloads and installs without asking (used to test releases).
        if CommandLine.arguments.contains("--update-now") {
            controller?.updater.automaticallyDownloadsUpdates = true
            controller?.updater.checkForUpdatesInBackground()
        }
    }

    var available: Bool { controller != nil }

    func check() {
        controller?.checkForUpdates(nil)
    }

    /// Test override: `defaults write com.cloudcoder.TurboFanPro proFeedURL http://localhost:8765/appcast.xml`
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        UserDefaults.standard.string(forKey: "proFeedURL")
    }
}
