import Foundation

enum AppError: LocalizedError, Equatable, Sendable {
    case invalidURL
    case missingConfiguration
    case missingCredential
    case authenticationFailed
    case forbidden
    case serviceUnavailable
    case server(status: Int)
    case incompatibleResponse
    case keychain(status: Int32)
    case launchAtLogin

    var errorDescription: String? {
        switch self {
        case .invalidURL: "请输入有效的 HTTP 或 HTTPS 地址。"
        case .missingConfiguration: "尚未配置 CPA Usage Keeper。"
        case .missingCredential: "请输入管理员密码或 CPA API Key。"
        case .authenticationFailed: "认证失败，请检查认证类型和凭据。"
        case .forbidden: "当前身份无权读取该用量数据。"
        case .serviceUnavailable: "无法连接 CPA Usage Keeper。"
        case let .server(status): "服务返回错误（HTTP \(status)）。"
        case .incompatibleResponse: "服务返回了无法识别的数据格式。"
        case .keychain: "无法访问 macOS Keychain。"
        case .launchAtLogin: "无法更新开机启动设置。"
        }
    }
}
