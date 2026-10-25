// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 CloudCoder Limited

import Foundation
import IOKit
import IOKit.ps
import ProShared
import TurboCore

/// Battery and charger facts from IOKit, no root needed.
struct BatteryInfo: Equatable {
    var percent: Int?
    var charging = false
    var onAC = false
    var cycles: Int?
    var designCapacity: Int?
    var maxCapacity: Int?
    var temperature: Double?
    var adapterWatts: Int?
    var adapterName: String?

    var healthPercent: Int? {
        guard let d = designCapacity, let m = maxCapacity, d > 0 else { return nil }
        return Int((Double(m) / Double(d) * 100).rounded())
    }

    static func read() -> BatteryInfo {
        var info = BatteryInfo()
        info.percent = Power.batteryPercent()
        info.onAC = !Power.onBattery()
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != 0 {
            defer { IOObjectRelease(service) }
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let d = props?.takeRetainedValue() as? [String: Any] {
                info.cycles = d["CycleCount"] as? Int
                info.designCapacity = d["DesignCapacity"] as? Int
                info.maxCapacity = (d["AppleRawMaxCapacity"] as? Int) ?? (d["MaxCapacity"] as? Int)
                info.charging = d["IsCharging"] as? Bool ?? false
                if let t = d["Temperature"] as? Int { info.temperature = Double(t) / 100 }
            }
        }
        if let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] {
            info.adapterWatts = adapter[kIOPSPowerAdapterWattsKey] as? Int
            info.adapterName = adapter["Name"] as? String
        }
        return info
    }

    /// macOS battery condition ("Normal", "Service Recommended"), from system_profiler. Slow; call off the main thread.
    static func condition() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        p.arguments = ["-json", "SPPowerDataType"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["SPPowerDataType"] as? [[String: Any]] else { return nil }
        for item in items {
            if let health = item["sppower_battery_health_info"] as? [String: Any],
               let c = health["sppower_battery_health"] as? String {
                // system_profiler's JSON uses internal codes; show the words macOS shows.
                let labels = ["Good": "Normal", "Check Battery": "Service Recommended", "Fair": "Service Recommended", "Poor": "Service Battery"]
                return labels[c] ?? c
            }
        }
        return nil
    }
}

enum MacModel {
    static var identifier: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        return String(cString: buf)
    }

    /// Apple's charger size for Intel MacBook models, in watts.
    static var recommendedAdapterWatts: Int? {
        let table: [String: Int] = [
            "MacBookPro16,1": 96, "MacBookPro16,4": 96, "MacBookPro15,1": 87, "MacBookPro15,3": 87,
            "MacBookPro14,3": 87, "MacBookPro13,3": 87, "MacBookPro16,2": 61, "MacBookPro16,3": 61,
            "MacBookPro15,2": 61, "MacBookPro15,4": 61, "MacBookPro14,1": 61, "MacBookPro14,2": 61,
            "MacBookPro13,1": 61, "MacBookPro13,2": 61, "MacBookAir9,1": 30, "MacBookAir8,1": 30, "MacBookAir8,2": 30,
        ]
        return table[identifier]
    }
}

/// Talks to the root battery helper.
enum BatteryClient {
    enum Failure: Error, CustomStringConvertible {
        case notRunning, helper(String)
        var description: String {
            switch self {
            case .notRunning: return "Battery helper not installed. Run the TurboFan Pro installer."
            case let .helper(s): return s
            }
        }
    }

    static func status() throws -> BatteryStatus { try send(BatteryRequest(cmd: "status")) }
    static func setLimit(_ limit: Int) throws -> BatteryStatus { try send(BatteryRequest(cmd: "setLimit", limit: limit)) }

    static func send(_ request: BatteryRequest) throws -> BatteryStatus {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.notRunning }
        defer { close(fd) }
        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var addr = unixAddress(BatteryHelper.socketPath)
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard ok == 0 else { throw Failure.notRunning }
        var data = try JSONEncoder().encode(request)
        data.append(0x0a)
        _ = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        shutdown(fd, SHUT_WR)
        guard let reply = try? JSONDecoder().decode(BatteryStatus.self, from: readAll(fd)) else { throw Failure.helper("bad reply") }
        if !reply.ok { throw Failure.helper(reply.error ?? "helper error") }
        return reply
    }
}
