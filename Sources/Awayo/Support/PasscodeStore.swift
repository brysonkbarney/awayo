import CryptoKit
import Foundation

final class PasscodeStore {
    private enum Key {
        static let salt = "awayoLockPasscodeSalt"
        static let digest = "awayoLockPasscodeDigest"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func hasPasscode() -> Bool {
        defaults.string(forKey: Key.salt)?.isEmpty == false
            && defaults.string(forKey: Key.digest)?.isEmpty == false
    }

    func savePasscode(_ passcode: String) {
        let salt = UUID().uuidString
        defaults.set(salt, forKey: Key.salt)
        defaults.set(digest(for: passcode, salt: salt), forKey: Key.digest)
    }

    func verify(_ passcode: String) -> Bool {
        guard
            let salt = defaults.string(forKey: Key.salt),
            let storedDigest = defaults.string(forKey: Key.digest)
        else {
            return false
        }

        return digest(for: passcode, salt: salt) == storedDigest
    }

    private func digest(for passcode: String, salt: String) -> String {
        let data = Data("\(salt):\(passcode)".utf8)
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
