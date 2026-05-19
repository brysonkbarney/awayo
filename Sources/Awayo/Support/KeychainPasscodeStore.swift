import Foundation
import Security

final class KeychainPasscodeStore {
    enum KeychainError: LocalizedError {
        case unexpectedData
        case unhandledStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .unexpectedData:
                "Awayo could not read the saved passcode from Keychain."
            case .unhandledStatus(let status):
                "Keychain returned status \(status)."
            }
        }
    }

    private let service = "app.awayo.Awayo"
    private let account = "AwayoLockPasscode"

    func hasPasscode() -> Bool {
        (try? loadPasscode())?.isEmpty == false
    }

    func loadPasscode() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.unhandledStatus(status)
        }

        guard
            let data = item as? Data,
            let passcode = String(data: data, encoding: .utf8)
        else {
            throw KeychainError.unexpectedData
        }

        return passcode
    }

    func savePasscode(_ passcode: String) throws {
        let data = Data(passcode.utf8)

        do {
            if try loadPasscode() != nil {
                let attributes: [String: Any] = [
                    kSecValueData as String: data
                ]
                let status = SecItemUpdate(baseQuery() as CFDictionary, attributes as CFDictionary)

                guard status == errSecSuccess else {
                    throw KeychainError.unhandledStatus(status)
                }

                return
            }
        } catch KeychainError.unhandledStatus(errSecItemNotFound) {
        }

        var item = baseQuery()
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(item as CFDictionary, nil)

        if status == errSecDuplicateItem {
            let attributes: [String: Any] = [
                kSecValueData as String: data
            ]
            let updateStatus = SecItemUpdate(baseQuery() as CFDictionary, attributes as CFDictionary)

            guard updateStatus == errSecSuccess else {
                throw KeychainError.unhandledStatus(updateStatus)
            }

            return
        }

        guard status == errSecSuccess else {
            throw KeychainError.unhandledStatus(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
