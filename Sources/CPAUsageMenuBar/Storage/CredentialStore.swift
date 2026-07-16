import Foundation
import Security

protocol CredentialStoring {
    func read() throws -> String?
    func replace(with credential: String) throws
    func delete() throws
}

protocol CredentialBackend: AnyObject {
    func read(service: String, account: String) throws -> Data?
    func write(_ data: Data, service: String, account: String) throws
    func delete(service: String, account: String) throws
}

final class KeychainCredentialStore: CredentialStoring {
    static let service = "cn.winlio.cpausage"
    static let account = "active-credential"

    private let backend: CredentialBackend

    init(backend: CredentialBackend = SecurityCredentialBackend()) {
        self.backend = backend
    }

    func read() throws -> String? {
        guard let data = try backend.read(service: Self.service, account: Self.account) else { return nil }
        guard let credential = String(data: data, encoding: .utf8) else { throw AppError.incompatibleResponse }
        return credential
    }

    func replace(with credential: String) throws {
        guard !credential.isEmpty else { throw AppError.missingCredential }
        try backend.write(Data(credential.utf8), service: Self.service, account: Self.account)
    }

    func delete() throws {
        try backend.delete(service: Self.service, account: Self.account)
    }
}

final class SecurityCredentialBackend: CredentialBackend {
    func read(service: String, account: String) throws -> Data? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw AppError.keychain(status: status)
        }
        return data
    }

    func write(_ data: Data, service: String, account: String) throws {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ] as CFDictionary
        var status = SecItemUpdate(query, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd([
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: account,
                kSecValueData: data
            ] as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw AppError.keychain(status: status) }
    }

    func delete(service: String, account: String) throws {
        let status = SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppError.keychain(status: status)
        }
    }
}
