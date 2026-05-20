import AppKit
import Foundation

@MainActor
final class AwayoController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let powerManager = PowerAssertionManager()
    private let privacyOverlay = PrivacyOverlayController()
    private let passcodeStore = PasscodeStore()
    private let defaults = UserDefaults.standard
    private lazy var settingsStore = AwayoSettingsStore(defaults: defaults)
    private lazy var settingsWindowController = AwayoSettingsWindowController(
        settingsStore: settingsStore,
        passcodeStore: passcodeStore
    ) { [weak self] in
        self?.refreshMenu()
    }

    private var session: AwayoSession?
    private var tickTimer: Timer?

    func start() {
        configureStatusItem()
        refreshMenu()

        if !settingsStore.hasCompletedFirstRun {
            DispatchQueue.main.async { [weak self] in
                self?.showSettings(onboarding: true)
            }
        }
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

        button.toolTip = "don't let your agents die."
    }

    private func refreshMenu() {
        let menu = NSMenu()

        if let session {
            let status = NSMenuItem(title: "\(session.mode.title): \(remainingLabel(for: session))", action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)
            menu.addItem(NSMenuItem.separator())
        }

        let privacyMenu = NSMenu(title: "Awayo Lock")
        addDurationItems(
            to: privacyMenu,
            action: #selector(startPrivacyCoverFromMenu(_:)),
            suffix: "..."
        )
        privacyMenu.addItem(NSMenuItem.separator())
        privacyMenu.addItem(menuItem(title: "Awayo Settings...", action: #selector(openSettings), symbol: "gearshape"))
        let privacyItem = submenuItem(title: "Awayo Lock", symbol: "lock.rectangle")
        menu.addItem(privacyItem)
        menu.setSubmenu(privacyMenu, for: privacyItem)

        let awakeMenu = NSMenu(title: "Keep Awake Only")
        addDurationItems(
            to: awakeMenu,
            action: #selector(startKeepAwakeFromMenu(_:)),
            suffix: ""
        )
        let awakeItem = submenuItem(title: "Keep Awake Only", symbol: "cup.and.saucer")
        menu.addItem(awakeItem)
        menu.setSubmenu(awakeMenu, for: awakeItem)

        let lockMenu = NSMenu(title: "macOS Lock + Keep Awake")
        addDurationItems(
            to: lockMenu,
            action: #selector(startLockScreenFromMenu(_:)),
            suffix: ""
        )
        let lockItem = submenuItem(title: "macOS Lock + Keep Awake", symbol: "lock.display")
        menu.addItem(lockItem)
        menu.setSubmenu(lockMenu, for: lockItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",", symbol: "gearshape"))
        menu.addItem(menuItem(title: "Custom Duration...", action: #selector(startCustomDuration), symbol: "timer"))
        addDebugPreviewMenu(to: menu)

        if session != nil {
            menu.addItem(menuItem(title: "Stop Awayo", action: #selector(stopAwayo), symbol: "stop.circle"))
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: "About Awayo", action: #selector(showAbout), symbol: "info.circle"))
        menu.addItem(menuItem(title: "Quit Awayo", action: #selector(quitAwayo), keyEquivalent: "q", symbol: "xmark.circle"))

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
            let item = menuItem(title: preset.title + suffix, action: action, symbol: "clock")
            item.representedObject = preset.representedValue
            menu.addItem(item)
        }
    }

    private func menuItem(title: String, action: Selector, keyEquivalent: String = "", symbol: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.image = symbol.flatMap {
            NSImage(systemSymbolName: $0, accessibilityDescription: title)
        }
        return item
    }

    private func submenuItem(title: String, symbol: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }

    private func addDebugPreviewMenu(to menu: NSMenu) {
        menu.addItem(NSMenuItem.separator())

        let debugItem = submenuItem(title: "Debug Preview", symbol: "hammer")
        let debugMenu = NSMenu(title: "Debug Preview")

        debugMenu.addItem(menuItem(
            title: "Current Settings (90 Seconds)",
            action: #selector(startDebugCurrentPreview),
            symbol: "play.rectangle"
        ))
        debugMenu.addItem(NSMenuItem.separator())
        addDebugBackgroundMenu(to: debugMenu)
        addDebugTimerMenu(to: debugMenu)
        addDebugDashboardMenu(to: debugMenu)
        addDebugNoteMenu(to: debugMenu)

        menu.addItem(debugItem)
        menu.setSubmenu(debugMenu, for: debugItem)
    }

    private func addDebugBackgroundMenu(to menu: NSMenu) {
        let item = submenuItem(title: "Backgrounds", symbol: "photo")
        let submenu = NSMenu(title: "Backgrounds")
        AwayoLockStyle.allCases.forEach { style in
            let previewItem = menuItem(title: style.title, action: #selector(startDebugBackgroundPreview(_:)))
            previewItem.representedObject = style.rawValue
            submenu.addItem(previewItem)
        }
        menu.addItem(item)
        menu.setSubmenu(submenu, for: item)
    }

    private func addDebugTimerMenu(to menu: NSMenu) {
        let item = submenuItem(title: "Timers", symbol: "timer")
        let submenu = NSMenu(title: "Timers")
        AwayoTimerStyle.allCases.forEach { style in
            let previewItem = menuItem(title: style.title, action: #selector(startDebugTimerPreview(_:)))
            previewItem.representedObject = style.rawValue
            submenu.addItem(previewItem)
        }
        menu.addItem(item)
        menu.setSubmenu(submenu, for: item)
    }

    private func addDebugDashboardMenu(to menu: NSMenu) {
        let item = submenuItem(title: "Dashboards", symbol: "rectangle.center.inset.filled")
        let submenu = NSMenu(title: "Dashboards")
        AwayoDashboardStyle.allCases.forEach { style in
            let previewItem = menuItem(title: style.title, action: #selector(startDebugDashboardPreview(_:)))
            previewItem.representedObject = style.rawValue
            submenu.addItem(previewItem)
        }
        menu.addItem(item)
        menu.setSubmenu(submenu, for: item)
    }

    private func addDebugNoteMenu(to menu: NSMenu) {
        let item = submenuItem(title: "Sticky Notes", symbol: "note.text")
        let submenu = NSMenu(title: "Sticky Notes")
        AwayoNoteStyle.allCases.forEach { style in
            let previewItem = menuItem(title: style.title, action: #selector(startDebugNotePreview(_:)))
            previewItem.representedObject = style.rawValue
            submenu.addItem(previewItem)
        }
        menu.addItem(item)
        menu.setSubmenu(submenu, for: item)
    }

    @objc private func startKeepAwakeFromMenu(_ sender: NSMenuItem) {
        startSession(mode: .awake, duration: duration(from: sender), message: "Keeping your agents alive")
    }

    @objc private func startLockScreenFromMenu(_ sender: NSMenuItem) {
        guard startSession(mode: .locked, duration: duration(from: sender), message: "Keeping your agents alive") else {
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
        let details = promptForAwayoLockDetails(duration: duration)

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
            appearance: settingsStore.appearance(),
            verifyPasscode: { [passcodeStore] passcode in
                passcodeStore.verify(passcode)
            }
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
        alert.addButton(withTitle: "Awayo Lock")
        alert.addButton(withTitle: "Keep Awake")
        alert.addButton(withTitle: "macOS Lock")
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

    @objc private func startDebugCurrentPreview() {
        startDebugPreview(label: "current settings", appearance: settingsStore.appearance())
    }

    @objc private func startDebugBackgroundPreview(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let style = AwayoLockStyle(rawValue: rawValue)
        else {
            return
        }

        var appearance = settingsStore.appearance()
        appearance.backgroundStyle = style
        startDebugPreview(label: "background: \(style.title)", appearance: appearance)
    }

    @objc private func startDebugTimerPreview(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let style = AwayoTimerStyle(rawValue: rawValue)
        else {
            return
        }

        var appearance = settingsStore.appearance()
        appearance.timerStyle = style
        startDebugPreview(label: "timer: \(style.title)", appearance: appearance)
    }

    @objc private func startDebugDashboardPreview(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let style = AwayoDashboardStyle(rawValue: rawValue)
        else {
            return
        }

        var appearance = settingsStore.appearance()
        appearance.dashboardStyle = style
        startDebugPreview(label: "dashboard: \(style.title)", appearance: appearance)
    }

    @objc private func startDebugNotePreview(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let style = AwayoNoteStyle(rawValue: rawValue)
        else {
            return
        }

        var appearance = settingsStore.appearance()
        appearance.noteStyle = style
        startDebugPreview(label: "sticky notes: \(style.title)", appearance: appearance)
    }

    private func startDebugPreview(label: String, appearance: AwayoAppearance) {
        guard ensureAwayoLockPasscodeExists() else {
            return
        }

        let duration: TimeInterval = 90
        let message = "debug preview: \(label)"
        guard startSession(mode: .privacy, duration: duration, message: message), let session else {
            return
        }

        privacyOverlay.show(
            message: message,
            endDate: session.endDate,
            appearance: appearance,
            showsDebugSampleNotes: true,
            verifyPasscode: { [passcodeStore] passcode in
                passcodeStore.verify(passcode)
            }
        ) { [weak self] in
            self?.stopSession()
        }
    }

    @objc private func stopAwayo() {
        stopSession()
    }

    @objc private func setAwayoLockPasscode() {
        showSettings(onboarding: false)
    }

    @objc private func openSettings() {
        showSettings(onboarding: false)
    }

    private func showSettings(onboarding: Bool) {
        settingsWindowController.show(onboarding: onboarding)
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Awayo"
        alert.informativeText = """
        don't let your agents die.

        Keep your Mac awake behind Awayo Lock. It covers your displays with a passcode screen while agents, scripts, and long-running tasks keep going.

        Awayo Lock covers your screen; it is not the macOS Lock Screen. For full security, use macOS Lock + Keep Awake.
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

    private func promptForAwayoLockDetails(duration: TimeInterval?) -> AwayoLockDetails? {
        guard ensureAwayoLockPasscodeExists() else {
            return nil
        }

        let alert = NSAlert()
        alert.messageText = "Start Awayo Lock"
        alert.informativeText = "Keep your Mac awake behind Awayo Lock. Choose the note people will see while your work keeps running."
        alert.alertStyle = .informational

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let messageField = NSTextField(string: defaultPrivacyMessage(duration: duration))
        messageField.placeholderString = "Message"
        messageField.frame.size.width = 340

        stack.addArrangedSubview(label("Away message"))
        stack.addArrangedSubview(messageField)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 54))
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

        let message = messageField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        return AwayoLockDetails(
            message: message.isEmpty ? "brb, agents are running" : message
        )
    }

    private func ensureAwayoLockPasscodeExists() -> Bool {
        if passcodeStore.hasPasscode() {
            return true
        }

        showSettings(onboarding: true)
        return false
    }

    private func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func defaultPrivacyMessage(duration _: TimeInterval?) -> String {
        "brb, agents are running"
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
