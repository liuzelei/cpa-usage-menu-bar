enum StatusItemPresentation {
    static func title(metric: MenuBarMetric, snapshot: UsageSnapshot?) -> String {
        UsageFormatter.statusText(metric: metric, snapshot: snapshot)
    }

    static func imageName(hasError: Bool) -> String {
        hasError ? "exclamationmark.circle" : "chart.bar.fill"
    }
}
