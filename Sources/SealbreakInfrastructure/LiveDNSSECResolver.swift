import Dispatch
import Foundation
import SealbreakCore
import dnssd

extension DNSSECResolver {
  package static let live = makeLive()

  static func makeLive(
    timeout: TimeInterval = 2,
    service: DNSSECService = .live
  ) -> Self {
    Self { host in
      await LiveDNSSECQuery(timeout: timeout, client: service).resolve(host: host)
    }
  }
}

// Keep the C service boundary injectable so missing callbacks and cancellation
// can be exercised without relying on the current network's DNSSEC support.
struct DNSSECService: Sendable {
  var start:
    @Sendable (
      UnsafeMutablePointer<DNSServiceRef?>,
      String,
      DNSServiceGetAddrInfoReply,
      UnsafeMutableRawPointer
    ) -> DNSServiceErrorType
  var schedule: @Sendable (DNSServiceRef, DispatchQueue) -> DNSServiceErrorType
  var deallocate: @Sendable (DNSServiceRef) -> Void

  static let live = Self(
    start: { service, host, callback, context in
      host.withCString { hostname in
        DNSServiceGetAddrInfo(
          service,
          kDNSServiceFlagsValidate | kDNSServiceFlagsTimeout,
          0,
          DNSServiceProtocol(kDNSServiceProtocol_IPv4 | kDNSServiceProtocol_IPv6),
          hostname,
          callback,
          context
        )
      }
    },
    schedule: { DNSServiceSetDispatchQueue($0, $1) },
    deallocate: { DNSServiceRefDeallocate($0) }
  )
}

// All mutable state and C service access are confined to queue. The async call
// retains this object until its continuation completes, including cancellation.
private final class LiveDNSSECQuery: @unchecked Sendable {
  private let queue = DispatchQueue(label: "app.sealbreak.dnssec")
  private let timeout: TimeInterval
  private let client: DNSSECService
  private var service: DNSServiceRef?
  private var timer: DispatchSourceTimer?
  private var continuation: CheckedContinuation<DNSSECStatus, Never>?
  private var isFinished = false

  init(timeout: TimeInterval, client: DNSSECService) {
    self.timeout = timeout
    self.client = client
  }

  func resolve(host: String) async -> DNSSECStatus {
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        queue.async {
          self.start(host: host, continuation: continuation)
        }
      }
    } onCancel: {
      self.queue.async {
        self.finish(.unavailable)
      }
    }
  }

  private func start(host: String, continuation: CheckedContinuation<DNSSECStatus, Never>) {
    guard !isFinished else {
      continuation.resume(returning: .unavailable)
      return
    }
    self.continuation = continuation

    let startError = client.start(
      &service,
      host,
      dnssecGetAddrInfoReply,
      Unmanaged.passUnretained(self).toOpaque()
    )
    guard startError == kDNSServiceErr_NoError,
      let service
    else {
      finish(.unavailable)
      return
    }
    guard client.schedule(service, queue) == kDNSServiceErr_NoError else {
      finish(.unavailable)
      return
    }

    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + timeout)
    timer.setEventHandler { [weak self] in
      self?.finish(.unavailable)
    }
    self.timer = timer
    timer.resume()
  }

  func receive(flags: DNSServiceFlags, errorCode: DNSServiceErrorType) {
    dispatchPrecondition(condition: .onQueue(queue))
    guard errorCode == kDNSServiceErr_NoError else {
      finish(.unavailable)
      return
    }
    if let status = dnssecStatus(from: flags) {
      finish(status)
    }
  }

  private func finish(_ status: DNSSECStatus) {
    guard !isFinished else { return }
    isFinished = true
    timer?.cancel()
    timer = nil
    if let service {
      // dnssd requires deallocation on the callback queue. This also
      // prevents further callbacks from using the unretained context.
      client.deallocate(service)
      self.service = nil
    }
    let continuation = self.continuation
    self.continuation = nil
    continuation?.resume(returning: status)
  }
}

private let dnssecGetAddrInfoReply: DNSServiceGetAddrInfoReply = {
  _, flags, _, errorCode, _, _, _, context in
  guard let context else {
    return
  }

  let query = Unmanaged<LiveDNSSECQuery>
    .fromOpaque(context)
    .takeUnretainedValue()
  query.receive(flags: flags, errorCode: errorCode)
}

private func dnssecStatus(from flags: DNSServiceFlags) -> DNSSECStatus? {
  guard (flags & kDNSServiceFlagsValidate) == kDNSServiceFlagsValidate,
    (flags & kDNSServiceFlagsAdd) == kDNSServiceFlagsAdd
  else {
    return nil
  }

  if (flags & kDNSServiceFlagsSecure) == kDNSServiceFlagsSecure {
    return .secure
  }
  if (flags & kDNSServiceFlagsInsecure) == kDNSServiceFlagsInsecure {
    return .insecure
  }
  if (flags & kDNSServiceFlagsBogus) == kDNSServiceFlagsBogus {
    return .bogus
  }
  if (flags & kDNSServiceFlagsIndeterminate) == kDNSServiceFlagsIndeterminate {
    return .indeterminate
  }
  return .unavailable
}
