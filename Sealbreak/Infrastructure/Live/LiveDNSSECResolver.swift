import dnssd

extension DNSSECResolver {
    static let live = Self { host in
        await Task.detached(priority: .userInitiated) {
            LiveDNSSECResolver.resolve(host: host)
        }.value
    }
}

private enum LiveDNSSECResolver {
    static func resolve(host: String) -> DNSSECStatus {
        var service: DNSServiceRef?
        let result = ResultBox()
        let context = Unmanaged.passUnretained(result).toOpaque()
        let flags = kDNSServiceFlagsValidate | kDNSServiceFlagsTimeout
        let protocols = DNSServiceProtocol(kDNSServiceProtocol_IPv4 | kDNSServiceProtocol_IPv6)

        let startError = host.withCString { hostname in
            DNSServiceGetAddrInfo(
                &service,
                flags,
                0,
                protocols,
                hostname,
                dnssecGetAddrInfoReply,
                context
            )
        }

        guard startError == kDNSServiceErr_NoError,
              let service else {
            return .unavailable
        }
        defer {
            DNSServiceRefDeallocate(service)
        }

        while result.status == nil {
            let processError = DNSServiceProcessResult(service)
            guard processError == kDNSServiceErr_NoError else {
                return .unavailable
            }
        }

        return result.status ?? .unavailable
    }
}

private final class ResultBox {
    var status: DNSSECStatus?
}

private func dnssecGetAddrInfoReply(
    _: DNSServiceRef?,
    flags: DNSServiceFlags,
    _: UInt32,
    errorCode: DNSServiceErrorType,
    _: UnsafePointer<CChar>?,
    _: UnsafePointer<sockaddr>?,
    _: UInt32,
    context: UnsafeMutableRawPointer?
) {
    guard let context else {
        return
    }

    let result = Unmanaged<ResultBox>
        .fromOpaque(context)
        .takeUnretainedValue()

    guard errorCode == kDNSServiceErr_NoError else {
        result.status = .unavailable
        return
    }

    result.status = dnssecStatus(from: flags)
}

private func dnssecStatus(from flags: DNSServiceFlags) -> DNSSECStatus? {
    guard (flags & kDNSServiceFlagsValidate) == kDNSServiceFlagsValidate,
          (flags & kDNSServiceFlagsAdd) == kDNSServiceFlagsAdd else {
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
