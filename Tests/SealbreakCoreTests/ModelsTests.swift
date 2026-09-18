import Foundation
import Testing
@testable import SealbreakCore

struct ModelsTests {
    private let origin = "https://bao.example.com"
    // Synthetic format-only input. Never use a real Shamir share in a test.
    private let syntheticShare = String(repeating: "a", count: 64)

    @Test
    func appFailureExposesLocalizedMessage() {
        let error = AppFailure("test failure")
        #expect(error.errorDescription == "test failure")
    }

    @Test(arguments: ["Server", "Freiburg – Süd", "東京", String(repeating: "🔒", count: 40)])
    func ordinaryNamesRoundTrip(name: String) throws {
        let profile = try ServerProfile(name: name, address: origin, product: .vault)
        let record = try ShareRecord(profile: profile, input: syntheticShare)
        let encoded = try JSONEncoder().encode(record)
        try StorageLimits.validateEncodedSize(encoded)
        let decoded = try JSONDecoder().decode(ShareRecord.self, from: encoded).validated()
        #expect(decoded.profile == profile)
        #expect(decoded.share == syntheticShare)
    }

    @Test
    func legacyProfileWithoutProductDefaultsToGeneric() throws {
        let json = #"{"name":"Test","origin":"https://bao.example.com"}"#
        let profile = try JSONDecoder()
            .decode(ServerProfile.self, from: Data(json.utf8))
            .validated()

        #expect(profile.product == .generic)
    }

    @Test
    func c01RejectsOversizedGrapheme() {
        let name = "a" + String(repeating: "\u{0301}", count: 3_000)
        #expect(name.count == 1)
        #expect(name.utf8.count == 6_001)
        #expect(throws: AppFailure.self) { try ServerProfile(name: name, address: origin) }
    }

    @Test
    func c01CountsEncodedOverhead() throws {
        let name = "é" + String(repeating: "\u{0301}", count: 2_047)
        #expect(name.utf8.count == StorageLimits.maxRecordBytes)
        let profile = try ServerProfile(name: name, address: origin)
        let record = try ShareRecord(profile: profile, input: syntheticShare)
        for data in [try JSONEncoder().encode(profile), try JSONEncoder().encode(record)] {
            #expect(data.count > StorageLimits.maxRecordBytes)
            #expect(throws: AppFailure.self) { try StorageLimits.validateEncodedSize(data) }
        }
    }

    @Test(arguments: [0, 4_095, 4_096])
    func acceptsStorageBoundary(size: Int) throws {
        try StorageLimits.validateEncodedSize(Data(repeating: 0, count: size))
    }

    @Test(arguments: [4_097, 8_192])
    func rejectsStorageOverflow(size: Int) {
        #expect(throws: AppFailure.self) {
            try StorageLimits.validateEncodedSize(Data(repeating: 0, count: size))
        }
    }

    @Test(arguments: ["", "a\nb", String(repeating: "a", count: 41)])
    func rejectsInvalidName(name: String) {
        #expect(throws: AppFailure.self) { try ServerProfile(name: name, address: origin) }
    }

    @Test(arguments: [
        "http://bao.example.com", "https://user:password@bao.example.com",
        "https://bao.example.com/v1", "https://bao.example.com?q=1",
        "https://bao.example.com#fragment", "https://bäo.example.com",
        "https://bao.example.com:0", "https://bao.example.com:65536",
        "https://bao%2eexample.com", "https://bao.example.com\\evil"
    ])
    func rejectsUnsafeOrigin(address: String) {
        #expect(throws: AppFailure.self) { try ServerProfile(name: "Test", address: address) }
    }

    @Test
    func canonicalizesOriginAndBuildsEndpoint() throws {
        let profile = try ServerProfile(name: " Test ", address: " https://BAO.example.com:443/ ")
        #expect(profile.name == "Test")
        #expect(profile.origin == origin)
        #expect(try profile.endpoint("unseal").absoluteString == "\(origin)/v1/sys/unseal")
        let custom = try ServerProfile(name: "Test", address: "\(origin):8200")
        #expect(custom.origin == "\(origin):8200")
    }

    @Test
    func decodedProfileStillNeedsValidation() throws {
        let unsafeJSON = #"{"name":"Test","origin":"http://bao.example.com"}"#
        let unsafe = try JSONDecoder().decode(ServerProfile.self, from: Data(unsafeJSON.utf8))
        #expect(throws: AppFailure.self) { try unsafe.validated() }

        let nonCanonicalJSON = #"{"name":"Test","origin":"https://BAO.example.com:443/"}"#
        let nonCanonical = try JSONDecoder().decode(ServerProfile.self, from: Data(nonCanonicalJSON.utf8))
        #expect(throws: AppFailure.self) { try nonCanonical.validated() }
    }

    @Test(arguments: ["", "short", String(repeating: "?", count: 64), String(repeating: "a", count: 1_025)])
    func rejectsInvalidShare(input: String) {
        #expect(throws: AppFailure.self) { try ShareRecord.validateShare(input) }
    }

    @Test
    func trimsShareAndRejectsUnknownRecordVersion() throws {
        let profile = try ServerProfile(name: "Test", address: origin)
        let record = try ShareRecord(profile: profile, input: " \(syntheticShare)\n")
        #expect(record.share == syntheticShare)
        let json = """
        {"version":2,"profile":{"name":"Test","origin":"\(origin)"},"share":"\(syntheticShare)"}
        """
        let decoded = try JSONDecoder().decode(ShareRecord.self, from: Data(json.utf8))
        #expect(throws: AppFailure.self) { try decoded.validated() }
    }

    @Test
    func quorumProgressDoesNotMeanUnsealed() throws {
        let json = #"{"type":"shamir","initialized":true,"sealed":true,"t":3,"n":5,"progress":1}"#
        let status = try JSONDecoder().decode(SealStatus.self, from: Data(json.utf8)).validated()
        #expect(status.supportsUnseal)
        #expect(status.sealed)
        #expect(status.progress == 1)
    }

    @Test(arguments: ["transit", "awskms"])
    func doesNotOfferShamirUnsealForOtherTypes(type: String) throws {
        let status = SealStatus(type: type, initialized: true, sealed: true,
                               t: 0, n: 0, progress: 0, migration: false, recoverySeal: true)
        #expect(try !status.validated().supportsUnseal)
    }

    @Test
    func rejectsInconsistentStatus() {
        let status = SealStatus(type: "shamir", initialized: true, sealed: true,
                               t: 3, n: 2, progress: 0, migration: false, recoverySeal: false)
        #expect(throws: AppFailure.self) { try status.validated() }
    }
}
