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
                "Awayo Lock"
            case .locked:
                "Locked"
            }
        }
    }

    let mode: Mode
    let endDate: Date?
    let message: String
}

struct AwayoLockDetails {
    let message: String
}

enum AwayoLockStyle: String, CaseIterable {
    case neonFlow
    case duckPond
    case offlineRunner
    case cosmicDesk
    case rainyWindow
    case arcadePulse
    case paperNotes
    case synthwave
    case solidColor
    case softWash
    case stripes
    case polkaDots

    var title: String {
        switch self {
        case .neonFlow:
            "Neon Flow"
        case .duckPond:
            "Duck Pond"
        case .offlineRunner:
            "Offline Runner"
        case .cosmicDesk:
            "Solar System"
        case .rainyWindow:
            "Rainy Day"
        case .arcadePulse:
            "Arcade Pulse"
        case .paperNotes:
            "Paper Notes"
        case .synthwave:
            "Synthwave"
        case .solidColor:
            "Custom Color"
        case .softWash:
            "Soft Wash"
        case .stripes:
            "Stripes"
        case .polkaDots:
            "Polka Dots"
        }
    }

    var statusText: String {
        switch self {
        case .neonFlow:
            "AGENTS STILL ALIVE"
        case .duckPond:
            "BRB, STILL RUNNING"
        case .offlineRunner:
            "RUNNING WHILE YOU'RE AWAY"
        case .cosmicDesk:
            "SOLAR SYSTEM RUNNING"
        case .rainyWindow:
            "RAINY DAY, STILL RUNNING"
        case .arcadePulse:
            "INSERT PASSCODE TO RESUME"
        case .paperNotes:
            "LEAVE A NOTE FOR THE HUMAN"
        case .synthwave:
            "BUILDING IN THE DISTANCE"
        case .solidColor:
            "AWAKE BEHIND AWAYO LOCK"
        case .softWash:
            "SOFT LOCK, STILL RUNNING"
        case .stripes:
            "STRIPED AND AWAKE"
        case .polkaDots:
            "DOTS ON DUTY"
        }
    }

    static var defaultStyle: AwayoLockStyle {
        .duckPond
    }
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
