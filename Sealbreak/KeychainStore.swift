import Foundation
import LocalAuthentication
import Security

struct KeychainStore {
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

        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        guard status == errSecSuccess, var data = result as? Data else {
            throw failure(status)
        }
        guard data.count <= 4096 else {
            throw AppFailure("The protected record is larger than expected. Use independent recovery.")
        }
        defer {
            data.resetBytes(in: data.startIndex..<data.endIndex)
        }

        do {
            return try JSONDecoder().decode(ShareRecord.self, from: data).validated()
        } catch {
            throw AppFailure("The protected record is unreadable. Use independent recovery; do not overwrite your only copy.")
        }
    }

    func insert(_ record: ShareRecord, context: LAContext) throws {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            .biometryCurrentSet,
            &error
        ) else {
            throw AppFailure("Could not create biometric Keychain protection. A device passcode and Face ID are required.")
        }

        var data = try JSONEncoder().encode(record)
        defer {
            data.resetBytes(in: data.startIndex..<data.endIndex)
        }
        var request = query
        request[kSecAttrAccessControl as String] = access
        request[kSecValueData as String] = data
        request[kSecUseAuthenticationContext as String] = context

        let status = SecItemAdd(request as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw failure(status)
        }
    }

    func replace(_ record: ShareRecord, context: LAContext) throws {
        var data = try JSONEncoder().encode(record)
        defer {
            data.resetBytes(in: data.startIndex..<data.endIndex)
        }
        var request = query
        request[kSecUseAuthenticationContext as String] = context

        let status = SecItemUpdate(
            request as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        guard status == errSecSuccess else {
            throw failure(status)
        }
    }

    func delete(context: LAContext) throws {
        var request = query
        request[kSecUseAuthenticationContext as String] = context
        let status = SecItemDelete(request as CFDictionary)
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
    private var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sealbreak", isDirectory: true)
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
        let data = try handle.read(upToCount: 4097) ?? Data()
        guard data.count <= 4096 else {
            throw AppFailure("Invalid display profile. Restore it from Keychain.")
        }
        return try JSONDecoder().decode(ServerProfile.self, from: data).validated()
    }

    func save(_ profile: ServerProfile) throws {
        var folder = directory
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        try JSONEncoder().encode(profile).write(
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
