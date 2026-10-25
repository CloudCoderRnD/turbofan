// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 CloudCoder Limited

import Charts
import SwiftUI
import TurboCore
import UserNotifications

public struct TurboFanMenuApp: App {
    @StateObject private var model = AppModel()
    @AppStorage("menuBarShowsFans") private var menuBarShowsFans = false

    public init() {
        UNUserNotificationCenter.current().delegate = NotificationOpener.shared
        MessageCenter.shared.start()
        // `TurboFan --snapshot out.png` renders the panel to a PNG and quits (for checking the UI).
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--shots"), i + 1 < args.count {
            let dir = URL(fileURLWithPath: args[i + 1])
            let shotModel = AppModel()
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                MainActor.assumeIsolated { Screenshots.run(dir: dir, model: shotModel, light: args.contains("--light")) }
            }
        }
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            let url = URL(fileURLWithPath: args[i + 1])
            let snapModel = AppModel()
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
                MainActor.assumeIsolated {
                    let tab = args.firstIndex(of: "--tab").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } ?? PanelView.builtIn[0]
                    let content: AnyView = args.contains("--about")
                        ? AnyView(AboutView())
                        : AnyView(PanelView(tab: tab).environmentObject(snapModel))
                    let renderer = ImageRenderer(content: content
                        .background(Color(nsColor: .windowBackgroundColor)))
                    renderer.scale = 2
                    if let tiff = renderer.nsImage?.tiffRepresentation,
                       let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                        try? png.write(to: url)
                    }
                    NSApp.terminate(nil)
                }
            }
        }
    }

    public var body: some Scene {
        MenuBarExtra {
            PanelView().environmentObject(model)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: model.thermal.throttled ? "thermometer.sun.fill" : model.status.turboOn ? "bolt.fill" : "bolt.slash.fill")
                if let t = model.temperature { Text("\(Int(t.rounded()))°") }
                // Fastest fan, e.g. "3.4k" rpm, when turned on in the Fans tab.
                if menuBarShowsFans, let rpm = model.fans.max() {
                    Image(systemName: "fanblades.fill")
                    Text(String(format: "%.1fk", rpm / 1000))
                }
            }
        }
        .menuBarExtraStyle(.window)

        Window("About \(Brand.product)", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
    }
}

struct PanelView: View {
    static let builtIn = ["Turbo", "Fans", "Profiles", "Sensors"]
    private static let builtInSymbols = ["bolt.fill", "fanblades.fill", "slider.horizontal.3", "thermometer.medium"]

    @EnvironmentObject var model: AppModel
    @ObservedObject private var messages = MessageCenter.shared
    @Environment(\.openWindow) private var openWindow
    @State var tab: String = PanelView.builtIn[0]

    private var extraTabs: [ExtraTab] { Extensions.edition?.tabs ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let message = messages.banner {
                MessageCard(message: message) { messages.dismiss(message) }
            }
            tabPicker

            switch tab {
            case "Turbo":
                header
                Divider()
                stats
                chart
                Divider()
                autoSection
            case "Fans":
                FansView()
            case "Profiles":
                ProfilesView()
            case "Sensors":
                SensorsView()
            default:
                extraTabs.first { $0.id == tab }?.view()
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: extraTabs.isEmpty ? 330 : 360)
    }

    /// Text tabs for the free build; icons once an edition adds more tabs.
    private var tabPicker: some View {
        Picker("Tab", selection: $tab) {
            if extraTabs.isEmpty {
                ForEach(Self.builtIn, id: \.self) { Text($0).tag($0) }
            } else {
                ForEach(Array(zip(Self.builtIn, Self.builtInSymbols)), id: \.0) { name, symbol in
                    Image(systemName: symbol).help(name).accessibilityLabel(name).tag(name)
                }
                ForEach(extraTabs) { t in Image(systemName: t.symbol).help(t.id).accessibilityLabel(t.id).tag(t.id) }
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Turbo Boost").font(.headline)
                Text(model.status.turboOn ? "On" : "Off")
                    .font(.title2.bold())
                    .foregroundStyle(model.status.turboOn ? .orange : .blue)
                Text("via \(model.status.backend.rawValue)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Turbo Boost", isOn: Binding(get: { model.status.turboOn }, set: { model.setTurbo($0) }))
                .toggleStyle(.switch)
                .controlSize(.large)
                .labelsHidden()
        }
    }

    private var stats: some View {
        VStack(alignment: .leading, spacing: 6) {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
            GridRow {
                stat("CPU", model.temperature.map { String(format: "%.0f °C", $0) } ?? "–")
                stat("Load", String(format: "%.0f%%", model.load * 100))
            }
            GridRow {
                stat("Clock", model.metrics?.cpuMHz.map { String(format: "%.2f GHz", $0 / 1000) } ?? "–")
                stat("Package", model.metrics?.packageWatts.map { String(format: "%.1f W", $0) } ?? "–")
            }
            GridRow {
                stat("Fans", model.fans.isEmpty ? "–" : model.fans.map { "\(Int($0))" }.joined(separator: " / ") + " rpm")
                stat("Power", model.onBattery ? "Battery \(model.battery.map { "\($0)%" } ?? "")" : "AC")
            }
        }
        if model.thermal.throttled {
            Label("macOS is limiting the CPU to \(model.thermal.speedLimit)% speed (heat or power)", systemImage: "thermometer.sun.fill")
                .font(.caption.bold())
                .foregroundStyle(.red)
        }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.body, design: .rounded).monospacedDigit())
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Temp °C (red) · Package W (orange) · Load % (blue) · 10 min").font(.caption2).foregroundStyle(.secondary)
            chartBody
        }
    }

    private var chartBody: some View {
        Chart {
            ForEach(model.samples) { s in
                if let t = s.temperature {
                    LineMark(x: .value("Time", s.date), y: .value("°C", t), series: .value("Series", "Temp"))
                        .foregroundStyle(.red)
                }
                if let w = s.watts {
                    LineMark(x: .value("Time", s.date), y: .value("°C", w), series: .value("Series", "Watts"))
                        .foregroundStyle(.orange)
                }
                AreaMark(x: .value("Time", s.date), y: .value("°C", s.load * 100), series: .value("Series", "Load"))
                    .foregroundStyle(.blue.opacity(0.18))
                if !s.turboOn {
                    RuleMark(x: .value("Time", s.date)).foregroundStyle(.blue.opacity(0.06))
                }
            }
        }
        .chartYScale(domain: 0...105)
        .chartXAxis(.hidden)
        .chartYAxis { AxisMarks(values: [0, 50, 100]) }
        .frame(height: 90)
    }

    private var autoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Auto mode", isOn: $model.autoMode).font(.headline)
            Group {
                Toggle("Turbo off on battery", isOn: $model.offOnBattery)
                HStack {
                    Toggle("Turbo off above", isOn: $model.offWhenHot)
                    Stepper(value: $model.hotThreshold, in: 60...100, step: 5) {
                        Text("\(Int(model.hotThreshold)) °C").monospacedDigit()
                    }
                }
                Toggle("Turbo off while these apps run:", isOn: $model.offForApps)
                TextField("App names or bundle IDs, comma separated", text: $model.apps)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .disabled(!model.offForApps)
                if let reason = model.autoReason {
                    Text("Auto: \(reason)").font(.caption).foregroundStyle(.secondary)
                }
            }
            .disabled(!model.autoMode)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.fansStuck {
                Label("Fan daemon is not responding and a fan is still in manual mode. Reinstall, or reboot to reset fans.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.red)
            }
            if let error = model.lastError {
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(3)
            }
            if !Turbo.kextInstalled {
                Text("Kext not installed — using Low Power Mode.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Toggle("Launch at login", isOn: $model.launchAtLogin)
                Spacer()
                ForEach(Extensions.edition?.actions ?? []) { a in Button(a.id, action: a.action) }
                Button("About") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "about")
                }
                Button("Quit") { NSApp.terminate(nil) }
            }
            Divider()
            HStack(spacing: 6) {
                Link(Brand.websiteLabel, destination: Brand.website)
                    .font(.caption.bold())
                Spacer()
                Text("\(Brand.product) \(Edition.name)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if !Edition.isPro {
                    Link("Get Pro", destination: Brand.proPage)
                        .font(.caption.bold())
                }
            }
        }
    }
}
