#if os(iOS)
import Foundation
import Testing
@testable import SealbreakCore
@testable import SealbreakInfrastructure

struct ProfileStorePlatformTests {
    #if targetEnvironment(simulator)
    private static let isSimulator = true
    #else
    private static let isSimulator = false
    #endif

    @Test
    func atomicLifecycleWritesKeepParentExcludedFromBackup() throws {
        try exerciseLifecycle(checkFile: { _ in }, checkDirectory: { directory in
            let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
            #expect(values.isExcludedFromBackup == true)
        })
    }

    @Test(.disabled(if: Self.isSimulator, "The iOS simulator omits file-protection attributes; physical iOS is required."))
    func atomicLifecycleWritesKeepCompleteFileAndDirectoryProtection() throws {
        try exerciseLifecycle(checkFile: expectCompleteProtection, checkDirectory: expectCompleteProtection)
    }

    private func exerciseLifecycle(
        checkFile: (URL) throws -> Void,
        checkDirectory: (URL) throws -> Void
    ) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SealbreakProtectionTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProfileStore(baseDirectory: root)
        let profile = try ServerProfile(id: UUID(), name: "Synthetic", address: "https://bao.example.com", product: .openBao)
        let directory = root.appendingPathComponent("Sealbreak", isDirectory: true)
        let file = directory.appendingPathComponent("profiles.json")

        try store.begin(profile)
        try checkFile(file)
        try checkDirectory(directory)
        #expect(try store.loadAll().map(\.state) == [.creating])
        try store.commit(id: profile.id)
        try checkFile(file)
        try checkDirectory(directory)
        #expect(try store.loadAll().map(\.state) == [.ready])
        try store.beginRemoval(id: profile.id)
        try checkFile(file)
        try checkDirectory(directory)
        #expect(try store.loadAll().map(\.state) == [.removing])
        try store.delete(id: profile.id)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        try checkDirectory(directory)

        try store.prepareForReset()
        try checkFile(file)
        try checkDirectory(directory)
        try store.reset()
        #expect(!FileManager.default.fileExists(atPath: file.path))
        try checkDirectory(directory)
    }

    private func expectCompleteProtection(_ url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let protection = try #require(attributes[.protectionKey] as? String)
        #expect(protection == FileProtectionType.complete.rawValue)
    }
}
#endif
