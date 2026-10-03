import Foundation
import LocalAuthentication
import SealbreakCore
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

package struct KeychainStore {
    package init() {
        self.init(access: SystemKeychainAccess())
    }

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

    package func read(profileID: UUID, context: LAContext) throws -> ShareRecord {
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
            throw AppFailure(LocalizedStringResource("The protected record is larger than expected. Use independent recovery.", bundle: .module))
        }

        let record: ShareRecord
        do {
            record = try JSONDecoder().decode(ShareRecord.self, from: data).validated()
        } catch {
            throw AppFailure(LocalizedStringResource("The protected record is unreadable. Use independent recovery; do not overwrite your only copy.", bundle: .module))
        }

        guard record.profileID == profileID else {
            throw AppFailure(LocalizedStringResource("The protected profile binding does not match this Keychain entry. Use independent recovery.", bundle: .module))
        }
        return record
    }

    package func insert(_ record: ShareRecord, context: LAContext) throws {
        guard let accessControl = access.makeBiometricAccessControl() else {
            throw AppFailure(LocalizedStringResource("Could not create biometric Keychain protection. A device passcode and Face ID are required.", bundle: .module))
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

    package func replace(_ record: ShareRecord, context: LAContext) throws {
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

    package func delete(profileID: UUID, context: LAContext) throws {
        var request = query(profileID: profileID)
        request[kSecUseAuthenticationContext as String] = context
        let status = access.delete(request)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw failure(status)
        }
    }

    package func deleteAll() throws {
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
            return AppFailure(LocalizedStringResource("A protected share already exists for this server profile.", bundle: .module))
        case errSecItemNotFound:
            return AppFailure(LocalizedStringResource("No accessible share was found. Face ID or the device passcode may have changed. Recover from your independent copy.", bundle: .module))
        case errSecAuthFailed, errSecInteractionNotAllowed, errSecUserCanceled:
            return AppFailure(LocalizedStringResource("Keychain access was denied. No passcode fallback is used. Try fresh Face ID; otherwise use independent recovery.", bundle: .module))
        default:
            let statusCode = String(status)
            return AppFailure(LocalizedStringResource("The Keychain operation failed (status \(statusCode)). Existing data was not deliberately deleted.", bundle: .module))
        }
    }
}
