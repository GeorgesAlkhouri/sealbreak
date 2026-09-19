import Foundation
import Security
import dnssd

enum DNSSECStatus: Equatable, Sendable {
    case secure
    case insecure
    case bogus
    case indeterminate
    case notApplicable
    case unavailable
}

private final class DNSSECResultBox {
    var status: DNSSECStatus?
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

    let result = Unmanaged<DNSSECResultBox>
        .fromOpaque(context)
        .takeUnretainedValue()

    guard errorCode == kDNSServiceErr_NoError else {
        result.status = .unavailable
        return
    }

    result.status = dnssecStatus(from: flags)
}

final class TransportPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    func urlSession(
        _: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    func urlSession(
        _ session: URLSession,
        task _: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        urlSession(session, didReceive: challenge, completionHandler: completionHandler)
    }
}

struct SealServerClient: Sendable {
    private let configuration: URLSessionConfiguration

    init(configuration: URLSessionConfiguration = SealServerClient.makeConfiguration()) {
        self.configuration = configuration
    }

    static func makeConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.urlCredentialStorage = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 25
        config.waitsForConnectivity = false
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        return config
    }

    static func encodeUnsealBody(_ share: String) throws -> Data {
        try JSONEncoder().encode(UnsealBody(key: share))
    }

    static func makeRequest(
        _ profile: ServerProfile,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: Data?,
        componentsForURL: (URL) -> URLComponents? = {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)
        }
    ) throws -> URLRequest {
        var url = try profile.endpoint(path)
        if !queryItems.isEmpty {
            guard var components = componentsForURL(url) else {
                throw AppFailure("Unable to build server request.")
            }
            components.queryItems = queryItems
            guard let queriedURL = components.url else {
                throw AppFailure("Unable to build server request.")
            }
            url = queriedURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    static func detectProduct(from data: Data) -> ServerProduct {
        guard let response = try? JSONDecoder().decode(HelpResponse.self, from: data),
              let title = response.openapi?.info?.title else {
            return .generic
        }

        switch title {
        case "OpenBao API":
            return .openBao
        case "HashiCorp Vault API":
            return .vault
        default:
            return .generic
        }
    }

    static func dnssecStatus(for host: String) async -> DNSSECStatus {
        let normalized = host
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .lowercased()

        guard !normalized.isEmpty else {
            return .unavailable
        }
        guard !isIPAddress(normalized),
              !normalized.hasSuffix(".local") else {
            return .notApplicable
        }

        return await Task.detached(priority: .userInitiated) {
            resolveDNSSECStatus(host: normalized)
        }.value
    }

    func detectProduct(_ profile: ServerProfile) async throws -> ServerProduct {
        let data = try await request(
            profile,
            path: "seal-status",
            queryItems: [URLQueryItem(name: "help", value: "1")],
            body: nil
        )
        return Self.detectProduct(from: data)
    }

    func status(_ profile: ServerProfile) async throws -> SealStatus {
        let data = try await request(profile, path: "seal-status", body: nil)
        do {
            return try JSONDecoder().decode(SealStatus.self, from: data).validated()
        } catch {
            throw AppFailure("Invalid seal-status response. Check the actual server state again.")
        }
    }

    func submit(_ record: ShareRecord) async throws {
        var body = try Self.encodeUnsealBody(record.share)
        defer {
            body.resetBytes(in: body.startIndex..<body.endIndex)
        }
        _ = try await request(record.profile, path: "unseal", body: body)
    }

    private struct HelpResponse: Decodable {
        let openapi: OpenAPIDocument?
    }

    private struct OpenAPIDocument: Decodable {
        let info: Info?

        struct Info: Decodable {
            let title: String?
        }
    }

    private struct UnsealBody: Encodable {
        let key: String
    }

    private static func isIPAddress(_ host: String) -> Bool {
        if host.contains(":") {
            return true
        }

        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else {
            return false
        }

        return octets.allSatisfy { octet in
            guard let value = Int(octet) else {
                return false
            }
            return (0...255).contains(value)
        }
    }

    private static func resolveDNSSECStatus(host: String) -> DNSSECStatus {
        var service: DNSServiceRef?
        let result = DNSSECResultBox()
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

    private func request(
        _ profile: ServerProfile,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: Data?
    ) async throws -> Data {
        let session = URLSession(
            configuration: configuration,
            delegate: TransportPolicy(),
            delegateQueue: nil
        )
        defer {
            session.invalidateAndCancel()
        }

        let request = try Self.makeRequest(
            profile,
            path: path,
            queryItems: queryItems,
            body: body
        )

        try Task.checkCancellation()

        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse,
                  response.url == request.url else {
                throw AppFailure("Unexpected server response or response target.")
            }
            guard response.statusCode == 200 else {
                if (300...399).contains(response.statusCode) {
                    throw AppFailure("Redirect blocked. Configure the direct HTTPS origin of one server node.")
                }
                throw AppFailure("Server returned HTTP \(response.statusCode). A share or request may have been rejected; no automatic retry is made.")
            }
            guard response.mimeType == "application/json" else {
                throw AppFailure("Expected a JSON response from the server.")
            }
            guard response.expectedContentLength <= 65_536 else {
                throw AppFailure("Server response too large.")
            }

            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < 65_536 else {
                    throw AppFailure("Server response too large.")
                }
                data.append(byte)
            }
            return data
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AppFailure {
            throw error
        } catch let error as URLError {
            if error.code == .cancelled {
                throw CancellationError()
            }
            switch error.code {
            case .serverCertificateHasBadDate,
                 .serverCertificateUntrusted,
                 .serverCertificateHasUnknownRoot,
                 .serverCertificateNotYetValid,
                 .secureConnectionFailed,
                 .clientCertificateRejected,
                 .clientCertificateRequired:
                throw AppFailure("TLS validation failed. Fix the server certificate/trust configuration; verification cannot be disabled.")
            default:
                throw AppFailure("Connection failed or timed out. Check the network, VPN, DNS, and the configured server endpoint.")
            }
        } catch {
            throw AppFailure("The request failed. No automatic retry is made.")
        }
    }
}
