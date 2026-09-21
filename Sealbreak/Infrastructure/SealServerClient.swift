import Foundation
import Security

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
        didReceive _: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        completionHandler(.performDefaultHandling, nil)
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
        try makeRequest(
            url: profile.endpoint(path),
            queryItems: queryItems,
            body: body,
            componentsForURL: componentsForURL
        )
    }

    private static func makeRequest(
        url initialURL: URL,
        queryItems: [URLQueryItem] = [],
        body: Data?,
        componentsForURL: (URL) -> URLComponents? = {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)
        }
    ) throws -> URLRequest {
        var url = initialURL
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
        let record = try record.validated()
        var body = try Self.encodeUnsealBody(record.share)
        defer {
            body.resetBytes(in: body.startIndex..<body.endIndex)
        }
        _ = try await request(record.endpoint("unseal"), body: body)
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

    private func request(
        _ profile: ServerProfile,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: Data?
    ) async throws -> Data {
        try await request(
            profile.endpoint(path),
            queryItems: queryItems,
            body: body
        )
    }

    private func request(
        _ url: URL,
        queryItems: [URLQueryItem] = [],
        body: Data?
    ) async throws -> Data {
        let session = URLSession(
            configuration: configuration,
            delegate: TransportPolicy(),
            delegateQueue: nil
        )
        var completedSuccessfully = false
        defer {
            if completedSuccessfully {
                session.finishTasksAndInvalidate()
            } else {
                session.invalidateAndCancel()
            }
        }

        let request = try Self.makeRequest(
            url: url,
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
            completedSuccessfully = true
            return data
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AppFailure {
            throw error
        } catch let error as URLError {
            if error.code == .cancelled, Task.isCancelled {
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
