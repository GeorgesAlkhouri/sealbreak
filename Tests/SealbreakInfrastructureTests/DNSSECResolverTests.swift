import Dispatch
import Foundation
import Testing
import dnssd
@testable import SealbreakCore
@testable import SealbreakInfrastructure

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
    func liveResolverFailsClosedForOverlongDNSLabel() async {
        // A DNS label can contain at most 63 bytes.
        let invalidHost = String(repeating: "a", count: 64) + ".invalid"

        #expect(await DNSSECResolver.live.status(for: invalidHost) == .unavailable)
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

    @Test
    func missingValidationCallbackTimesOutAndReleasesService() async {
        let probe = DNSSECServiceProbe()
        let resolver = DNSSECResolver.makeLive(timeout: 0.02, service: probe.client)

        #expect(await resolver.status(for: "bao.example.com") == .unavailable)
        #expect(probe.deallocationCount == 1)
    }

    @Test(arguments: [
        (kDNSServiceFlagsSecure, DNSSECStatus.secure),
        (kDNSServiceFlagsInsecure, DNSSECStatus.insecure),
        (kDNSServiceFlagsBogus, DNSSECStatus.bogus),
        (kDNSServiceFlagsIndeterminate, DNSSECStatus.indeterminate)
    ])
    func validationResultCompletesAndReleasesService(
        flags: DNSServiceFlags,
        expected: DNSSECStatus
    ) async {
        let probe = DNSSECServiceProbe()
        let resolver = DNSSECResolver.makeLive(timeout: 5, service: probe.client)
        let task = Task { await resolver.status(for: "bao.example.com") }
        await probe.waitForScheduling()

        // An address may arrive before its separate DNSSEC validation result.
        await probe.reply(flags: kDNSServiceFlagsAdd)
        #expect(probe.deallocationCount == 0)
        await probe.reply(flags: flags | kDNSServiceFlagsAdd)

        #expect(await task.value == expected)
        #expect(probe.deallocationCount == 1)
    }

    @Test
    func cancellationReleasesPendingServiceWithoutWaitingForTimeout() async {
        let probe = DNSSECServiceProbe()
        let resolver = DNSSECResolver.makeLive(timeout: 60, service: probe.client)
        let task = Task { await resolver.status(for: "bao.example.com") }
        await probe.waitForScheduling()

        task.cancel()

        #expect(await task.value == .unavailable)
        #expect(probe.deallocationCount == 1)
    }

    @Test
    func cancellationBeforeStartingDoesNotCreateService() async {
        let probe = DNSSECServiceProbe()
        let resolver = DNSSECResolver.makeLive(timeout: 60, service: probe.client)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await resolver.status(for: "bao.example.com")
        }

        #expect(await task.value == .unavailable)
        #expect(probe.startCount == 0)
        #expect(probe.deallocationCount == 0)
    }

    @Test(arguments: 0..<10)
    func cancellationRacingWithCallbackCompletesOnce(_ iteration: Int) async {
        let probe = DNSSECServiceProbe()
        let resolver = DNSSECResolver.makeLive(timeout: 5, service: probe.client)
        let task = Task { await resolver.status(for: "bao.example.com") }
        await probe.waitForScheduling()

        async let reply: Void = probe.reply(flags: kDNSServiceFlagsBogus | kDNSServiceFlagsAdd)
        task.cancel()
        await reply

        let result = await task.value
        #expect(result == .bogus || result == .unavailable)
        #expect(probe.deallocationCount == 1)
    }

    @Test
    func serviceErrorsReturnUnavailableAndReleaseAllocatedService() async {
        let startFailure = DNSSECServiceProbe(startError: DNSServiceErrorType(kDNSServiceErr_BadParam))
        #expect(await DNSSECResolver.makeLive(service: startFailure.client)
            .status(for: "bao.example.com") == .unavailable)
        #expect(startFailure.deallocationCount == 0)

        let scheduleFailure = DNSSECServiceProbe(scheduleError: DNSServiceErrorType(kDNSServiceErr_NoMemory))
        #expect(await DNSSECResolver.makeLive(service: scheduleFailure.client)
            .status(for: "bao.example.com") == .unavailable)
        #expect(scheduleFailure.deallocationCount == 1)

        let callbackFailure = DNSSECServiceProbe()
        let resolver = DNSSECResolver.makeLive(timeout: 5, service: callbackFailure.client)
        let task = Task { await resolver.status(for: "bao.example.com") }
        await callbackFailure.waitForScheduling()
        await callbackFailure.reply(flags: 0, error: DNSServiceErrorType(kDNSServiceErr_ServiceNotRunning))
        #expect(await task.value == .unavailable)
        #expect(callbackFailure.deallocationCount == 1)
    }
}

private final class DNSSECServiceProbe: @unchecked Sendable {
    private struct Query {
        let callback: DNSServiceGetAddrInfoReply
        let context: UnsafeMutableRawPointer
    }

    private let lock = NSLock()
    private let scheduled = AsyncStream<Void>.makeStream()
    private let startError: DNSServiceErrorType
    private let scheduleError: DNSServiceErrorType
    private var query: Query?
    private var queue: DispatchQueue?
    private var starts = 0
    private var deallocations = 0

    init(
        startError: DNSServiceErrorType = DNSServiceErrorType(kDNSServiceErr_NoError),
        scheduleError: DNSServiceErrorType = DNSServiceErrorType(kDNSServiceErr_NoError)
    ) {
        self.startError = startError
        self.scheduleError = scheduleError
    }

    var startCount: Int { lock.withLock { starts } }
    var deallocationCount: Int { lock.withLock { deallocations } }

    var client: DNSSECService {
        DNSSECService(
            start: { reference, _, callback, context in
                self.lock.withLock {
                    self.starts += 1
                    if self.startError == kDNSServiceErr_NoError {
                        reference.pointee = OpaquePointer(bitPattern: 1)
                        self.query = Query(callback: callback, context: context)
                    }
                }
                return self.startError
            },
            schedule: { _, queue in
                self.lock.withLock { self.queue = queue }
                self.scheduled.continuation.yield(())
                self.scheduled.continuation.finish()
                return self.scheduleError
            },
            deallocate: { _ in
                self.lock.withLock {
                    if let queue = self.queue {
                        dispatchPrecondition(condition: .onQueue(queue))
                    }
                    self.query = nil
                    self.deallocations += 1
                }
            }
        )
    }

    func waitForScheduling() async {
        for await _ in scheduled.stream { return }
    }

    func reply(
        flags: DNSServiceFlags,
        error: DNSServiceErrorType = DNSServiceErrorType(kDNSServiceErr_NoError)
    ) async {
        guard let queue = lock.withLock({ queue }) else {
            Issue.record("DNS query must be scheduled before delivering a callback")
            return
        }
        await withCheckedContinuation { continuation in
            queue.async {
                if let query = self.lock.withLock({ self.query }) {
                    query.callback(nil, flags, 0, error, nil, nil, 0, query.context)
                }
                continuation.resume()
            }
        }
    }
}

private actor HostRecorder {
    private(set) var host: String?

    func record(_ host: String) {
        self.host = host
    }
}
