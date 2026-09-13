import Foundation

struct AppFailure: LocalizedError, Sendable {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

struct ServerProfile: Codable, Equatable, Sendable {
    let name: String
    let origin: String

    init(name: String, address: String) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              name.count <= 40,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw AppFailure("Use a server name of 1–40 characters without control characters.")
        }
        self.name = name
        self.origin = try Self.canonicalOrigin(address)
    }

    func validated() throws -> Self {
        guard try ServerProfile(name: name, address: origin) == self else {
            throw AppFailure("The server profile is invalid. Restore its protected copy from Keychain.")
        }
        return self
    }

    func endpoint(_ path: String) throws -> URL {
        _ = try validated()
        guard let base = URL(string: origin) else {
            throw AppFailure("Invalid server address.")
        }
        return base.appendingPathComponent("v1/sys/\(path)")
    }

    private static func canonicalOrigin(_ input: String) throws -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.utf8.count <= 512,
              value.unicodeScalars.allSatisfy({ $0.value > 32 && $0.value < 127 }),
              !value.contains("\\"),
              !value.contains("%"),
              var parts = URLComponents(string: value),
              parts.scheme?.lowercased() == "https",
              let host = parts.host,
              !host.isEmpty,
              parts.user == nil,
              parts.password == nil,
              parts.query == nil,
              parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/",
              parts.port == nil || (1...65535).contains(parts.port!) else {
            throw AppFailure("Use an HTTPS origin such as https://bao.example.com:8200. No credentials, path, query, fragment, or non-ASCII hostname is allowed.")
        }

        parts.scheme = "https"
        parts.host = host.lowercased()
        parts.path = ""
        if parts.port == 443 {
            parts.port = nil
        }
        guard let result = parts.url?.absoluteString else {
            throw AppFailure("Invalid HTTPS origin.")
        }
        return result
    }
}

struct ShareRecord: Codable, Sendable {
    let version: Int
    let profile: ServerProfile
    var share: String

    init(profile: ServerProfile, input: String) throws {
        self.version = 1
        self.profile = try profile.validated()
        self.share = try Self.validateShare(input)
    }

    func validated() throws -> Self {
        guard version == 1 else {
            throw AppFailure("Unsupported Keychain record version.")
        }
        _ = try profile.validated()
        _ = try Self.validateShare(share)
        return self
    }

    static func validateShare(_ input: String) throws -> String {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let isHex = text.utf8.count.isMultiple(of: 2) && text.utf8.allSatisfy {
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }
        guard (16...1024).contains(text.utf8.count),
              isHex || Data(base64Encoded: text) != nil else {
            throw AppFailure("Enter one hexadecimal or Base64 Shamir share. Its validity is ultimately checked by OpenBao.")
        }
        return text
    }
}

struct SealStatus: Decodable, Sendable {
    let type: String
    let initialized: Bool
    let sealed: Bool
    let t: Int
    let n: Int
    let progress: Int
    let migration: Bool?
    let recoverySeal: Bool?

    enum CodingKeys: String, CodingKey {
        case type, initialized, sealed, t, n, progress, migration
        case recoverySeal = "recovery_seal"
    }

    var supportsUnseal: Bool {
        initialized && type == "shamir" && migration != true && recoverySeal != true
    }

    func validated() throws -> Self {
        guard !type.isEmpty,
              type.count <= 40,
              (0...255).contains(n),
              (0...n).contains(t),
              (0...255).contains(progress),
              !initialized || type != "shamir" || (t > 0 && progress < t),
              initialized || sealed else {
            throw AppFailure("The server returned inconsistent seal status. No share was sent by this status request.")
        }
        return self
    }
}
