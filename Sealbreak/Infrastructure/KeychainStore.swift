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

    private var service: String {
        "\(Bundle.main.bundleIdentifier ?? "Sealbreak").unseal"
    }

    private func query(profileID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "share.\(profileID.uuidString.lowercased())",
            kSecAttrSynchronizable as String: false
        ]
    }

    func read(profileID: UUID, context: LAContext) throws -> ShareRecord {
        var request = query(profileID: profileID)
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

        let record: ShareRecord
        do {
            record = try JSONDecoder().decode(ShareRecord.self, from: data).validated()
        } catch {
            throw AppFailure("The protected record is unreadable. Use independent recovery; do not overwrite your only copy.")
        }

        guard record.profileID == profileID else {
            throw AppFailure("The protected profile binding does not match this Keychain entry. Use independent recovery.")
        }
        return record
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
        var request = query(profileID: record.profileID)
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
        var request = query(profileID: record.profileID)
        request[kSecUseAuthenticationContext as String] = context

        let status = access.update(
            request,
            attributes: [kSecValueData as String: data]
        )
        guard status == errSecSuccess else {
            throw failure(status)
        }
    }

    func delete(profileID: UUID, context: LAContext) throws {
        var request = query(profileID: profileID)
        request[kSecUseAuthenticationContext as String] = context
        let status = access.delete(request)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw failure(status)
        }
    }

    func deleteAll() throws {
        let request: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: false
        ]
        let status = access.delete(request)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw failure(status)
        }
    }

    private func failure(_ status: OSStatus) -> AppFailure {
        switch status {
        case errSecDuplicateItem:
            return AppFailure("A protected share already exists for this server profile.")
        case errSecItemNotFound:
            return AppFailure("No accessible share was found. Face ID or the device passcode may have changed. Recover from your independent copy.")
        case errSecAuthFailed, errSecInteractionNotAllowed, errSecUserCanceled:
            return AppFailure("Keychain access was denied. No passcode fallback is used. Try fresh Face ID; otherwise use independent recovery.")
        default:
            return AppFailure("The Keychain operation failed (status \(status)). Existing data was not deliberately deleted.")
        }
    }
}

enum StoredProfileState: String, Codable, Equatable {
    case pending
    case ready
}

struct StoredProfile: Codable, Equatable {
    let profile: ServerProfile
    var state: StoredProfileState
}

private struct ProfileCatalog: Codable {
    static let currentVersion = 2

    let version: Int
    var profiles: [StoredProfile]
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
        directory.appendingPathComponent("profiles.json")
    }

    func loadAll() throws -> [StoredProfile] {
        guard FileManager.default.fileExists(atPath: file.path) else {
            return []
        }

        let handle = try FileHandle(forReadingFrom: file)
        defer {
            try? handle.close()
        }
        let data = try handle.read(upToCount: StorageLimits.maxProfileCatalogBytes + 1) ?? Data()
        guard data.count <= StorageLimits.maxProfileCatalogBytes else {
            throw AppFailure(
                "Invalid profile catalog. Reset local Sealbreak data before setting up again using your independent share copies."
            )
        }

        let catalog: ProfileCatalog
        do {
            catalog = try JSONDecoder().decode(ProfileCatalog.self, from: data)
        } catch {
            throw AppFailure(
                "Invalid profile catalog. Reset local Sealbreak data before setting up again using your independent share copies."
            )
        }
        guard catalog.version == ProfileCatalog.currentVersion else {
            throw AppFailure(
                "Unsupported profile catalog version. Reset local Sealbreak data before setting up again using your independent share copies."
            )
        }

        var ids = Set<UUID>()
        var origins = Set<String>()
        var validated: [StoredProfile] = []
        validated.reserveCapacity(catalog.profiles.count)

        for entry in catalog.profiles {
            let profile = try entry.profile.validated()
            try StorageLimits.validateEncodedSize(JSONEncoder().encode(profile))
            guard ids.insert(profile.id).inserted else {
                throw AppFailure("The profile catalog contains a duplicate profile identifier.")
            }
            guard origins.insert(profile.origin).inserted else {
                throw AppFailure("The profile catalog contains the same server origin more than once.")
            }
            validated.append(
                StoredProfile(
                    profile: profile,
                    state: entry.state
                )
            )
        }

        return validated
    }

    func begin(_ profile: ServerProfile) throws {
        let profile = try profile.validated()
        try StorageLimits.validateEncodedSize(JSONEncoder().encode(profile))

        var entries = try loadAll()
        guard entries.isEmpty else {
            throw AppFailure(
                "Local profile data already exists. Reset local Sealbreak data before continuing."
            )
        }
        entries.append(
            StoredProfile(
                profile: profile,
                state: .pending
            )
        )
        try write(entries)
    }

    func commit(id: UUID) throws {
        var entries = try loadAll()
        guard entries.count == 1,
              entries[0].profile.id == id,
              entries[0].state == .pending else {
            throw AppFailure(
                "Local setup state cannot be committed. Reset local Sealbreak data before continuing."
            )
        }

        entries[0].state = .ready
        try write(entries)
    }

    func delete(id: UUID) throws {
        var entries = try loadAll()
        entries.removeAll { $0.profile.id == id }

        if entries.isEmpty {
            if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
            }
            return
        }

        try write(entries)
    }

    func reset() throws {
        guard FileManager.default.fileExists(atPath: file.path) else {
            return
        }
        try FileManager.default.removeItem(at: file)
    }

    private func write(_ profiles: [StoredProfile]) throws {
        let catalog = ProfileCatalog(
            version: ProfileCatalog.currentVersion,
            profiles: profiles
        )
        let data = try JSONEncoder().encode(catalog)
        try StorageLimits.validateProfileCatalogSize(data)

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
}

func resolveLocalSetupState(
    profiles: [StoredProfile]
) -> LocalSetupState {
    guard profiles.count <= 1 else {
        return .recoveryRequired(
            "Local Sealbreak data contains multiple server profiles, but this app version supports one. Reset local data to continue."
        )
    }

    guard let entry = profiles.first else {
        return .empty
    }

    switch entry.state {
    case .pending:
        return .recoveryRequired(
            "Local Sealbreak setup did not finish cleanly. Reset local data to continue, then set up again using your independent share copy."
        )

    case .ready:
        return .ready(entry.profile)
    }
}

func resetLocalStorage(
    deleteShares: () throws -> Void,
    resetProfiles: () throws -> Void
) throws {
    try deleteShares()
    try resetProfiles()
}
