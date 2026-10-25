// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 CloudCoder Limited

import Foundation
import ProShared
import SwiftUI
import TurboFanUI

/// Licence and trial state. Pro features work while a licence is active or the 14-day trial runs.
@MainActor
final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    /// CloudCoder's licence-signing public key (Ed25519). The private key never ships.
    static let publicKey = "9leumVOK7xNUdf76rnUDF3ohuCpTN/KRBmMdL9/NUW4="
    static let trialDays = 14
    static let buyPage = Brand.proPage

    @Published private(set) var license: License?
    @Published var error: String?

    private let defaults = UserDefaults.standard

    private init() {
        if defaults.object(forKey: "proTrialStart") == nil { defaults.set(Date(), forKey: "proTrialStart") }
        if let key = defaults.string(forKey: "proLicenseKey") {
            license = try? License.verify(key, publicKey: Self.publicKey)
        }
    }

    var trialDaysLeft: Int {
        let start = defaults.object(forKey: "proTrialStart") as? Date ?? Date()
        let used = Calendar.current.dateComponents([.day], from: start, to: Date()).day ?? 0
        return max(0, Self.trialDays - used)
    }

    var isActive: Bool { license != nil || trialDaysLeft > 0 }

    var editionLabel: String {
        if license != nil { return "Pro" }
        return trialDaysLeft > 0 ? "Pro trial · \(trialDaysLeft) days left" : "Pro · trial ended"
    }

    func activate(_ key: String) {
        do {
            license = try License.verify(key, publicKey: Self.publicKey)
            defaults.set(key.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "proLicenseKey")
            error = nil
        } catch {
            self.error = "\(error)"
        }
    }

    func deactivate() {
        license = nil
        defaults.removeObject(forKey: "proLicenseKey")
    }
}

/// Licence details and key entry, shown in the About window.
struct LicenseView: View {
    @ObservedObject private var manager = LicenseManager.shared
    @State private var key = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Licence").font(.headline)
            if let l = manager.license {
                Text("Licensed to \(l.name) (\(l.email))").font(.callout)
                Text("\(l.plan.capitalized) · \(l.seats) seat\(l.seats == 1 ? "" : "s") · issued \(l.issued)\(l.expires.map { " · until \($0)" } ?? "")")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Remove licence from this Mac") { manager.deactivate() }.controlSize(.small)
            } else {
                Text(manager.trialDaysLeft > 0
                     ? "Trial: \(manager.trialDaysLeft) days left. Enter a licence key to keep Pro features."
                     : "Your trial has ended. Enter a licence key to use Pro features.")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                licenseEntry
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var licenseEntry: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("TFPRO-…", text: $key)
                .textFieldStyle(.roundedBorder)
                .font(.caption.monospaced())
            HStack {
                Button("Activate") { manager.activate(key) }.disabled(key.isEmpty)
                Link("Buy a licence", destination: LicenseManager.buyPage)
            }
            .controlSize(.small)
            if let e = manager.error { Text(e).font(.caption).foregroundStyle(.red) }
        }
    }
}

/// Shows Pro content while licensed or in trial, otherwise an unlock prompt.
struct ProGate<Content: View>: View {
    @ObservedObject private var manager = LicenseManager.shared
    @ViewBuilder let content: () -> Content
    @State private var key = ""

    var body: some View {
        if manager.isActive {
            content()
        } else {
            VStack(spacing: 10) {
                Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(.secondary)
                Text("Your TurboFan Pro trial has ended").font(.headline)
                Text("Turbo and fan control keep working. Enter a licence key to unlock battery care and health reports again.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("TFPRO-…", text: $key).textFieldStyle(.roundedBorder).font(.caption.monospaced())
                HStack {
                    Button("Activate") { manager.activate(key) }.disabled(key.isEmpty)
                    Link("Buy a licence", destination: LicenseManager.buyPage)
                }
                if let e = manager.error { Text(e).font(.caption).foregroundStyle(.red) }
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
    }
}
