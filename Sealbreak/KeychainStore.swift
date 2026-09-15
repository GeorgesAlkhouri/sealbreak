import Foundation
import LocalAuthentication
import Security

protocol KeychainAccessing {
    func makeBiometricAccessControl() -> SecAccessControl?
    func copyMatching(_ request: [String: Any]) -> (OSStatus, Data?)
    func add(_ request: [String: Any]) -> OSStatus
    func update(_ request: [String: Any], attributes: [String: Any]) -> OSStatus
    func delete(_ request: [String: Any]) -> OSStatus
}

struct SystemKeychainAccess: KeychainAccessing {
    func makeBiometricAccessControl() -> SecAccessControl? {
        SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            .biometryCurrentSet,
            nil
        )
    }

    func copyMatching(_ request: [String: Any]) -> (OSStatus, Data?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        return (status, result as? Data)
    }

    func add(_ request: [String: Any]) -> OSStatus {
        SecItemAdd(request as CFDictionary, nil)
    }

    func update(_ request: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(request as CFDictionary, attributes as CFDictionary)
    }

    func delete(_ request: [String: Any]) -> OSStatus {
        SecItemDelete(request as CFDictionary)
    }
}

struct KeychainStore {
    private let access: any KeychainAccessing

    init(access: any KeychainAccessing = SystemKeychainAccess()) {
        self.access = access
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(Bundle.main.bundleIdentifier ?? "Sealbreak").unseal",
            kSecAttrAccount as String: "single-share-v1",
            kSecAttrSynchronizable as String: false
        ]
    }

    func read(context: LAContext) throws -> ShareRecord {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        request[kSecUseAuthenticationContext as String] = context

        let (status, storedData) = access.copyMatching(request)
        guard status == errSecSuccess, var data = storedData else {
            throw failure(status)
        }
        defer {
            data.resetBytes(in: data.startIndex..<data.endIndex)
        }
        guard data.count <= StorageLimits.maxRecordBytes else {
            throw AppFailure("The protected record is larger than expected. Use independent recovery.")
        }

        do {
            return try JSONDecoder().decode(ShareRecord.self, from: data).validated()
        } catch {
            throw AppFailure("The protected record is unreadable. Use independent recovery; do not overwrite your only copy.")
        }
    }

    func insert(_ record: ShareRecord, context: LAContext) throws {
        guard let accessControl = access.makeBiometricAccessControl() else {
            throw AppFailure("Could not create biometric Keychain protection. A device passcode and Face ID are required.")
        }

        var data = try JSONEncoder().encode(record.validated())
        defer {
            data.resetBytes(in: data.startIndex..<data.endIndex)
        }
        try StorageLimits.validateEncodedSize(data)
        var request = query
        request[kSecAttrAccessControl as String] = accessControl
        request[kSecValueData as String] = data
        request[kSecUseAuthenticationContext as String] = context

        let status = access.add(request)
        guard status == errSecSuccess else {
            throw failure(status)
        }
    }

    func replace(_ record: ShareRecord, context: LAContext) throws {
        var data = try JSONEncoder().encode(record.validated())
        defer {
            data.resetBytes(in: data.startIndex..<data.endIndex)
        }
        try StorageLimits.validateEncodedSize(data)
        var request = query
        request[kSecUseAuthenticationContext as String] = context

        let status = access.update(
            request,
            attributes: [kSecValueData as String: data]
        )
        guard status == errSecSuccess else {
            throw failure(status)
        }
    }

    func delete(context: LAContext) throws {
        var request = query
        request[kSecUseAuthenticationContext as String] = context
        let status = access.delete(request)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw failure(status)
        }
    }

    private func failure(_ status: OSStatus) -> AppFailure {
        switch status {
        case errSecDuplicateItem:
            return AppFailure("A protected share already exists. Restore its profile from Keychain, or explicitly remove local data before importing again.")
        case errSecItemNotFound:
            return AppFailure("No accessible share was found. Face ID or the device passcode may have changed. Recover from your independent copy.")
        case errSecAuthFailed, errSecInteractionNotAllowed, errSecUserCanceled:
            return AppFailure("Keychain access was denied. No passcode fallback is used. Try fresh Face ID; otherwise use independent recovery.")
        default:
            return AppFailure("The Keychain operation failed (status \(status)). Existing data was not deliberately deleted.")
        }
    }
}

struct ProfileStore {
    private let baseDirectory: URL

    init(baseDirectory: URL? = nil) {
        self.baseDirectory = baseDirectory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
    }

    private var directory: URL {
        baseDirectory.appendingPathComponent("Sealbreak", isDirectory: true)
    }

    private var file: URL {
        directory.appendingPathComponent("profile.json")
    }

    func load() throws -> ServerProfile? {
        guard FileManager.default.fileExists(atPath: file.path) else {
            return nil
        }
        let handle = try FileHandle(forReadingFrom: file)
        defer {
            try? handle.close()
        }
        let data = try handle.read(upToCount: StorageLimits.maxRecordBytes + 1) ?? Data()
        guard data.count <= StorageLimits.maxRecordBytes else {
            throw AppFailure("Invalid display profile. Restore it from Keychain.")
        }
        return try JSONDecoder().decode(ServerProfile.self, from: data).validated()
    }

    func save(_ profile: ServerProfile) throws {
        let data = try JSONEncoder().encode(profile.validated())
        try StorageLimits.validateEncodedSize(data)

        var folder = directory
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        try data.write(
            to: file,
            options: [.atomic, .completeFileProtection]
        )
    }

    func delete() throws {
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }
}
