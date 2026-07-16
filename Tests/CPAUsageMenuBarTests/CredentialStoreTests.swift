import Foundation
import Testing
@testable import CPAUsageMenuBar

private final class MemoryCredentialBackend: CredentialBackend {
    var data: Data?
    var deleted = false

    func read(service: String, account: String) throws -> Data? { data }
    func write(_ data: Data, service: String, account: String) throws { self.data = data }
    func delete(service: String, account: String) throws { data = nil; deleted = true }
}

@Test
func credentialRoundTripUsesSingleActiveItem() throws {
    let backend = MemoryCredentialBackend()
    let store = KeychainCredentialStore(backend: backend)

    try store.replace(with: "first")
    try store.replace(with: "second")

    #expect(try store.read() == "second")
}

@Test
func credentialDeleteClearsItem() throws {
    let backend = MemoryCredentialBackend()
    let store = KeychainCredentialStore(backend: backend)
    try store.replace(with: "secret")

    try store.delete()

    #expect(try store.read() == nil)
    #expect(backend.deleted)
}
