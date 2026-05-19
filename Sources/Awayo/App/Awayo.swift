import AppKit

@main
enum Awayo {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()

        app.delegate = delegate
        app.setActivationPolicy(.accessory)

        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
