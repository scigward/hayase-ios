//
//  Keychain.swift
//  Hayase
//

import Foundation
import Security

/// Storage for credentials. They live in the Keychain, not the UserDefaults plist,
/// which ends up in unencrypted device backups.
enum Keychain {
    private static let service = Bundle.main.bundleIdentifier ?? "Hayase"

    private static func query(forKey key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }

    /// Reads a credential. A plaintext copy that earlier versions left in UserDefaults under
    /// the same key is moved into the Keychain the first time it is read.
    static func string(forKey key: String) -> String? {
        var request = query(forKey: key)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        if SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess, let data = item as? Data {
            return String(data: data, encoding: .utf8)
        }
        guard let legacy = UserDefaults.standard.string(forKey: key) else { return nil }
        set(legacy, forKey: key)
        return legacy
    }

    /// Stores a credential; `nil` or an empty value deletes it.
    static func set(_ value: String?, forKey key: String) {
        SecItemDelete(query(forKey: key) as CFDictionary)
        guard let value, !value.isEmpty else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        var item = query(forKey: key)
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        if SecItemAdd(item as CFDictionary, nil) == errSecSuccess {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            // A build re-signed without keychain access must still keep its logins.
            UserDefaults.standard.set(value, forKey: key)
        }
    }

    /// Deletes every credential this app stored.
    static func removeAll() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrService as String: service] as CFDictionary)
    }
}
