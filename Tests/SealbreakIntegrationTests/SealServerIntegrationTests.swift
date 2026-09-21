import Foundation
import Testing
@testable import Sealbreak

@Suite(
    .serialized,
    .enabled(
        if: IntegrationFixture.isConfigured,
        "Requires the ephemeral OpenBao or Vault instance created by the CI integration job."
    )
)
struct SealServerIntegrationTests {
    @Test
    func completesRealShamirUnsealFlowAndDetectsProduct() async throws {
        let profile = try ServerProfile(
            id: UUID(),
            name: "Integration Test",
            address: IntegrationFixture.serverURL
        )
        let client = SealServerClient()

        let initialStatus = try await client.status(profile)
        #expect(initialStatus.initialized)
        #expect(initialStatus.sealed)
        #expect(initialStatus.type == "shamir")
        #expect(initialStatus.n == 3)
        #expect(initialStatus.t == 2)
        #expect(initialStatus.progress == 0)
        #expect(initialStatus.supportsUnseal)

        try await client.submit(
            ShareRecord(profile: profile, input: IntegrationFixture.firstShare)
        )

        let statusAfterFirstShare = try await client.status(profile)
        #expect(statusAfterFirstShare.sealed)
        #expect(statusAfterFirstShare.progress == 1)

        try await client.submit(
            ShareRecord(profile: profile, input: IntegrationFixture.secondShare)
        )

        let finalStatus = try await client.status(profile)
        #expect(finalStatus.initialized)
        #expect(!finalStatus.sealed)
        #expect(finalStatus.type == "shamir")
        #expect(finalStatus.progress == 0)

        let detectedProduct = try await client.detectProduct(profile)
        #expect(detectedProduct == IntegrationFixture.expectedProduct)
    }
}
