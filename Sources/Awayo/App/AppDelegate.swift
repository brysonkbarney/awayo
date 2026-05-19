import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = AwayoController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.shutdown()
    }
}
