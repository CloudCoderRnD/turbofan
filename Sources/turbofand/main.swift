// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 CloudCoder Limited
// turbofand — root LaunchDaemon that owns fan control and root-only CPU readings.
//
// Listens on /var/run/turbofan.sock for one JSON request per connection
// (see FanRequest / FanResponse). Only root and the uid given with --allow-uid may talk to it.
// Every 2 s it applies each fan's mode. On exit, all fans go back to macOS control.
// While a client keeps asking for metrics, it runs powermetrics for CPU clock and package power.
//
// Safety:
//   - target speed is always clamped to the fan's own min/max
//   - a sensor-driven mode with an unreadable sensor runs the fan at max
//   - any fan not in Auto goes back to Auto if the CPU reaches 100 °C
//   - on start, fans left in manual mode with no saved setting (e.g. after a crash) go back to Auto

import Foundation
import TurboCore

let configPath = "/Library/Application Support/TurboFan/fans.json"
let hotLimit = 100.0

var allowedUID: uid_t?
if let i = CommandLine.arguments.firstIndex(of: "--allow-uid"), i + 1 < CommandLine.arguments.count {
    allowedUID = uid_t(CommandLine.arguments[i + 1])
}

guard getuid() == 0 else {
    FileHandle.standardError.write("turbofand must run as root\n".data(using: .utf8)!)
    exit(1)
}

let smc = SMC.shared
let fanCount = Int(smc.value("FNum") ?? 0)
var modes: [Int: FanMode] = [:]
var forced = Set<Int>() // fans we put in manual mode

func log(_ s: String) { print("turbofand: \(s)"); fflush(stdout) }

func loadConfig() {
    guard let data = FileManager.default.contents(atPath: configPath),
          let saved = try? JSONDecoder().decode([String: FanMode].self, from: data) else { return }
    for (k, v) in saved { if let i = Int(k), i < fanCount { modes[i] = v } }
}

func saveConfig() {
    let dict = Dictionary(uniqueKeysWithValues: modes.map { (String($0.key), $0.value) })
    guard let data = try? JSONEncoder().encode(dict) else { return }
    try? FileManager.default.createDirectory(atPath: (configPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: configPath, contents: data, attributes: [.posixPermissions: 0o644])
}

func limits(_ i: Int) -> (min: Double, max: Double) {
    let lo = smc.value("F\(i)Mn") ?? 1000
    let hi = smc.value("F\(i)Mx") ?? 6000
    return (lo, max(lo, hi))
}

func setAuto(_ i: Int) {
    smc.write("F\(i)Md", value: 0)
    forced.remove(i)
}

func setTarget(_ i: Int, _ rpm: Double) {
    let (lo, hi) = limits(i)
    let target = min(hi, max(lo, rpm))
    if smc.value("F\(i)Md") != 1 { smc.write("F\(i)Md", value: 1) }
    if abs((smc.value("F\(i)Tg") ?? 0) - target) >= 20 {
        if !smc.write("F\(i)Tg", value: target) { log("write F\(i)Tg failed") }
    }
    forced.insert(i)
}

func apply() {
    let cpu = smc.cpuTemperature() ?? 0
    for i in 0..<fanCount {
        let mode = modes[i] ?? .auto
        if cpu >= hotLimit && mode != .auto {
            if forced.contains(i) { log("CPU \(Int(cpu)) °C: fan \(i) back to auto") }
            setAuto(i)
            continue
        }
        switch mode {
        case .auto:
            if forced.contains(i) { setAuto(i) }
        case let .constant(rpm):
            setTarget(i, rpm)
        case .sensor, .curve:
            let (lo, hi) = limits(i)
            guard let key = mode.sensorKey, let t = smc.value(key), let f = mode.fraction(at: t) else {
                setTarget(i, hi)
                continue
            }
            setTarget(i, lo + (hi - lo) * f)
        }
    }
    metrics.stopIfIdle()
}

func fanInfo() -> [FanInfo] {
    (0..<fanCount).map { i in
        let (lo, hi) = limits(i)
        return FanInfo(index: i, actual: smc.value("F\(i)Ac") ?? 0, min: lo, max: hi,
                       target: smc.value("F\(i)Tg") ?? 0, mode: modes[i] ?? .auto)
    }
}

func validate(_ mode: FanMode) -> String? {
    switch mode {
    case .auto, .constant:
        return nil
    case let .sensor(key, from, to):
        return validKey(key) && to > from ? nil : "bad sensor curve"
    case let .curve(key, points):
        guard validKey(key), (2...12).contains(points.count) else { return "bad curve" }
        let ok = points.allSatisfy { (0...120).contains($0.temp) && (0...100).contains($0.percent) }
        return ok ? nil : "curve points out of range"
    }
}

func validKey(_ key: String) -> Bool {
    key.count == 4 && key.hasPrefix("T") && smc.value(key) != nil
}

// MARK: powermetrics (CPU clock + package power)

final class MetricsSampler {
    private var process: Process?
    private var buffer = ""
    private var lastAsked = Date.distantPast
    private(set) var latest: PowerMetrics?
    private(set) var raw = ""

    func touch() {
        lastAsked = Date()
        if process == nil { start() }
    }

    func stopIfIdle() {
        if let p = process, Date().timeIntervalSince(lastAsked) > 30 {
            p.terminate()
            process = nil
            latest = nil
            buffer = ""
            log("powermetrics stopped (idle)")
        }
    }

    private func start() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/powermetrics")
        p.arguments = ["--samplers", "cpu_power", "-i", "2000"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            // Empty read = end of file (powermetrics exited). Without this the handler fires
            // forever and floods the main queue.
            guard !data.isEmpty else { h.readabilityHandler = nil; return }
            let chunk = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async { self?.consume(chunk) }
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { if self?.process === p { self?.process = nil } }
        }
        do {
            try p.run()
            process = p
            log("powermetrics started")
        } catch {
            log("powermetrics failed: \(error)")
        }
    }

    private func consume(_ chunk: String) {
        buffer += chunk
        if buffer.count > 500_000 { buffer = "" } // never let a bad stream grow without bound
        // Each sample starts with "*** Sampled system activity"; parse every complete one.
        let marker = "*** Sampled system activity"
        var parts = buffer.components(separatedBy: marker)
        guard parts.count > 2 else { return }
        buffer = marker + parts.removeLast()
        if let sample = parts.last, !sample.isEmpty {
            raw = String(sample.prefix(8000))
            latest = PowerMetrics.parse(sample)
        }
    }
}

let metrics = MetricsSampler()

func handle(_ req: FanRequest) -> FanResponse {
    if req.metrics == true { metrics.touch() }
    switch req.cmd {
    case "status":
        return FanResponse(ok: true, fans: fanInfo(), metrics: metrics.latest)
    case "rawMetrics":
        return FanResponse(ok: true, fans: fanInfo(), metrics: metrics.latest, raw: metrics.raw)
    case "set":
        guard let i = req.fan, (0..<fanCount).contains(i), let mode = req.mode else {
            return FanResponse(ok: false, error: "bad fan or mode", fans: fanInfo())
        }
        if let problem = validate(mode) {
            return FanResponse(ok: false, error: problem, fans: fanInfo())
        }
        modes[i] = mode
        saveConfig()
        apply()
        return FanResponse(ok: true, fans: fanInfo(), metrics: metrics.latest)
    case "autoAll":
        modes.removeAll()
        saveConfig()
        apply()
        return FanResponse(ok: true, fans: fanInfo(), metrics: metrics.latest)
    default:
        return FanResponse(ok: false, error: "unknown command", fans: fanInfo())
    }
}

// MARK: socket

unlink(FanClient.socketPath)
let server = socket(AF_UNIX, SOCK_STREAM, 0)
var addr = unixAddress(FanClient.socketPath)
let bound = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(server, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
}
guard server >= 0, bound == 0, listen(server, 8) == 0 else {
    log("cannot listen on \(FanClient.socketPath): \(String(cString: strerror(errno)))")
    exit(1)
}
chmod(FanClient.socketPath, 0o666) // access is checked per connection with getpeereid

let acceptSource = DispatchSource.makeReadSource(fileDescriptor: server, queue: .main)
acceptSource.setEventHandler {
    let client = accept(server, nil, nil)
    guard client >= 0 else { return }
    defer { close(client) }
    var uid: uid_t = 0, gid: gid_t = 0
    guard getpeereid(client, &uid, &gid) == 0, uid == 0 || uid == allowedUID else { return }
    var timeout = timeval(tv_sec: 2, tv_usec: 0)
    setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    // A client that disconnects before the reply must not kill the helper with SIGPIPE
    var noSigPipe: Int32 = 1
    setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
    let response: FanResponse
    if let req = try? JSONDecoder().decode(FanRequest.self, from: readAll(client)) {
        response = handle(req)
    } else {
        response = FanResponse(ok: false, error: "bad request", fans: [])
    }
    if var data = try? JSONEncoder().encode(response) {
        data.append(0x0a)
        _ = data.withUnsafeBytes { write(client, $0.baseAddress, $0.count) }
    }
}
acceptSource.resume()

// MARK: lifecycle

func shutdownAndExit() {
    for i in 0..<fanCount where forced.contains(i) || (modes[i] ?? .auto) != .auto { setAuto(i) }
    unlink(FanClient.socketPath)
    log("stopped, fans back to auto")
    exit(0)
}

signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termSource.setEventHandler(handler: shutdownAndExit)
termSource.resume()
let intSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
intSource.setEventHandler(handler: shutdownAndExit)
intSource.resume()

loadConfig()
// Fans stuck in manual from a previous crash, with nothing saved for them: hand back to macOS.
for i in 0..<fanCount where modes[i] == nil && smc.value("F\(i)Md") == 1 {
    log("fan \(i) was left in manual mode, back to auto")
    setAuto(i)
}
apply()
let timer = DispatchSource.makeTimerSource(queue: .main)
timer.schedule(deadline: .now() + 2, repeating: 2)
timer.setEventHandler(handler: apply)
timer.resume()

log("started: \(fanCount) fans, allowed uid \(allowedUID.map(String.init) ?? "root only")")
dispatchMain()
