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

struct OpenBaoClient: Sendable {
    private let configuration: URLSessionConfiguration

    init(configuration: URLSessionConfiguration = OpenBaoClient.makeConfiguration()) {
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

    func status(_ profile: ServerProfile) async throws -> SealStatus {
        let data = try await request(profile, path: "seal-status", body: nil)
        do {
            return try JSONDecoder().decode(SealStatus.self, from: data).validated()
        } catch {
            throw AppFailure("Invalid seal-status response. Check the actual server state again.")
        }
    }

    func submit(_ record: ShareRecord) async throws {
        var body = try JSONEncoder().encode(UnsealBody(key: record.share))
        defer {
            body.resetBytes(in: body.startIndex..<body.endIndex)
        }
        _ = try await request(record.profile, path: "unseal", body: body)
    }

    private struct UnsealBody: Encodable {
        let key: String
    }

    private func request(
        _ profile: ServerProfile,
        path: String,
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

        var request = URLRequest(url: try profile.endpoint(path))
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        try Task.checkCancellation()

        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse,
                  response.url == request.url else {
                throw AppFailure("Unexpected server response or response target.")
            }
            guard response.statusCode == 200 else {
                if (300...399).contains(response.statusCode) {
                    throw AppFailure("Redirect blocked. Configure the direct HTTPS origin of one OpenBao node.")
                }
                throw AppFailure("OpenBao returned HTTP \(response.statusCode). A share or request may have been rejected; no automatic retry is made.")
            }
            guard response.mimeType == "application/json" else {
                throw AppFailure("Expected a JSON response from OpenBao.")
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
                throw AppFailure("Connection failed or timed out. Check the network, VPN, DNS, and the direct OpenBao endpoint.")
            }
        } catch {
            throw AppFailure("The request failed. No automatic retry is made.")
        }
    }
}
