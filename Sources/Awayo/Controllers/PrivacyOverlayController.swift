import AppKit
import CoreGraphics

@MainActor
final class PrivacyOverlayController: NSObject {
    private struct Configuration {
        let message: String
        let endDate: Date?
        let appearance: AwayoAppearance
        let verifyPasscode: (String) -> Bool
        let onUnlock: () -> Void
    }

    private var windows: [NSWindow] = []
    private var overlayViews: [PrivacyOverlayView] = []
    private var configuration: Configuration?
    private var previousPresentationOptions: NSApplication.PresentationOptions?
    private var enforcementTimer: Timer?
    private var localEventMonitor: Any?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func show(
        message: String,
        endDate: Date?,
        appearance: AwayoAppearance,
        verifyPasscode: @escaping (String) -> Bool,
        onUnlock: @escaping () -> Void
    ) {
        configuration = Configuration(
            message: message,
            endDate: endDate,
            appearance: appearance,
            verifyPasscode: verifyPasscode,
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
        startEventGuard()
        startEnforcementTimer()
        rebuildWindows()
    }

    func update(endDate: Date?) {
        overlayViews.forEach { $0.update(endDate: endDate) }
    }

    func hide() {
        stopEventGuard()
        stopEnforcementTimer()
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

    @objc private func applicationDidResignActive() {
        guard configuration != nil else {
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        bringWindowsForward()
    }

    @objc private func activeSpaceChanged() {
        guard configuration != nil else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.configuration != nil else {
                return
            }

            self.rebuildWindows()
            self.bringWindowsForward()
        }
    }

    private func rebuildWindows() {
        guard let configuration else {
            return
        }

        closeWindows()

        let mainScreen = NSScreen.main
        var mainWindow: NSWindow?
        var mainOverlayView: PrivacyOverlayView?

        windows = NSScreen.screens.map { screen in
            let isMainDisplay = screen == mainScreen
            let view = PrivacyOverlayView(
                message: configuration.message,
                endDate: configuration.endDate,
                appearance: configuration.appearance,
                verifyPasscode: configuration.verifyPasscode,
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
            window.level = .awayoLock
            window.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .ignoresCycle,
                .stationary
            ]
            window.backgroundColor = .black
            window.hasShadow = false
            window.hidesOnDeactivate = false
            window.isOpaque = true
            window.isMovable = false
            window.isReleasedWhenClosed = false
            window.setFrame(screen.frame, display: true)
            window.contentView = view
            window.orderFrontRegardless()

            overlayViews.append(view)

            if isMainDisplay {
                mainWindow = window
                mainOverlayView = view
            }

            return window
        }

        mainWindow?.makeKeyAndOrderFront(nil)
        mainOverlayView?.focusUnlockFieldIfAppropriate()
    }

    @objc private func enforceLockSurface() {
        guard configuration != nil else {
            return
        }

        if windows.count != NSScreen.screens.count {
            rebuildWindows()
            return
        }

        bringWindowsForward()
    }

    private func bringWindowsForward() {
        windows.forEach { window in
            if let screen = window.screen {
                window.setFrame(screen.frame, display: true)
            }

            window.level = .awayoLock
            window.orderFrontRegardless()
        }

        let mainWindow = windows.first { $0.screen == NSScreen.main } ?? windows.first
        mainWindow?.makeKeyAndOrderFront(nil)

        (mainWindow?.contentView as? PrivacyOverlayView)?.focusUnlockFieldIfAppropriate()
    }

    private func closeWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        overlayViews.removeAll()
    }

    private func startEnforcementTimer() {
        enforcementTimer?.invalidate()
        enforcementTimer = Timer.scheduledTimer(
            timeInterval: 0.5,
            target: self,
            selector: #selector(enforceLockSurface),
            userInfo: nil,
            repeats: true
        )
    }

    private func stopEnforcementTimer() {
        enforcementTimer?.invalidate()
        enforcementTimer = nil
    }

    private func startEventGuard() {
        stopEventGuard()

        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .scrollWheel, .swipe, .magnify, .rotate]
        ) { [weak self] event in
            guard self?.configuration != nil else {
                return event
            }

            switch event.type {
            case .scrollWheel, .swipe, .magnify, .rotate:
                return nil
            case .keyDown:
                if event.charactersIgnoringModifiers == " " {
                    self?.overlayViews.forEach { $0.jumpRunnerIfNeeded() }
                    return nil
                }

                let blockedModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
                if event.modifierFlags.intersection(blockedModifiers).isEmpty {
                    return event
                }

                NSSound.beep()
                return nil
            default:
                return event
            }
        }
    }

    private func stopEventGuard() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
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

private extension NSWindow.Level {
    static let awayoLock = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
}
