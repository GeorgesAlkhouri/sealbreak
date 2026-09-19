import Foundation
import Testing
@testable import SealbreakCore

struct SealbreakClientTests {
    private struct ForeignError: Error {}

    @Test
    func unimplementedDependenciesFailClosed() async throws {
        #if !canImport(UIKit)
        let liveClient = SealbreakClient.liveValue
        #expect(
            await failureMessage { try await liveClient.loadProfile() }
                == "Unimplemented profile load dependency."
        )
        #endif

        let dependency = SealbreakClient.unimplemented
        let profile = try ServerProfile(name: "Server", address: "https://server.example.com")
        let record = try ShareRecord(profile: profile, input: String(repeating: "a", count: 64))

        #expect(await failureMessage { try await dependency.loadProfile() } != nil)
        #expect(await failureMessage { try await dependency.saveProfile(profile) } != nil)
        #expect(await failureMessage { try await dependency.deleteProfile() } != nil)
        #expect(await failureMessage { try await dependency.detectProduct(profile) } != nil)
        #expect(await failureMessage { try await dependency.status(profile) } != nil)
        #expect(await failureMessage { try await dependency.submit(record) } != nil)
        #expect(await failureMessage { try await dependency.readShare("Test") } != nil)
        #expect(await failureMessage { try await dependency.insertShare(record, "Test") } != nil)
        #expect(await failureMessage { try await dependency.replaceShare(profile, record, "Test") } != nil)
        #expect(await failureMessage { try await dependency.deleteShare("Test") } != nil)
        #expect(await failureMessage { try await dependency.requireForeground() } != nil)
        #expect(await failureMessage { try await dependency.waitForForeground() } != nil)
        await dependency.cancelSensitiveOperation()
    }

    @Test
    func unknownErrorsAreNormalizedWithoutSensitiveDetails() {
        let failure = normalizedAppFailure(ForeignError())

        #expect(failure.message == "Operation failed. No sensitive diagnostic data was recorded.")
    }

    private func failureMessage<Value>(
        _ operation: () async throws -> Value
    ) async -> String? {
        do {
            _ = try await operation()
            return nil
        } catch let failure as AppFailure {
            return failure.message
        } catch {
            return nil
        }
    }
}
