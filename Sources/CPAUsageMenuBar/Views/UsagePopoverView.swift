import AppKit
import SwiftUI

struct UsagePopoverView: View {
    @ObservedObject var model: UsageRefreshModel
    let openSettings: @MainActor () -> Void
    let quit: @MainActor () -> Void

    private var snapshot: UsageSnapshot? { model.selectedSnapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if model.configuration == nil {
                setup
            } else {
                summary
            }
            Divider()
            footer
        }
        .padding(PopoverLayout.padding)
        .frame(width: PopoverLayout.hostWidth, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: model.error == nil ? "chart.bar.fill" : "exclamationmark.circle")
                .foregroundStyle(model.error == nil ? Color.accentColor : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("CPA Usage")
                    .font(.headline)
                Text(model.configuration?.baseURL.host ?? "尚未配置")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isRefreshing { ProgressView().controlSize(.small) }
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("配置 CPA Usage Keeper 后，即可在状态栏查看用量。")
                .foregroundStyle(.secondary)
            Button("开始设置", action: openSettings)
                .buttonStyle(.borderedProminent)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let authenticationType = model.configuration?.authenticationType {
                let items = APIKeyFilterPresentation.items(
                    authenticationType: authenticationType,
                    options: model.apiKeyOptions
                )
                if !items.isEmpty {
                    Picker("API Key", selection: Binding(
                        get: { model.selectedAPIKeyID },
                        set: { id in Task { await model.selectAPIKey(id) } }
                    )) {
                        ForEach(items) { item in
                            Text(item.title).tag(item.apiKeyID)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            Picker("时间范围", selection: Binding(
                get: { model.selectedRange },
                set: { range in Task { await model.selectRange(range) } }
            )) {
                ForEach(UsageRange.allCases, id: \.self) { range in
                    Text(range.title).tag(range)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 10) {
                MetricCard(title: "请求数", value: snapshot.map { UsageFormatter.compactNumber($0.requests) } ?? "--")
                MetricCard(title: "Token", value: snapshot.map { UsageFormatter.compactNumber($0.tokens) } ?? "--")
                MetricCard(title: "费用", value: snapshot?.cost.map(UsageFormatter.cost) ?? "--")
                MetricCard(title: "成功率", value: snapshot.map(UsageFormatter.successRate) ?? "--")
            }

            if let error = model.error {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if let refreshedAt = snapshot?.refreshedAt {
                Text("更新于 \(refreshedAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                Task { await model.refresh(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("刷新")
            .disabled(model.configuration == nil || model.isRefreshing)

            if let url = model.configuration?.baseURL {
                Button("打开面板") { NSWorkspace.shared.open(url) }
            }
            Spacer()
            Button("设置…", action: openSettings)
            Button("退出", action: quit)
        }
        .buttonStyle(.borderless)
    }
}
