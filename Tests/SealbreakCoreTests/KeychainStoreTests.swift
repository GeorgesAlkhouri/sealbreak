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
    func deleteAllTargetsOnlySealbreakServiceNamespace() throws {
        let access = KeychainStub()
        let store = KeychainStore(access: access)

        try store.deleteAll()

        let request = try #require(access.lastDeleteRequest)
        #expect(
            request[kSecClass as String] as? String
                == kSecClassGenericPassword as String
        )
        #expect(
            request[kSecAttrService as String] as? String
                == "\(Bundle.main.bundleIdentifier ?? "Sealbreak").unseal"
        )
        #expect(request[kSecAttrAccount as String] == nil)
        #expect(request[kSecAttrSynchronizable as String] as? Bool == false)

        access.deleteStatus = errSecItemNotFound
        try store.deleteAll()

        access.deleteStatus = errSecParam
        #expect(throws: AppFailure.self) {
            try store.deleteAll()
        }
    }

    @Test
    func profileStoreDefaultDirectoryCanBeResolved() {
        _ = ProfileStore()
    }

    @Test
    func profileStorePersistsCreatingReadyRemovingAndDeletes() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProfileStore(baseDirectory: root)
        let profile = try ServerProfile(
            id: UUID(),
            name: "Test",
            address: origin,
            product: .openBao
        )

        #expect(try store.loadAll().isEmpty)

        try store.begin(profile)
        #expect(
            try store.loadAll() == [
                StoredProfile(profile: profile, state: .creating)
            ]
        )

        try store.commit(id: profile.id)
        #expect(
            try store.loadAll() == [
                StoredProfile(profile: profile, state: .ready)
            ]
        )

        try store.beginRemoval(id: profile.id)
        #expect(
            try store.loadAll() == [
                StoredProfile(profile: profile, state: .removing)
            ]
        )

        try store.delete(id: profile.id)
        #expect(try store.loadAll().isEmpty)

        try store.delete(id: profile.id)
    }

    @Test
    func profileStoreRejectsInvalidLifecycleTransitions() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProfileStore(baseDirectory: root)
        let profile = try ServerProfile(
            id: UUID(),
            name: "Test",
            address: origin
        )

        #expect(throws: AppFailure.self) {
            try store.commit(id: profile.id)
        }

        try store.begin(profile)

        #expect(throws: AppFailure.self) {
            try store.begin(profile)
        }
        #expect(throws: AppFailure.self) {
            try store.commit(id: UUID())
        }

        #expect(
            try store.loadAll() == [
                StoredProfile(profile: profile, state: .creating)
            ]
        )
        #expect(throws: AppFailure.self) {
            try store.beginRemoval(id: profile.id)
        }
    }

    @Test
    func createLocalProfileTransactionPersistsReadyOnlyAfterShareWrite() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProfileStore(baseDirectory: root)
        let profile = try ServerProfile(
            id: UUID(),
            name: "Test",
            address: origin
        )
        var stateDuringShareWrite: StoredProfileState?

        let outcome = createLocalProfileTransaction(
            profile: profile,
            profiles: store,
            insertShare: {
                stateDuringShareWrite = try store.loadAll().first?.state
            }
        )

        #expect(outcome == .completed)
        #expect(stateDuringShareWrite == .creating)
        #expect(
            try store.loadAll() == [
                StoredProfile(profile: profile, state: .ready)
            ]
        )
    }

    @Test
    func createLocalProfileTransactionLeavesCreatingOnShareFailure() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProfileStore(baseDirectory: root)
        let profile = try ServerProfile(
            id: UUID(),
            name: "Test",
            address: origin
        )

        let outcome = createLocalProfileTransaction(
            profile: profile,
            profiles: store,
            insertShare: {
                throw AppFailure("share write failed")
            }
        )

        guard case .recoveryRequired = outcome else {
            Issue.record("Failed share creation must require recovery.")
            return
        }
        #expect(
            try store.loadAll() == [
                StoredProfile(profile: profile, state: .creating)
            ]
        )
    }

    @Test
    func removeLocalProfileTransactionMarksRemovingBeforeDelete() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProfileStore(baseDirectory: root)
        let profile = try ServerProfile(
            id: UUID(),
            name: "Test",
            address: origin
        )
        try store.begin(profile)
        try store.commit(id: profile.id)

        var stateDuringShareDelete: StoredProfileState?
        let outcome = removeLocalProfileTransaction(
            profileID: profile.id,
            profiles: store,
            deleteShare: {
                stateDuringShareDelete = try store.loadAll().first?.state
            }
        )

        #expect(outcome == .completed)
        #expect(stateDuringShareDelete == .removing)
        #expect(try store.loadAll().isEmpty)
    }

    @Test
    func removeLocalProfileTransactionLeavesRemovingOnDeleteFailure() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProfileStore(baseDirectory: root)
        let profile = try ServerProfile(
            id: UUID(),
            name: "Test",
            address: origin
        )
        try store.begin(profile)
        try store.commit(id: profile.id)

        let outcome = removeLocalProfileTransaction(
            profileID: profile.id,
            profiles: store,
            deleteShare: {
                throw AppFailure("share delete failed")
            }
        )

        guard case .recoveryRequired = outcome else {
            Issue.record("Failed local removal must require recovery.")
            return
        }
        #expect(
            try store.loadAll() == [
                StoredProfile(profile: profile, state: .removing)
            ]
        )
    }

    @Test
    func profileStoreResetRemovesMalformedCatalogWithoutReadingIt() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeCatalogData(Data("{}".utf8), to: root)

        let store = ProfileStore(baseDirectory: root)
        try store.reset()
        #expect(try store.loadAll().isEmpty)

        try store.reset()
    }

    @Test
    func localResetRecoversMalformedCatalogWithoutOrphaningShares() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeCatalogData(Data("{}".utf8), to: root)

        let access = KeychainStub()
        let keychain = KeychainStore(access: access)
        let profiles = ProfileStore(baseDirectory: root)

        try resetLocalStorage(
            deleteShares: {
                try keychain.deleteAll()
            },
            resetProfiles: {
                try profiles.reset()
            }
        )

        #expect(try profiles.loadAll().isEmpty)
        let request = try #require(access.lastDeleteRequest)
        #expect(request[kSecAttrAccount as String] == nil)

        try writeCatalogData(Data("{}".utf8), to: root)
        access.deleteStatus = errSecParam

        #expect(throws: AppFailure.self) {
            try resetLocalStorage(
                deleteShares: {
                    try keychain.deleteAll()
                },
                resetProfiles: {
                    try profiles.reset()
                }
            )
        }
        #expect(throws: AppFailure.self) {
            try profiles.loadAll()
        }
    }

    @Test
    func localResetDeletesSharesBeforeProfileCatalog() throws {
        var events: [String] = []

        try resetLocalStorage(
            deleteShares: {
                events.append("shares")
            },
            resetProfiles: {
                events.append("profiles")
            }
        )
        #expect(events == ["shares", "profiles"])

        events = []
        #expect(throws: AppFailure.self) {
            try resetLocalStorage(
                deleteShares: {
                    events.append("shares")
                    throw AppFailure("keychain delete failed")
                },
                resetProfiles: {
                    events.append("profiles")
                }
            )
        }
        #expect(events == ["shares"])
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
    func profileStoreRejectsMalformedUnsupportedAndLegacyCatalogs() throws {
        let malformedRoot = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: malformedRoot) }
        try writeCatalogData(Data("{}".utf8), to: malformedRoot)

        #expect(throws: AppFailure.self) {
            try ProfileStore(baseDirectory: malformedRoot).loadAll()
        }

        let unsupportedRoot = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: unsupportedRoot) }
        try writeCatalog(
            TestProfileCatalog(version: 99, profiles: []),
            to: unsupportedRoot
        )

        #expect(throws: AppFailure.self) {
            try ProfileStore(baseDirectory: unsupportedRoot).loadAll()
        }

        let legacyRoot = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: legacyRoot) }
        let legacyProfile = try ServerProfile(
            id: UUID(),
            name: "Legacy",
            address: origin
        )
        try writeCatalogData(
            try JSONEncoder().encode(
                LegacyProfileCatalog(
                    version: 1,
                    profiles: [legacyProfile]
                )
            ),
            to: legacyRoot
        )

        #expect(throws: AppFailure.self) {
            try ProfileStore(baseDirectory: legacyRoot).loadAll()
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
            TestProfileCatalog(
                version: 2,
                profiles: [
                    StoredProfile(profile: first, state: .ready),
                    StoredProfile(profile: duplicateID, state: .ready)
                ]
            ),
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
            TestProfileCatalog(
                version: 2,
                profiles: [
                    StoredProfile(profile: first, state: .ready),
                    StoredProfile(profile: duplicateOrigin, state: .ready)
                ]
            ),
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
            TestProfileCatalog(
                version: 2,
                profiles: [
                    StoredProfile(profile: profile, state: .ready)
                ]
            ),
            to: root
        )

        #expect(throws: AppFailure.self) {
            try ProfileStore(baseDirectory: root).loadAll()
        }
    }

    private struct TestProfileCatalog: Codable {
        let version: Int
        let profiles: [StoredProfile]
    }

    private struct LegacyProfileCatalog: Codable {
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
