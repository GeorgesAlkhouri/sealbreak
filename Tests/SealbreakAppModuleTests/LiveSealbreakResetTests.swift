import Foundation
import Security
import Testing
@testable import SealbreakAppModule
@testable import SealbreakCore
@testable import SealbreakInfrastructure

@Suite(.serialized)
@MainActor
struct LiveSealbreakResetTests {
    @Test
    func resetIsDeletionOnlyAndPersistsRecoveryBeforeDeletingShares() throws {
        let fixture = try resetFixture()
        defer { fixture.cleanUp() }
        let catalog = fixture.root.appendingPathComponent("Sealbreak/profiles.json")
        var catalogStatesAtDeletion: [String] = []
        fixture.access.beforeCall = { _ in
            do {
                let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: catalog)) as? [String: Any])
                catalogStatesAtDeletion.append(try #require(json["state"] as? String))
                #expect(throws: AppFailure.self) { try fixture.profiles.loadAll() }
            } catch {
                Issue.record(error)
            }
        }

        try fixture.controller.resetLocalData()

        #expect(catalogStatesAtDeletion == ["resetting"])
        #expect(fixture.access.calls.map(\.operation) == ["delete"])
        let request = try #require(fixture.access.calls.first?.request)
        #expect(request[kSecAttrAccount as String] == nil)
        #expect(request[kSecUseAuthenticationContext as String] == nil)
        #expect(request[kSecAttrSynchronizable as String] as? Bool == false)
        #expect(fixture.factory.created.isEmpty)
        #expect(ResetNetworkTrap.requestCount == 0)
        #expect(!FileManager.default.fileExists(atPath: catalog.path))
        #expect(try fixture.controller.loadLocalSetupState() == .empty)
    }

    @Test
    func failedResetPreparationNeverDeletesShares() throws {
        let fixture = try ControllerFixture()
        defer { fixture.cleanUp() }
        // A file at the injected base directory deterministically prevents preparation.
        try Data("fixture blocks directory creation".utf8).write(to: fixture.root)

        #expect(throws: (any Error).self) { try fixture.controller.resetLocalData() }
        #expect(fixture.access.calls.isEmpty)
        #expect(fixture.factory.created.isEmpty)
    }

    @Test
    func failedShareDeletionPreservesResetRecoveryMarker() throws {
        let fixture = try ControllerFixture(ready: true)
        defer { fixture.cleanUp() }
        fixture.access.status = errSecAuthFailed

        #expect(throws: AppFailure.self) { try fixture.controller.resetLocalData() }

        #expect(fixture.access.calls.map(\.operation) == ["delete"])
        #expect(fixture.factory.created.isEmpty)
        #expect(throws: AppFailure.self) { try fixture.profiles.loadAll() }
        let catalog = fixture.root.appendingPathComponent("Sealbreak/profiles.json")
        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: catalog)) as? [String: Any])
        #expect(json["state"] as? String == "resetting")
        #expect((json["profiles"] as? [Any])?.isEmpty == true)
    }

    @Test
    func resetProfileRemovalFailureDoesNotRepeatKeychainDeletion() throws {
        let fixture = try ControllerFixture(ready: true)
        defer { fixture.cleanUp() }
        let catalog = fixture.root.appendingPathComponent("Sealbreak/profiles.json")
        fixture.access.beforeCall = { _ in
            // Make final removal fail without changing production storage interfaces.
            do {
                try FileManager.default.removeItem(at: catalog)
                try FileManager.default.createDirectory(at: catalog, withIntermediateDirectories: false)
                try Data().write(to: catalog.appendingPathComponent("cannot-remove"))
                try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: catalog.path)
            } catch {
                Issue.record(error)
            }
        }
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: catalog.path) }

        #expect(throws: (any Error).self) { try fixture.controller.resetLocalData() }
        #expect(fixture.access.calls.map(\.operation) == ["delete"])
        #expect(fixture.factory.created.isEmpty)
    }
    private func resetFixture() throws -> ControllerFixture {
        ResetNetworkTrap.requestCount = 0
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ResetNetworkTrap.self]
        return try ControllerFixture(ready: true, client: SealServerClient(configuration: configuration))
    }
}

private final class ResetNetworkTrap: URLProtocol, @unchecked Sendable {
    static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requestCount += 1
        client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
    }
    override func stopLoading() {}
}
