import Foundation

struct AgentSession: Equatable {
    enum State: String, Codable {
        case working
        case readyForInput = "ready_for_input"
        case waiting
        case quiet
        case alive

        var label: String {
            switch self {
            case .working:
                "working"
            case .readyForInput:
                "needs you"
            case .waiting:
                "waiting"
            case .quiet:
                "quiet"
            case .alive:
                "alive"
            }
        }
    }

    let name: String
    let detail: String
    let state: State

    var displayLine: String {
        "\(name) - \(detail)"
    }
}
