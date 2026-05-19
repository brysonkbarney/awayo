import AppKit

@MainActor
final class PrivacyOverlayController: NSObject {
    private struct Configuration {
        let message: String
        let endDate: Date?
        let passcode: String
        let onUnlock: () -> Void
    }

    private var windows: [NSWindow] = []
    private var overlayViews: [PrivacyOverlayView] = []
    private var configuration: Configuration?
    private var previousPresentationOptions: NSApplication.PresentationOptions?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func show(message: String, endDate: Date?, passcode: String, onUnlock: @escaping () -> Void) {
        configuration = Configuration(
            message: message,
            endDate: endDate,
            passcode: passcode,
            onUnlock: onUnlock
        )

        if previousPresentationOptions == nil {
            previousPresentationOptions = NSApp.presentationOptions
        }

        NSApp.presentationOptions = [
            .hideDock,
            .hideMenuBar,
            .disableHideApplication,
            .disableProcessSwitching
        ]

        NSApp.activate(ignoringOtherApps: true)
        rebuildWindows()
    }

    func update(endDate: Date?) {
        overlayViews.forEach { $0.update(endDate: endDate) }
    }

    func hide() {
        closeWindows()
        configuration = nil

        if let previousPresentationOptions {
            NSApp.presentationOptions = previousPresentationOptions
            self.previousPresentationOptions = nil
        }
    }

    @objc private func screenParametersChanged() {
        guard configuration != nil else {
            return
        }

        rebuildWindows()
    }

    private func rebuildWindows() {
        guard let configuration else {
            return
        }

        closeWindows()

        let mainScreen = NSScreen.main
        var mainWindow: NSWindow?
        var mainUnlockField: NSSecureTextField?

        windows = NSScreen.screens.map { screen in
            let isMainDisplay = screen == mainScreen
            let view = PrivacyOverlayView(
                message: configuration.message,
                endDate: configuration.endDate,
                passcode: configuration.passcode,
                showsUnlockField: isMainDisplay,
                onUnlock: configuration.onUnlock
            )

            let window = PrivacyOverlayWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.level = .screenSaver
            window.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .stationary
            ]
            window.backgroundColor = .black
            window.isOpaque = true
            window.isReleasedWhenClosed = false
            window.contentView = view
            window.orderFrontRegardless()

            overlayViews.append(view)

            if isMainDisplay {
                mainWindow = window
                mainUnlockField = view.unlockField
            }

            return window
        }

        mainWindow?.makeKeyAndOrderFront(nil)

        if let mainUnlockField {
            mainWindow?.makeFirstResponder(mainUnlockField)
        }
    }

    private func closeWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        overlayViews.removeAll()
    }
}

private final class PrivacyOverlayWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}
