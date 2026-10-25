// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 CloudCoder Limited

import CryptoKit
import Foundation
import SwiftUI

/// Installs or updates the root helpers bundled inside the app (Contents/Resources/Installer).
/// Needed on first launch and after a Sparkle update, which replaces only the app.
@MainActor
final class HelperInstaller: ObservableObject {
    static let shared = HelperInstaller()

    @Published private(set) var needsInstall = false
    @Published private(set) var installing = false
    @Published var error: String?

    private var installerDir: URL? { Bundle.main.resourceURL?.appendingPathComponent("Installer") }

    /// Bundled binary -> installed path.
    private var pairs: [(String, String)] {
        [("build/turbofand", "/Library/PrivilegedHelperTools/com.cloudcoder.turbofan.helper"),
         ("build/turbofanpro-helper", "/Library/PrivilegedHelperTools/com.cloudcoder.turbofanpro.helper"),
         ("build/turbofan", "/usr/local/bin/turbofan")]
    }

    func check() {
        guard let dir = installerDir, FileManager.default.fileExists(atPath: dir.path) else { needsInstall = false; return }
        needsInstall = pairs.contains { bundled, installed in
            Self.hash(dir.appendingPathComponent(bundled).path) != Self.hash(installed)
        }
    }

    private static func hash(_ path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func install() {
        guard let dir = installerDir else { return }
        installing = true
        let script = dir.appendingPathComponent("scripts/install-pro-privileged.sh").path
        let user = NSUserName()
        Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            let quoted = script.replacingOccurrences(of: "'", with: "'\\''")
            p.arguments = ["-e", "do shell script \"'\(quoted)' \(user) 2>&1\" with prompt \"TurboFan Pro needs to install its helpers.\" with administrator privileges"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            try? p.run()
            p.waitUntilExit()
            let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let status = p.terminationStatus
            await MainActor.run {
                self.installing = false
                self.error = status == 0 ? nil : (out.contains("-128") ? "Cancelled." : out.trimmingCharacters(in: .whitespacesAndNewlines))
                self.check()
            }
        }
    }
}

/// Card asking to install or update the helpers.
struct HelperSetupCard: View {
    @ObservedObject private var installer = HelperInstaller.shared

    var body: some View {
        if installer.needsInstall {
            VStack(alignment: .leading, spacing: 6) {
                Label("Finish setting up TurboFan Pro", systemImage: "wrench.and.screwdriver.fill").font(.headline)
                Text("Install the helpers that control fans, turbo and the battery limit. macOS will ask for your password.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button(installer.installing ? "Installing…" : "Install helpers") { installer.install() }
                    .buttonStyle(.borderedProminent)
                    .disabled(installer.installing)
                if let e = installer.error { Text(e).font(.caption).foregroundStyle(.red).lineLimit(4) }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.1)))
        }
    }
}
