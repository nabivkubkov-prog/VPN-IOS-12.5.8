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
    private static func check(_ status: OSStatus) throws {
        if status != errSecSuccess { throw ProfileError.invalid("Ошибка Keychain (\(status)). Проверьте подпись приложения и VPN-расширения.") }
    }
}

