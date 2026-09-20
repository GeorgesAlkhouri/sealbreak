import Foundation

// Readers and writers must agree on the size of the complete encoded payload.
enum StorageLimits {
    static let maxRecordBytes = 4_096

    static func validateEncodedSize(_ data: Data) throws {
        guard data.count <= maxRecordBytes else {
            throw AppFailure("The record exceeds the \(maxRecordBytes)-byte storage limit. Shorten the server name; nothing was saved.")
        }
    }
}

enum ServerProduct: String, Codable, Equatable, Sendable {
    case openBao = "OpenBao"
    case vault = "Vault"
    case generic = "Generic"
}

struct ServerProfile: Codable, Equatable, Sendable {
    let name: String
    let origin: String
    let product: ServerProduct

    init(
        name: String,
        address: String,
        product: ServerProduct = .generic
    ) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              name.utf8.count <= StorageLimits.maxRecordBytes,
              name.count <= 40,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw AppFailure("Use a server name of 1–40 characters without control characters, within \(StorageLimits.maxRecordBytes) UTF-8 bytes.")
        }
        self.name = name
        self.origin = try Self.canonicalOrigin(address)
        self.product = product
    }

    func validated() throws -> Self {
        guard try ServerProfile(name: name, address: origin, product: product) == self else {
            throw AppFailure("The server profile is invalid. Set up this server profile again.")
        }
        return self
    }

    func endpoint(_ path: String) throws -> URL {
        _ = try validated()
        return try Self.url(fromCanonicalOrigin: origin)
            .appendingPathComponent("v1/sys/\(path)")
    }

    static func canonicalOrigin(_ input: String) throws -> String {
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
            throw AppFailure("Use an HTTPS origin such as https://server.example.com:8200. No credentials, path, query, fragment, or non-ASCII hostname is allowed.")
        }
        parts.scheme = "https"
        parts.host = host.lowercased()
        parts.path = ""
        if parts.port == 443 {
            parts.port = nil
        }
        return try url(from: parts).absoluteString
    }

    static func url(from components: URLComponents) throws -> URL {
        guard let url = components.url else {
            throw AppFailure("Unable to construct a canonical HTTPS server origin.")
        }
        return url
    }

    static func url(fromCanonicalOrigin origin: String) throws -> URL {
        guard let url = URL(string: origin) else {
            throw AppFailure("The canonical server origin could not be converted to a URL.")
        }
        return url
    }
}

struct ShareRecord: Codable, Equatable, Sendable {
    let version: Int
    let boundOrigin: String
    var share: String

    init(profile: ServerProfile, input: String) throws {
        let profile = try profile.validated()
        self.version = 1
        self.boundOrigin = profile.origin
        self.share = try Self.validateShare(input)
    }

    func validated() throws -> Self {
        guard version == 1 else {
            throw AppFailure("Unsupported Keychain record version.")
        }
        guard try ServerProfile.canonicalOrigin(boundOrigin) == boundOrigin else {
            throw AppFailure("The protected target binding is invalid. Use independent recovery.")
        }
        _ = try Self.validateShare(share)
        return self
    }

    func endpoint(_ path: String) throws -> URL {
        _ = try validated()
        return try ServerProfile.url(fromCanonicalOrigin: boundOrigin)
            .appendingPathComponent("v1/sys/\(path)")
    }

    static func validateShare(_ input: String) throws -> String {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let isHex = text.utf8.count.isMultiple(of: 2) && text.utf8.allSatisfy {
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }
        guard (16...1024).contains(text.utf8.count),
              isHex || Data(base64Encoded: text) != nil else {
            throw AppFailure("Enter one hexadecimal or Base64 Shamir share. Its validity is ultimately checked by the configured server.")
        }
        return text
    }
}

struct SealStatus: Decodable, Equatable, Sendable {
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
