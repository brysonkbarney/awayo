import Foundation
import AppKit

final class AwayoSettingsStore {
    private enum Key {
        static let backgroundStyle = "awayoBackgroundStyle"
        static let solidBackgroundColorRed = "awayoSolidBackgroundColorRed"
        static let solidBackgroundColorGreen = "awayoSolidBackgroundColorGreen"
        static let solidBackgroundColorBlue = "awayoSolidBackgroundColorBlue"
        static let timerStyle = "awayoTimerStyle"
        static let dashboardStyle = "awayoDashboardStyle"
        static let noteStyle = "awayoNoteStyle"
        static let cameraGagEnabled = "awayoCameraGagEnabled"
        static let awayMessage = "awayoAwayMessage"
        static let showsAwayMessage = "awayoShowsAwayMessage"
        static let hotKeyKeyCode = "awayoHotKeyKeyCode"
        static let hotKeyModifiers = "awayoHotKeyModifiers"
        static let completedFirstRun = "completedFirstRun"
    }

    static let defaultAwayMessage = "brb, agents are running"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasCompletedFirstRun: Bool {
        defaults.bool(forKey: Key.completedFirstRun)
    }

    func markFirstRunComplete() {
        defaults.set(true, forKey: Key.completedFirstRun)
    }

    func appearance() -> AwayoAppearance {
        AwayoAppearance(
            backgroundStyle: value(for: Key.backgroundStyle, fallback: AwayoAppearance.fallback.backgroundStyle),
            solidBackgroundColor: solidBackgroundColor(),
            timerStyle: value(for: Key.timerStyle, fallback: AwayoAppearance.fallback.timerStyle),
            dashboardStyle: value(for: Key.dashboardStyle, fallback: AwayoAppearance.fallback.dashboardStyle),
            noteStyle: value(for: Key.noteStyle, fallback: AwayoAppearance.fallback.noteStyle),
            cameraGagEnabled: cameraGagEnabled()
        )
    }

    func saveBackgroundStyle(_ style: AwayoLockStyle) {
        defaults.set(style.rawValue, forKey: Key.backgroundStyle)
    }

    func saveSolidBackgroundColor(_ color: AwayoColor) {
        defaults.set(color.red, forKey: Key.solidBackgroundColorRed)
        defaults.set(color.green, forKey: Key.solidBackgroundColorGreen)
        defaults.set(color.blue, forKey: Key.solidBackgroundColorBlue)
    }

    func saveTimerStyle(_ style: AwayoTimerStyle) {
        defaults.set(style.rawValue, forKey: Key.timerStyle)
    }

    func saveDashboardStyle(_ style: AwayoDashboardStyle) {
        defaults.set(style.rawValue, forKey: Key.dashboardStyle)
    }

    func saveNoteStyle(_ style: AwayoNoteStyle) {
        defaults.set(style.rawValue, forKey: Key.noteStyle)
    }

    func cameraGagEnabled() -> Bool {
        guard defaults.object(forKey: Key.cameraGagEnabled) != nil else {
            return AwayoAppearance.fallback.cameraGagEnabled
        }

        return defaults.bool(forKey: Key.cameraGagEnabled)
    }

    func saveCameraGagEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Key.cameraGagEnabled)
    }

    func awayMessage() -> String {
        let message = defaults.string(forKey: Key.awayMessage)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return message.isEmpty ? Self.defaultAwayMessage : message
    }

    func lockMessage() -> String {
        showsAwayMessage() ? awayMessage() : ""
    }

    func saveAwayMessage(_ message: String) {
        defaults.set(message, forKey: Key.awayMessage)
    }

    func showsAwayMessage() -> Bool {
        guard defaults.object(forKey: Key.showsAwayMessage) != nil else {
            return true
        }

        return defaults.bool(forKey: Key.showsAwayMessage)
    }

    func saveShowsAwayMessage(_ shows: Bool) {
        defaults.set(shows, forKey: Key.showsAwayMessage)
    }

    func hotKey() -> AwayoHotKey? {
        guard defaults.object(forKey: Key.hotKeyKeyCode) != nil,
              defaults.object(forKey: Key.hotKeyModifiers) != nil else {
            return nil
        }

        return AwayoHotKey(
            keyCode: UInt16(defaults.integer(forKey: Key.hotKeyKeyCode)),
            modifiers: NSEvent.ModifierFlags(rawValue: UInt(defaults.integer(forKey: Key.hotKeyModifiers)))
        )
    }

    func saveHotKey(_ hotKey: AwayoHotKey?) {
        guard let hotKey else {
            defaults.removeObject(forKey: Key.hotKeyKeyCode)
            defaults.removeObject(forKey: Key.hotKeyModifiers)
            return
        }

        defaults.set(Int(hotKey.keyCode), forKey: Key.hotKeyKeyCode)
        defaults.set(Int(hotKey.modifierRawValue), forKey: Key.hotKeyModifiers)
    }

    private func value<T: RawRepresentable>(for key: String, fallback: T) -> T where T.RawValue == String {
        guard
            let rawValue = defaults.string(forKey: key),
            let value = T(rawValue: rawValue)
        else {
            return fallback
        }

        return value
    }

    private func solidBackgroundColor() -> AwayoColor {
        guard defaults.object(forKey: Key.solidBackgroundColorRed) != nil else {
            return AwayoAppearance.fallback.solidBackgroundColor
        }

        return AwayoColor(
            red: defaults.double(forKey: Key.solidBackgroundColorRed),
            green: defaults.double(forKey: Key.solidBackgroundColorGreen),
            blue: defaults.double(forKey: Key.solidBackgroundColorBlue)
        )
    }
}
