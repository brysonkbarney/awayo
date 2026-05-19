import Foundation

struct AwayoAppearance {
    var backgroundStyle: AwayoLockStyle
    var timerStyle: AwayoTimerStyle
    var dashboardStyle: AwayoDashboardStyle
    var noteStyle: AwayoNoteStyle

    static let fallback = AwayoAppearance(
        backgroundStyle: .duckPond,
        timerStyle: .heroCountdown,
        dashboardStyle: .centerStage,
        noteStyle: .tapedPaper
    )
}

enum AwayoTimerStyle: String, CaseIterable {
    case heroCountdown
    case paperClock
    case glassPill
    case terminalTicker

    var title: String {
        switch self {
        case .heroCountdown:
            "Hero Countdown"
        case .paperClock:
            "Paper Clock"
        case .glassPill:
            "Glass Pill"
        case .terminalTicker:
            "Terminal Ticker"
        }
    }
}

enum AwayoDashboardStyle: String, CaseIterable {
    case centerStage
    case paperDesk
    case minimalBadge
    case commandCenter

    var title: String {
        switch self {
        case .centerStage:
            "Center Stage"
        case .paperDesk:
            "Paper Desk"
        case .minimalBadge:
            "Minimal Badge"
        case .commandCenter:
            "Command Center"
        }
    }
}

enum AwayoNoteStyle: String, CaseIterable {
    case tapedPaper
    case stickyStack
    case glassCard
    case markerCard

    var title: String {
        switch self {
        case .tapedPaper:
            "Taped Paper"
        case .stickyStack:
            "Sticky Stack"
        case .glassCard:
            "Glass Card"
        case .markerCard:
            "Marker Card"
        }
    }
}
