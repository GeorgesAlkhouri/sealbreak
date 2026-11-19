import Foundation
import Testing

@testable import SealbreakCore
@testable import SealbreakInfrastructure

@Suite(.serialized)
struct SealServerClientTests {
  private let origin = "https://server.example.com"
  private let syntheticShare = String(repeating: "a", count: 64)

  @Test
  func defaultClientPreservesCancellationBeforeSendingARequest() async throws {
    let client = SealServerClient()
    let target = try profile()
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await client.status(target)
    }

    await #expect(throws: CancellationError.self) {
      try await task.value
    }
  }

  @Test
  func defaultConfigurationKeepsTransportEphemeralAndStrict() {
    let config = SealServerClient.makeConfiguration()

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
  func requestSessionKeepsTLS12Minimum() {
    let session = SealServerClient().makeSession()
    defer { session.invalidateAndCancel() }

    #expect(session.configuration.tlsMinimumSupportedProtocolVersion == .TLSv12)
  }

  @Test
  func requestSessionUsesTransportPolicyAsDelegate() {
    let session = SealServerClient().makeSession()
    defer { session.invalidateAndCancel() }

    #expect(session.delegate is TransportPolicy)
  }

  @Test
  func transportPolicyLeavesServerTrustToSystemValidation() throws {
    let decisions = try Self.transportPolicyDecisions(for: NSURLAuthenticationMethodServerTrust)

    #expect(decisions.count == 2)
    for (disposition, credential) in decisions {
      #expect(disposition == .performDefaultHandling)
      #expect(credential == nil)
    }
  }

  @Test(arguments: [
    NSURLAuthenticationMethodDefault,
    NSURLAuthenticationMethodHTTPBasic,
    NSURLAuthenticationMethodHTTPDigest,
    NSURLAuthenticationMethodHTMLForm,
    NSURLAuthenticationMethodNTLM,
    NSURLAuthenticationMethodNegotiate,
    NSURLAuthenticationMethodClientCertificate,
  ])
  func transportPolicyCancelsEveryOtherChallenge(method: String) throws {
    let decisions = try Self.transportPolicyDecisions(for: method)

    #expect(decisions.count == 2)
    for (disposition, credential) in decisions {
      #expect(disposition == .cancelAuthenticationChallenge)
      #expect(credential == nil)
    }
  }

  @Test
  func requestBuilderSetsTransportPolicyAndUnsealBody() throws {
    let profile = try profile()
    let get = try SealServerClient.makeRequest(profile, path: "seal-status", body: nil)
    let body = try SealServerClient.encodeUnsealBody(syntheticShare)
    let post = try SealServerClient.makeRequest(profile, path: "unseal", body: body)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])

    #expect(get.httpMethod == "GET")
    #expect(get.url?.absoluteString == "\(origin)/v1/sys/seal-status")
    #expect(get.httpBody == nil)
    #expect(get.value(forHTTPHeaderField: "Accept") == "application/json")
    #expect(get.value(forHTTPHeaderField: "Cache-Control") == "no-store")
    #expect(get.value(forHTTPHeaderField: "Content-Type") == nil)
    #expect(get.httpShouldHandleCookies == false)

    #expect(post.httpMethod == "POST")
    #expect(post.url?.absoluteString == "\(origin)/v1/sys/unseal")
    #expect(post.httpBody == body)
    #expect(post.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(json == ["key": syntheticShare])
  }

  @Test
  func requestBuilderFailsWhenURLComponentsCannotBeCreated() throws {
    let profile = try profile()

    #expect(throws: AppFailure.self) {
      _ = try SealServerClient.makeRequest(
        profile,
        path: "seal-status",
        queryItems: [URLQueryItem(name: "help", value: "1")],
        body: nil,
        componentsForURL: { _ in nil }
      )
    }
  }

  @Test
  func requestBuilderFailsWhenURLComponentsCannotProduceURL() throws {
    let profile = try profile()

    #expect(throws: AppFailure.self) {
      _ = try SealServerClient.makeRequest(
        profile,
        path: "seal-status",
        queryItems: [URLQueryItem(name: "help", value: "1")],
        body: nil,
        componentsForURL: { _ in
          var components = URLComponents()
          components.scheme = "https"
          components.host = "["
          return components
        }
      )
    }
  }

  @Test
  func detectsServerProductFromSealStatusHelp() async throws {
    let cases: [(String, ServerProduct)] = [
      (#"{"openapi":{"info":{"title":"OpenBao API"}}}"#, .openBao),
      (#"{"openapi":{"info":{"title":"HashiCorp Vault API"}}}"#, .vault),
      (#"{"openapi":{"info":{"title":"Compatible Server API"}}}"#, .generic),
    ]

    for (payload, expected) in cases {
      let recorder = RequestRecorder()
      let client = makeClient { request in
        recorder.record(request)
        return (try Self.response(for: request), Data(payload.utf8))
      }

      let product = try await client.detectProduct(try profile())
      let request = try #require(recorder.request)

      #expect(product == expected)
      #expect(request.httpMethod == "GET")
      #expect(request.url?.absoluteString == "\(origin)/v1/sys/seal-status?help=1")
    }
  }

  @Test
  func missingProductMetadataFallsBackToGeneric() {
    #expect(SealServerClient.detectProduct(from: Data("{}".utf8)) == .generic)
    #expect(SealServerClient.detectProduct(from: Data("not-json".utf8)) == .generic)
  }

  @Test
  func statusBuildsGetRequestAndDecodesResponse() async throws {
    let recorder = RequestRecorder()
    let client = makeClient { request in
      recorder.record(request)
      return (try Self.response(for: request), Self.statusData())
    }

    let status = try await client.status(try profile())
    let request = recorder.request

    #expect(status.sealed)
    #expect(status.progress == 1)
    #expect(request?.httpMethod == "GET")
    #expect(request?.url?.absoluteString == "\(origin)/v1/sys/seal-status")
  }

  @Test
  func submitSendsPostToUnsealEndpoint() async throws {
    let recorder = RequestRecorder()
    let client = makeClient { request in
      recorder.record(request)
      return (try Self.response(for: request), Data("{}".utf8))
    }
    let record = try ShareRecord(profile: profile(), input: syntheticShare)

    try await client.submit(record)
    let request = try #require(recorder.request)

    #expect(request.httpMethod == "POST")
    #expect(request.url?.absoluteString == "\(origin)/v1/sys/unseal")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
  }

  @Test
  func statusRejectsInvalidPayload() async {
    let client = makeClient { request in
      (try Self.response(for: request), Data("{}".utf8))
    }

    let message = await failureMessage {
      _ = try await client.status(try profile())
    }
    #expect(message == "Invalid seal-status response. Check the actual server state again.")
  }

  @Test
  func requestRejectsUnexpectedResponses() async {
    let cases: [(Int, [String: String], String, String)] = [
      (302, ["Content-Type": "application/json"], origin, "Redirect blocked."),
      (500, ["Content-Type": "application/json"], origin, "Server returned HTTP 500."),
      (200, ["Content-Type": "text/plain"], origin, "Expected a JSON response from the server."),
      (
        200, ["Content-Type": "application/json", "Content-Length": "65537"], origin,
        "Server response too large."
      ),
      (
        200, ["Content-Type": "application/json"], "https://other.example.com",
        "Unexpected server response or response target."
      ),
    ]

    for (statusCode, headers, responseOrigin, prefix) in cases {
      let client = makeClient { _ in
        let url = try #require(URL(string: "\(responseOrigin)/v1/sys/seal-status"))
        let response = try #require(
          HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
          ))
        return (response, Self.statusData())
      }
      let message = await failureMessage {
        _ = try await client.status(try profile())
      }
      #expect(message?.hasPrefix(prefix) == true)
    }
  }

  @Test(arguments: [301, 302, 303, 307, 308])
  func submitDoesNotFollowRedirectsOrResendTheShare(statusCode: Int) async throws {
    let recorder = RequestRecorder()
    let client = makeClient { request in
      recorder.record(request)
      let url = try #require(request.url)
      return (
        try #require(
          HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: [
              "Content-Type": "application/json",
              "Location": "https://other.example.com/v1/sys/unseal",
            ]
          )),
        Data("{}".utf8)
      )
    }
    let record = try ShareRecord(profile: profile(), input: syntheticShare)

    let message = await failureMessage {
      try await client.submit(record)
    }

    #expect(recorder.requests.compactMap(\.url?.absoluteString) == ["\(origin)/v1/sys/unseal"])
    #expect(message?.hasPrefix("Redirect blocked.") == true)
  }

  @Test(arguments: [65_536, 65_537])
  func requestEnforcesResponseSizeLimitWithoutContentLength(byteCount: Int) async throws {
    let statusData = Self.statusData()
    let data = statusData + Data(repeating: 0x20, count: byteCount - statusData.count)
    let client = makeClient { request in
      (try Self.response(for: request), data)
    }

    if byteCount == 65_536 {
      let status = try await client.status(try profile())
      #expect(status.sealed)
      #expect(status.progress == 1)
    } else {
      let message = await failureMessage {
        _ = try await client.status(try profile())
      }
      #expect(message == "Server response too large.")
    }
  }

  @Test
  func requestMapsUnexpectedTransportErrorsWithoutExposingDiagnostics() async {
    let client = makeClient { _ in
      throw NSError(
        domain: "SealbreakTests.Transport",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Sensitive transport diagnostics"]
      )
    }

    let message = await failureMessage {
      _ = try await client.status(try profile())
    }
    #expect(message == "The request failed. No automatic retry is made.")
  }

  @Test
  func requestMapsTLSErrorsAndOrdinaryNetworkFailures() async {
    let cases: [(URLError.Code, String)] = [
      (.serverCertificateUntrusted, "TLS validation failed."),
      (.secureConnectionFailed, "TLS validation failed."),
      (.timedOut, "Connection failed or timed out."),
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
      (try Self.response(for: request), Self.statusData())
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
    try ServerProfile(id: UUID(), name: "Test", address: origin)
  }

  private func makeClient(
    handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
  ) -> SealServerClient {
    MockURLProtocol.setHandler(handler)
    let config = SealServerClient.makeConfiguration()
    config.protocolClasses = [MockURLProtocol.self]
    return SealServerClient(configuration: config)
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

  private static func transportPolicyDecisions(
    for authenticationMethod: String
  ) throws -> [(URLSession.AuthChallengeDisposition, URLCredential?)] {
    let session = URLSession(configuration: .ephemeral)
    defer { session.invalidateAndCancel() }
    let task = session.dataTask(with: try #require(URL(string: "https://server.example.com")))
    let challenge = URLAuthenticationChallenge(
      protectionSpace: URLProtectionSpace(
        host: "server.example.com",
        port: 443,
        protocol: NSURLProtectionSpaceHTTPS,
        realm: nil,
        authenticationMethod: authenticationMethod
      ),
      proposedCredential: nil,
      previousFailureCount: 0,
      failureResponse: nil,
      error: nil,
      sender: ChallengeSender()
    )
    let policy = TransportPolicy()
    var decisions: [(URLSession.AuthChallengeDisposition, URLCredential?)] = []
    policy.urlSession(session, didReceive: challenge) { decisions.append(($0, $1)) }
    policy.urlSession(session, task: task, didReceive: challenge) { decisions.append(($0, $1)) }
    return decisions
  }

  private static func response(for request: URLRequest) throws -> HTTPURLResponse {
    let url = try #require(request.url)
    return try #require(
      HTTPURLResponse(
        url: url,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"]
      ))
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
      // A 3xx with a Location header goes through the session's redirect decision,
      // carrying the method and body along as a 307/308 does.
      if (300...399).contains(response.statusCode),
        let location = response.value(forHTTPHeaderField: "Location"),
        let target = URL(string: location, relativeTo: request.url)
      {
        var redirect = request
        redirect.url = target.absoluteURL
        client?.urlProtocol(self, wasRedirectedTo: redirect, redirectResponse: response)
      }
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

private final class ChallengeSender: NSObject, URLAuthenticationChallengeSender {
  func use(_: URLCredential, for _: URLAuthenticationChallenge) {}
  func continueWithoutCredential(for _: URLAuthenticationChallenge) {}
  func cancel(_: URLAuthenticationChallenge) {}
}

private final class RequestRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var storedRequests: [URLRequest] = []

  var request: URLRequest? {
    requests.last
  }

  var requests: [URLRequest] {
    lock.lock()
    defer { lock.unlock() }
    return storedRequests
  }

  func record(_ request: URLRequest) {
    lock.lock()
    storedRequests.append(request)
    lock.unlock()
  }
}
