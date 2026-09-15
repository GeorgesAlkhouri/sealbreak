import Foundation
import Testing
@testable import SealbreakCore

@Suite(.serialized)
struct OpenBaoClientTests {
    private let origin = "https://bao.example.com"
    private let syntheticShare = String(repeating: "a", count: 64)

    @Test
    func defaultConfigurationKeepsTransportEphemeralAndStrict() {
        let config = OpenBaoClient.makeConfiguration()

        #expect(config.urlCache == nil)
        #expect(config.urlCredentialStorage == nil)
        #expect(config.httpCookieStorage == nil)
        #expect(!config.httpShouldSetCookies)
        #expect(config.httpCookieAcceptPolicy == .never)
        #expect(config.requestCachePolicy == .reloadIgnoringLocalCacheData)
        #expect(config.timeoutIntervalForRequest == 15)
        #expect(config.timeoutIntervalForResource == 25)
        #expect(!config.waitsForConnectivity)
        #expect(config.tlsMinimumSupportedProtocolVersion == .TLSv12)
    }

    @Test
    func statusBuildsGetRequestAndDecodesResponse() async throws {
        let recorder = RequestRecorder()
        let client = makeClient { request in
            recorder.record(request)
            return (Self.response(for: request), Self.statusData())
        }

        let status = try await client.status(try profile())
        let request = recorder.request

        #expect(status.sealed)
        #expect(status.progress == 1)
        #expect(request?.httpMethod == "GET")
        #expect(request?.url?.absoluteString == "\(origin)/v1/sys/seal-status")
        #expect(request?.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request?.value(forHTTPHeaderField: "Cache-Control") == "no-store")
        #expect(request?.value(forHTTPHeaderField: "Content-Type") == nil)
        #expect(request?.httpShouldHandleCookies == false)
    }

    @Test
    func submitBuildsPostRequestWithOnlyTheShare() async throws {
        let recorder = RequestRecorder()
        let client = makeClient { request in
            recorder.record(request)
            return (Self.response(for: request), Data("{}".utf8))
        }
        let record = try ShareRecord(profile: profile(), input: syntheticShare)

        try await client.submit(record)
        let request = try #require(recorder.request)
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "\(origin)/v1/sys/unseal")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(json == ["key": syntheticShare])
    }

    @Test
    func statusRejectsInvalidPayload() async throws {
        let client = makeClient { request in
            (Self.response(for: request), Data("{}".utf8))
        }

        let message = await failureMessage {
            _ = try await client.status(try profile())
        }
        #expect(message == "Invalid seal-status response. Check the actual server state again.")
    }

    @Test
    func requestRejectsUnexpectedResponses() async throws {
        let cases: [(Int, [String: String], String, String)] = [
            (302, ["Content-Type": "application/json"], origin, "Redirect blocked."),
            (500, ["Content-Type": "application/json"], origin, "OpenBao returned HTTP 500."),
            (200, ["Content-Type": "text/plain"], origin, "Expected a JSON response from OpenBao."),
            (200, ["Content-Type": "application/json", "Content-Length": "65537"], origin, "Server response too large."),
            (200, ["Content-Type": "application/json"], "https://other.example.com", "Unexpected server response or response target.")
        ]

        for (statusCode, headers, responseOrigin, prefix) in cases {
            let client = makeClient { request in
                let url = URL(string: "\(responseOrigin)/v1/sys/seal-status")!
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: statusCode,
                    httpVersion: "HTTP/1.1",
                    headerFields: headers
                )!
                return (response, Self.statusData())
            }
            let message = await failureMessage {
                _ = try await client.status(try profile())
            }
            #expect(message?.hasPrefix(prefix) == true)
        }
    }

    @Test
    func requestMapsTLSErrorsAndOrdinaryNetworkFailures() async throws {
        let cases: [(URLError.Code, String)] = [
            (.serverCertificateUntrusted, "TLS validation failed."),
            (.secureConnectionFailed, "TLS validation failed."),
            (.timedOut, "Connection failed or timed out.")
        ]

        for (code, prefix) in cases {
            let client = makeClient { _ in throw URLError(code) }
            let message = await failureMessage {
                _ = try await client.status(try profile())
            }
            #expect(message?.hasPrefix(prefix) == true)
        }
    }

    @Test
    func cancellationIsPreserved() async throws {
        let client = makeClient { request in
            (Self.response(for: request), Self.statusData())
        }
        let target = try profile()
        let task = Task {
            try await client.status(target)
        }
        task.cancel()

        do {
            _ = try await task.value
            #expect(Bool(false))
        } catch {
            #expect(error is CancellationError)
        }
    }

    private func profile() throws -> ServerProfile {
        try ServerProfile(name: "Test", address: origin)
    }

    private func makeClient(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> OpenBaoClient {
        MockURLProtocol.setHandler(handler)
        let config = OpenBaoClient.makeConfiguration()
        config.protocolClasses = [MockURLProtocol.self]
        return OpenBaoClient(configuration: config)
    }

    private func failureMessage(_ operation: () async throws -> Void) async -> String? {
        do {
            try await operation()
            return nil
        } catch let error as AppFailure {
            return error.message
        } catch {
            return nil
        }
    }

    private static func response(for request: URLRequest) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
    }

    private static func statusData() -> Data {
        Data(#"{"type":"shamir","initialized":true,"sealed":true,"t":3,"n":5,"progress":1}"#.utf8)
    }
}

private final class MockURLProtocol: URLProtocol {
    private static let storage = HandlerStorage()

    static func setHandler(
        _ handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) {
        storage.set(handler)
    }

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.storage.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class HandlerStorage: @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private let lock = NSLock()
    private var storedHandler: Handler?

    var handler: Handler? {
        lock.lock()
        defer { lock.unlock() }
        return storedHandler
    }

    func set(_ handler: @escaping Handler) {
        lock.lock()
        storedHandler = handler
        lock.unlock()
    }
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequest: URLRequest?

    var request: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return storedRequest
    }

    func record(_ request: URLRequest) {
        lock.lock()
        storedRequest = request
        lock.unlock()
    }
}
