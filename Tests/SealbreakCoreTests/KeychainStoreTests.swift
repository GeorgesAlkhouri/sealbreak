import Foundation
import LocalAuthentication
import Security
import Testing
@testable import SealbreakCore

struct KeychainStoreTests {
    private let origin = "https://bao.example.com"
    private let syntheticShare = String(repeating: "a", count: 64)

    @Test
    func readReturnsValidatedRecordAndBuildsExpectedQuery() throws {
        let stub = KeychainStub()
        let record = try makeRecord()
        stub.copyStatus = errSecSuccess
        stub.copyData = try JSONEncoder().encode(record)
        let context = LAContext()

        let result = try KeychainStore(access: stub).read(context: context)

        #expect(result.profile == record.profile)
        #expect(result.share == record.share)
        #expect(stub.lastCopyRequest?[kSecAttrAccount as String] as? String == "single-share-v1")
        #expect(stub.lastCopyRequest?[kSecReturnData as String] as? Bool == true)
        #expect(stub.lastCopyRequest?[kSecUseAuthenticationContext as String] as? LAContext === context)
    }

    @Test
    func readRejectsOversizedAndUnreadableRecords() throws {
        let stub = KeychainStub()
        let store = KeychainStore(access: stub)
        let context = LAContext()

        stub.copyStatus = errSecSuccess
        stub.copyData = Data(repeating: 0, count: StorageLimits.maxRecordBytes + 1)
        #expect(throws: AppFailure.self) { try store.read(context: context) }

        stub.copyData = Data("{}".utf8)
        #expect(throws: AppFailure.self) { try store.read(context: context) }
    }

    @Test
    func readMapsKeychainFailures() {
        let cases: [(OSStatus, String)] = [
            (errSecDuplicateItem, "A protected share already exists."),
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
                _ = try KeychainStore(access: stub).read(context: LAContext())
                #expect(Bool(false))
            } catch let error as AppFailure {
                #expect(error.message.hasPrefix(prefix))
            } catch {
                #expect(Bool(false))
            }
        }
    }

    @Test
    func insertProtectsEncodedRecordAndMapsFailures() throws {
        let stub = KeychainStub()
        let store = KeychainStore(access: stub)
        let context = LAContext()
        let record = try makeRecord()

        try store.insert(record, context: context)
        let data = try #require(stub.lastAddRequest?[kSecValueData as String] as? Data)
        let decoded = try JSONDecoder().decode(ShareRecord.self, from: data)
        #expect(decoded.profile == record.profile)
        #expect(decoded.profile.product == .vault)
        #expect(decoded.share == record.share)
        #expect(stub.lastAddRequest?[kSecAttrAccessControl as String] != nil)
        #expect(stub.lastAddRequest?[kSecUseAuthenticationContext as String] as? LAContext === context)

        stub.addStatus = errSecDuplicateItem
        #expect(throws: AppFailure.self) { try store.insert(record, context: context) }

        stub.accessControl = nil
        #expect(throws: AppFailure.self) { try store.insert(record, context: context) }
    }

    @Test
    func replaceUpdatesOnlyValueDataAndMapsFailure() throws {
        let stub = KeychainStub()
        let store = KeychainStore(access: stub)
        let context = LAContext()
        let record = try makeRecord()

        try store.replace(record, context: context)
        let data = try #require(stub.lastUpdateAttributes?[kSecValueData as String] as? Data)
        #expect(try JSONDecoder().decode(ShareRecord.self, from: data).share == record.share)
        #expect(stub.lastUpdateRequest?[kSecUseAuthenticationContext as String] as? LAContext === context)

        stub.updateStatus = errSecAuthFailed
        #expect(throws: AppFailure.self) { try store.replace(record, context: context) }
    }

    @Test
    func deleteTreatsMissingItemAsSuccessAndRejectsOtherFailures() throws {
        let stub = KeychainStub()
        let store = KeychainStore(access: stub)
        let context = LAContext()

        stub.deleteStatus = errSecSuccess
        try store.delete(context: context)
        #expect(stub.lastDeleteRequest?[kSecUseAuthenticationContext as String] as? LAContext === context)

        stub.deleteStatus = errSecItemNotFound
        try store.delete(context: context)

        stub.deleteStatus = errSecAuthFailed
        #expect(throws: AppFailure.self) { try store.delete(context: context) }
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
    func profileStoreRoundTripsAndDeletesProfile() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProfileStore(baseDirectory: root)
        let profile = try ServerProfile(name: "Test", address: origin, product: .openBao)

        #expect(try store.load() == nil)
        try store.save(profile)
        #expect(try store.load() == profile)
        try store.delete()
        #expect(try store.load() == nil)
        try store.delete()
    }

    @Test
    func profileStoreRejectsOversizedFile() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Sealbreak", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(repeating: 0, count: StorageLimits.maxRecordBytes + 1)
            .write(to: folder.appendingPathComponent("profile.json"))

        #expect(throws: AppFailure.self) {
            try ProfileStore(baseDirectory: root).load()
        }
    }

    private func makeRecord() throws -> ShareRecord {
        let profile = try ServerProfile(name: "Test", address: origin, product: .vault)
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
