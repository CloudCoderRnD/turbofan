// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 CloudCoder Limited
//
// Internal tool for issuing TurboFan Pro licence keys. Never ship this or the private key.
//
//   turbofan-license keygen <private-key-file>        new Ed25519 key pair; prints the public key
//   turbofan-license issue <private-key-file> --name N --email E [--plan pro|business] [--seats 1] [--expires YYYY-MM-DD]
//   turbofan-license verify <public-key-base64> <key>

import CryptoKit
import Foundation
import ProShared

func fail(_ s: String) -> Never {
    FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
    exit(1)
}

func option(_ name: String, in args: [String]) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func loadPrivateKey(_ path: String) -> Curve25519.Signing.PrivateKey {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8),
          let data = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: data) else { fail("cannot read private key \(path)") }
    return key
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "keygen":
    guard args.count == 2 else { fail("usage: turbofan-license keygen <private-key-file>") }
    let path = args[1]
    guard !FileManager.default.fileExists(atPath: path) else { fail("\(path) exists; refusing to overwrite") }
    let key = Curve25519.Signing.PrivateKey()
    FileManager.default.createFile(atPath: path, contents: key.rawRepresentation.base64EncodedString().data(using: .utf8),
                                   attributes: [.posixPermissions: 0o600])
    print(key.publicKey.rawRepresentation.base64EncodedString())

case "issue":
    guard args.count >= 2 else { fail("usage: turbofan-license issue <private-key-file> --name N --email E ...") }
    let key = loadPrivateKey(args[1])
    guard let name = option("--name", in: args), let email = option("--email", in: args) else { fail("--name and --email are required") }
    let license = License(id: UUID().uuidString.lowercased(), name: name, email: email,
                          plan: option("--plan", in: args) ?? "pro",
                          seats: Int(option("--seats", in: args) ?? "1") ?? 1,
                          issued: License.day.string(from: Date()),
                          expires: option("--expires", in: args))
    print(try license.sign(privateKey: key))

case "verify":
    guard args.count == 3 else { fail("usage: turbofan-license verify <public-key-base64> <key>") }
    do {
        let l = try License.verify(args[2], publicKey: args[1])
        print("valid: \(l.name) <\(l.email)>, \(l.plan), \(l.seats) seat(s), issued \(l.issued), expires \(l.expires ?? "never")")
    } catch {
        fail("invalid: \(error)")
    }

default:
    fail("usage: turbofan-license keygen|issue|verify ...")
}
