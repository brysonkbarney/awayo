import AppKit
import Foundation

@MainActor
final class AwayoController: NSObject {
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
            let status = NSMenuItem(title: "\(session.mode.title): \(remainingLabel(for: session))", action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)
            menu.addItem(NSMenuItem.separator())
        }

        let privacyMenu = NSMenu()
        addDurationItems(
            to: privacyMenu,
            action: #selector(startPrivacyCoverFromMenu(_:)),
            suffix: "..."
        )
        menu.setSubmenu(privacyMenu, for: menu.addItem(withTitle: "Privacy Cover", action: nil, keyEquivalent: ""))

        let awakeMenu = NSMenu()
        addDurationItems(
            to: awakeMenu,
            action: #selector(startKeepAwakeFromMenu(_:)),
            suffix: ""
        )
        menu.setSubmenu(awakeMenu, for: menu.addItem(withTitle: "Keep Awake Only", action: nil, keyEquivalent: ""))

        let lockMenu = NSMenu()
        addDurationItems(
            to: lockMenu,
            action: #selector(startLockScreenFromMenu(_:)),
            suffix: ""
        )
        menu.setSubmenu(lockMenu, for: menu.addItem(withTitle: "Lock + Keep Awake", action: nil, keyEquivalent: ""))

        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: "Custom Duration...", action: #selector(startCustomDuration)))

        if session != nil {
            menu.addItem(menuItem(title: "Stop Awayo", action: #selector(stopAwayo)))
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: "About Awayo", action: #selector(showAbout)))
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

    private func addDurationItems(to menu: NSMenu, action: Selector, suffix: String) {
        DurationPreset.standard.forEach { preset in
            let item = menuItem(title: preset.title + suffix, action: action)
            item.representedObject = preset.representedValue
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
        guard startSession(mode: .locked, duration: duration(from: sender), message: "Keeping your Mac awake") else {
            return
        }

        do {
            try LockScreenController.lock()
        } catch {
            showError(error.localizedDescription)
        }
    }

    @objc private func startPrivacyCoverFromMenu(_ sender: NSMenuItem) {
        let duration = duration(from: sender)
        let details = promptForPrivacyCoverDetails(duration: duration)

        guard let details else {
            return
        }

        guard startSession(mode: .privacy, duration: duration, message: details.message) else {
            return
        }

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
        alert.informativeText = "Enter a custom duration in minutes."
        alert.alertStyle = .informational

        let durationField = NSTextField(string: "30")
        durationField.placeholderString = "Minutes"
        durationField.frame = NSRect(x: 0, y: 0, width: 240, height: 24)

        alert.accessoryView = durationField
        alert.addButton(withTitle: "Privacy Cover")
        alert.addButton(withTitle: "Keep Awake")
        alert.addButton(withTitle: "Lock + Keep Awake")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response.rawValue != NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + 3 else {
            return
        }

        let minutes = Double(durationField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 30
        let duration = max(1, minutes) * 60
        let fakeSender = NSMenuItem()
        fakeSender.representedObject = NSNumber(value: duration)

        switch response.rawValue {
        case NSApplication.ModalResponse.alertFirstButtonReturn.rawValue:
            startPrivacyCoverFromMenu(fakeSender)
        case NSApplication.ModalResponse.alertSecondButtonReturn.rawValue:
            startKeepAwakeFromMenu(fakeSender)
        case NSApplication.ModalResponse.alertThirdButtonReturn.rawValue:
            startLockScreenFromMenu(fakeSender)
        default:
            break
        }
    }

    @objc private func stopAwayo() {
        stopSession()
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Awayo"
        alert.informativeText = """
        Step away. Stay running.

        Privacy Cover is a casual screen cover, not a security boundary. Use Lock + Keep Awake when the Mac should be protected by the native macOS Lock Screen.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quitAwayo() {
        NSApp.terminate(nil)
    }

    @discardableResult
    private func startSession(mode: AwayoSession.Mode, duration: TimeInterval?, message: String) -> Bool {
        stopSession()

        do {
            try powerManager.start(keepDisplayAwake: mode == .privacy, reason: "Awayo \(mode.title)")
        } catch {
            showError(error.localizedDescription)
            return false
        }

        let endDate = duration.map { Date().addingTimeInterval($0) }
        session = AwayoSession(mode: mode, endDate: endDate, message: message)
        scheduleTick()
        refreshMenu()
        return true
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
        messageField.frame.size.width = 340

        let passcodeField = NSSecureTextField()
        passcodeField.placeholderString = "Passcode to dismiss"
        passcodeField.frame.size.width = 340

        stack.addArrangedSubview(label("Away message"))
        stack.addArrangedSubview(messageField)
        stack.addArrangedSubview(label("Passcode"))
        stack.addArrangedSubview(passcodeField)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 118))
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
            showError("Privacy Cover needs a passcode for this version.")
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

        return DurationFormatter.awayoString(from: max(0, endDate.timeIntervalSinceNow))
    }

    private func shortRemainingLabel(for session: AwayoSession) -> String {
        guard let endDate = session.endDate else {
            return "On"
        }

        return DurationFormatter.awayoString(from: max(0, endDate.timeIntervalSinceNow))
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Awayo"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
