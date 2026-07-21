import Foundation
import Testing
@testable import CPAUsageMenuBar

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stub: Sendable {
        let status: Int
        let headers: [String: String]
        let body: Data
    }

    nonisolated(unsafe) static var stubs: [Stub] = []
    nonisolated(unsafe) static var requests: [URLRequest] = []
    private static let lock = NSLock()

    static func reset(_ newStubs: [Stub]) {
        lock.lock(); defer { lock.unlock() }
        stubs = newStubs
        requests = []
    }

    private static func capturedRequest(_ request: URLRequest) -> URLRequest {
        guard request.httpBody == nil, let stream = request.httpBodyStream else { return request }

        stream.open()
        defer { stream.close() }

        var body = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1_024)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 1_024)
            guard count >= 0 else { return request }
            if count == 0 { break }
            body.append(buffer, count: count)
        }

        var captured = request
        captured.httpBodyStream = nil
        captured.httpBody = body
        return captured
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(Self.capturedRequest(request))
        let stub = Self.stubs.isEmpty ? nil : Self.stubs.removeFirst()
        Self.lock.unlock()

        guard let stub else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let response = HTTPURLResponse(url: request.url!, statusCode: stub.status, httpVersion: nil, headerFields: stub.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !stub.body.isEmpty { client?.urlProtocol(self, didLoad: stub.body) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private let overviewJSON = Data("""
{
  "usage": {"total_requests": 4, "success_count": 3, "failure_count": 1, "total_tokens": 1234},
  "summary": {"total_cost": 0.42, "cost_available": true},
  "timezone": "Asia/Shanghai"
}
""".utf8)

private func makeClient() -> KeeperAPIClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    configuration.httpCookieStorage = HTTPCookieStorage()
    configuration.httpCookieAcceptPolicy = .always
    return KeeperAPIClient(session: URLSession(configuration: configuration), now: { Date(timeIntervalSince1970: 100) })
}

private func configuration(_ type: AuthenticationType) -> AppConfiguration {
    .init(baseURL: URL(string: "http://keeper.local:8318")!, authenticationType: type, refreshInterval: 60, menuBarMetric: .tokens, launchAtLogin: false)
}

@Suite(.serialized)
struct KeeperAPIClientTests {
    @Test
    func administratorFetchesSafeAPIKeyOptions() async throws {
        let body = Data("""
        {"options":[{"id":"42","label":"Primary Key"},{"id":"84","label":"sk-*********abcd"}]}
        """.utf8)
        StubURLProtocol.reset([
            .init(status: 204, headers: [:], body: Data()),
            .init(status: 200, headers: [:], body: body)
        ])

        let options = try await makeClient().fetchAPIKeyOptions(
            configuration: configuration(.administratorPassword),
            credential: "secret"
        )

        #expect(options == [
            CPAAPIKeyOption(id: "42", label: "Primary Key"),
            CPAAPIKeyOption(id: "84", label: "sk-*********abcd")
        ])
        #expect(StubURLProtocol.requests.map { $0.url!.path } == [
            "/api/v1/auth/login",
            "/api/v1/usage/api-keys/options"
        ])
        #expect(StubURLProtocol.requests[1].httpBody == nil)
    }

    @Test
    func unsupportedAPIKeyOptionsReturnEmptyList() async throws {
        for status in [404, 501] {
            StubURLProtocol.reset([
                .init(status: 204, headers: [:], body: Data()),
                .init(status: status, headers: [:], body: Data())
            ])

            let options = try await makeClient().fetchAPIKeyOptions(
                configuration: configuration(.administratorPassword),
                credential: "secret"
            )

            #expect(options.isEmpty)
        }
    }

    @Test
    func administratorOverviewIncludesSelectedAPIKeyID() async throws {
        StubURLProtocol.reset([
            .init(status: 204, headers: [:], body: Data()),
            .init(status: 200, headers: [:], body: overviewJSON)
        ])

        _ = try await makeClient().fetchOverview(
            configuration: configuration(.administratorPassword),
            credential: "secret",
            range: .last7Days,
            apiKeyID: "42"
        )

        let components = try #require(
            URLComponents(url: StubURLProtocol.requests[1].url!, resolvingAgainstBaseURL: false)
        )
        #expect(Set(components.queryItems ?? []) == Set([
            URLQueryItem(name: "range", value: "7d"),
            URLQueryItem(name: "api_key_id", value: "42")
        ]))
    }

    @Test
    func administratorAggregateOverviewOmitsAPIKeyID() async throws {
        StubURLProtocol.reset([
            .init(status: 204, headers: [:], body: Data()),
            .init(status: 200, headers: [:], body: overviewJSON)
        ])

        _ = try await makeClient().fetchOverview(
            configuration: configuration(.administratorPassword),
            credential: "secret",
            range: .last7Days,
            apiKeyID: nil
        )

        let components = try #require(
            URLComponents(url: StubURLProtocol.requests[1].url!, resolvingAgainstBaseURL: false)
        )
        #expect(components.queryItems == [URLQueryItem(name: "range", value: "7d")])
    }

    @Test
    func viewerOverviewNeverIncludesSelectedAPIKeyID() async throws {
        StubURLProtocol.reset([
            .init(status: 204, headers: [:], body: Data()),
            .init(status: 200, headers: [:], body: overviewJSON)
        ])

        _ = try await makeClient().fetchOverview(
            configuration: configuration(.cpaAPIKey),
            credential: "key",
            range: .last7Days,
            apiKeyID: "42"
        )

        #expect(StubURLProtocol.requests[1].url?.path == "/api/v1/key-overview")
        #expect(StubURLProtocol.requests[1].url?.query == "range=7d")
    }

    @Test
    func administratorUsesPasswordLoginAndAdminOverview() async throws {
        StubURLProtocol.reset([
            .init(status: 204, headers: ["Set-Cookie": "cpa_usage_keeper_session=session; Path=/; HttpOnly"], body: Data()),
            .init(status: 200, headers: [:], body: overviewJSON)
        ])

        let snapshot = try await makeClient().fetchOverview(configuration: configuration(.administratorPassword), credential: "secret", range: .today)

        #expect(StubURLProtocol.requests.map { $0.url!.path } == ["/api/v1/auth/login", "/api/v1/usage/overview"])
        let loginBody = try #require(StubURLProtocol.requests[0].httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: loginBody) as? [String: String])
        #expect(json == ["password": "secret"])
        #expect(StubURLProtocol.requests[1].value(forHTTPHeaderField: "Cookie")?.contains("cpa_usage_keeper_session=session") == true)
        #expect(snapshot.tokens == 1234)
        #expect(snapshot.cost == 0.42)
        #expect(snapshot.refreshedAt == Date(timeIntervalSince1970: 100))
    }

    @Test
    func apiKeyUsesScopedEndpoints() async throws {
        StubURLProtocol.reset([
            .init(status: 204, headers: [:], body: Data()),
            .init(status: 200, headers: [:], body: overviewJSON)
        ])

        _ = try await makeClient().fetchOverview(configuration: configuration(.cpaAPIKey), credential: "key", range: .last7Days)

        #expect(StubURLProtocol.requests.map { $0.url!.path } == ["/api/v1/auth/api-key-login", "/api/v1/key-overview"])
        #expect(StubURLProtocol.requests[1].url?.query == "range=7d")
    }

    @Test
    func unauthorizedOverviewReauthenticatesOnlyOnce() async throws {
        StubURLProtocol.reset([
            .init(status: 204, headers: [:], body: Data()),
            .init(status: 401, headers: [:], body: Data()),
            .init(status: 204, headers: [:], body: Data()),
            .init(status: 200, headers: [:], body: overviewJSON)
        ])

        _ = try await makeClient().fetchOverview(configuration: configuration(.administratorPassword), credential: "secret", range: .today)

        #expect(StubURLProtocol.requests.count == 4)
    }

    @Test
    func repeatedUnauthorizedReturnsAuthenticationError() async {
        StubURLProtocol.reset([
            .init(status: 204, headers: [:], body: Data()),
            .init(status: 401, headers: [:], body: Data()),
            .init(status: 204, headers: [:], body: Data()),
            .init(status: 401, headers: [:], body: Data())
        ])

        do {
            _ = try await makeClient().fetchOverview(configuration: configuration(.administratorPassword), credential: "secret", range: .today)
            Issue.record("Expected authentication failure")
        } catch {
            #expect(error as? AppError == .authenticationFailed)
        }
    }
}
