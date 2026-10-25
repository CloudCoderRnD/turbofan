// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 CloudCoder Limited
//
// turbofanpro-helper — root LaunchDaemon for the battery charge limit.
// Keeps SMC key BCLM at the chosen limit (re-applied every 60 s, since sleep and SMC resets
// can clear it). On stop, the limit goes back to 100 % so the Mac charges normally.
// Socket: /var/run/turbofanpro.sock, only root and --allow-uid may connect.

import Foundation
import ProShared
import TurboCore

let configPath = "/Library/Application Support/TurboFan Pro/battery.json"

var allowedUID: uid_t?
if let i = CommandLine.arguments.firstIndex(of: "--allow-uid"), i + 1 < CommandLine.arguments.count {
    allowedUID = uid_t(CommandLine.arguments[i + 1])
}
guard getuid() == 0 else {
    FileHandle.standardError.write("turbofanpro-helper must run as root\n".data(using: .utf8)!)
    exit(1)
}

func log(_ s: String) { print("turbofanpro-helper: \(s)"); fflush(stdout) }

let smc = SMC.shared
var limit = 100

func loadConfig() {
    guard let data = FileManager.default.contents(atPath: configPath),
          let saved = try? JSONDecoder().decode([String: Int].self, from: data),
          let l = saved["limit"], BatteryHelper.limitRange.contains(l) else { return }
    limit = l
}

func saveConfig() {
    try? FileManager.default.createDirectory(atPath: (configPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    let data = try? JSONEncoder().encode(["limit": limit])
    FileManager.default.createFile(atPath: configPath, contents: data, attributes: [.posixPermissions: 0o644])
}

func smcLimit() -> Int? { smc.value("BCLM").map { Int($0) } }

func apply() {
    guard smcLimit() != limit else { return }
    if smc.write("BCLM", value: Double(limit)) {
        log("BCLM set to \(limit)")
    } else {
        log("BCLM write failed")
    }
}

func status(error: String? = nil) -> BatteryStatus {
    BatteryStatus(ok: error == nil, error: error, limit: limit, smcLimit: smcLimit())
}

func handle(_ req: BatteryRequest) -> BatteryStatus {
    switch req.cmd {
    case "status":
        return status()
    case "setLimit":
        guard let l = req.limit, BatteryHelper.limitRange.contains(l) else { return status(error: "limit must be 50–100") }
        limit = l
        saveConfig()
        apply()
        return smcLimit() == l ? status() : status(error: "the SMC did not accept the limit")
    default:
        return status(error: "unknown command")
    }
}

// MARK: socket

guard smc.value("BCLM") != nil else {
    log("this Mac has no BCLM key; charge limit not supported")
    exit(0)
}

unlink(BatteryHelper.socketPath)
let server = socket(AF_UNIX, SOCK_STREAM, 0)
var addr = unixAddress(BatteryHelper.socketPath)
let bound = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(server, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
}
guard server >= 0, bound == 0, listen(server, 8) == 0 else {
    log("cannot listen: \(String(cString: strerror(errno)))")
    exit(1)
}
chmod(BatteryHelper.socketPath, 0o666) // checked per connection with getpeereid

let acceptSource = DispatchSource.makeReadSource(fileDescriptor: server, queue: .main)
acceptSource.setEventHandler {
    let client = accept(server, nil, nil)
    guard client >= 0 else { return }
    defer { close(client) }
    var uid: uid_t = 0, gid: gid_t = 0
    guard getpeereid(client, &uid, &gid) == 0, uid == 0 || uid == allowedUID else { return }
    var timeout = timeval(tv_sec: 2, tv_usec: 0)
    setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    let reply = (try? JSONDecoder().decode(BatteryRequest.self, from: readAll(client))).map(handle) ?? status(error: "bad request")
    if var data = try? JSONEncoder().encode(reply) {
        data.append(0x0a)
        _ = data.withUnsafeBytes { write(client, $0.baseAddress, $0.count) }
    }
}
acceptSource.resume()

func shutdownAndExit() {
    smc.write("BCLM", value: 100)
    unlink(BatteryHelper.socketPath)
    log("stopped, charge limit back to 100")
    exit(0)
}
signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
term.setEventHandler(handler: shutdownAndExit)
term.resume()
let int = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
int.setEventHandler(handler: shutdownAndExit)
int.resume()

loadConfig()
apply()
let timer = DispatchSource.makeTimerSource(queue: .main)
timer.schedule(deadline: .now() + 60, repeating: 60)
timer.setEventHandler(handler: apply)
timer.resume()
log("started: limit \(limit), allowed uid \(allowedUID.map(String.init) ?? "root only")")
dispatchMain()
