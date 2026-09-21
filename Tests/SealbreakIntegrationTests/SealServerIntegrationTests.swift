import Foundation
import Testing
@testable import SealbreakCore

@Suite(
    .serialized,
    .enabled(
        if: IntegrationEnvironment.isConfigured,
        "Requires the ephemeral OpenBao or Vault instance created by the CI integration job."
    )
)
struct SealServerIntegrationTests {
    @Test
    func detectsProductThenCompletesRealShamirUnsealFlow() async throws {
        let environment = try IntegrationEnvironment()
        let profile = try ServerProfile(
            id: UUID(),
            name: "Integration Test",
            address: environment.serverURL
        )
        let client = SealServerClient()

        let fixtureStatus = try await client.status(profile)
        #expect(fixtureStatus.initialized)
        #expect(!fixtureStatus.sealed)

        let detectedProduct = try await client.detectProduct(profile)
        #expect(detectedProduct == environment.expectedProduct)

        try await environment.sealFixture()

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
    }
}

private struct IntegrationEnvironment {
    private static let serverURLKey = "SEALBREAK_INTEGRATION_SERVER_URL"
    private static let productKey = "SEALBREAK_INTEGRATION_SERVER_PRODUCT"
    private static let firstShareKey = "SEALBREAK_INTEGRATION_SHARE_1"
    private static let secondShareKey = "SEALBREAK_INTEGRATION_SHARE_2"
    private static let rootTokenKey = "SEALBREAK_INTEGRATION_ROOT_TOKEN"

    static var isConfigured: Bool {
        let environment = ProcessInfo.processInfo.environment
        return [
            serverURLKey,
            productKey,
            firstShareKey,
            secondShareKey,
            rootTokenKey
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
    private let rootToken: String

    init(environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        serverURL = try Self.requiredValue(for: Self.serverURLKey, in: environment)
        firstShare = try Self.requiredValue(for: Self.firstShareKey, in: environment)
        secondShare = try Self.requiredValue(for: Self.secondShareKey, in: environment)
        rootToken = try Self.requiredValue(for: Self.rootTokenKey, in: environment)

        let product = try Self.requiredValue(for: Self.productKey, in: environment)
        switch product {
        case "openbao":
            expectedProduct = .openBao
        case "vault":
            expectedProduct = .vault
        default:
            throw IntegrationEnvironmentError.unsupportedProduct(product)
        }
    }

    func sealFixture() async throws {
        guard let baseURL = URL(string: serverURL) else {
            throw IntegrationEnvironmentError.invalidServerURL
        }

        var request = URLRequest(
            url: baseURL
                .appendingPathComponent("v1")
                .appendingPathComponent("sys")
                .appendingPathComponent("seal")
        )
        request.httpMethod = "POST"
        request.setValue(rootToken, forHTTPHeaderField: "X-Vault-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200...299).contains(response.statusCode) else {
            throw IntegrationEnvironmentError.fixtureSealFailed
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
    case invalidServerURL
    case fixtureSealFailed
}
