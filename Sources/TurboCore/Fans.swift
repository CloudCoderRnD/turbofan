// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 CloudCoder Limited

import Foundation

/// How one fan is driven.
public enum FanMode: Codable, Equatable {
    /// macOS controls the fan.
    case auto
    /// Fixed speed. Values above the fan's max mean "full speed".
    case constant(rpm: Double)
    /// Linear curve: min speed at `from` °C, max speed at `to` °C, on the given sensor.
    case sensor(key: String, from: Double, to: Double)
    /// Multi-point curve on a sensor: speed percent (0 = fan min, 100 = fan max) by temperature.
    case curve(key: String, points: [CurvePoint])

    /// Fraction 0...1 of the fan's range for a temperature, for the sensor-driven modes.
    public func fraction(at temp: Double) -> Double? {
        switch self {
        case .auto, .constant:
            return nil
        case let .sensor(_, from, to):
            return to > from ? Swift.min(1, Swift.max(0, (temp - from) / (to - from))) : 1
        case let .curve(_, points):
            return CurvePoint.interpolate(points, at: temp) / 100
        }
    }

    public var sensorKey: String? {
        switch self {
        case .auto, .constant: return nil
        case let .sensor(key, _, _), let .curve(key, _): return key
        }
    }
}

public struct CurvePoint: Codable, Equatable, Hashable {
    public var temp: Double
    public var percent: Double

    public init(temp: Double, percent: Double) {
        self.temp = temp
        self.percent = percent
    }

    /// Piecewise-linear percent at `temp`; flat before the first and after the last point.
    public static func interpolate(_ points: [CurvePoint], at temp: Double) -> Double {
        let sorted = points.sorted { $0.temp < $1.temp }
        guard let first = sorted.first, let last = sorted.last else { return 100 }
        if temp <= first.temp { return first.percent }
        if temp >= last.temp { return last.percent }
        for (a, b) in zip(sorted, sorted.dropFirst()) where temp <= b.temp {
            let f = b.temp > a.temp ? (temp - a.temp) / (b.temp - a.temp) : 1
            return a.percent + (b.percent - a.percent) * f
        }
        return last.percent
    }
}

/// One-click fan settings, applied to every fan.
public enum FanPreset: String, CaseIterable, Identifiable {
    case auto = "Auto"
    case quiet = "Quiet"
    case balanced = "Balanced"
    case cool = "Cool"
    case full = "Full speed"

    public var id: String { rawValue }

    /// Sensor the curve presets follow: CPU package temperature.
    public static let sensor = "TCXC"

    public var mode: FanMode {
        switch self {
        case .auto: return .auto
        case .quiet: return .curve(key: Self.sensor, points: Self.points([(55, 0), (70, 10), (85, 45), (95, 100)]))
        case .balanced: return .curve(key: Self.sensor, points: Self.points([(45, 0), (60, 20), (75, 55), (90, 100)]))
        case .cool: return .curve(key: Self.sensor, points: Self.points([(40, 10), (55, 40), (70, 75), (80, 100)]))
        case .full: return .constant(rpm: 100_000)
        }
    }

    private static func points(_ list: [(Double, Double)]) -> [CurvePoint] {
        list.map { CurvePoint(temp: $0.0, percent: $0.1) }
    }

    /// Preset whose mode matches, if any.
    public static func matching(_ mode: FanMode) -> FanPreset? {
        allCases.first { $0.mode == mode }
    }
}

public struct FanInfo: Codable, Equatable {
    public var index: Int
    public var actual: Double
    public var min: Double
    public var max: Double
    public var target: Double
    public var mode: FanMode

    public init(index: Int, actual: Double, min: Double, max: Double, target: Double, mode: FanMode) {
        self.index = index
        self.actual = actual
        self.min = min
        self.max = max
        self.target = target
        self.mode = mode
    }

    public var name: String { "Fan \(index + 1)" }
}

/// CPU readings that need root, sampled by the daemon with powermetrics.
public struct PowerMetrics: Codable, Equatable {
    public var cpuMHz: Double?
    public var nominalPercent: Double?
    public var packageWatts: Double?
    public var date: Date

    public init(cpuMHz: Double?, nominalPercent: Double?, packageWatts: Double?, date: Date) {
        self.cpuMHz = cpuMHz
        self.nominalPercent = nominalPercent
        self.packageWatts = packageWatts
        self.date = date
    }

    /// Reads one `powermetrics --samplers cpu_power` sample. Fields it can't find stay nil.
    public static func parse(_ text: String, date: Date = Date()) -> PowerMetrics {
        func number(_ pattern: String, group: Int = 1) -> Double? {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let r = Range(m.range(at: group), in: text) else { return nil }
            return Double(text[r])
        }
        // e.g. "System Average frequency as fraction of nominal: 72.10% (1730.31 Mhz)"
        let freqPattern = #"average frequency as fraction of nominal:\s*([\d.]+)%\s*\(([\d.]+)\s*Mhz\)"#
        // e.g. "Intel energy model derived package power (CPUs+GT+SA): 5.66W"
        let watts = number(#"package power[^:\n]*:\s*([\d.]+)\s*W"#)
        return PowerMetrics(cpuMHz: number(freqPattern, group: 2), nominalPercent: number(freqPattern),
                            packageWatts: watts, date: date)
    }
}

public struct FanRequest: Codable {
    public var cmd: String // "status" | "set" | "autoAll" | "rawMetrics"
    public var fan: Int?
    public var mode: FanMode?
    /// Ask the daemon to keep sampling CPU clock and power (it stops ~30 s after the last ask).
    public var metrics: Bool?

    public init(cmd: String, fan: Int? = nil, mode: FanMode? = nil, metrics: Bool? = nil) {
        self.cmd = cmd
        self.fan = fan
        self.mode = mode
        self.metrics = metrics
    }
}

public struct FanResponse: Codable {
    public var ok: Bool
    public var error: String?
    public var fans: [FanInfo]
    public var metrics: PowerMetrics?
    public var raw: String?

    public init(ok: Bool, error: String? = nil, fans: [FanInfo], metrics: PowerMetrics? = nil, raw: String? = nil) {
        self.ok = ok
        self.error = error
        self.fans = fans
        self.metrics = metrics
        self.raw = raw
    }
}

/// Talks to the root fan daemon (turbofand) over its UNIX socket.
public enum FanClient {
    public static let socketPath = "/var/run/turbofan.sock"
    public static let daemonLabel = "com.cloudcoder.turbofan.helper"

    public enum Failure: Error, CustomStringConvertible {
        case notRunning
        case daemon(String)
        public var description: String {
            switch self {
            case .notRunning: return "fan daemon not running (run scripts/install.sh)"
            case let .daemon(msg): return msg
            }
        }
    }

    public static func status() throws -> [FanInfo] { try send(FanRequest(cmd: "status")).fans }

    /// Fans plus CPU clock/power; keeps the daemon's powermetrics sampler running.
    public static func snapshot() throws -> FanResponse { try send(FanRequest(cmd: "status", metrics: true)) }

    /// Last raw powermetrics sample (debugging the parser).
    public static func rawMetrics() throws -> String { try send(FanRequest(cmd: "rawMetrics", metrics: true)).raw ?? "" }

    @discardableResult
    public static func apply(preset: FanPreset, fanCount: Int) throws -> [FanInfo] {
        var fans: [FanInfo] = []
        for i in 0..<fanCount { fans = try set(fan: i, mode: preset.mode) }
        return fans
    }

    @discardableResult
    public static func set(fan: Int, mode: FanMode) throws -> [FanInfo] {
        try send(FanRequest(cmd: "set", fan: fan, mode: mode)).fans
    }

    @discardableResult
    public static func autoAll() throws -> [FanInfo] { try send(FanRequest(cmd: "autoAll")).fans }

    public static func send(_ request: FanRequest) throws -> FanResponse {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.notRunning }
        defer { close(fd) }
        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        // If the daemon closes the connection (e.g. it rejected our uid), write must fail with EPIPE, not kill us
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        var addr = unixAddress(socketPath)
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { throw Failure.notRunning }

        var data = try JSONEncoder().encode(request)
        data.append(0x0a)
        _ = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        shutdown(fd, SHUT_WR)

        let reply = readAll(fd)
        guard let response = try? JSONDecoder().decode(FanResponse.self, from: reply) else {
            throw Failure.daemon("bad reply from fan daemon")
        }
        if !response.ok { throw Failure.daemon(response.error ?? "fan daemon error") }
        return response
    }
}

/// sockaddr_un for a path.
public func unixAddress(_ path: String) -> sockaddr_un {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    withUnsafeMutableBytes(of: &addr.sun_path) { buf in
        let bytes = Array(path.utf8.prefix(buf.count - 1))
        for (i, b) in bytes.enumerated() { buf[i] = b }
        buf[bytes.count] = 0
    }
    return addr
}

/// Reads until EOF, newline, timeout or 1 MB.
public func readAll(_ fd: Int32) -> Data {
    var data = Data()
    var buf = [UInt8](repeating: 0, count: 4096)
    while data.count < 1 << 20 {
        let n = read(fd, &buf, buf.count)
        if n <= 0 { break }
        data.append(contentsOf: buf[0..<n])
        if buf[n - 1] == 0x0a { break }
    }
    return data
}

// MARK: - Temperature sensors

public struct Sensor: Identifiable, Equatable {
    public var id: String { key }
    public let key: String
    public let name: String
    public let value: Double
}

extension SMC {
    private static let sensorNames: [String: String] = [
        "TCXC": "CPU (PECI)", "TCMX": "CPU max core", "TC0P": "CPU proximity", "TC0E": "CPU die (E)", "TC0F": "CPU die (F)",
        "TCSA": "CPU system agent", "TCGC": "CPU graphics", "TG0P": "GPU proximity", "TGDD": "GPU die",
        "TGDF": "GPU die (F)", "TGVP": "GPU VRM", "TM0P": "Memory proximity", "Tm0P": "Mainboard",
        "TPCD": "Platform controller", "TW0P": "Wi-Fi", "TA0V": "Ambient", "TB0T": "Battery",
        "TB1T": "Battery 1", "TB2T": "Battery 2", "TH0F": "SSD", "TH0X": "SSD (X)", "TH0a": "SSD A", "TH0b": "SSD B",
        "TaLC": "Airflow left", "TaRC": "Airflow right", "Ts0P": "Palm rest", "Ts1P": "Palm rest 2",
        "Ts0S": "Memory bank 1", "Ts1S": "Memory bank 2", "Ts2S": "Memory bank 3", "Th1H": "Heatpipe 1", "Th2H": "Heatpipe 2",
        "TTLD": "Thunderbolt left", "TTRD": "Thunderbolt right",
    ]

    /// Human name for a temperature key ("TC3C" -> "CPU core 3").
    public static func sensorName(_ key: String) -> String {
        if let name = sensorNames[key] { return name }
        if key.count == 4, key.hasPrefix("TC"), key.hasSuffix("C"), let n = Int(String(key.dropFirst(2).prefix(1))) {
            return "CPU core \(n)"
        }
        return key
    }

    /// All temperature sensors with a plausible reading, sorted by name.
    public func temperatureSensors() -> [Sensor] {
        if temperatureKeys == nil {
            temperatureKeys = allKeys().filter { key in
                guard key.hasPrefix("T"), key != "TF0S", let t = type(of: key), t == "sp78" || t == "flt " else { return false }
                return true
            }
        }
        return (temperatureKeys ?? []).compactMap { key in
            guard let v = value(key), v > 1, v < 130 else { return nil }
            return Sensor(key: key, name: Self.sensorName(key), value: v)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
