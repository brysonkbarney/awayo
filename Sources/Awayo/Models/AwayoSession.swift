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

    var title: String {
        switch self {
        case .neonFlow:
            "Neon Flow"
        case .duckPond:
            "Duck Pond"
        case .offlineRunner:
            "Offline Runner"
        case .cosmicDesk:
            "Cosmic Desk"
        case .rainyWindow:
            "Rainy Window"
        case .arcadePulse:
            "Arcade Pulse"
        case .paperNotes:
            "Paper Notes"
        case .synthwave:
            "Synthwave"
        }
    }

    var statusText: String {
        switch self {
        case .neonFlow:
            "WORK IS STILL RUNNING"
        case .duckPond:
            "FLOATING BACK SOON"
        case .offlineRunner:
            "RUNNING WHILE YOU'RE AWAY"
        case .cosmicDesk:
            "ORBITING YOUR TASKS"
        case .rainyWindow:
            "RAIN CHECK IN PROGRESS"
        case .arcadePulse:
            "INSERT PASSCODE TO RESUME"
        case .paperNotes:
            "LEAVE A NOTE IF YOU STOPPED BY"
        case .synthwave:
            "BUILDING IN THE DISTANCE"
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
