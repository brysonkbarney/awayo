import Foundation

struct AwayoSession {
    enum Mode {
        case awake
        case privacy
        case locked

        var title: String {
            switch self {
            case .awake:
                "Awake"
            case .privacy:
                "Privacy Cover"
            case .locked:
                "Locked"
            }
        }
    }

    let mode: Mode
    let endDate: Date?
    let message: String
}

struct PrivacyCoverDetails {
    let message: String
    let passcode: String
}

struct DurationPreset {
    let title: String
    let seconds: TimeInterval?

    var representedValue: NSNumber {
        NSNumber(value: seconds ?? -1)
    }

    static let standard: [DurationPreset] = [
        DurationPreset(title: "15 Minutes", seconds: 15 * 60),
        DurationPreset(title: "30 Minutes", seconds: 30 * 60),
        DurationPreset(title: "1 Hour", seconds: 60 * 60),
        DurationPreset(title: "2 Hours", seconds: 2 * 60 * 60),
        DurationPreset(title: "Until Stopped", seconds: nil)
    ]
}
