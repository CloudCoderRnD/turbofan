// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 CloudCoder Limited

import Foundation
import os
import SwiftUI

/// What this app was built from, filled in by scripts/build-info.sh (Info.plist TFBuild* keys).
/// Test (alpha) builds show it in a strip; release builds only write it to the log.
public struct BuildInfo {
    public static let current = BuildInfo(bundle: .main)

    public let version: String
    public let build: String
    public let channel: String
    public let branch: String?
    public let commit: String?
    public let pr: String?
    public let time: String?

    init(bundle: Bundle) {
        func value(_ key: String) -> String? {
            (bundle.object(forInfoDictionaryKey: key) as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        version = value("CFBundleShortVersionString") ?? "dev"
        build = value("CFBundleVersion") ?? "-"
        // No channel at all means a plain `swift build` run: treat it as a test build too.
        channel = value("TFBuildChannel") ?? "dev"
        branch = value("TFBuildBranch")
        commit = value("TFBuildCommit")
        pr = value("TFBuildPR")
        time = value("TFBuildTime")
    }

    public var isTestBuild: Bool { channel != "release" }

    /// "ALPHA · v1.1.0 · PR #9 · fix-profile-highlight · c46e462 · 2026-10-25 21:06 +06 · build 202610252106"
    public var summary: String {
        [channel.uppercased(), "v\(version)", pr.map { "PR #\($0)" }, branch, commit, time, "build \(build)"]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// Writes the full build details to the unified log (Console app, subsystem com.cloudcoder.turbofan)
    /// and to ~/Library/Logs/TurboFan/build.log, once per launch.
    public func logLaunch() {
        let line = "\(Bundle.main.bundleIdentifier ?? "TurboFan") started: \(summary)"
        Logger(subsystem: "com.cloudcoder.turbofan", category: "build").notice("\(line, privacy: .public)")
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/TurboFan", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("build.log")
        let stamp = ISO8601DateFormatter().string(from: Date())
        let entry = Data("\(stamp) \(line)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(entry)
            try? handle.close()
        } else {
            try? entry.write(to: file)
        }
    }
}

/// Coloured strip with the build details, shown only in test builds.
struct TestBuildStrip: View {
    let info = BuildInfo.current

    var body: some View {
        if info.isTestBuild {
            Text(info.summary)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(red: 0.10, green: 0.06, blue: 0.0))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.94, green: 0.64, blue: 0.29)))
                .help("Test build. Release builds don't show this strip; details are in ~/Library/Logs/TurboFan/build.log")
                .accessibilityLabel("Test build: \(info.summary)")
        }
    }
}
