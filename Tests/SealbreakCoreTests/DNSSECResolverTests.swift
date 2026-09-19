import Testing
@testable import SealbreakCore

struct DNSSECResolverTests {
    private let resolver = DNSSECResolver()

    @Test
    func literalAndLocalHostsAreNotApplicable() async {
        #expect(await resolver.status(for: "127.0.0.1") == .notApplicable)
        #expect(await resolver.status(for: "::1") == .notApplicable)
        #expect(await resolver.status(for: "[::1]") == .notApplicable)
        #expect(await resolver.status(for: "server.local") == .notApplicable)
    }

    @Test
    func emptyHostIsUnavailable() async {
        #expect(await resolver.status(for: "") == .unavailable)
    }
}
