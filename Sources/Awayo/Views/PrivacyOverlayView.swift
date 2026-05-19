import AppKit

@MainActor
final class PrivacyOverlayView: NSView {
    let unlockField = NSSecureTextField()

    private let badgeLabel = NSTextField(labelWithString: "  AWAYO LOCK  ")
    private let statusLabel = NSTextField(labelWithString: "  WORK IS STILL RUNNING  ")
    private let messageLabel = NSTextField(labelWithString: "")
    private let countdownLabel = NSTextField(labelWithString: "")
    private let backAtLabel = NSTextField(labelWithString: "")
    private let activityLabel = NSTextField(labelWithString: "Agents, scripts, builds, and local services are still moving.")
    private let unlockButton = NSButton(title: "Unlock", target: nil, action: nil)
    private let passcode: String
    private let showsUnlockField: Bool
    private let onUnlock: () -> Void

    private var animationTimer: Timer?
    private var animationPhase: CGFloat = 0

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
        startAnimation()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)

        if newWindow == nil {
            stopAnimation()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if showsUnlockField {
            window?.makeFirstResponder(unlockField)
        }
    }

    override func layout() {
        super.layout()

        let availableWidth = max(300, bounds.width - 96)
        messageLabel.preferredMaxLayoutWidth = min(960, availableWidth)
        messageLabel.font = .systemFont(ofSize: bounds.width < 760 ? 34 : 58, weight: .black)
        countdownLabel.font = .monospacedDigitSystemFont(ofSize: bounds.width < 760 ? 48 : 86, weight: .heavy)
        backAtLabel.font = .systemFont(ofSize: bounds.width < 760 ? 16 : 20, weight: .semibold)
        activityLabel.font = .systemFont(ofSize: bounds.width < 760 ? 14 : 16, weight: .medium)
    }

    override func draw(_ dirtyRect: NSRect) {
        drawBackground(in: bounds)
        drawMotionBands(in: bounds)
        drawGrid(in: bounds)
        drawConfetti(in: bounds)
    }

    func update(endDate: Date?) {
        if let endDate {
            countdownLabel.stringValue = DurationFormatter.awayoString(from: max(0, endDate.timeIntervalSinceNow))
            backAtLabel.stringValue = "Back around \(endDate.formatted(date: .omitted, time: .shortened))"
        } else {
            countdownLabel.stringValue = "Running"
            backAtLabel.stringValue = "Until stopped"
        }
    }

    private func setupView(message: String, endDate: Date?, showsUnlockField: Bool) {
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .centerX
        content.spacing = 18
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        let topRow = NSStackView()
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 10

        configurePillLabel(badgeLabel, foreground: .black, background: NSColor(calibratedRed: 0.98, green: 0.88, blue: 0.33, alpha: 1))
        configurePillLabel(statusLabel, foreground: .white, background: NSColor.white.withAlphaComponent(0.14))

        topRow.addArrangedSubview(badgeLabel)
        topRow.addArrangedSubview(statusLabel)

        messageLabel.stringValue = message
        messageLabel.textColor = .white
        messageLabel.alignment = .center
        messageLabel.maximumNumberOfLines = 4
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        countdownLabel.textColor = .white
        countdownLabel.alignment = .center
        countdownLabel.maximumNumberOfLines = 1

        backAtLabel.textColor = NSColor.white.withAlphaComponent(0.74)
        backAtLabel.alignment = .center

        activityLabel.textColor = NSColor.white.withAlphaComponent(0.60)
        activityLabel.alignment = .center
        activityLabel.maximumNumberOfLines = 2
        activityLabel.preferredMaxLayoutWidth = 620

        update(endDate: endDate)

        content.addArrangedSubview(topRow)
        content.addArrangedSubview(messageLabel)
        content.addArrangedSubview(countdownLabel)
        content.addArrangedSubview(backAtLabel)
        content.addArrangedSubview(activityLabel)

        if showsUnlockField {
            let unlockRow = NSStackView()
            unlockRow.orientation = .horizontal
            unlockRow.alignment = .centerY
            unlockRow.spacing = 10
            unlockRow.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0)

            unlockField.placeholderString = "Passcode"
            unlockField.font = .systemFont(ofSize: 18, weight: .semibold)
            unlockField.alignment = .center
            unlockField.target = self
            unlockField.action = #selector(checkPasscode)
            unlockField.translatesAutoresizingMaskIntoConstraints = false
            unlockField.bezelStyle = .roundedBezel

            unlockButton.target = self
            unlockButton.action = #selector(checkPasscode)
            unlockButton.bezelStyle = .rounded
            unlockButton.controlSize = .large
            unlockButton.font = .systemFont(ofSize: 15, weight: .bold)

            unlockRow.addArrangedSubview(unlockField)
            unlockRow.addArrangedSubview(unlockButton)

            content.addArrangedSubview(unlockRow)

            unlockField.widthAnchor.constraint(equalToConstant: 280).isActive = true
        } else {
            let hint = NSTextField(labelWithString: "Unlock from the main display")
            hint.font = .systemFont(ofSize: 15, weight: .semibold)
            hint.textColor = NSColor.white.withAlphaComponent(0.58)
            content.addArrangedSubview(hint)
        }

        let footer = NSTextField(labelWithString: "Awayo Lock")
        footer.font = .systemFont(ofSize: 13, weight: .bold)
        footer.textColor = NSColor.white.withAlphaComponent(0.38)
        footer.alignment = .center
        footer.maximumNumberOfLines = 1
        content.addArrangedSubview(footer)

        NSLayoutConstraint.activate([
            content.centerXAnchor.constraint(equalTo: centerXAnchor),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
            content.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 48),
            content.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -48)
        ])
    }

    private func configurePillLabel(_ label: NSTextField, foreground: NSColor, background: NSColor) {
        label.font = .monospacedSystemFont(ofSize: 13, weight: .heavy)
        label.textColor = foreground
        label.alignment = .center
        label.wantsLayer = true
        label.layer?.backgroundColor = background.cgColor
        label.layer?.cornerRadius = 14
        label.layer?.masksToBounds = true
    }

    private func startAnimation() {
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(
            timeInterval: 1 / 30,
            target: self,
            selector: #selector(animationTimerFired),
            userInfo: nil,
            repeats: true
        )
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    @objc private func animationTimerFired() {
        animationPhase += 0.016
        needsDisplay = true
    }

    @objc private func checkPasscode() {
        guard unlockField.stringValue == passcode else {
            NSSound.beep()
            unlockField.stringValue = ""
            return
        }

        onUnlock()
    }

    private func drawBackground(in rect: NSRect) {
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.02, green: 0.03, blue: 0.06, alpha: 1),
            NSColor(calibratedRed: 0.02, green: 0.19, blue: 0.22, alpha: 1),
            NSColor(calibratedRed: 0.16, green: 0.06, blue: 0.17, alpha: 1)
        ])

        gradient?.draw(in: rect, angle: -24)

        NSColor(calibratedWhite: 0, alpha: 0.16).setFill()
        rect.fill()
    }

    private func drawMotionBands(in rect: NSRect) {
        let colors = [
            NSColor(calibratedRed: 0.99, green: 0.80, blue: 0.24, alpha: 0.30),
            NSColor(calibratedRed: 0.05, green: 0.76, blue: 0.70, alpha: 0.22),
            NSColor(calibratedRed: 0.98, green: 0.22, blue: 0.45, alpha: 0.18)
        ]

        for index in 0..<3 {
            let path = NSBezierPath()
            let yBase = rect.midY + CGFloat(index - 1) * rect.height * 0.18
            let amplitude = rect.height * (0.045 + CGFloat(index) * 0.012)
            let frequency = CGFloat(0.010 + Double(index) * 0.002)
            let phase = animationPhase * CGFloat(index + 1) * 1.8

            path.move(to: NSPoint(x: rect.minX - 80, y: yBase))

            stride(from: rect.minX - 80, through: rect.maxX + 80, by: 28).forEach { x in
                let y = yBase + sin(x * frequency + phase) * amplitude
                path.line(to: NSPoint(x: x, y: y))
            }

            path.lineWidth = rect.height < 900 ? 26 : 38
            colors[index].setStroke()
            path.stroke()
        }
    }

    private func drawGrid(in rect: NSRect) {
        let path = NSBezierPath()
        let spacing: CGFloat = rect.width < 900 ? 72 : 96
        let offset = (animationPhase * 12).truncatingRemainder(dividingBy: spacing)

        stride(from: rect.minX - spacing + offset, through: rect.maxX + spacing, by: spacing).forEach { x in
            path.move(to: NSPoint(x: x, y: rect.minY))
            path.line(to: NSPoint(x: x, y: rect.maxY))
        }

        stride(from: rect.minY - spacing + offset, through: rect.maxY + spacing, by: spacing).forEach { y in
            path.move(to: NSPoint(x: rect.minX, y: y))
            path.line(to: NSPoint(x: rect.maxX, y: y))
        }

        path.lineWidth = 1
        NSColor.white.withAlphaComponent(0.045).setStroke()
        path.stroke()
    }

    private func drawConfetti(in rect: NSRect) {
        let count = rect.width < 900 ? 22 : 42

        for index in 0..<count {
            let seed = CGFloat(index)
            let x = unitNoise(seed * 12.9898) * rect.width
            let baseY = unitNoise(seed * 78.233) * rect.height
            let drift = sin(animationPhase * 1.6 + seed) * 16
            let y = baseY + drift
            let size = CGFloat(5 + (index % 5) * 2)

            let color: NSColor
            switch index % 4 {
            case 0:
                color = NSColor(calibratedRed: 0.98, green: 0.84, blue: 0.28, alpha: 0.42)
            case 1:
                color = NSColor(calibratedRed: 0.16, green: 0.80, blue: 0.75, alpha: 0.34)
            case 2:
                color = NSColor(calibratedRed: 1.00, green: 0.36, blue: 0.55, alpha: 0.30)
            default:
                color = NSColor.white.withAlphaComponent(0.24)
            }

            color.setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: y, width: size * 2.2, height: size), xRadius: size / 2, yRadius: size / 2).fill()
        }
    }

    private func unitNoise(_ value: CGFloat) -> CGFloat {
        let raw = sin(value) * 43758.5453
        return raw - floor(raw)
    }
}
