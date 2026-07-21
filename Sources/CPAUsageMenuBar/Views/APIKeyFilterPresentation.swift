struct APIKeyFilterItem: Equatable, Identifiable {
    let apiKeyID: String?
    let title: String

    var id: String { apiKeyID ?? "all" }
}

enum APIKeyFilterPresentation {
    static func items(
        authenticationType: AuthenticationType,
        options: [CPAAPIKeyOption]
    ) -> [APIKeyFilterItem] {
        guard authenticationType == .administratorPassword, !options.isEmpty else { return [] }
        return [APIKeyFilterItem(apiKeyID: nil, title: "全部用量")]
            + options.map { APIKeyFilterItem(apiKeyID: $0.id, title: $0.label) }
    }
}
