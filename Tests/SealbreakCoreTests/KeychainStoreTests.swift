import Foundation
import LocalAuthentication
import Security
import Testing
@testable import SealbreakCore

struct KeychainStoreTests {
    private let origin = "https://bao.example.com"
    private let syntheticShare = String(repeating: "a", count: 64)

    @Test
    func readReturnsValidatedRecordAndBuildsProfileScopedQuery() throws {
        let stub = KeychainStub()
        let record = try makeRecord()
        stub.copyStatus = errSecSuccess
        stub.copyData = try JSONEncoder().encode(record)
        let context = LAContext()

        let result = try KeychainStore(access: stub).read(
            profileID: record.profileID,
            context: context
        )

        #expect(result.profileID == record.profileID)
        #expect(result.boundOrigin == record.boundOrigin)
        #expect(result.share == record.share)
        #expect(
            stub.lastCopyRequest?[kSecAttrAccount as String] as? String
                == "share.\(record.profileID.uuidString.lowercased())"
        )
        #expect(stub.lastCopyRequest?[kSecReturnData as String] as? Bool == true)
        #expect(stub.lastCopyRequest?[kSecUseAuthenticationContext as String] as? LAContext === context)
    }

    @Test
    func readRejectsOversizedUnreadableAndMismatchedRecords() throws {
        let stub = KeychainStub()
        let store = KeychainStore(access: stub)
        let context = LAContext()
        let profileID = UUID()

        stub.copyStatus = errSecSuccess
        stub.copyData = Data(repeating: 0, count: StorageLimits.maxRecordBytes + 1)
        #expect(throws: AppFailure.self) {
            try store.read(profileID: profileID, context: context)
        }

        stub.copyData = Data("{}".utf8)
        #expect(throws: AppFailure.self) {
            try store.read(profileID: profileID, context: context)
        }

        let foreign = try makeRecord()
        #expect(foreign.profileID != profileID)
        stub.copyData = try JSONEncoder().encode(foreign)
        #expect(throws: AppFailure.self) {
            try store.read(profileID: profileID, context: context)
        }
    }

    @Test
    func readMapsKeychainFailures() {
        let cases: [(OSStatus, String)] = [
            (errSecDuplicateItem, "A protected share already exists"),
            (errSecItemNotFound, "No accessible share was found."),
            (errSecAuthFailed, "Keychain access was denied."),
            (errSecInteractionNotAllowed, "Keychain access was denied."),
            (errSecUserCanceled, "Keychain access was denied."),
            (-9_999, "The Keychain operation failed (status -9999).")
        ]

        for (status, prefix) in cases {
            let stub = KeychainStub()
            stub.copyStatus = status
            do {
                _ = try KeychainStore(access: stub).read(
                    profileID: UUID(),
                    context: LAContext()
                )
                #expect(Bool(false))
            } catch let error as AppFailure {
                #expect(error.message.hasPrefix(prefix))
            } catch {
                #expect(Bool(false))
            }
        }
    }

    @Test
    func insertProtectsEncodedRecordInProfileScopedAccountAndMapsFailures() throws {
        let stub = KeychainStub()
        let store = KeychainStore(access: stub)
        let context = LAContext()
        let record = try makeRecord()

        try store.insert(record, context: context)
        let data = try #require(stub.lastAddRequest?[kSecValueData as String] as? Data)
        let decoded = try JSONDecoder().decode(ShareRecord.self, from: data)
        #expect(decoded.profileID == record.profileID)
        #expect(decoded.boundOrigin == record.boundOrigin)
        #expect(decoded.share == record.share)
        #expect(
            stub.lastAddRequest?[kSecAttrAccount as String] as? String
                == "share.\(record.profileID.uuidString.lowercased())"
        )
        #expect(stub.lastAddRequest?[kSecAttrAccessControl as String] != nil)
        #expect(stub.lastAddRequest?[kSecUseAuthenticationContext as String] as? LAContext === context)

        stub.addStatus = errSecDuplicateItem
        #expect(throws: AppFailure.self) { try store.insert(record, context: context) }

        stub.accessControl = nil
        #expect(throws: AppFailure.self) { try store.insert(record, context: context) }
    }

    @Test
    func replaceUpdatesOnlyTheSelectedProfileAccountAndMapsFailure() throws {
        let stub = KeychainStub()
        let store = KeychainStore(access: stub)
        let context = LAContext()
        let record = try makeRecord()

        try store.replace(record, context: context)
        let data = try #require(stub.lastUpdateAttributes?[kSecValueData as String] as? Data)
        #expect(try JSONDecoder().decode(ShareRecord.self, from: data).share == record.share)
        #expect(
            stub.lastUpdateRequest?[kSecAttrAccount as String] as? String
                == "share.\(record.profileID.uuidString.lowercased())"
        )
        #expect(stub.lastUpdateRequest?[kSecUseAuthenticationContext as String] as? LAContext === context)

        stub.updateStatus = errSecAuthFailed
        #expect(throws: AppFailure.self) { try store.replace(record, context: context) }
    }

    @Test
    func deleteTargetsOneProfileAndTreatsMissingItemAsSuccess() throws {
        let stub = KeychainStub()
        let store = KeychainStore(access: stub)
        let context = LAContext()
        let profileID = UUID()

        stub.deleteStatus = errSecSuccess
        try store.delete(profileID: profileID, context: context)
        #expect(
            stub.lastDeleteRequest?[kSecAttrAccount as String] as? String
                == "share.\(profileID.uuidString.lowercased())"
        )
        #expect(stub.lastDeleteRequest?[kSecUseAuthenticationContext as String] as? LAContext === context)

        stub.deleteStatus = errSecItemNotFound
        try store.delete(profileID: profileID, context: context)

        stub.deleteStatus = errSecAuthFailed
        #expect(throws: AppFailure.self) {
            try store.delete(profileID: profileID, context: context)
        }
    }

    @Test
    func systemKeychainAdapterRejectsInvalidQueriesWithoutPersistingData() {
        let access = SystemKeychainAccess()
        let invalidQuery: [String: Any] = [kSecClass as String: "invalid-class"]

        _ = access.makeBiometricAccessControl()
        let (copyStatus, data) = access.copyMatching(invalidQuery)
        let addStatus = access.add(invalidQuery)
        let updateStatus = access.update(invalidQuery, attributes: [:])
        let deleteStatus = access.delete(invalidQuery)

        #expect(copyStatus != errSecSuccess)
        #expect(data == nil)
        #expect(addStatus != errSecSuccess)
        #expect(updateStatus != errSecSuccess)
        #expect(deleteStatus != errSecSuccess)
    }

    @Test
    func profileStoreDefaultDirectoryCanBeResolved() {
        _ = ProfileStore()
    }

    @Test
    func profileStorePersistsCollectionAndDeletesOnlySelectedProfile() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProfileStore(baseDirectory: root)
        let first = try ServerProfile(id: UUID(), name: "Test", address: origin, product: .openBao)
        let second = try ServerProfile(
            id: UUID(),
            name: "Production",
            address: "https://prod.example.com",
            product: .vault
        )

        #expect(try store.loadAll().isEmpty)
        try store.save(first)
        #expect(try store.loadAll() == [first])

        try store.save(second)
        #expect(try store.loadAll() == [first, second])

        let renamedFirst = try ServerProfile(
            id: first.id,
            name: "Renamed",
            address: first.origin,
            product: first.product
        )
        try store.save(renamedFirst)
        #expect(try store.loadAll() == [renamedFirst, second])

        try store.delete(id: first.id)
        #expect(try store.loadAll() == [second])

        try store.delete(id: second.id)
        #expect(try store.loadAll().isEmpty)
        try store.delete(id: second.id)
    }

    @Test
    func profileStoreRejectsDuplicateOriginAndRetargeting() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProfileStore(baseDirectory: root)
        let profile = try ServerProfile(id: UUID(), name: "Test", address: origin)

        try store.save(profile)

        let duplicateOrigin = try ServerProfile(id: UUID(), name: "Duplicate", address: origin)
        #expect(throws: AppFailure.self) {
            try store.save(duplicateOrigin)
        }

        let retargeted = try ServerProfile(
            id: profile.id,
            name: profile.name,
            address: "https://other.example.com",
            product: profile.product
        )
        #expect(throws: AppFailure.self) {
            try store.save(retargeted)
        }
    }

    @Test
    func profileStoreRejectsOversizedCatalog() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Sealbreak", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(repeating: 0, count: StorageLimits.maxProfileCatalogBytes + 1)
            .write(to: folder.appendingPathComponent("profiles.json"))

        #expect(throws: AppFailure.self) {
            try ProfileStore(baseDirectory: root).loadAll()
        }
    }

    @Test
    func profileStoreRejectsMalformedAndUnsupportedCatalogs() throws {
        let malformedRoot = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: malformedRoot) }
        try writeCatalogData(Data("{}".utf8), to: malformedRoot)

        #expect(throws: AppFailure.self) {
            try ProfileStore(baseDirectory: malformedRoot).loadAll()
        }

        let versionRoot = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: versionRoot) }
        try writeCatalog(
            TestProfileCatalog(version: 2, profiles: []),
            to: versionRoot
        )

        #expect(throws: AppFailure.self) {
            try ProfileStore(baseDirectory: versionRoot).loadAll()
        }
    }

    @Test
    func profileStoreRejectsInvalidCollectionInvariants() throws {
        let sharedID = UUID()
        let first = try ServerProfile(
            id: sharedID,
            name: "First",
            address: "https://first.example.com"
        )
        let duplicateID = try ServerProfile(
            id: sharedID,
            name: "Second",
            address: "https://second.example.com"
        )

        let duplicateIDRoot = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: duplicateIDRoot) }
        try writeCatalog(
            TestProfileCatalog(version: 1, profiles: [first, duplicateID]),
            to: duplicateIDRoot
        )

        #expect(throws: AppFailure.self) {
            try ProfileStore(baseDirectory: duplicateIDRoot).loadAll()
        }

        let duplicateOrigin = try ServerProfile(
            id: UUID(),
            name: "Duplicate origin",
            address: first.origin
        )
        let duplicateOriginRoot = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: duplicateOriginRoot) }
        try writeCatalog(
            TestProfileCatalog(version: 1, profiles: [first, duplicateOrigin]),
            to: duplicateOriginRoot
        )

        #expect(throws: AppFailure.self) {
            try ProfileStore(baseDirectory: duplicateOriginRoot).loadAll()
        }
    }

    @Test
    func profileStoreRejectsOversizedProfileInsideCatalog() throws {
        let name = "é" + String(repeating: "\u{0301}", count: 2_047)
        let profile = try ServerProfile(
            id: UUID(),
            name: name,
            address: origin
        )
        #expect(try JSONEncoder().encode(profile).count > StorageLimits.maxRecordBytes)

        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeCatalog(
            TestProfileCatalog(version: 1, profiles: [profile]),
            to: root
        )

        #expect(throws: AppFailure.self) {
            try ProfileStore(baseDirectory: root).loadAll()
        }
    }

    private struct TestProfileCatalog: Codable {
        let version: Int
        let profiles: [ServerProfile]
    }

    private func writeCatalog(_ catalog: TestProfileCatalog, to root: URL) throws {
        try writeCatalogData(try JSONEncoder().encode(catalog), to: root)
    }

    private func writeCatalogData(_ data: Data, to root: URL) throws {
        let folder = root.appendingPathComponent("Sealbreak", isDirectory: true)
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        try data.write(to: folder.appendingPathComponent("profiles.json"))
    }

    private func makeRecord() throws -> ShareRecord {
        let profile = try ServerProfile(id: UUID(), name: "Test", address: origin, product: .vault)
        return try ShareRecord(profile: profile, input: syntheticShare)
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SealbreakTests-\(UUID().uuidString)", isDirectory: true)
    }
}

private final class KeychainStub: KeychainAccessing {
    var accessControl = SecAccessControlCreateWithFlags(
        nil,
        kSecAttrAccessibleAfterFirstUnlock,
        [],
        nil
    )
    var copyStatus = errSecItemNotFound
    var copyData: Data?
    var addStatus = errSecSuccess
    var updateStatus = errSecSuccess
    var deleteStatus = errSecSuccess

    private(set) var lastCopyRequest: [String: Any]?
    private(set) var lastAddRequest: [String: Any]?
    private(set) var lastUpdateRequest: [String: Any]?
    private(set) var lastUpdateAttributes: [String: Any]?
    private(set) var lastDeleteRequest: [String: Any]?

    func makeBiometricAccessControl() -> SecAccessControl? {
        accessControl
    }

    func copyMatching(_ request: [String: Any]) -> (OSStatus, Data?) {
        lastCopyRequest = request
        return (copyStatus, copyData)
    }

    func add(_ request: [String: Any]) -> OSStatus {
        lastAddRequest = request
        return addStatus
    }

    func update(_ request: [String: Any], attributes: [String: Any]) -> OSStatus {
        lastUpdateRequest = request
        lastUpdateAttributes = attributes
        return updateStatus
    }

    func delete(_ request: [String: Any]) -> OSStatus {
        lastDeleteRequest = request
        return deleteStatus
    }
}
