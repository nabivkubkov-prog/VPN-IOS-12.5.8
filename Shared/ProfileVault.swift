import Foundation
import Security

enum ProfileVault {
    private static let service = "INCY.Profiles.v1"
    static func save(_ p: Profile) throws {
        let data = try JSONEncoder().encode(p)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: p.id]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            try check(SecItemAdd(item as CFDictionary, nil))
        } else { try check(status) }
    }
    static func load(_ id: String) throws -> Profile {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?; try check(SecItemCopyMatching(query as CFDictionary, &result))
        guard let data = result as? Data else { throw ProfileError.invalid("Профиль недоступен в Keychain.") }
        return try JSONDecoder().decode(Profile.self, from: data)
    }
    static func delete(_ id: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }
    private static var failureQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "INCY.TunnelStatus.v1", kSecAttrAccount as String: "last-error"]
    }
    // iOS 12 cannot fetchLastDisconnectError. Relay the provider's safe,
    // user-facing failure through the same shared Keychain as the profiles.
    static func saveTunnelFailure(_ message: String?) throws {
        let query = failureQuery
        guard let message = message else {
            let status = SecItemDelete(query as CFDictionary)
            if status != errSecItemNotFound { try check(status) }; return
        }
        let data = Data(message.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            try check(SecItemAdd(item as CFDictionary, nil))
        } else { try check(status) }
    }
    static func takeTunnelFailure() -> String? {
        var query = failureQuery
        query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let message = String(data: data, encoding: .utf8) else { return nil }
        try? saveTunnelFailure(nil)
        return message
    }
    private static func check(_ status: OSStatus) throws {
        if status != errSecSuccess { throw ProfileError.invalid("Ошибка Keychain (\(status)). Проверьте подпись приложения и VPN-расширения.") }
    }
}

