import Foundation

enum AuthenticationType: String, Codable, CaseIterable, Sendable {
    case administratorPassword
    case cpaAPIKey

    var title: String {
        switch self {
        case .administratorPassword: "Keeper 管理密钥"
        case .cpaAPIKey: "CPA API Key"
        }
    }
}

enum UsageRange: String, Codable, CaseIterable, Sendable {
    case today
    case last24Hours = "24h"
    case last7Days = "7d"
    case last30Days = "30d"

    var title: String {
        switch self {
        case .today: "今日"
        case .last24Hours: "24 小时"
        case .last7Days: "7 天"
        case .last30Days: "30 天"
        }
    }
}

enum MenuBarMetric: String, Codable, CaseIterable, Sendable {
    case iconOnly
    case tokens
    case cost
    case requests

    var title: String {
        switch self {
        case .iconOnly: "仅图标"
        case .tokens: "今日 Token"
        case .cost: "今日费用"
        case .requests: "今日请求数"
        }
    }
}

struct AppConfiguration: Codable, Equatable, Sendable {
    let baseURL: URL
    let authenticationType: AuthenticationType
    let refreshInterval: TimeInterval
    let menuBarMetric: MenuBarMetric
    let launchAtLogin: Bool

    static func normalizedBaseURL(_ input: String) throws -> URL {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host?.isEmpty == false,
              components.query == nil,
              components.fragment == nil else {
            throw AppError.invalidURL
        }
        components.scheme = scheme
        while components.path.count > 1 && components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        if components.path == "/" { components.path = "" }
        guard let url = components.url else { throw AppError.invalidURL }
        return url
    }
}
