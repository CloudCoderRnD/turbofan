// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 CloudCoder Limited

import AppKit
import Combine
import ServiceManagement
import TurboCore

@MainActor
final class AppModel: ObservableObject {
    // Live readings
    @Published private(set) var status = Turbo.status()
    @Published private(set) var temperature: Double?
    @Published private(set) var fans: [Double] = []
    @Published private(set) var load: Double = 0
    @Published private(set) var onBattery = Power.onBattery()
    @Published private(set) var battery = Power.batteryPercent()
    @Published private(set) var samples: [Sample] = []
    @Published private(set) var autoReason: String?
    @Published var lastError: String?

    // Fans (via root daemon) and sensors
    @Published private(set) var fanInfo: [FanInfo] = []
    @Published private(set) var fanError: String?
    @Published private(set) var sensors: [Sensor] = []
    /// Set when the daemon is unreachable but the SMC shows a fan in manual mode.
    @Published private(set) var fansStuck = false

    // CPU clock / power (from the daemon) and throttling
    @Published private(set) var metrics: PowerMetrics?
    @Published private(set) var thermal = Thermal.read()

    // Profiles
    @Published var profiles: [Profile] { didSet { saveProfiles() } }
    @Published var rules: ProfileRules { didSet { saveProfiles(); evaluateProfiles(force: true) } }
    @Published private(set) var activeProfile: String?
    @Published private(set) var profileReason: String?
    private var lastProfileSwitch = Date.distantPast

    // Settings
    @Published var autoMode: Bool { didSet { save(); evaluate(force: true) } }
    @Published var offOnBattery: Bool { didSet { save(); evaluate(force: true) } }
    @Published var offWhenHot: Bool { didSet { save(); evaluate(force: true) } }
    @Published var hotThreshold: Double { didSet { save() } }
    @Published var offForApps: Bool { didSet { save(); evaluate(force: true) } }
    @Published var apps: String { didSet { save() } }
    @Published var launchAtLogin: Bool {
        didSet {
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                lastError = "Launch at login: \(error.localizedDescription)"
            }
        }
    }

    /// The state the user (or auto mode) wants; re-applied after wake.
    private var wantOn: Bool
    private var hot = false
    private var lastSwitch = Date.distantPast
    private let cpu = CPULoad()
    private var timer: Timer?
    private let defaults = UserDefaults.standard
    private static let historyLength = 300 // 10 minutes at 2 s

    init() {
        defaults.register(defaults: ["autoMode": false, "offOnBattery": true, "offWhenHot": true,
                                     "hotThreshold": 85.0, "offForApps": false, "apps": "Zoom, Microsoft Teams"])
        autoMode = defaults.bool(forKey: "autoMode")
        offOnBattery = defaults.bool(forKey: "offOnBattery")
        offWhenHot = defaults.bool(forKey: "offWhenHot")
        hotThreshold = defaults.double(forKey: "hotThreshold")
        offForApps = defaults.bool(forKey: "offForApps")
        apps = defaults.string(forKey: "apps") ?? ""
        launchAtLogin = SMAppService.mainApp.status == .enabled
        let decoder = JSONDecoder()
        profiles = defaults.data(forKey: "profiles").flatMap { try? decoder.decode([Profile].self, from: $0) } ?? Profile.defaults
        rules = defaults.data(forKey: "profileRules").flatMap { try? decoder.decode(ProfileRules.self, from: $0) } ?? ProfileRules()
        activeProfile = defaults.string(forKey: "activeProfile")
        wantOn = Turbo.status().turboOn

        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.didWake() }
        }
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func save() {
        defaults.set(autoMode, forKey: "autoMode")
        defaults.set(offOnBattery, forKey: "offOnBattery")
        defaults.set(offWhenHot, forKey: "offWhenHot")
        defaults.set(hotThreshold, forKey: "hotThreshold")
        defaults.set(offForApps, forKey: "offForApps")
        defaults.set(apps, forKey: "apps")
    }

    /// Forget the active profile and save that, so it isn't highlighted again after a restart.
    private func clearActiveProfile() {
        guard activeProfile != nil else { return }
        activeProfile = nil
        saveProfiles()
    }

    private func saveProfiles() {
        let encoder = JSONEncoder()
        defaults.set(try? encoder.encode(profiles), forKey: "profiles")
        defaults.set(try? encoder.encode(rules), forKey: "profileRules")
        defaults.set(activeProfile, forKey: "activeProfile")
    }

    var appList: [String] {
        apps.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
    }

    func tick() {
        status = Turbo.status()
        temperature = SMC.shared.cpuTemperature()
        fans = SMC.shared.fanSpeeds()
        load = cpu.sample()
        onBattery = Power.onBattery()
        battery = Power.batteryPercent()
        thermal = Thermal.read()
        samples.append(Sample(date: Date(), temperature: temperature, fan: fans.first, load: load, turboOn: status.turboOn,
                              watts: metrics?.packageWatts, mhz: metrics?.cpuMHz))
        if samples.count > Self.historyLength { samples.removeFirst(samples.count - Self.historyLength) }
        sensors = SMC.shared.temperatureSensors()
        refreshFans()
        evaluate(force: false)
        evaluateProfiles(force: false)
    }

    private func refreshFans() {
        fanCall { try FanClient.snapshot() }
    }

    func setFan(_ index: Int, _ mode: FanMode) {
        clearActiveProfile() // hand-tuned fans no longer match a profile
        fanCall { _ = try FanClient.set(fan: index, mode: mode); return try FanClient.snapshot() }
    }

    func allFansAuto() {
        fanCall { _ = try FanClient.autoAll(); return try FanClient.snapshot() }
    }

    func applyFanPreset(_ preset: FanPreset) {
        let count = max(fanInfo.count, Int(SMC.shared.value("FNum") ?? 0))
        fanCall { _ = try FanClient.apply(preset: preset, fanCount: count); return try FanClient.snapshot() }
    }

    /// Runs a daemon call off the main thread and publishes the result.
    private func fanCall(_ body: @escaping @Sendable () throws -> FanResponse) {
        Task {
            let result = await Task.detached { () -> Result<FanResponse, Error> in Result { try body() } }.value
            switch result {
            case let .success(response):
                fanInfo = response.fans
                metrics = response.metrics
                fanError = nil
                fansStuck = false
            case let .failure(error):
                fanError = "\(error)"
                metrics = nil
                // Daemon gone: warn if it left any fan in manual mode.
                let count = Int(SMC.shared.value("FNum") ?? 0)
                fansStuck = (0..<count).contains { SMC.shared.value("F\($0)Md") == 1 }
            }
        }
    }

    // MARK: profiles

    /// Manual pick from the UI. Turns automatic profile switching off so it sticks.
    func selectProfile(_ id: String) {
        if rules.enabled { rules.enabled = false }
        applyProfile(id, reason: nil)
    }

    private func applyProfile(_ id: String, reason: String?) {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        activeProfile = id
        profileReason = reason
        lastProfileSwitch = Date()
        saveProfiles()
        switch profile.turbo {
        case .on: autoMode = false; apply(true)
        case .off: autoMode = false; apply(false)
        case .rules: autoMode = true
        }
        applyFanPreset(profile.fanPreset)
    }

    func updateProfile(_ profile: Profile) {
        guard let i = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[i] = profile
        if activeProfile == profile.id { applyProfile(profile.id, reason: profileReason) }
    }

    /// Automatic profile switching: apps first, then external display, then battery/AC.
    private func evaluateProfiles(force: Bool) {
        guard rules.enabled else { return }
        let target: String
        let reason: String
        if let profile = rules.apps, let app = Situation.runningApp(from: rules.appNames) {
            target = profile; reason = "\(app) running"
        } else if let profile = rules.externalDisplay, Situation.externalDisplay() {
            target = profile; reason = "external display"
        } else if onBattery {
            target = rules.onBattery; reason = "on battery"
        } else {
            target = rules.onAC; reason = "on AC power"
        }
        profileReason = reason
        guard target != activeProfile, force || Date().timeIntervalSince(lastProfileSwitch) > 10 else { return }
        applyProfile(target, reason: reason)
    }

    /// Manual switch from the UI. Turns auto mode and profile switching off so it sticks.
    func setTurbo(_ on: Bool) {
        if autoMode { autoMode = false }
        if rules.enabled { rules.enabled = false }
        clearActiveProfile()
        apply(on)
    }

    private func apply(_ on: Bool) {
        wantOn = on
        let work = Task.detached { () -> String? in
            do { try Turbo.set(on: on); return nil } catch { return "\(error)" }
        }
        Task {
            lastError = await work.value
            lastSwitch = Date()
            status = Turbo.status()
        }
    }

    private func didWake() {
        Task.detached { [wantOn] in Turbo.reapply(wantOn: wantOn) }
        tick()
    }

    /// Auto mode: decide turbo state from the enabled rules.
    private func evaluate(force: Bool) {
        guard autoMode else { autoReason = nil; return }

        if let t = temperature {
            // Hysteresis: go "hot" at the threshold, back to normal 8 °C below it.
            if t >= hotThreshold { hot = true } else if t < hotThreshold - 8 { hot = false }
        }

        var reasons: [String] = []
        if offOnBattery && onBattery { reasons.append("on battery") }
        if offWhenHot && hot { reasons.append("CPU hot") }
        if offForApps, let app = runningListedApp() { reasons.append("\(app) running") }

        let shouldBeOn = reasons.isEmpty
        autoReason = shouldBeOn ? "no rule active" : reasons.joined(separator: ", ")

        // Avoid flapping: at most one automatic switch per 10 s.
        guard shouldBeOn != status.turboOn, force || Date().timeIntervalSince(lastSwitch) > 10 else { return }
        apply(shouldBeOn)
    }

    private func runningListedApp() -> String? {
        let wanted = appList
        guard !wanted.isEmpty else { return nil }
        for app in NSWorkspace.shared.runningApplications {
            let name = app.localizedName?.lowercased() ?? ""
            let bundle = app.bundleIdentifier?.lowercased() ?? ""
            if wanted.contains(name) || wanted.contains(bundle) { return app.localizedName ?? bundle }
        }
        return nil
    }
}
