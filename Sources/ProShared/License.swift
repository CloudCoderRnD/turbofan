// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 CloudCoder Limited

import CryptoKit
import Foundation

/// A TurboFan Pro licence. Keys look like `TFPRO-<payload>.<signature>` (base64url),
/// signed with CloudCoder's Ed25519 private key and checked offline with the public key.
public struct License: Codable, Equatable {
    public var v: Int = 1
    public var id: String
    public var name: String
    public var email: String
    /// "pro" or "business"
    public var plan: String
    public var seats: Int
    public var issued: String
    /// nil = perpetual
    public var expires: String?

    public init(id: String, name: String, email: String, plan: String, seats: Int, issued: String, expires: String?) {
        self.id = id
        self.name = name
        self.email = email
        self.plan = plan
        self.seats = seats
        self.issued = issued
        self.expires = expires
    }

    public static let prefix = "TFPRO-"

    public enum Problem: Error, CustomStringConvertible {
        case format, signature, expired
        public var description: String {
            switch self {
            case .format: return "This is not a TurboFan Pro licence key."
            case .signature: return "This licence key is not valid."
            case .expired: return "This licence has expired."
            }
        }
    }

    /// Checks a key against the public key and returns the licence.
    public static func verify(_ key: String, publicKey: String, now: Date = Date()) throws -> License {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix) else { throw Problem.format }
        let parts = trimmed.dropFirst(prefix.count).split(separator: ".")
        guard parts.count == 2, let payload = Data(base64URL: String(parts[0])),
              let signature = Data(base64URL: String(parts[1])),
              let keyData = Data(base64Encoded: publicKey),
              let pub = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else { throw Problem.format }
        guard pub.isValidSignature(signature, for: payload) else { throw Problem.signature }
        guard let license = try? JSONDecoder().decode(License.self, from: payload) else { throw Problem.format }
        if let e = license.expires, let date = Self.day.date(from: e), now > date.addingTimeInterval(86400) {
            throw Problem.expired
        }
        return license
    }

    /// Signs a licence (issuer tool only; the private key never ships).
    public func sign(privateKey: Curve25519.Signing.PrivateKey) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let payload = try encoder.encode(self)
        let signature = try privateKey.signature(for: payload)
        return Self.prefix + payload.base64URL + "." + signature.base64URL
    }

    public static let day: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

extension Data {
    public var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public init?(base64URL s: String) {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        self.init(base64Encoded: b)
    }
}
