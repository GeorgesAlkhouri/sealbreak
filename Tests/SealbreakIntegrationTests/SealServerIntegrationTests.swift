import Foundation
import Testing

@Suite(
    .serialized,
    .enabled(
        if: IntegrationEnvironment.isConfigured,
        "Requires the ephemeral OpenBao or Vault instance created by the CI integration job."
    )
)
struct SealServerIntegrationTests {
    @Test
    func completesRealShamirUnsealFlowAndDetectsProduct() async throws {
        let environment = try IntegrationEnvironment()
        let profile = try ServerProfile(
            id: UUID(),
            name: "Integration Test",
            address: environment.serverURL
        )
        let client = SealServerClient()

        let healthURL = try #require(URL(string: "\(environment.serverURL)/v1/sys/health"))
        let (_, healthResponse) = try await URLSession.shared.data(from: healthURL)
        let healthHTTPResponse = try #require(healthResponse as? HTTPURLResponse)
        #expect(healthHTTPResponse.statusCode == 503)

        let initialStatus = try await client.status(profile)
        #expect(initialStatus.initialized)
        #expect(initialStatus.sealed)
        #expect(initialStatus.type == "shamir")
        #expect(initialStatus.n == 3)
        #expect(initialStatus.t == 2)
        #expect(initialStatus.progress == 0)
        #expect(initialStatus.supportsUnseal)

        try await client.submit(
            ShareRecord(profile: profile, input: environment.firstShare)
        )

        let statusAfterFirstShare = try await client.status(profile)
        #expect(statusAfterFirstShare.sealed)
        #expect(statusAfterFirstShare.progress == 1)

        try await client.submit(
            ShareRecord(profile: profile, input: environment.secondShare)
        )

        let finalStatus = try await client.status(profile)
        #expect(finalStatus.initialized)
        #expect(!finalStatus.sealed)
        #expect(finalStatus.type == "shamir")
        #expect(finalStatus.progress == 0)

        let detectedProduct = try await client.detectProduct(profile)
        #expect(detectedProduct == environment.expectedProduct)
    }
}

private struct IntegrationEnvironment {
    private static let serverURLKey = "SEALBREAK_INTEGRATION_SERVER_URL"
    private static let serverProductKey = "SEALBREAK_INTEGRATION_SERVER_PRODUCT"
    private static let firstShareKey = "SEALBREAK_INTEGRATION_SHARE_1"
    private static let secondShareKey = "SEALBREAK_INTEGRATION_SHARE_2"

    static var isConfigured: Bool {
        let environment = ProcessInfo.processInfo.environment
        return [
            serverURLKey,
            serverProductKey,
            firstShareKey,
            secondShareKey
        ].allSatisfy { key in
            guard let value = environment[key] else {
                return false
            }
            return !value.isEmpty
        }
    }

    let serverURL: String
    let expectedProduct: ServerProduct
    let firstShare: String
    let secondShare: String

    init(environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        serverURL = try Self.requiredValue(for: Self.serverURLKey, in: environment)
        firstShare = try Self.requiredValue(for: Self.firstShareKey, in: environment)
        secondShare = try Self.requiredValue(for: Self.secondShareKey, in: environment)

        let product = try Self.requiredValue(for: Self.serverProductKey, in: environment)
        switch product {
        case "openbao":
            expectedProduct = .openBao
        case "vault":
            expectedProduct = .vault
        default:
            throw IntegrationEnvironmentError.unsupportedProduct(product)
        }
    }

    private static func requiredValue(
        for key: String,
        in environment: [String: String]
    ) throws -> String {
        guard let value = environment[key], !value.isEmpty else {
            throw IntegrationEnvironmentError.missingValue(key)
        }
        return value
    }
}

private enum IntegrationEnvironmentError: Error {
    case missingValue(String)
    case unsupportedProduct(String)
}
