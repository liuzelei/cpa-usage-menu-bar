import Testing
@testable import CPAUsageMenuBar

@Test
func administratorFilterStartsWithAggregateThenKeeperOptions() {
    let items = APIKeyFilterPresentation.items(
        authenticationType: .administratorPassword,
        options: [
            .init(id: "42", label: "Primary Key"),
            .init(id: "84", label: "sk-*********abcd")
        ]
    )

    #expect(items.map(\.apiKeyID) == [nil, "42", "84"])
    #expect(items.map(\.title) == ["全部用量", "Primary Key", "sk-*********abcd"])
}

@Test
func filterIsHiddenForViewerOrEmptyOptions() {
    #expect(APIKeyFilterPresentation.items(
        authenticationType: .cpaAPIKey,
        options: [.init(id: "42", label: "Primary Key")]
    ).isEmpty)
    #expect(APIKeyFilterPresentation.items(
        authenticationType: .administratorPassword,
        options: []
    ).isEmpty)
}
