import Foundation
import Testing
@testable import SealbreakCore

struct SealbreakClientTests {
    private struct ForeignError: Error {}

    @Test
    func unimplementedDependenciesFailClosed() async throws {
        let dependency = SealbreakClient.testValue
        let profile = try ServerProfile(name: "Server", address: "https://server.example.com")
        let record = try ShareRecord(profile: profile, input: String(repeating: "a", count: 64))

        #expect(
            await failureMessage { try await dependency.loadProfile() }
                == "Unimplemented profile load dependency."
        )
        #expect(
            await failureMessage { try await dependency.saveProfile(profile) }
                == "Unimplemented profile save dependency."
        )
        #expect(
            await failureMessage { try await dependency.deleteProfile(profile.id) }
                == "Unimplemented profile delete dependency."
        )
        #expect(
            await failureMessage { try await dependency.detectProduct(profile) }
                == "Unimplemented server-product detection dependency."
        )
        #expect(
            await failureMessage { try await dependency.dnssecStatus("server.example.com") }
                == "Unimplemented DNSSEC status dependency."
        )
        #expect(
            await failureMessage { try await dependency.status(profile) }
                == "Unimplemented seal-status dependency."
        )
        #expect(
            await failureMessage { try await dependency.submit(record) }
                == "Unimplemented share submission dependency."
        )
        #expect(
            await failureMessage { try await dependency.readShare(profile.id, "Test") }
                == "Unimplemented protected-share dependency."
        )
        #expect(
            await failureMessage { try await dependency.insertShare(record, "Test") }
                == "Unimplemented protected-share dependency."
        )
        #expect(
            await failureMessage { try await dependency.replaceShare(profile, record, "Test") }
                == "Unimplemented protected-share dependency."
        )
        #expect(
            await failureMessage { try await dependency.deleteShare(profile.id, "Test") }
                == "Unimplemented protected-share dependency."
        )
        #expect(
            await failureMessage { try await dependency.requireForeground() }
                == "Unimplemented foreground dependency."
        )
        #expect(
            await failureMessage { try await dependency.waitForForeground() }
                == "Unimplemented foreground dependency."
        )
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
