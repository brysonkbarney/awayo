import Foundation

enum LockScreenController {
    enum LockScreenError: LocalizedError {
        case missingSystemLockTool
        case launchFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingSystemLockTool:
                "Awayo could not find the macOS Lock Screen tool."
            case .launchFailed(let message):
                "Awayo could not open the macOS Lock Screen. \(message)"
            }
        }
    }

    static func lock() throws {
        let path = "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"

        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw LockScreenError.missingSystemLockTool
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-suspend"]

        do {
            try process.run()
        } catch {
            throw LockScreenError.launchFailed(error.localizedDescription)
        }
    }
}
