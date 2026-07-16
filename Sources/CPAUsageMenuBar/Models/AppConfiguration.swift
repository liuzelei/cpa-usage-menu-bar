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

enum CelebrationStyle: String, Codable, CaseIterable, Sendable {
    case off
    case cinematic
    case achievementToast
    case retro
    case random

    var title: String {
        switch self {
        case .off: "关闭"
        case .cinematic: "电影烟花"
        case .achievementToast: "顶部成就通知"
        case .retro: "复古游戏成就"
        case .random: "每次随机"
        }
    }
}

struct AppConfiguration: Codable, Equatable, Sendable {
    let baseURL: URL
    let authenticationType: AuthenticationType
    let refreshInterval: TimeInterval
    let menuBarMetric: MenuBarMetric
    let launchAtLogin: Bool
    let celebrationStyle: CelebrationStyle
    let celebrationSoundEnabled: Bool

    init(
        baseURL: URL,
        authenticationType: AuthenticationType,
        refreshInterval: TimeInterval,
        menuBarMetric: MenuBarMetric,
        launchAtLogin: Bool,
        celebrationStyle: CelebrationStyle = .off,
        celebrationSoundEnabled: Bool = false
    ) {
        self.baseURL = baseURL
        self.authenticationType = authenticationType
        self.refreshInterval = refreshInterval
        self.menuBarMetric = menuBarMetric
        self.launchAtLogin = launchAtLogin
        self.celebrationStyle = celebrationStyle
        self.celebrationSoundEnabled = celebrationSoundEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case baseURL
        case authenticationType
        case refreshInterval
        case menuBarMetric
        case launchAtLogin
        case celebrationStyle
        case celebrationSoundEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try container.decode(URL.self, forKey: .baseURL)
        authenticationType = try container.decode(AuthenticationType.self, forKey: .authenticationType)
        refreshInterval = try container.decode(TimeInterval.self, forKey: .refreshInterval)
        menuBarMetric = try container.decode(MenuBarMetric.self, forKey: .menuBarMetric)
        launchAtLogin = try container.decode(Bool.self, forKey: .launchAtLogin)
        celebrationStyle = try container.decodeIfPresent(CelebrationStyle.self, forKey: .celebrationStyle) ?? .off
        celebrationSoundEnabled = try container.decodeIfPresent(Bool.self, forKey: .celebrationSoundEnabled) ?? false
    }

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
