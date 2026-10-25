// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 CloudCoder Limited

import Foundation

/// Wire format between the Pro app and the root battery helper.
public struct BatteryRequest: Codable {
    public var cmd: String // "status" | "setLimit"
    public var limit: Int?

    public init(cmd: String, limit: Int? = nil) {
        self.cmd = cmd
        self.limit = limit
    }
}

public struct BatteryStatus: Codable, Equatable {
    public var ok: Bool
    public var error: String?
    /// Charge limit the helper keeps (50...100; 100 = no limit).
    public var limit: Int
    /// Value the SMC reports right now (BCLM).
    public var smcLimit: Int?

    public init(ok: Bool, error: String? = nil, limit: Int, smcLimit: Int?) {
        self.ok = ok
        self.error = error
        self.limit = limit
        self.smcLimit = smcLimit
    }
}

public enum BatteryHelper {
    public static let socketPath = "/var/run/turbofanpro.sock"
    public static let label = "com.cloudcoder.turbofanpro.helper"
    public static let limitRange = 50...100
}
