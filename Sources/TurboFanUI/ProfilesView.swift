// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 CloudCoder Limited

import SwiftUI
import TurboCore

struct ProfilesView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(model.profiles) { profile in
                    ProfileTile(profile: profile, active: model.activeProfile == profile.id)
                }
            }
            Divider()
            autoSwitch
        }
    }

    private var profileIDs: [String] { model.profiles.map(\.id) }

    private func picker(_ title: String, _ binding: Binding<String>) -> some View {
        Picker(title, selection: binding) {
            ForEach(profileIDs, id: \.self) { Text($0).tag($0) }
        }
    }

    private func optionalPicker(_ title: String, _ binding: Binding<String?>) -> some View {
        Picker(title, selection: binding) {
            Text("Ignore").tag(String?.none)
            ForEach(profileIDs, id: \.self) { Text($0).tag(String?.some($0)) }
        }
    }

    private var autoSwitch: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Switch profiles automatically", isOn: $model.rules.enabled).font(.headline)
            Group {
                optionalPicker("These apps running", $model.rules.apps)
                TextField("App names or bundle IDs, comma separated", text: $model.rules.appList)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                optionalPicker("External display", $model.rules.externalDisplay)
                picker("On battery", $model.rules.onBattery)
                picker("On AC power", $model.rules.onAC)
                Text("Checked top to bottom; first match wins.").font(.caption2).foregroundStyle(.secondary)
            }
            .disabled(!model.rules.enabled)
            if model.rules.enabled, let reason = model.profileReason {
                Text("Now: \(model.activeProfile ?? "–") (\(reason))").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct ProfileTile: View {
    @EnvironmentObject var model: AppModel
    let profile: Profile
    let active: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                model.selectProfile(profile.id)
            } label: {
                HStack {
                    Image(systemName: profile.symbol)
                    Text(profile.id).bold()
                    Spacer()
                    if active { Image(systemName: "checkmark.circle.fill").accessibilityLabel("Active") }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(active ? .accentColor : .gray.opacity(0.5))

            Picker("Turbo", selection: Binding(get: { profile.turbo }, set: { new in
                var p = profile; p.turbo = new; model.updateProfile(p)
            })) {
                ForEach(TurboChoice.allCases) { Text("Turbo \($0.rawValue.lowercased())").tag($0) }
            }
            .labelsHidden()
            .controlSize(.small)

            Picker("Fans", selection: Binding(get: { profile.fanPreset }, set: { new in
                var p = profile; p.fans = new.rawValue; model.updateProfile(p)
            })) {
                ForEach(FanPreset.allCases) { Text("Fans \($0.rawValue.lowercased())").tag($0) }
            }
            .labelsHidden()
            .controlSize(.small)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(active ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08)))
    }
}
