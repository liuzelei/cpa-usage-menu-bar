import Foundation

protocol KeeperAPIClientProtocol: Sendable {
    func fetchOverview(
        configuration: AppConfiguration,
        credential: String,
        range: UsageRange,
        apiKeyID: String?
    ) async throws -> UsageSnapshot

    func fetchAPIKeyOptions(
        configuration: AppConfiguration,
        credential: String
    ) async throws -> [CPAAPIKeyOption]
}

extension KeeperAPIClientProtocol {
    func fetchOverview(
        configuration: AppConfiguration,
        credential: String,
        range: UsageRange
    ) async throws -> UsageSnapshot {
        try await fetchOverview(
            configuration: configuration,
            credential: credential,
            range: range,
            apiKeyID: nil
        )
    }
}

actor KeeperAPIClient: KeeperAPIClientProtocol {
    private struct AuthContext: Equatable {
        let baseURL: URL
        let authenticationType: AuthenticationType
    }

    private struct OverviewResponse: Decodable {
        let usage: Usage
        let summary: Summary?
        let timezone: String?
    }

    private struct APIKeyOptionsResponse: Decodable {
        let options: [CPAAPIKeyOption]
    }

    private struct Usage: Decodable {
        let totalRequests: Int64
        let successCount: Int64
        let failureCount: Int64
        let totalTokens: Int64

        enum CodingKeys: String, CodingKey {
            case totalRequests = "total_requests"
            case successCount = "success_count"
            case failureCount = "failure_count"
            case totalTokens = "total_tokens"
        }
    }

    private struct Summary: Decodable {
        let totalCost: Double
        let costAvailable: Bool

        enum CodingKeys: String, CodingKey {
            case totalCost = "total_cost"
            case costAvailable = "cost_available"
        }
    }

    private let session: URLSession
    private let now: @Sendable () -> Date
    private var authenticatedContext: AuthContext?
    private var sessionCookieHeader: String?

    init(session: URLSession? = nil, now: @escaping @Sendable () -> Date = Date.init) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = HTTPCookieStorage()
            configuration.httpShouldSetCookies = true
            configuration.httpCookieAcceptPolicy = .always
            configuration.timeoutIntervalForRequest = 15
            self.session = URLSession(configuration: configuration)
        }
        self.now = now
    }

    func fetchOverview(
        configuration: AppConfiguration,
        credential: String,
        range: UsageRange,
        apiKeyID: String?
    ) async throws -> UsageSnapshot {
        let context = AuthContext(baseURL: configuration.baseURL, authenticationType: configuration.authenticationType)
        if authenticatedContext != context {
            sessionCookieHeader = nil
            try await login(configuration: configuration, credential: credential)
            authenticatedContext = context
        }

        let first = try await overviewResponse(
            configuration: configuration,
            range: range,
            apiKeyID: apiKeyID
        )
        if first.statusCode == 401 {
            authenticatedContext = nil
            sessionCookieHeader = nil
            try await login(configuration: configuration, credential: credential)
            authenticatedContext = context
            let retried = try await overviewResponse(
                configuration: configuration,
                range: range,
                apiKeyID: apiKeyID
            )
            guard retried.statusCode != 401 else {
                authenticatedContext = nil
                throw AppError.authenticationFailed
            }
            return try decode(retried.data, response: retried.response, range: range)
        }
        return try decode(first.data, response: first.response, range: range)
    }

    func fetchAPIKeyOptions(
        configuration: AppConfiguration,
        credential: String
    ) async throws -> [CPAAPIKeyOption] {
        guard configuration.authenticationType == .administratorPassword else { return [] }
        let context = AuthContext(
            baseURL: configuration.baseURL,
            authenticationType: configuration.authenticationType
        )
        if authenticatedContext != context {
            sessionCookieHeader = nil
            try await login(configuration: configuration, credential: credential)
            authenticatedContext = context
        }

        let first = try await apiKeyOptionsResponse(configuration: configuration)
        if first.response.statusCode == 401 {
            authenticatedContext = nil
            sessionCookieHeader = nil
            try await login(configuration: configuration, credential: credential)
            authenticatedContext = context
            let retried = try await apiKeyOptionsResponse(configuration: configuration)
            guard retried.response.statusCode != 401 else {
                authenticatedContext = nil
                throw AppError.authenticationFailed
            }
            return try decodeAPIKeyOptions(retried.data, response: retried.response)
        }
        return try decodeAPIKeyOptions(first.data, response: first.response)
    }

    private func login(configuration: AppConfiguration, credential: String) async throws {
        guard !credential.isEmpty else { throw AppError.missingCredential }
        let path: String
        let body: [String: String]
        switch configuration.authenticationType {
        case .administratorPassword:
            path = "api/v1/auth/login"
            body = ["password": credential]
        case .cpaAPIKey:
            path = "api/v1/auth/api-key-login"
            body = ["apiKey": credential]
        }
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("fetch", forHTTPHeaderField: "X-CPA-Usage-Keeper-Request")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await perform(request)
        switch response.statusCode {
        case 200..<300:
            let headerFields = response.allHeaderFields.reduce(into: [String: String]()) { result, pair in
                result[String(describing: pair.key)] = String(describing: pair.value)
            }
            let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: request.url!)
            sessionCookieHeader = HTTPCookie.requestHeaderFields(with: cookies)["Cookie"]
            return
        case 401: throw AppError.authenticationFailed
        case 403: throw AppError.forbidden
        default: throw AppError.server(status: response.statusCode)
        }
    }

    private func overviewResponse(
        configuration: AppConfiguration,
        range: UsageRange,
        apiKeyID: String?
    ) async throws -> (data: Data, response: HTTPURLResponse, statusCode: Int) {
        let path = configuration.authenticationType == .administratorPassword
            ? "api/v1/usage/overview"
            : "api/v1/key-overview"
        var components = URLComponents(url: configuration.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        var queryItems = [URLQueryItem(name: "range", value: range.rawValue)]
        if configuration.authenticationType == .administratorPassword,
           let apiKeyID,
           !apiKeyID.isEmpty {
            queryItems.append(URLQueryItem(name: "api_key_id", value: apiKeyID))
        }
        components.queryItems = queryItems
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        if let sessionCookieHeader {
            request.setValue(sessionCookieHeader, forHTTPHeaderField: "Cookie")
        }
        let (data, response) = try await perform(request)
        return (data, response, response.statusCode)
    }

    private func apiKeyOptionsResponse(
        configuration: AppConfiguration
    ) async throws -> (data: Data, response: HTTPURLResponse) {
        var request = URLRequest(
            url: configuration.baseURL.appendingPathComponent("api/v1/usage/api-keys/options")
        )
        request.timeoutInterval = 15
        if let sessionCookieHeader {
            request.setValue(sessionCookieHeader, forHTTPHeaderField: "Cookie")
        }
        return try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw AppError.incompatibleResponse }
            return (data, response)
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.serviceUnavailable
        }
    }

    private func decode(_ data: Data, response: HTTPURLResponse, range: UsageRange) throws -> UsageSnapshot {
        switch response.statusCode {
        case 200..<300: break
        case 401: throw AppError.authenticationFailed
        case 403: throw AppError.forbidden
        default: throw AppError.server(status: response.statusCode)
        }
        let payload: OverviewResponse
        do { payload = try JSONDecoder().decode(OverviewResponse.self, from: data) }
        catch { throw AppError.incompatibleResponse }
        return UsageSnapshot(
            requests: payload.usage.totalRequests,
            successes: payload.usage.successCount,
            failures: payload.usage.failureCount,
            tokens: payload.usage.totalTokens,
            cost: payload.summary?.costAvailable == true ? payload.summary?.totalCost : nil,
            range: range,
            timezone: payload.timezone,
            refreshedAt: now()
        )
    }

    private func decodeAPIKeyOptions(
        _ data: Data,
        response: HTTPURLResponse
    ) throws -> [CPAAPIKeyOption] {
        switch response.statusCode {
        case 200..<300:
            do { return try JSONDecoder().decode(APIKeyOptionsResponse.self, from: data).options }
            catch { throw AppError.incompatibleResponse }
        case 404, 501:
            return []
        case 401:
            throw AppError.authenticationFailed
        case 403:
            throw AppError.forbidden
        default:
            throw AppError.server(status: response.statusCode)
        }
    }
}
