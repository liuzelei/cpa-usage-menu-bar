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
    }

    var body: some View {
        Form {
            Section("连接") {
                TextField("http://keeper.local:8318", text: $urlText)
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
        .frame(width: 460, height: 400)
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
                    launchAtLogin: launchAtLogin
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
