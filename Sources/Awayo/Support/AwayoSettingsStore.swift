import Foundation

final class AwayoSettingsStore {
    private enum Key {
        static let backgroundStyle = "awayoBackgroundStyle"
        static let timerStyle = "awayoTimerStyle"
        static let dashboardStyle = "awayoDashboardStyle"
        static let noteStyle = "awayoNoteStyle"
        static let completedFirstRun = "completedFirstRun"
    }

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
            timerStyle: value(for: Key.timerStyle, fallback: AwayoAppearance.fallback.timerStyle),
            dashboardStyle: value(for: Key.dashboardStyle, fallback: AwayoAppearance.fallback.dashboardStyle),
            noteStyle: value(for: Key.noteStyle, fallback: AwayoAppearance.fallback.noteStyle)
        )
    }

    func saveBackgroundStyle(_ style: AwayoLockStyle) {
        defaults.set(style.rawValue, forKey: Key.backgroundStyle)
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

    private func value<T: RawRepresentable>(for key: String, fallback: T) -> T where T.RawValue == String {
        guard
            let rawValue = defaults.string(forKey: key),
            let value = T(rawValue: rawValue)
        else {
            return fallback
        }

        return value
    }
}
