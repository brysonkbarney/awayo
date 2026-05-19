import Foundation

enum DurationFormatter {
    static func awayoString(from interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = interval >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.maximumUnitCount = 2
        formatter.unitsStyle = .abbreviated

        return formatter.string(from: interval) ?? "0s"
    }
}
