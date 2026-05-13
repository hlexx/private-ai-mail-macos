import Foundation
import Security

public final class KeychainTokenStore: TokenStore, @unchecked Sendable {
    private let service: String
    private let lock = NSLock()

    public init(service: String = "com.hlexx.privateaimail.oauth") {
        self.service = service
    }

    public func save(_ credential: TokenCredential, for accountID: String) throws {
        lock.lock()
        defer { lock.unlock() }

        let data = try JSONEncoder().encode(credential)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery.merge(attributes) { _, new in new }
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw AuthError.keychain(status)
        }
    }

    public func load(for accountID: String) throws -> TokenCredential? {
        lock.lock()
        defer { lock.unlock() }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return try JSONDecoder().decode(TokenCredential.self, from: data)
        case errSecItemNotFound:
            return nil
        default:
            throw AuthError.keychain(status)
        }
    }

    public func delete(for accountID: String) throws {
        lock.lock()
        defer { lock.unlock() }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AuthError.keychain(status)
        }
    }
}
