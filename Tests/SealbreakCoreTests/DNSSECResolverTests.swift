import Testing
@testable import SealbreakCore

struct DNSSECResolverTests {
    @Test
    func literalAndLocalHostsAreNotApplicable() async {
        let resolver = DNSSECResolver { _ in .secure }

        #expect(await resolver.status(for: "127.0.0.1") == .notApplicable)
        #expect(await resolver.status(for: "::1") == .notApplicable)
        #expect(await resolver.status(for: "[::1]") == .notApplicable)
        #expect(await resolver.status(for: "SERVER.LOCAL") == .notApplicable)
    }

    @Test
    func emptyHostIsUnavailable() async {
        let resolver = DNSSECResolver { _ in .secure }

        #expect(await resolver.status(for: "") == .unavailable)
    }

    @Test
    func normalHostIsNormalizedAndForwardedToResolver() async {
        let recorder = HostRecorder()
        let resolver = DNSSECResolver { host in
            await recorder.record(host)
            return .indeterminate
        }

        #expect(await resolver.status(for: "Bao.Example.COM") == .indeterminate)
        #expect(await recorder.host == "bao.example.com")
    }
}

private actor HostRecorder {
    private(set) var host: String?

    func record(_ host: String) {
        self.host = host
    }
}
