import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: UsageRefreshModel
    let onSaved: @MainActor () -> Void

    @State private var urlText: String
    @State private var authenticationType: AuthenticationType
    @State private var credential = ""
    @State private var refreshInterval: TimeInterval
    @State private var menuBarMetric: MenuBarMetric
    @State private var launchAtLogin: Bool
    @State private var celebrationStyle: CelebrationStyle
    @State private var celebrationSoundEnabled: Bool
    @State private var isSaving = false
    @State private var validationError: String?

    init(model: UsageRefreshModel, onSaved: @escaping @MainActor () -> Void) {
        self.model = model
        self.onSaved = onSaved
        let configuration = model.configuration
        _urlText = State(initialValue: configuration?.baseURL.absoluteString ?? "")
        _authenticationType = State(initialValue: configuration?.authenticationType ?? .administratorPassword)
        _refreshInterval = State(initialValue: configuration?.refreshInterval ?? 60)
        _menuBarMetric = State(initialValue: configuration?.menuBarMetric ?? .tokens)
        _launchAtLogin = State(initialValue: configuration?.launchAtLogin ?? false)
        _celebrationStyle = State(initialValue: configuration?.celebrationStyle ?? .off)
        _celebrationSoundEnabled = State(initialValue: configuration?.celebrationSoundEnabled ?? false)
    }

    var body: some View {
        Form {
            Section("连接") {
                VStack(alignment: .leading, spacing: 5) {
                    Text(SettingsCopy.keeperURLLabel)
                        .font(.body)
                    TextField(SettingsCopy.keeperURLPlaceholder, text: $urlText)
                    Text(SettingsCopy.keeperURLHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker("认证类型", selection: $authenticationType) {
                    ForEach(AuthenticationType.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                SecureField(model.configuration == nil ? "凭据" : "留空表示继续使用当前凭据", text: $credential)
                if urlText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("http://") {
                    Label("HTTP 连接不会加密传输凭据，仅建议用于可信局域网。", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("显示与刷新") {
                Picker("状态栏显示", selection: $menuBarMetric) {
                    ForEach(MenuBarMetric.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("刷新间隔", selection: $refreshInterval) {
                    Text("30 秒").tag(TimeInterval(30))
                    Text("60 秒").tag(TimeInterval(60))
                    Text("5 分钟").tag(TimeInterval(300))
                    Text("15 分钟").tag(TimeInterval(900))
                }
                Toggle("登录时启动", isOn: $launchAtLogin)
            }

            Section("Token 里程碑彩蛋") {
                Picker("庆祝效果", selection: $celebrationStyle) {
                    ForEach(CelebrationStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("播放提示音", isOn: $celebrationSoundEnabled)
                    .disabled(celebrationStyle == .off)
                HStack {
                    Text("当天达到 10M、50M、100M，之后每增加 100M 播放一次。不会补播错过的里程碑。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("预览效果") {
                        model.previewCelebration(style: celebrationStyle, soundEnabled: celebrationSoundEnabled)
                    }
                    .disabled(celebrationStyle == .off || model.isCelebrationPresenting)
                }
            }

            if let validationError {
                Text(validationError).foregroundStyle(.red).font(.caption)
            }

            HStack {
                Spacer()
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .frame(width: 500, height: 560)
    }

    private func save() {
        isSaving = true
        validationError = nil
        Task { @MainActor in
            defer { isSaving = false }
            do {
                let baseURL = try AppConfiguration.normalizedBaseURL(urlText)
                let configuration = AppConfiguration(
                    baseURL: baseURL,
                    authenticationType: authenticationType,
                    refreshInterval: refreshInterval,
                    menuBarMetric: menuBarMetric,
                    launchAtLogin: launchAtLogin,
                    celebrationStyle: celebrationStyle,
                    celebrationSoundEnabled: celebrationSoundEnabled
                )
                try await model.validateAndSave(configuration: configuration, credential: credential)
                credential = ""
                onSaved()
            } catch {
                validationError = error.localizedDescription
            }
        }
    }
}
