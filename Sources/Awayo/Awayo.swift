import AppKit
import Foundation
import IOKit.pwr_mgt

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

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = AwayoController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.shutdown()
    }
}

@MainActor
private final class AwayoController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let powerManager = PowerAssertionManager()
    private let privacyOverlay = PrivacyOverlayController()
    private var session: AwayoSession?
    private var tickTimer: Timer?

    func start() {
        configureStatusItem()
        refreshMenu()
    }

    func shutdown() {
        stopSession()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        if let image = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: "Awayo") {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "Awayo"
        }

        button.toolTip = "Awayo"
    }

    private func refreshMenu() {
        let menu = NSMenu()

        if let session {
            let title = "\(session.mode.title): \(remainingLabel(for: session))"
            let status = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)
            menu.addItem(NSMenuItem.separator())
        }

        let privacyMenu = NSMenu()
        addDurationItems(
            to: privacyMenu,
            action: #selector(startPrivacyCoverFromMenu(_:)),
            includeIndefinite: true,
            suffix: "..."
        )
        menu.setSubmenu(privacyMenu, for: menu.addItem(withTitle: "Privacy Cover", action: nil, keyEquivalent: ""))

        let awakeMenu = NSMenu()
        addDurationItems(
            to: awakeMenu,
            action: #selector(startKeepAwakeFromMenu(_:)),
            includeIndefinite: true,
            suffix: ""
        )
        menu.setSubmenu(awakeMenu, for: menu.addItem(withTitle: "Keep Awake Only", action: nil, keyEquivalent: ""))

        let lockMenu = NSMenu()
        addDurationItems(
            to: lockMenu,
            action: #selector(startLockScreenFromMenu(_:)),
            includeIndefinite: true,
            suffix: ""
        )
        menu.setSubmenu(lockMenu, for: menu.addItem(withTitle: "Lock + Keep Awake", action: nil, keyEquivalent: ""))

        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: "Custom Duration...", action: #selector(startCustomDuration)))

        if session != nil {
            menu.addItem(menuItem(title: "Stop Awayo", action: #selector(stopAwayo)))
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: "Quit Awayo", action: #selector(quitAwayo), keyEquivalent: "q"))

        statusItem.menu = menu
        refreshStatusButton()
    }

    private func refreshStatusButton() {
        guard let button = statusItem.button else {
            return
        }

        if let session {
            button.title = " \(shortRemainingLabel(for: session))"
        } else {
            button.title = ""
        }
    }

    private func addDurationItems(to menu: NSMenu, action: Selector, includeIndefinite: Bool, suffix: String) {
        [
            ("15 Minutes", 15 * 60),
            ("30 Minutes", 30 * 60),
            ("1 Hour", 60 * 60),
            ("2 Hours", 2 * 60 * 60)
        ].forEach { title, seconds in
            let item = menuItem(title: title + suffix, action: action)
            item.representedObject = NSNumber(value: seconds)
            menu.addItem(item)
        }

        if includeIndefinite {
            menu.addItem(NSMenuItem.separator())
            let item = menuItem(title: "Until Stopped" + suffix, action: action)
            item.representedObject = NSNumber(value: -1)
            menu.addItem(item)
        }
    }

    private func menuItem(title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    @objc private func startKeepAwakeFromMenu(_ sender: NSMenuItem) {
        startSession(mode: .awake, duration: duration(from: sender), message: "Keeping your Mac awake")
    }

    @objc private func startLockScreenFromMenu(_ sender: NSMenuItem) {
        startSession(mode: .locked, duration: duration(from: sender), message: "Keeping your Mac awake")
        lockScreen()
    }

    @objc private func startPrivacyCoverFromMenu(_ sender: NSMenuItem) {
        let duration = duration(from: sender)
        let details = promptForPrivacyCoverDetails(duration: duration)

        guard let details else {
            return
        }

        startSession(mode: .privacy, duration: duration, message: details.message)

        guard let session else {
            return
        }

        privacyOverlay.show(
            message: details.message,
            endDate: session.endDate,
            passcode: details.passcode
        ) { [weak self] in
            self?.stopSession()
        }
    }

    @objc private func startCustomDuration() {
        let alert = NSAlert()
        alert.messageText = "Start Awayo"
        alert.informativeText = "Enter a duration in minutes."
        alert.alertStyle = .informational

        let durationField = NSTextField(string: "30")
        durationField.placeholderString = "Minutes"
        durationField.frame = NSRect(x: 0, y: 0, width: 220, height: 24)
        alert.accessoryView = durationField
        alert.addButton(withTitle: "Privacy Cover")
        alert.addButton(withTitle: "Keep Awake")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response != .alertThirdButtonReturn else {
            return
        }

        let minutes = Double(durationField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 30
        let duration = max(1, minutes) * 60

        if response == .alertFirstButtonReturn {
            let fakeSender = NSMenuItem()
            fakeSender.representedObject = NSNumber(value: duration)
            startPrivacyCoverFromMenu(fakeSender)
        } else {
            startSession(mode: .awake, duration: duration, message: "Keeping your Mac awake")
        }
    }

    @objc private func stopAwayo() {
        stopSession()
    }

    @objc private func quitAwayo() {
        NSApp.terminate(nil)
    }

    private func startSession(mode: AwayoSession.Mode, duration: TimeInterval?, message: String) {
        stopSession()

        let keepDisplayAwake = mode == .privacy
        guard powerManager.start(keepDisplayAwake: keepDisplayAwake, reason: "Awayo \(mode.title)") else {
            showError("Awayo could not create a macOS keep-awake assertion.")
            return
        }

        let endDate = duration.map { Date().addingTimeInterval($0) }
        session = AwayoSession(mode: mode, endDate: endDate, message: message)
        scheduleTick()
        refreshMenu()
    }

    private func stopSession() {
        tickTimer?.invalidate()
        tickTimer = nil
        session = nil
        privacyOverlay.hide()
        powerManager.stop()
        refreshMenu()
    }

    private func scheduleTick() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(
            timeInterval: 1,
            target: self,
            selector: #selector(tickTimerFired),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func tickTimerFired() {
        tick()
    }

    private func tick() {
        guard let session else {
            return
        }

        if let endDate = session.endDate, Date() >= endDate {
            stopSession()
            return
        }

        privacyOverlay.update(endDate: session.endDate)
        refreshStatusButton()
        refreshMenu()
    }

    private func duration(from sender: NSMenuItem) -> TimeInterval? {
        guard let seconds = (sender.representedObject as? NSNumber)?.doubleValue, seconds > 0 else {
            return nil
        }

        return seconds
    }

    private func promptForPrivacyCoverDetails(duration: TimeInterval?) -> PrivacyCoverDetails? {
        let alert = NSAlert()
        alert.messageText = "Start Privacy Cover"
        alert.informativeText = "Choose the note people will see and the passcode that dismisses the cover."
        alert.alertStyle = .informational

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let messageField = NSTextField(string: defaultPrivacyMessage(duration: duration))
        messageField.placeholderString = "Message"
        messageField.frame.size.width = 320

        let passcodeField = NSSecureTextField()
        passcodeField.placeholderString = "Passcode to dismiss"
        passcodeField.frame.size.width = 320

        stack.addArrangedSubview(label("Away message"))
        stack.addArrangedSubview(messageField)
        stack.addArrangedSubview(label("Passcode"))
        stack.addArrangedSubview(passcodeField)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 118))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        alert.accessoryView = container
        alert.addButton(withTitle: "Start")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }

        let passcode = passcodeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !passcode.isEmpty else {
            showError("Privacy Cover needs a passcode for this MVP.")
            return nil
        }

        let message = messageField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return PrivacyCoverDetails(
            message: message.isEmpty ? "Away for a minute. Work is still running." : message,
            passcode: passcode
        )
    }

    private func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func defaultPrivacyMessage(duration: TimeInterval?) -> String {
        guard let duration else {
            return "Away for a minute. Work is still running."
        }

        let backAt = Date().addingTimeInterval(duration).formatted(date: .omitted, time: .shortened)
        return "Away for a minute. Back around \(backAt)."
    }

    private func remainingLabel(for session: AwayoSession) -> String {
        guard let endDate = session.endDate else {
            return "until stopped"
        }

        return formattedDuration(from: max(0, endDate.timeIntervalSinceNow))
    }

    private func shortRemainingLabel(for session: AwayoSession) -> String {
        guard let endDate = session.endDate else {
            return "On"
        }

        return formattedDuration(from: max(0, endDate.timeIntervalSinceNow))
    }

    private func formattedDuration(from interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = interval >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: interval) ?? "0s"
    }

    private func lockScreen() {
        let process = Process()
        process.executableURL = URL(
            fileURLWithPath: "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
        )
        process.arguments = ["-suspend"]

        do {
            try process.run()
        } catch {
            showError("Awayo could not open the macOS Lock Screen.")
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Awayo"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

private struct AwayoSession {
    enum Mode {
        case awake
        case privacy
        case locked

        var title: String {
            switch self {
            case .awake:
                "Awake"
            case .privacy:
                "Privacy Cover"
            case .locked:
                "Locked"
            }
        }
    }

    let mode: Mode
    let endDate: Date?
    let message: String
}

private struct PrivacyCoverDetails {
    let message: String
    let passcode: String
}

private final class PowerAssertionManager {
    private var systemAssertionID: IOPMAssertionID = 0
    private var displayAssertionID: IOPMAssertionID = 0

    func start(keepDisplayAwake: Bool, reason: String) -> Bool {
        stop()

        let systemResult = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoIdleSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &systemAssertionID
        )

        guard systemResult == kIOReturnSuccess else {
            return false
        }

        if keepDisplayAwake {
            _ = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason as CFString,
                &displayAssertionID
            )
        }

        return true
    }

    func stop() {
        release(&displayAssertionID)
        release(&systemAssertionID)
    }

    private func release(_ assertionID: inout IOPMAssertionID) {
        guard assertionID != 0 else {
            return
        }

        IOPMAssertionRelease(assertionID)
        assertionID = 0
    }
}

@MainActor
private final class PrivacyOverlayController {
    private var windows: [NSWindow] = []
    private var overlayViews: [PrivacyOverlayView] = []
    private var previousPresentationOptions: NSApplication.PresentationOptions = []

    func show(message: String, endDate: Date?, passcode: String, onUnlock: @escaping () -> Void) {
        hide()

        previousPresentationOptions = NSApp.presentationOptions
        NSApp.presentationOptions = [
            .hideDock,
            .hideMenuBar,
            .disableHideApplication,
            .disableProcessSwitching
        ]

        NSApp.activate(ignoringOtherApps: true)

        let mainScreen = NSScreen.main
        windows = NSScreen.screens.map { screen in
            let isMainDisplay = screen == mainScreen
            let view = PrivacyOverlayView(
                message: message,
                endDate: endDate,
                passcode: passcode,
                showsUnlockField: isMainDisplay,
                onUnlock: onUnlock
            )

            let window = NSWindow(
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
            window.contentView = view
            window.makeKeyAndOrderFront(nil)

            overlayViews.append(view)

            if isMainDisplay {
                window.makeFirstResponder(view.unlockField)
            }

            return window
        }
    }

    func update(endDate: Date?) {
        overlayViews.forEach { $0.update(endDate: endDate) }
    }

    func hide() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        overlayViews.removeAll()
        NSApp.presentationOptions = previousPresentationOptions
    }
}

@MainActor
private final class PrivacyOverlayView: NSView {
    let unlockField = NSSecureTextField()

    private let messageLabel = NSTextField(labelWithString: "")
    private let countdownLabel = NSTextField(labelWithString: "")
    private let passcode: String
    private let onUnlock: () -> Void

    init(
        message: String,
        endDate: Date?,
        passcode: String,
        showsUnlockField: Bool,
        onUnlock: @escaping () -> Void
    ) {
        self.passcode = passcode
        self.onUnlock = onUnlock
        super.init(frame: .zero)

        wantsLayer = true
        setupView(message: message, endDate: endDate, showsUnlockField: showsUnlockField)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.03, green: 0.04, blue: 0.07, alpha: 1),
            NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.13, alpha: 1),
            NSColor(calibratedRed: 0.03, green: 0.12, blue: 0.12, alpha: 1)
        ])

        gradient?.draw(in: bounds, angle: -28)
    }

    func update(endDate: Date?) {
        if let endDate {
            countdownLabel.stringValue = "Back around \(endDate.formatted(date: .omitted, time: .shortened))"
                + "  /  "
                + formattedDuration(from: max(0, endDate.timeIntervalSinceNow))
        } else {
            countdownLabel.stringValue = "Running until stopped"
        }
    }

    private func setupView(message: String, endDate: Date?, showsUnlockField: Bool) {
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .centerX
        content.spacing = 18
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        let badge = NSTextField(labelWithString: "Awayo")
        badge.font = .systemFont(ofSize: 18, weight: .bold)
        badge.textColor = NSColor.white.withAlphaComponent(0.74)

        messageLabel.stringValue = message
        messageLabel.font = .systemFont(ofSize: 42, weight: .bold)
        messageLabel.textColor = .white
        messageLabel.alignment = .center
        messageLabel.maximumNumberOfLines = 3
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.preferredMaxLayoutWidth = 840

        countdownLabel.font = .monospacedDigitSystemFont(ofSize: 24, weight: .medium)
        countdownLabel.textColor = NSColor.white.withAlphaComponent(0.78)
        countdownLabel.alignment = .center
        update(endDate: endDate)

        content.addArrangedSubview(badge)
        content.addArrangedSubview(messageLabel)
        content.addArrangedSubview(countdownLabel)

        if showsUnlockField {
            unlockField.placeholderString = "Passcode"
            unlockField.font = .systemFont(ofSize: 18, weight: .medium)
            unlockField.alignment = .center
            unlockField.target = self
            unlockField.action = #selector(checkPasscode)
            unlockField.translatesAutoresizingMaskIntoConstraints = false
            content.addArrangedSubview(unlockField)
            unlockField.widthAnchor.constraint(equalToConstant: 260).isActive = true
        } else {
            let hint = NSTextField(labelWithString: "Unlock from the main display")
            hint.font = .systemFont(ofSize: 15, weight: .medium)
            hint.textColor = NSColor.white.withAlphaComponent(0.52)
            content.addArrangedSubview(hint)
        }

        let footer = NSTextField(labelWithString: "Privacy cover only")
        footer.font = .systemFont(ofSize: 13, weight: .medium)
        footer.textColor = NSColor.white.withAlphaComponent(0.42)
        content.addArrangedSubview(footer)

        NSLayoutConstraint.activate([
            content.centerXAnchor.constraint(equalTo: centerXAnchor),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
            content.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 48),
            content.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -48)
        ])
    }

    @objc private func checkPasscode() {
        guard unlockField.stringValue == passcode else {
            NSSound.beep()
            unlockField.stringValue = ""
            return
        }

        onUnlock()
    }

    private func formattedDuration(from interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = interval >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: interval) ?? "0s"
    }
}
