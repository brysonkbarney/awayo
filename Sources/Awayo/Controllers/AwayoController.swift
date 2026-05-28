import AppKit
import Foundation

@MainActor
final class AwayoController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let powerManager = PowerAssertionManager()
    private let privacyOverlay = PrivacyOverlayController()
    private let hotKeyManager = AwayoHotKeyManager()
    private let passcodeStore = PasscodeStore()
    private let defaults = UserDefaults.standard
    private lazy var settingsStore = AwayoSettingsStore(defaults: defaults)
    private lazy var settingsWindowController = AwayoSettingsWindowController(
        settingsStore: settingsStore,
        passcodeStore: passcodeStore
    ) { [weak self] in
        self?.refreshMenu()
        self?.refreshHotKeyRegistration(showErrors: true)
    }

    private var session: AwayoSession?
    private var tickTimer: Timer?

    func start() {
        configureStatusItem()
        refreshHotKeyRegistration(showErrors: false)
        refreshMenu()

        if !settingsStore.hasCompletedFirstRun {
            DispatchQueue.main.async { [weak self] in
                self?.showSettings(onboarding: true)
            }
        }
    }

    func shutdown() {
        hotKeyManager.unregister()
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
        let settingsAvailable = session?.mode != .privacy

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
        let privacySettingsItem = menuItem(title: "Awayo Settings...", action: #selector(openSettings), symbol: "gearshape")
        privacySettingsItem.isEnabled = settingsAvailable
        privacyMenu.addItem(privacySettingsItem)
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

        menu.addItem(NSMenuItem.separator())
        let settingsItem = menuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",", symbol: "gearshape")
        settingsItem.isEnabled = settingsAvailable
        menu.addItem(settingsItem)
        menu.addItem(menuItem(title: "Custom Duration...", action: #selector(startCustomDuration), symbol: "timer"))

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

    @objc private func startKeepAwakeFromMenu(_ sender: NSMenuItem) {
        startSession(mode: .awake, duration: duration(from: sender), message: "Keeping your agents alive")
    }

    @objc private func startPrivacyCoverFromMenu(_ sender: NSMenuItem) {
        startPrivacyCover(duration: duration(from: sender))
    }

    private func startPrivacyCoverFromHotKey() {
        guard session?.mode != .privacy else {
            return
        }

        guard settingsWindowController.window?.isVisible != true else {
            return
        }

        startPrivacyCover(duration: nil)
    }

    private func startPrivacyCover(duration: TimeInterval?) {

        guard ensureAwayoLockPasscodeExists() else {
            return
        }

        let message = settingsStore.lockMessage()
        settingsWindowController.close()

        guard startSession(mode: .privacy, duration: duration, message: message) else {
            return
        }

        guard let session else {
            return
        }

        privacyOverlay.show(
            message: message,
            endDate: session.endDate,
            appearance: settingsStore.appearance(),
            verifyPasscode: { [passcodeStore] passcode in
                passcodeStore.verify(passcode)
            }
        ) { [weak self] in
            self?.stopSession()
        }
    }

    private func refreshHotKeyRegistration(showErrors: Bool) {
        do {
            try hotKeyManager.register(settingsStore.hotKey()) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.startPrivacyCoverFromHotKey()
                }
            }
        } catch {
            if showErrors {
                showError(error.localizedDescription)
            }
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
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response.rawValue != NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + 2 else {
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
        default:
            break
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
        guard session?.mode != .privacy else {
            return
        }

        settingsWindowController.show(onboarding: onboarding)
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Awayo"
        alert.informativeText = """
        don't let your agents die.

        Keep your Mac awake behind Awayo Lock. It covers your displays with a passcode screen while agents, scripts, and long-running tasks keep going.

        Awayo Lock covers your screen; it is not the macOS Lock Screen.
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

    private func ensureAwayoLockPasscodeExists() -> Bool {
        if passcodeStore.hasPasscode() {
            return true
        }

        showSettings(onboarding: true)
        return false
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
