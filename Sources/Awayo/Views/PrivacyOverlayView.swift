import AppKit

@MainActor
final class PrivacyOverlayView: NSView {
    let unlockField = NSSecureTextField()

    private let messageLabel = NSTextField(labelWithString: "")
    private let countdownLabel = NSTextField(labelWithString: "")
    private let passcode: String
    private let showsUnlockField: Bool
    private let onUnlock: () -> Void

    init(
        message: String,
        endDate: Date?,
        passcode: String,
        showsUnlockField: Bool,
        onUnlock: @escaping () -> Void
    ) {
        self.passcode = passcode
        self.showsUnlockField = showsUnlockField
        self.onUnlock = onUnlock
        super.init(frame: .zero)

        wantsLayer = true
        setupView(message: message, endDate: endDate, showsUnlockField: showsUnlockField)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if showsUnlockField {
            window?.makeFirstResponder(unlockField)
        }
    }

    override func layout() {
        super.layout()

        let availableWidth = max(260, bounds.width - 96)
        messageLabel.preferredMaxLayoutWidth = min(860, availableWidth)
        messageLabel.font = .systemFont(ofSize: bounds.width < 760 ? 30 : 42, weight: .bold)
        countdownLabel.font = .monospacedDigitSystemFont(ofSize: bounds.width < 760 ? 18 : 24, weight: .medium)
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
                + DurationFormatter.awayoString(from: max(0, endDate.timeIntervalSinceNow))
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
        messageLabel.textColor = .white
        messageLabel.alignment = .center
        messageLabel.maximumNumberOfLines = 4
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

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

        let footer = NSTextField(labelWithString: "Privacy cover only. Use Lock + Keep Awake for real security.")
        footer.font = .systemFont(ofSize: 13, weight: .medium)
        footer.textColor = NSColor.white.withAlphaComponent(0.42)
        footer.alignment = .center
        footer.maximumNumberOfLines = 2
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
}
