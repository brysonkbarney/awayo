import AppKit
@preconcurrency import AVFoundation
import CoreImage

@MainActor
final class PrivacyOverlayView: NSView {
    let unlockField = NSSecureTextField()

    private let awayoAppearance: AwayoAppearance
    private let badgeLabel = NSTextField(labelWithString: "  AWAYO LOCK  ")
    private let messageLabel = NSTextField(labelWithString: "")
    private let countdownLabel = NSTextField(labelWithString: "")
    private let backAtLabel = NSTextField(labelWithString: "")
    private let unlockButton = NSButton(title: "Unlock", target: nil, action: nil)
    private let safetyExitButton = NSButton(title: "Safety Exit", target: nil, action: nil)
    private let unlockErrorLabel = NSTextField(labelWithString: "")
    private let notePanel = NSStackView()
    private let notesStack = NSStackView()
    private let noteNameField = NSTextField(string: "")
    private let noteMessageField = NSTextField(string: "")
    private let noteComposerHost = StickyNoteComposerView()
    private let noteComposer = NSStackView()
    private let verifyPasscode: (String) -> Bool
    private let showsUnlockField: Bool
    private let screenSnapshot: NSImage?
    private let onUnlock: () -> Void

    private var animationTimer: Timer?
    private var animationPhase: CGFloat = 0
    private var stickyNotes: [AwayoStickyNote] = []
    private var floatingNoteViews: [StickyNoteCardView] = []
    private var pendingNotePoint: NSPoint?
    private var noteComposerActive = false
    private var runnerJumpOffset: CGFloat = 0
    private var runnerVelocity: CGFloat = 0
    private var runnerScore = 0
    private var snapshotPrankTrackingArea: NSTrackingArea?
    private var snapshotPrankCards: [SnapshotPrankCardView] = []
    private var lastSnapshotPrankTime: TimeInterval = -Double.infinity
    private var snapshotPrankCount = 0
    private var snapshotPrankInProgress = false
    private var snapshotPrankCountdownView: SnapshotPrankCountdownView?
    private var snapshotPrankCountdownTimer: Timer?
    private var snapshotPrankCamera: AwayoCameraSnapshotter?
    private var snapshotPrankPendingPoint = NSPoint.zero
    private var snapshotPrankRemainingSeconds = 3
    private var snapshotPrankGeneration = 0
    private weak var snapshotUnlockPanel: NSView?
    private var style: AwayoLockStyle {
        awayoAppearance.backgroundStyle
    }
    private var allowsNoteFeatures: Bool {
        showsUnlockField && style != .screenSnapshot && awayoAppearance.noteStyle != .hidden
    }

    init(
        message: String,
        endDate: Date?,
        appearance: AwayoAppearance,
        screenSnapshot: NSImage?,
        verifyPasscode: @escaping (String) -> Bool,
        showsUnlockField: Bool,
        onUnlock: @escaping () -> Void
    ) {
        self.verifyPasscode = verifyPasscode
        self.awayoAppearance = appearance
        self.showsUnlockField = showsUnlockField
        self.screenSnapshot = screenSnapshot
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

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hitView = super.hitTest(point)
        guard showsUnlockField, let hitView, hitView !== self else {
            return hitView
        }

        var interactiveViews: [NSView] = [unlockField, unlockButton]
        if allowsNoteFeatures {
            interactiveViews.append(contentsOf: [notePanel, noteComposerHost])
        }
        if interactiveViews.contains(where: { hitView === $0 || hitView.isDescendant(of: $0) }) {
            return hitView
        }

        return self
    }

    override func updateTrackingAreas() {
        if let snapshotPrankTrackingArea {
            removeTrackingArea(snapshotPrankTrackingArea)
            self.snapshotPrankTrackingArea = nil
        }

        super.updateTrackingAreas()

        guard style == .screenSnapshot else {
            return
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        snapshotPrankTrackingArea = trackingArea
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)

        if newWindow == nil {
            stopAnimation()
            snapshotPrankCountdownTimer?.invalidate()
            snapshotPrankCountdownTimer = nil
            snapshotPrankCamera = nil
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if showsUnlockField {
            focusUnlockFieldIfAppropriate()
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard allowsNoteFeatures else {
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let ignoredViews: [NSView] = [unlockField, unlockButton, notePanel, noteComposerHost]
        let clickedControl = ignoredViews.contains { view in
            view.convert(view.bounds, to: self).insetBy(dx: -14, dy: -14).contains(point)
        }

        guard !clickedControl else {
            super.mouseDown(with: event)
            return
        }

        showNoteComposer(at: point)
    }

    override func mouseMoved(with event: NSEvent) {
        handleSnapshotPointerEvent(event)
    }

    override func mouseDragged(with event: NSEvent) {
        handleSnapshotPointerEvent(event)
    }

    func focusUnlockFieldIfAppropriate() {
        guard showsUnlockField, style != .screenSnapshot, !noteComposerActive, !isTypingInUnlockField else {
            return
        }

        window?.makeFirstResponder(unlockField)
    }

    var isEnteringText: Bool {
        isTypingInUnlockField || isTypingInNoteComposer
    }

    func jumpRunnerIfNeeded() {
        guard style == .offlineRunner, runnerJumpOffset <= 1 else {
            return
        }

        runnerVelocity = 21
        runnerJumpOffset = 2
    }

    override func layout() {
        super.layout()

        let availableWidth = max(300, bounds.width - 96)
        let noteAwareWidth = showsUnlockField && bounds.width > 1200 ? min(760, availableWidth - 360) : min(760, availableWidth)
        messageLabel.preferredMaxLayoutWidth = max(320, noteAwareWidth)
        messageLabel.font = messageFont(compact: bounds.width < 760)
        countdownLabel.font = timerFont(compact: bounds.width < 760)
        backAtLabel.font = .systemFont(ofSize: bounds.width < 760 ? 14 : 18, weight: .semibold)
        if allowsNoteFeatures {
            positionFloatingNotes()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        switch style {
        case .neonFlow:
            drawNeonFlow(in: bounds)
        case .duckPond:
            drawDuckPond(in: bounds)
        case .offlineRunner:
            drawOfflineRunner(in: bounds)
        case .cosmicDesk:
            drawCosmicDesk(in: bounds)
        case .rainyWindow:
            drawRainyWindow(in: bounds)
        case .arcadePulse:
            drawArcadePulse(in: bounds)
        case .paperNotes:
            drawPaperNotes(in: bounds)
        case .synthwave:
            drawSynthwave(in: bounds)
        case .solidColor:
            drawSolidColor(in: bounds)
        case .softWash:
            drawSoftWash(in: bounds)
        case .stripes:
            drawStripes(in: bounds)
        case .polkaDots:
            drawPolkaDots(in: bounds)
        case .screenSnapshot:
            drawScreenSnapshot(in: bounds)
        }
    }

    func update(endDate: Date?) {
        guard awayoAppearance.timerStyle != .hidden else {
            countdownLabel.stringValue = ""
            backAtLabel.stringValue = ""
            countdownLabel.isHidden = true
            backAtLabel.isHidden = true
            return
        }

        if let endDate {
            let value = DurationFormatter.awayoString(from: max(0, endDate.timeIntervalSinceNow))
            countdownLabel.stringValue = awayoAppearance.timerStyle == .terminalTicker ? "$ \(value)" : value
            backAtLabel.stringValue = "until \(endDate.formatted(date: .omitted, time: .shortened))"
        } else {
            countdownLabel.stringValue = awayoAppearance.timerStyle == .terminalTicker ? "$ running" : "Running"
            backAtLabel.stringValue = "Until stopped"
        }
    }

    private func setupView(message: String, endDate: Date?, showsUnlockField: Bool) {
        if style == .screenSnapshot {
            setupScreenSnapshotView(showsUnlockField: showsUnlockField)
            return
        }

        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .centerX
        content.spacing = 14
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        let topRow = NSStackView()
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 10

        configurePillLabel(
            badgeLabel,
            foreground: NSColor.black.withAlphaComponent(0.82),
            background: NSColor(calibratedRed: 0.98, green: 0.88, blue: 0.33, alpha: 0.92)
        )

        topRow.addArrangedSubview(badgeLabel)

        let displayMessage = displayMessage(from: message)
        messageLabel.stringValue = displayMessage
        messageLabel.isHidden = displayMessage.isEmpty
        messageLabel.textColor = .white
        messageLabel.alignment = .center
        messageLabel.maximumNumberOfLines = 3
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        countdownLabel.textColor = .white
        countdownLabel.alignment = .center
        countdownLabel.maximumNumberOfLines = 1

        backAtLabel.textColor = NSColor.white.withAlphaComponent(0.76)
        backAtLabel.alignment = .center

        update(endDate: endDate)
        applyDashboardStyle(to: content)
        applyTimerStyle()

        content.addArrangedSubview(topRow)
        content.addArrangedSubview(messageLabel)
        content.addArrangedSubview(countdownLabel)
        content.addArrangedSubview(backAtLabel)

        if showsUnlockField {
            content.addArrangedSubview(makeUnlockRow())
        } else {
            let hint = NSTextField(labelWithString: "Unlock from the main display")
            hint.font = .systemFont(ofSize: 15, weight: .semibold)
            hint.textColor = NSColor.white.withAlphaComponent(0.58)
            content.addArrangedSubview(hint)
        }

        NSLayoutConstraint.activate([
            content.centerXAnchor.constraint(equalTo: centerXAnchor),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
            content.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 48),
            content.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -48)
        ])

        if allowsNoteFeatures {
            setupNotePanel()
        }
    }

    private func setupScreenSnapshotView(showsUnlockField: Bool) {
        guard showsUnlockField else {
            return
        }

        let unlockPanel = makeUnlockRow()
        unlockPanel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(unlockPanel)

        NSLayoutConstraint.activate([
            unlockPanel.centerXAnchor.constraint(equalTo: centerXAnchor),
            unlockPanel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18)
        ])
    }

    private func displayMessage(from message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let markers = [". Back around ", " Back around ", ". back around ", " back around "]

        for marker in markers {
            if let range = trimmed.range(of: marker) {
                return String(trimmed[..<range.lowerBound])
                    .trimmingCharacters(in: CharacterSet(charactersIn: ". \n\t"))
            }
        }

        return trimmed
    }

    private func makeUnlockRow() -> NSStackView {
        if style == .screenSnapshot {
            return makeSnapshotUnlockRow()
        }

        let unlockPanel = NSStackView()
        unlockPanel.orientation = .vertical
        unlockPanel.alignment = .centerX
        unlockPanel.spacing = 8
        unlockPanel.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        unlockPanel.wantsLayer = true
        unlockPanel.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
        unlockPanel.layer?.cornerRadius = 12
        unlockPanel.layer?.borderWidth = 1
        unlockPanel.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor

        let unlockRow = NSStackView()
        unlockRow.orientation = .horizontal
        unlockRow.alignment = .centerY
        unlockRow.spacing = 8

        unlockField.placeholderString = "Passcode"
        unlockField.font = .systemFont(ofSize: 16, weight: .semibold)
        unlockField.alignment = .center
        unlockField.target = self
        unlockField.action = #selector(checkPasscode)
        unlockField.translatesAutoresizingMaskIntoConstraints = false
        unlockField.bezelStyle = .roundedBezel

        unlockButton.target = self
        unlockButton.action = #selector(checkPasscode)
        unlockButton.bezelStyle = .rounded
        unlockButton.controlSize = .regular
        unlockButton.font = .systemFont(ofSize: 13, weight: .bold)

        safetyExitButton.target = self
        safetyExitButton.action = #selector(safetyExit)
        safetyExitButton.bezelStyle = .rounded
        safetyExitButton.controlSize = .small
        safetyExitButton.font = .systemFont(ofSize: 11, weight: .semibold)

        unlockErrorLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        unlockErrorLabel.textColor = NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.45, alpha: 1)
        unlockErrorLabel.alignment = .center
        unlockErrorLabel.isHidden = true

        unlockRow.addArrangedSubview(unlockField)
        unlockRow.addArrangedSubview(unlockButton)
        unlockField.widthAnchor.constraint(equalToConstant: 240).isActive = true

        unlockPanel.addArrangedSubview(unlockRow)
        unlockPanel.addArrangedSubview(unlockErrorLabel)
        unlockPanel.addArrangedSubview(safetyExitButton)
        return unlockPanel
    }

    private func makeSnapshotUnlockRow() -> NSStackView {
        let unlockPanel = NSStackView()
        unlockPanel.orientation = .vertical
        unlockPanel.alignment = .centerX
        unlockPanel.spacing = 3
        unlockPanel.edgeInsets = NSEdgeInsets(top: 5, left: 7, bottom: 5, right: 7)
        unlockPanel.alphaValue = 0.14
        unlockPanel.wantsLayer = true
        unlockPanel.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.035).cgColor
        unlockPanel.layer?.cornerRadius = 7
        unlockPanel.layer?.borderWidth = 1
        unlockPanel.layer?.borderColor = NSColor.white.withAlphaComponent(0.025).cgColor
        snapshotUnlockPanel = unlockPanel

        let unlockRow = NSStackView()
        unlockRow.orientation = .horizontal
        unlockRow.alignment = .centerY
        unlockRow.spacing = 4

        unlockField.placeholderString = "Password"
        unlockField.font = .systemFont(ofSize: 11, weight: .medium)
        unlockField.alignment = .center
        unlockField.target = self
        unlockField.action = #selector(checkPasscode)
        unlockField.translatesAutoresizingMaskIntoConstraints = false
        unlockField.bezelStyle = .roundedBezel
        unlockField.controlSize = .small
        unlockField.alphaValue = 0.60

        unlockButton.title = "OK"
        unlockButton.target = self
        unlockButton.action = #selector(checkPasscode)
        unlockButton.bezelStyle = .rounded
        unlockButton.controlSize = .small
        unlockButton.font = .systemFont(ofSize: 10, weight: .bold)
        unlockButton.alphaValue = 0.56

        safetyExitButton.title = "Exit"
        safetyExitButton.target = self
        safetyExitButton.action = #selector(safetyExit)
        safetyExitButton.bezelStyle = .inline
        safetyExitButton.controlSize = .mini
        safetyExitButton.font = .systemFont(ofSize: 9, weight: .medium)
        safetyExitButton.alphaValue = 0.22

        unlockErrorLabel.font = .systemFont(ofSize: 9, weight: .semibold)
        unlockErrorLabel.textColor = NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.45, alpha: 0.9)
        unlockErrorLabel.alignment = .center
        unlockErrorLabel.isHidden = true

        unlockRow.addArrangedSubview(unlockField)
        unlockRow.addArrangedSubview(unlockButton)
        unlockField.widthAnchor.constraint(equalToConstant: 128).isActive = true

        unlockPanel.addArrangedSubview(unlockRow)
        unlockPanel.addArrangedSubview(unlockErrorLabel)
        unlockPanel.addArrangedSubview(safetyExitButton)
        return unlockPanel
    }

    private func handleSnapshotPointerEvent(_ event: NSEvent) {
        guard style == .screenSnapshot else {
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        updateSnapshotUnlockVisibility(at: point)
        if point.y <= 112 || isTypingInUnlockField {
            cancelSnapshotPrank()
            return
        }

        showSnapshotPrankIfNeeded(at: point, timestamp: event.timestamp)
    }

    private func updateSnapshotUnlockVisibility(at point: NSPoint) {
        guard let snapshotUnlockPanel else {
            return
        }

        let shouldReveal = point.y <= 104 || isTypingInUnlockField
        let targetAlpha: CGFloat = shouldReveal ? 0.86 : 0.14
        guard abs(snapshotUnlockPanel.alphaValue - targetAlpha) > 0.02 else {
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            snapshotUnlockPanel.animator().alphaValue = targetAlpha
        }
    }

    private func showSnapshotPrankIfNeeded(at point: NSPoint, timestamp: TimeInterval) {
        guard style == .screenSnapshot, !snapshotPrankInProgress, !isTypingInUnlockField else {
            return
        }

        guard awayoAppearance.cameraGagEnabled else {
            return
        }

        guard bounds.contains(point), point.y > 112 else {
            return
        }

        guard timestamp - lastSnapshotPrankTime > 4.0 else {
            return
        }

        lastSnapshotPrankTime = timestamp
        beginSnapshotPrank(at: point)
    }

    private func beginSnapshotPrank(at point: NSPoint) {
        snapshotPrankInProgress = true
        snapshotPrankGeneration += 1
        snapshotPrankCountdownTimer?.invalidate()

        let countdownView = SnapshotPrankCountdownView()
        countdownView.frame = countdownFrame(near: point)
        addSubview(countdownView, positioned: .above, relativeTo: nil)
        snapshotPrankCountdownView = countdownView

        snapshotPrankPendingPoint = point
        snapshotPrankRemainingSeconds = 2
        countdownView.remainingSeconds = snapshotPrankRemainingSeconds
        NSSound(named: NSSound.Name("Tink"))?.play()

        snapshotPrankCountdownTimer = Timer.scheduledTimer(
            timeInterval: 1,
            target: self,
            selector: #selector(snapshotPrankCountdownTick(_:)),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func snapshotPrankCountdownTick(_ timer: Timer) {
        snapshotPrankRemainingSeconds -= 1
        if snapshotPrankRemainingSeconds > 0 {
            snapshotPrankCountdownView?.remainingSeconds = snapshotPrankRemainingSeconds
            NSSound(named: NSSound.Name("Tink"))?.play()
            return
        }

        timer.invalidate()
        snapshotPrankCountdownTimer = nil
        snapshotPrankCountdownView?.statusText = "smile"
        snapshotPrankCountdownView?.remainingSeconds = 0
        captureSnapshotPrank(at: snapshotPrankPendingPoint)
    }

    private func captureSnapshotPrank(at point: NSPoint) {
        let generation = snapshotPrankGeneration
        let snapshotter = AwayoCameraSnapshotter { [weak self] image in
            guard let self else {
                return
            }

            guard generation == self.snapshotPrankGeneration else {
                return
            }

            self.snapshotPrankCamera = nil
            self.snapshotPrankCountdownView?.removeFromSuperview()
            self.snapshotPrankCountdownView = nil
            self.snapshotPrankInProgress = false

            if let image {
                self.showSnapshotPrankCard(
                    at: point,
                    image: image,
                    focusPoint: nil,
                    detail: "visible camera snap"
                )
            } else {
                NSSound.beep()
            }
        }
        snapshotPrankCamera = snapshotter
        snapshotter.capture()
    }

    private func showSnapshotPrankCard(at point: NSPoint, image: NSImage?, focusPoint: NSPoint?, detail: String) {
        let cardSize = NSSize(width: 232, height: 286)
        let minX: CGFloat = 28
        let maxX = max(minX, bounds.width - cardSize.width - 28)
        let minY: CGFloat = 112
        let maxY = max(minY, bounds.height - cardSize.height - 28)
        let x = min(max(point.x - cardSize.width / 2 + 18, minX), maxX)
        let y = min(max(point.y - cardSize.height / 2 + 28, minY), maxY)

        let card = SnapshotPrankCardView(
            image: image,
            focusPoint: focusPoint,
            timestamp: Date(),
            detail: detail,
            index: snapshotPrankCount
        )
        card.frame = NSRect(origin: NSPoint(x: x, y: y), size: cardSize)
        card.frameCenterRotation = CGFloat((snapshotPrankCount % 5) - 2) * 2.6
        addSubview(card, positioned: .above, relativeTo: nil)
        snapshotPrankCards.append(card)
        snapshotPrankCount += 1

        while snapshotPrankCards.count > 6 {
            snapshotPrankCards.removeFirst().removeFromSuperview()
        }

        NSSound(named: NSSound.Name("Pop"))?.play()
    }

    private func countdownFrame(near point: NSPoint) -> NSRect {
        let size = NSSize(width: 248, height: 124)
        let minX: CGFloat = 34
        let maxX = max(minX, bounds.width - size.width - 34)
        let minY: CGFloat = 130
        let maxY = max(minY, bounds.height - size.height - 34)
        let x = min(max(point.x - size.width / 2, minX), maxX)
        let y = min(max(point.y - size.height / 2, minY), maxY)
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }

    private func cancelSnapshotPrank() {
        guard snapshotPrankInProgress || snapshotPrankCountdownView != nil || snapshotPrankCamera != nil else {
            return
        }

        snapshotPrankGeneration += 1
        snapshotPrankCountdownTimer?.invalidate()
        snapshotPrankCountdownTimer = nil
        snapshotPrankCountdownView?.removeFromSuperview()
        snapshotPrankCountdownView = nil
        snapshotPrankCamera = nil
        snapshotPrankInProgress = false
    }

    private func snapshotFocusPoint(from point: NSPoint) -> NSPoint? {
        guard let screenSnapshot else {
            return nil
        }

        return NSPoint(
            x: point.x / max(1, bounds.width) * screenSnapshot.size.width,
            y: point.y / max(1, bounds.height) * screenSnapshot.size.height
        )
    }

    private func setupNotePanel() {
        notePanel.orientation = .vertical
        notePanel.alignment = .leading
        notePanel.spacing = 10
        notePanel.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        notePanel.translatesAutoresizingMaskIntoConstraints = false
        notePanel.wantsLayer = true
        notePanel.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.24).cgColor
        notePanel.layer?.cornerRadius = 8
        notePanel.layer?.borderWidth = 1
        notePanel.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        addSubview(notePanel)

        let title = NSTextField(labelWithString: "Sticky notes")
        title.font = .systemFont(ofSize: 15, weight: .heavy)
        title.textColor = .white

        let subtitle = NSTextField(labelWithString: "Click anywhere to leave a note for the human.")
        subtitle.font = .systemFont(ofSize: 12, weight: .medium)
        subtitle.textColor = NSColor.white.withAlphaComponent(0.56)
        subtitle.maximumNumberOfLines = 2

        notesStack.orientation = .vertical
        notesStack.alignment = .leading
        notesStack.spacing = 8

        let leaveButton = NSButton(title: "Leave a sticky note", target: self, action: #selector(showNoteComposerFromButton))
        leaveButton.bezelStyle = .rounded
        leaveButton.controlSize = .regular
        leaveButton.font = .systemFont(ofSize: 13, weight: .bold)

        configureNoteComposer()

        notePanel.addArrangedSubview(title)
        notePanel.addArrangedSubview(subtitle)
        notePanel.addArrangedSubview(notesStack)
        notePanel.addArrangedSubview(leaveButton)

        noteComposerHost.isHidden = true
        noteComposerHost.translatesAutoresizingMaskIntoConstraints = true
        addSubview(noteComposerHost)
        renderStickyNotes()

        NSLayoutConstraint.activate([
            notePanel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32),
            notePanel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -32),
            notePanel.widthAnchor.constraint(equalToConstant: 320)
        ])
    }

    private func configureNoteComposer() {
        noteComposer.orientation = .vertical
        noteComposer.alignment = .leading
        noteComposer.spacing = 8
        noteComposer.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 16, right: 18)
        noteComposer.translatesAutoresizingMaskIntoConstraints = false
        noteComposerHost.addSubview(noteComposer)

        noteNameField.placeholderString = "Your name"
        (noteNameField.cell as? NSTextFieldCell)?.placeholderAttributedString = NSAttributedString(
            string: "Your name",
            attributes: [.foregroundColor: NSColor.black.withAlphaComponent(0.38)]
        )
        noteNameField.font = .systemFont(ofSize: 14, weight: .semibold)
        noteNameField.textColor = NSColor.black.withAlphaComponent(0.70)
        noteNameField.isBordered = false
        noteNameField.backgroundColor = .clear
        noteNameField.widthAnchor.constraint(equalToConstant: 256).isActive = true

        noteMessageField.placeholderString = "Leave a note"
        (noteMessageField.cell as? NSTextFieldCell)?.placeholderAttributedString = NSAttributedString(
            string: "Leave a note",
            attributes: [.foregroundColor: NSColor.black.withAlphaComponent(0.40)]
        )
        noteMessageField.font = handwrittenFont(size: 18, weight: .semibold)
        noteMessageField.textColor = NSColor.black.withAlphaComponent(0.84)
        noteMessageField.isBordered = false
        noteMessageField.backgroundColor = .clear
        noteMessageField.widthAnchor.constraint(equalToConstant: 256).isActive = true

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        let saveButton = NSButton(title: "Pin note", target: self, action: #selector(saveStickyNote))
        saveButton.bezelStyle = .rounded
        saveButton.font = .systemFont(ofSize: 12, weight: .bold)

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelStickyNote))
        cancelButton.bezelStyle = .rounded

        buttonRow.addArrangedSubview(saveButton)
        buttonRow.addArrangedSubview(cancelButton)

        noteComposer.addArrangedSubview(noteNameField)
        noteComposer.addArrangedSubview(noteMessageField)
        noteComposer.addArrangedSubview(buttonRow)

        NSLayoutConstraint.activate([
            noteComposer.leadingAnchor.constraint(equalTo: noteComposerHost.leadingAnchor),
            noteComposer.trailingAnchor.constraint(equalTo: noteComposerHost.trailingAnchor),
            noteComposer.topAnchor.constraint(equalTo: noteComposerHost.topAnchor),
            noteComposer.bottomAnchor.constraint(equalTo: noteComposerHost.bottomAnchor)
        ])
    }

    private func renderStickyNotes() {
        notesStack.arrangedSubviews.forEach {
            notesStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        if stickyNotes.isEmpty {
            let empty = NSTextField(labelWithString: "No notes yet.")
            empty.font = .systemFont(ofSize: 12, weight: .medium)
            empty.textColor = NSColor.white.withAlphaComponent(0.46)
            notesStack.addArrangedSubview(empty)
            return
        }

        stickyNotes.suffix(3).forEach { note in
            notesStack.addArrangedSubview(StickyNoteCardView(note: note, style: awayoAppearance.noteStyle))
        }
    }

    @objc private func showNoteComposerFromButton() {
        pendingNotePoint = NSPoint(x: bounds.width - 210, y: bounds.height - 190)
        activateNoteComposer()
    }

    private func showNoteComposer(at point: NSPoint) {
        pendingNotePoint = point
        activateNoteComposer()
    }

    private func activateNoteComposer() {
        noteComposerActive = true
        noteComposerHost.isHidden = false
        positionComposerHost()
        noteNameField.stringValue = ""
        noteMessageField.stringValue = ""
        noteNameField.textColor = NSColor.black.withAlphaComponent(0.70)
        noteMessageField.textColor = NSColor.black.withAlphaComponent(0.84)
        window?.makeFirstResponder(noteNameField)
    }

    @objc private func cancelStickyNote() {
        noteComposerActive = false
        noteComposerHost.isHidden = true
        window?.makeFirstResponder(unlockField)
    }

    @objc private func saveStickyNote() {
        let message = noteMessageField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            NSSound.beep()
            return
        }

        let author = noteNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let position = pendingNotePoint ?? NSPoint(x: bounds.midX, y: bounds.midY)
        stickyNotes.append(AwayoStickyNote(
            author: author.isEmpty ? "Visitor" : author,
            message: message,
            colorIndex: stickyNotes.count,
            position: position
        ))
        pendingNotePoint = nil
        noteComposerActive = false
        noteComposerHost.isHidden = true
        renderStickyNotes()
        renderFloatingNotes()
        window?.makeFirstResponder(unlockField)
    }

    private func positionComposerHost() {
        let size = NSSize(width: 292, height: 218)
        let point = pendingNotePoint ?? NSPoint(x: bounds.midX, y: bounds.midY)
        let x = min(max(point.x - size.width / 2, 22), max(22, bounds.width - size.width - 22))
        let y = min(max(point.y - size.height / 2, 22), max(22, bounds.height - size.height - 22))
        noteComposerHost.frame = NSRect(origin: NSPoint(x: x, y: y), size: size)
    }

    private func renderFloatingNotes() {
        floatingNoteViews.forEach { $0.removeFromSuperview() }
        floatingNoteViews = stickyNotes.map { note in
            let card = StickyNoteCardView(note: note, style: awayoAppearance.noteStyle, usesConstraints: false)
            card.frameCenterRotation = CGFloat((note.colorIndex % 5) - 2) * 1.8
            addSubview(card, positioned: .above, relativeTo: nil)
            return card
        }
        positionFloatingNotes()
    }

    private func positionFloatingNotes() {
        zip(stickyNotes, floatingNoteViews).forEach { note, view in
            let size = NSSize(width: 238, height: 206)
            let minX: CGFloat = 22
            let maxX = max(minX, bounds.width - size.width - 22)
            let minY: CGFloat = 22
            let maxY = max(minY, bounds.height - size.height - 22)
            let x = min(max(note.position.x - size.width / 2, minX), maxX)
            let y = min(max(note.position.y - size.height / 2, minY), maxY)
            view.frame = NSRect(origin: NSPoint(x: x, y: y), size: size)
        }

        if noteComposerActive {
            positionComposerHost()
        }
    }

    private func applyDashboardStyle(to content: NSStackView) {
        content.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.clear.cgColor
        content.layer?.borderWidth = 0
        content.layer?.borderColor = NSColor.clear.cgColor
        content.layer?.cornerRadius = 8
        content.spacing = 14
        badgeLabel.isHidden = false
        backAtLabel.isHidden = false
        badgeLabel.stringValue = "  AWAYO LOCK  "
        badgeLabel.textColor = NSColor.black.withAlphaComponent(0.82)
        badgeLabel.layer?.backgroundColor = NSColor(calibratedRed: 0.98, green: 0.88, blue: 0.33, alpha: 0.92).cgColor
        messageLabel.alignment = .center
        countdownLabel.alignment = .center
        backAtLabel.alignment = .center
        backAtLabel.textColor = NSColor.white.withAlphaComponent(0.76)

        switch awayoAppearance.dashboardStyle {
        case .centerStage:
            messageLabel.textColor = .white
        case .paperDesk:
            content.edgeInsets = NSEdgeInsets(top: 26, left: 34, bottom: 26, right: 34)
            content.layer?.backgroundColor = NSColor(calibratedRed: 1.0, green: 0.91, blue: 0.60, alpha: 0.88).cgColor
            content.layer?.borderWidth = 1
            content.layer?.borderColor = NSColor(calibratedRed: 0.38, green: 0.27, blue: 0.14, alpha: 0.24).cgColor
            content.layer?.cornerRadius = 10
            badgeLabel.stringValue = "  TAPED NOTE  "
            badgeLabel.textColor = NSColor(calibratedRed: 0.26, green: 0.18, blue: 0.10, alpha: 0.88)
            badgeLabel.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.54).cgColor
            messageLabel.textColor = NSColor(calibratedRed: 0.24, green: 0.16, blue: 0.08, alpha: 1)
            backAtLabel.textColor = NSColor(calibratedRed: 0.30, green: 0.21, blue: 0.12, alpha: 0.74)
        case .minimalBadge:
            content.spacing = 7
            badgeLabel.isHidden = true
            backAtLabel.isHidden = true
            messageLabel.textColor = .white
        case .commandCenter:
            content.edgeInsets = NSEdgeInsets(top: 24, left: 30, bottom: 24, right: 30)
            content.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.54).cgColor
            content.layer?.borderWidth = 1
            content.layer?.borderColor = NSColor(calibratedRed: 0.14, green: 0.88, blue: 0.94, alpha: 0.34).cgColor
            content.layer?.cornerRadius = 12
            badgeLabel.stringValue = "  COMMAND CENTER  "
            badgeLabel.textColor = NSColor(calibratedRed: 0.48, green: 1.0, blue: 0.66, alpha: 1)
            badgeLabel.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.56).cgColor
            messageLabel.textColor = NSColor(calibratedRed: 0.82, green: 0.96, blue: 1.0, alpha: 1)
            backAtLabel.textColor = NSColor(calibratedRed: 0.48, green: 1.0, blue: 0.66, alpha: 0.72)
        }
    }

    private func applyTimerStyle() {
        countdownLabel.wantsLayer = true
        countdownLabel.isHidden = false
        countdownLabel.layer?.cornerRadius = 8
        countdownLabel.layer?.masksToBounds = true
        countdownLabel.layer?.borderWidth = 0

        switch awayoAppearance.timerStyle {
        case .heroCountdown:
            countdownLabel.textColor = awayoAppearance.dashboardStyle == .paperDesk
                ? NSColor(calibratedRed: 0.24, green: 0.16, blue: 0.08, alpha: 1)
                : .white
            countdownLabel.layer?.backgroundColor = NSColor.clear.cgColor
        case .paperClock:
            countdownLabel.layer?.cornerRadius = 10
            countdownLabel.textColor = NSColor(calibratedRed: 0.16, green: 0.12, blue: 0.09, alpha: 1)
            countdownLabel.layer?.backgroundColor = NSColor(calibratedRed: 1.0, green: 0.91, blue: 0.54, alpha: 0.90).cgColor
        case .glassPill:
            countdownLabel.layer?.cornerRadius = 24
            countdownLabel.textColor = .white
            countdownLabel.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
            countdownLabel.layer?.borderWidth = 1
            countdownLabel.layer?.borderColor = NSColor.white.withAlphaComponent(0.24).cgColor
        case .terminalTicker:
            countdownLabel.layer?.cornerRadius = 8
            countdownLabel.textColor = NSColor(calibratedRed: 0.48, green: 1.0, blue: 0.66, alpha: 1)
            countdownLabel.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.42).cgColor
            countdownLabel.layer?.borderWidth = 1
            countdownLabel.layer?.borderColor = NSColor(calibratedRed: 0.48, green: 1.0, blue: 0.66, alpha: 0.34).cgColor
        case .hidden:
            countdownLabel.isHidden = true
            backAtLabel.isHidden = true
            countdownLabel.layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    private func messageFont(compact: Bool) -> NSFont {
        switch awayoAppearance.dashboardStyle {
        case .centerStage:
            .systemFont(ofSize: compact ? 30 : 46, weight: .heavy)
        case .paperDesk:
            handwrittenFont(size: compact ? 30 : 42, weight: .bold)
        case .minimalBadge:
            .systemFont(ofSize: compact ? 24 : 32, weight: .semibold)
        case .commandCenter:
            .monospacedSystemFont(ofSize: compact ? 26 : 38, weight: .bold)
        }
    }

    private func timerFont(compact: Bool) -> NSFont {
        switch awayoAppearance.timerStyle {
        case .heroCountdown:
            .monospacedDigitSystemFont(ofSize: compact ? 42 : 64, weight: .heavy)
        case .paperClock:
            .systemFont(ofSize: compact ? 40 : 58, weight: .black)
        case .glassPill:
            .monospacedDigitSystemFont(ofSize: compact ? 34 : 50, weight: .bold)
        case .terminalTicker:
            .monospacedSystemFont(ofSize: compact ? 30 : 44, weight: .bold)
        case .hidden:
            .systemFont(ofSize: compact ? 1 : 1, weight: .regular)
        }
    }

    private func handwrittenFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        NSFont(name: "Marker Felt", size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    private func configurePillLabel(_ label: NSTextField, foreground: NSColor, background: NSColor) {
        label.font = .monospacedSystemFont(ofSize: 11, weight: .heavy)
        label.textColor = foreground
        label.alignment = .center
        label.wantsLayer = true
        label.layer?.backgroundColor = background.cgColor
        label.layer?.cornerRadius = 12
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
        updateRunnerPhysics()
        needsDisplay = true
    }

    private func updateRunnerPhysics() {
        guard style == .offlineRunner else {
            return
        }

        runnerScore = Int(animationPhase * 8)
        if runnerJumpOffset > 0 || runnerVelocity > 0 {
            runnerJumpOffset = max(0, runnerJumpOffset + runnerVelocity)
            runnerVelocity -= 1.18

            if runnerJumpOffset <= 0 {
                runnerJumpOffset = 0
                runnerVelocity = 0
            }
        }
    }

    @objc private func checkPasscode() {
        guard verifyPasscode(unlockField.stringValue) else {
            NSSound.beep()
            unlockField.stringValue = ""
            unlockErrorLabel.stringValue = "That passcode did not match."
            unlockErrorLabel.isHidden = false
            return
        }

        onUnlock()
    }

    @objc private func safetyExit() {
        onUnlock()
    }

    private var isTypingInUnlockField: Bool {
        guard let firstResponder = window?.firstResponder else {
            return false
        }

        return firstResponder === unlockField.currentEditor()
            || firstResponder === unlockField
            || unlockField.currentEditor() === firstResponder
    }

    private var isTypingInNoteComposer: Bool {
        guard let firstResponder = window?.firstResponder else {
            return false
        }

        return firstResponder === noteNameField.currentEditor()
            || firstResponder === noteMessageField.currentEditor()
            || firstResponder === noteNameField
            || firstResponder === noteMessageField
    }

    private func drawNeonFlow(in rect: NSRect) {
        drawGradient(in: rect, colors: [
            NSColor(calibratedRed: 0.02, green: 0.03, blue: 0.06, alpha: 1),
            NSColor(calibratedRed: 0.02, green: 0.19, blue: 0.22, alpha: 1),
            NSColor(calibratedRed: 0.16, green: 0.06, blue: 0.17, alpha: 1)
        ], angle: -24)
        drawMotionBands(in: rect)
        drawGrid(in: rect, alpha: 0.045)
        drawConfetti(in: rect)
    }

    private func drawDuckPond(in rect: NSRect) {
        drawGradient(in: rect, colors: [
            NSColor(calibratedRed: 0.70, green: 0.91, blue: 0.94, alpha: 1),
            NSColor(calibratedRed: 0.13, green: 0.55, blue: 0.62, alpha: 1),
            NSColor(calibratedRed: 0.02, green: 0.20, blue: 0.27, alpha: 1)
        ], angle: -90)

        drawSun(in: rect)
        drawWaterRipples(in: rect)
        drawDuckFamily(in: rect)
        drawReeds(in: rect)
    }

    private func drawOfflineRunner(in rect: NSRect) {
        drawGradient(in: rect, colors: [
            NSColor(calibratedRed: 0.96, green: 0.92, blue: 0.80, alpha: 1),
            NSColor(calibratedRed: 0.90, green: 0.76, blue: 0.52, alpha: 1),
            NSColor(calibratedRed: 0.22, green: 0.18, blue: 0.16, alpha: 1)
        ], angle: -90)

        let groundY = rect.height * 0.28
        drawRunnerGround(in: rect, groundY: groundY)
        drawCacti(in: rect, groundY: groundY)
        drawPixelRunner(in: rect, groundY: groundY)
        drawPixelClouds(in: rect)
        drawRunnerScore(in: rect)
    }

    private func drawCosmicDesk(in rect: NSRect) {
        drawGradient(in: rect, colors: [
            NSColor(calibratedRed: 0.01, green: 0.01, blue: 0.05, alpha: 1),
            NSColor(calibratedRed: 0.06, green: 0.02, blue: 0.16, alpha: 1),
            NSColor(calibratedRed: 0.00, green: 0.08, blue: 0.14, alpha: 1)
        ], angle: 18)
        drawStars(in: rect)
        drawSolarSystem(in: rect)
    }

    private func drawRainyWindow(in rect: NSRect) {
        drawGradient(in: rect, colors: [
            NSColor(calibratedRed: 0.47, green: 0.57, blue: 0.64, alpha: 1),
            NSColor(calibratedRed: 0.28, green: 0.41, blue: 0.48, alpha: 1),
            NSColor(calibratedRed: 0.09, green: 0.19, blue: 0.23, alpha: 1)
        ], angle: -90)
        drawRainyHorizon(in: rect)
        drawRainClouds(in: rect)
        drawRain(in: rect)
        drawPuddles(in: rect)
    }

    private func drawArcadePulse(in rect: NSRect) {
        drawGradient(in: rect, colors: [
            NSColor(calibratedRed: 0.03, green: 0.00, blue: 0.08, alpha: 1),
            NSColor(calibratedRed: 0.11, green: 0.02, blue: 0.18, alpha: 1),
            NSColor(calibratedRed: 0.00, green: 0.08, blue: 0.12, alpha: 1)
        ], angle: 22)
        drawArcadeGrid(in: rect)
        drawArcadeBlocks(in: rect)
        drawPulseRings(in: rect)
    }

    private func drawPaperNotes(in rect: NSRect) {
        drawGradient(in: rect, colors: [
            NSColor(calibratedRed: 0.83, green: 0.78, blue: 0.68, alpha: 1),
            NSColor(calibratedRed: 0.54, green: 0.63, blue: 0.61, alpha: 1),
            NSColor(calibratedRed: 0.20, green: 0.23, blue: 0.26, alpha: 1)
        ], angle: -65)
        drawPaperTexture(in: rect)
        drawPinnedNotes(in: rect)
    }

    private func drawSynthwave(in rect: NSRect) {
        drawGradient(in: rect, colors: [
            NSColor(calibratedRed: 0.04, green: 0.01, blue: 0.12, alpha: 1),
            NSColor(calibratedRed: 0.20, green: 0.04, blue: 0.28, alpha: 1),
            NSColor(calibratedRed: 0.02, green: 0.08, blue: 0.16, alpha: 1)
        ], angle: -90)
        drawSynthSun(in: rect)
        drawPerspectiveGrid(in: rect)
        drawMountains(in: rect)
    }

    private func drawSolidColor(in rect: NSRect) {
        awayoAppearance.solidBackgroundColor.nsColor.setFill()
        rect.fill()
        drawSubtleVignette(in: rect)
    }

    private func drawSoftWash(in rect: NSRect) {
        let base = awayoAppearance.solidBackgroundColor.nsColor
        NSGradient(colors: [
            base.blended(withFraction: 0.40, of: .white) ?? base,
            base,
            base.blended(withFraction: 0.32, of: .black) ?? base
        ])?.draw(in: rect, angle: -35)

        for index in 0..<7 {
            let diameter = rect.height * (0.42 + CGFloat(index) * 0.08)
            let x = rect.width * unitNoise(CGFloat(index) * 17.3) - diameter * 0.35
            let y = rect.height * unitNoise(CGFloat(index) * 29.1) - diameter * 0.35
            NSColor.white.withAlphaComponent(0.035 + CGFloat(index % 3) * 0.018).setStroke()
            let path = NSBezierPath(ovalIn: NSRect(x: x, y: y, width: diameter, height: diameter))
            path.lineWidth = 3
            path.stroke()
        }

        drawSubtleVignette(in: rect)
    }

    private func drawStripes(in rect: NSRect) {
        let base = awayoAppearance.solidBackgroundColor.nsColor
        (base.blended(withFraction: 0.15, of: .black) ?? base).setFill()
        rect.fill()

        for index in -8..<Int(rect.width / 54) + 10 {
            let path = NSBezierPath()
            let x = CGFloat(index) * 72 - (animationPhase * 18).truncatingRemainder(dividingBy: 72)
            path.move(to: NSPoint(x: x, y: rect.minY - 140))
            path.line(to: NSPoint(x: x + 280, y: rect.maxY + 140))
            path.lineWidth = 38
            let color = (index.isMultiple(of: 2)
                ? base.blended(withFraction: 0.25, of: .white)
                : base.blended(withFraction: 0.18, of: .black)
            ) ?? base
            color.withAlphaComponent(0.92).setStroke()
            path.stroke()
        }

        drawSubtleVignette(in: rect)
    }

    private func drawPolkaDots(in rect: NSRect) {
        let base = awayoAppearance.solidBackgroundColor.nsColor
        base.setFill()
        rect.fill()

        let dotColor = (base.blended(withFraction: 0.62, of: .white) ?? .white).withAlphaComponent(0.58)
        dotColor.setFill()
        let spacing: CGFloat = rect.width < 900 ? 52 : 76
        let radius: CGFloat = rect.width < 900 ? 6 : 9
        let drift = sin(animationPhase) * 3

        var row = 0
        for y in stride(from: rect.minY - spacing, through: rect.maxY + spacing, by: spacing) {
            let xOffset = row.isMultiple(of: 2) ? 0 : spacing / 2
            for x in stride(from: rect.minX - spacing, through: rect.maxX + spacing, by: spacing) {
                NSBezierPath(ovalIn: NSRect(
                    x: x + xOffset + drift,
                    y: y - drift,
                    width: radius * 2,
                    height: radius * 2
                )).fill()
            }
            row += 1
        }

        drawSubtleVignette(in: rect)
    }

    private func drawScreenSnapshot(in rect: NSRect) {
        guard let screenSnapshot else {
            NSColor.black.setFill()
            rect.fill()
            drawSubtleVignette(in: rect)
            return
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.imageInterpolation = .high
        screenSnapshot.draw(
            in: rect,
            from: NSRect(origin: .zero, size: screenSnapshot.size),
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawGradient(in rect: NSRect, colors: [NSColor], angle: CGFloat) {
        NSGradient(colors: colors)?.draw(in: rect, angle: angle)
        NSColor(calibratedWhite: 0, alpha: 0.12).setFill()
        rect.fill()
    }

    private func drawSubtleVignette(in rect: NSRect) {
        NSColor.black.withAlphaComponent(0.12).setFill()
        rect.fill(using: .sourceAtop)
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

    private func drawGrid(in rect: NSRect, alpha: CGFloat) {
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
        NSColor.white.withAlphaComponent(alpha).setStroke()
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
            colorForIndex(index, alpha: 0.35).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: y, width: size * 2.2, height: size), xRadius: size / 2, yRadius: size / 2).fill()
        }
    }

    private func drawSun(in rect: NSRect) {
        let sunRect = NSRect(x: rect.width * 0.12, y: rect.height * 0.68, width: 150, height: 150)
        NSColor(calibratedRed: 1.00, green: 0.82, blue: 0.36, alpha: 0.92).setFill()
        NSBezierPath(ovalIn: sunRect).fill()
    }

    private func drawWaterRipples(in rect: NSRect) {
        for index in 0..<9 {
            let path = NSBezierPath()
            let y = rect.height * (0.18 + CGFloat(index) * 0.07)
            let phase = animationPhase * (1.0 + CGFloat(index) * 0.12)
            path.move(to: NSPoint(x: -40, y: y))
            stride(from: -40, through: rect.width + 40, by: 36).forEach { x in
                path.line(to: NSPoint(x: x, y: y + sin(x * 0.018 + phase) * 6))
            }
            path.lineWidth = 2
            NSColor.white.withAlphaComponent(0.18).setStroke()
            path.stroke()
        }
    }

    private func drawDuckFamily(in rect: NSRect) {
        let travel = (animationPhase * 44).truncatingRemainder(dividingBy: rect.width + 520) - 260
        let y = rect.height * 0.42 + sin(animationPhase * 1.4) * 10
        drawDuck(at: NSPoint(x: travel, y: y), scale: 1.2, parent: true)
        drawDuck(at: NSPoint(x: travel - 86, y: y - 34), scale: 0.62, parent: false)
        drawDuck(at: NSPoint(x: travel - 142, y: y - 12), scale: 0.58, parent: false)
        drawDuck(at: NSPoint(x: travel - 196, y: y - 42), scale: 0.54, parent: false)
    }

    private func drawDuck(at point: NSPoint, scale: CGFloat, parent: Bool) {
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: point.x, yBy: point.y)
        transform.scale(by: scale)
        transform.concat()

        NSColor.black.withAlphaComponent(0.10).setFill()
        NSBezierPath(ovalIn: NSRect(x: -52, y: -28, width: 122, height: 28)).fill()

        NSColor(calibratedRed: 1.00, green: 0.80, blue: 0.20, alpha: 1).setFill()
        let body = NSBezierPath()
        body.move(to: NSPoint(x: -48, y: -4))
        body.curve(to: NSPoint(x: -16, y: 24), controlPoint1: NSPoint(x: -46, y: 16), controlPoint2: NSPoint(x: -32, y: 26))
        body.curve(to: NSPoint(x: 38, y: 18), controlPoint1: NSPoint(x: 4, y: 24), controlPoint2: NSPoint(x: 28, y: 24))
        body.curve(to: NSPoint(x: 58, y: -2), controlPoint1: NSPoint(x: 50, y: 12), controlPoint2: NSPoint(x: 58, y: 6))
        body.curve(to: NSPoint(x: 6, y: -22), controlPoint1: NSPoint(x: 46, y: -20), controlPoint2: NSPoint(x: 24, y: -26))
        body.curve(to: NSPoint(x: -48, y: -4), controlPoint1: NSPoint(x: -16, y: -24), controlPoint2: NSPoint(x: -40, y: -16))
        body.close()
        body.fill()

        NSColor(calibratedRed: 1.00, green: 0.88, blue: 0.30, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 22, y: 16, width: 38, height: 36)).fill()
        NSColor(calibratedRed: 0.93, green: 0.61, blue: 0.08, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: -16, y: -4, width: 44, height: 22)).fill()

        NSColor(calibratedRed: 1.00, green: 0.44, blue: 0.12, alpha: 1).setFill()
        let beak = NSBezierPath()
        beak.move(to: NSPoint(x: 56, y: 35))
        beak.line(to: NSPoint(x: 82, y: 29))
        beak.line(to: NSPoint(x: 56, y: 23))
        beak.close()
        beak.fill()

        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(ovalIn: NSRect(x: 45, y: 38, width: 5, height: 5)).fill()

        if parent {
            NSColor.white.withAlphaComponent(0.24).setFill()
            NSBezierPath(ovalIn: NSRect(x: -13, y: 1, width: 38, height: 17)).fill()
        }

        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawReeds(in rect: NSRect) {
        for index in 0..<18 {
            let x = rect.width * unitNoise(CGFloat(index) * 8.3)
            let height = CGFloat(80 + (index % 4) * 28)
            let baseY: CGFloat = 0
            let path = NSBezierPath()
            path.move(to: NSPoint(x: x, y: baseY))
            path.curve(to: NSPoint(x: x + CGFloat(index % 2 == 0 ? 20 : -20), y: height), controlPoint1: NSPoint(x: x + 8, y: height * 0.3), controlPoint2: NSPoint(x: x - 8, y: height * 0.7))
            path.lineWidth = 4
            NSColor(calibratedRed: 0.58, green: 0.74, blue: 0.32, alpha: 0.45).setStroke()
            path.stroke()
        }
    }

    private func drawRunnerGround(in rect: NSRect, groundY: CGFloat) {
        let ground = NSBezierPath()
        ground.move(to: NSPoint(x: rect.minX, y: groundY))
        ground.line(to: NSPoint(x: rect.maxX, y: groundY))
        ground.lineWidth = 4
        NSColor(calibratedRed: 0.18, green: 0.15, blue: 0.13, alpha: 0.70).setStroke()
        ground.stroke()

        let dashOffset = (animationPhase * 260).truncatingRemainder(dividingBy: 52)
        for x in stride(from: rect.minX - dashOffset, through: rect.maxX, by: 52) {
            NSColor(calibratedRed: 0.18, green: 0.15, blue: 0.13, alpha: 0.38).setFill()
            NSRect(x: x, y: groundY - 18, width: 24, height: 4).fill()
        }
    }

    private func drawCacti(in rect: NSRect, groundY: CGFloat) {
        for index in 0..<6 {
            let speed = CGFloat(210 + index * 11)
            let laneOffset = CGFloat(index * 260)
            let x = rect.maxX - (animationPhase * speed + laneOffset).truncatingRemainder(dividingBy: rect.width + 360)
            drawCactus(at: NSPoint(x: x, y: groundY), scale: CGFloat(0.9 + Double(index % 3) * 0.16))
        }
    }

    private func drawCactus(at point: NSPoint, scale: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: point.x, yBy: point.y)
        transform.scale(by: scale)
        transform.concat()
        NSColor(calibratedRed: 0.08, green: 0.34, blue: 0.23, alpha: 0.78).setFill()
        NSBezierPath(roundedRect: NSRect(x: -8, y: 0, width: 16, height: 64), xRadius: 7, yRadius: 7).fill()
        NSBezierPath(roundedRect: NSRect(x: -28, y: 30, width: 14, height: 34), xRadius: 7, yRadius: 7).fill()
        NSBezierPath(roundedRect: NSRect(x: 15, y: 22, width: 14, height: 30), xRadius: 7, yRadius: 7).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawPixelRunner(in rect: NSRect, groundY: CGFloat) {
        let x = rect.width * 0.25
        let runBob = runnerJumpOffset == 0 ? abs(sin(animationPhase * 10)) * 7 : 0
        let y = groundY + runnerJumpOffset + runBob
        NSColor(calibratedRed: 0.12, green: 0.10, blue: 0.09, alpha: 0.90).setFill()
        let s: CGFloat = rect.width < 900 ? 9 : 11
        [
            NSRect(x: x, y: y + s * 2, width: s * 7, height: s * 7),
            NSRect(x: x + s * 5, y: y + s * 7, width: s * 6, height: s * 5),
            NSRect(x: x + s * 10, y: y + s * 6, width: s * 2, height: s * 2),
            NSRect(x: x - s * 2, y: y + s * 4, width: s * 4, height: s * 2),
            NSRect(x: x + s * 1.5, y: y, width: s * 1.3, height: s * 4),
            NSRect(x: x + s * 5.2, y: y, width: s * 1.3, height: s * 4),
            NSRect(x: x + s * 6.4, y: y + s * 10.6, width: s, height: s)
        ].forEach { $0.fill() }

        NSColor(calibratedRed: 0.96, green: 0.92, blue: 0.80, alpha: 1).setFill()
        NSRect(x: x + s * 8.6, y: y + s * 10.4, width: s * 0.9, height: s * 0.9).fill()
    }

    private func drawPixelClouds(in rect: NSRect) {
        for index in 0..<4 {
            let x = rect.width - (animationPhase * CGFloat(34 + index * 5)).truncatingRemainder(dividingBy: rect.width + 180) + CGFloat(index * 240)
            let y = rect.height * (0.65 + CGFloat(index % 2) * 0.10)
            NSColor.white.withAlphaComponent(0.36).setFill()
            NSRect(x: x, y: y, width: 72, height: 12).fill()
            NSRect(x: x + 18, y: y + 12, width: 32, height: 12).fill()
        }
    }

    private func drawRunnerScore(in rect: NSRect) {
        let score = "SCORE \(runnerScore)"
        score.draw(in: NSRect(x: rect.maxX - 190, y: rect.maxY - 58, width: 150, height: 26), withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 18, weight: .heavy),
            .foregroundColor: NSColor(calibratedRed: 0.18, green: 0.15, blue: 0.13, alpha: 0.68)
        ])
    }

    private func drawStars(in rect: NSRect) {
        for index in 0..<90 {
            let x = unitNoise(CGFloat(index) * 13.4) * rect.width
            let y = unitNoise(CGFloat(index) * 41.2) * rect.height
            let pulse = 0.28 + abs(sin(animationPhase * 2 + CGFloat(index))) * 0.38
            NSColor.white.withAlphaComponent(pulse).setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 2.2, height: 2.2)).fill()
        }
    }

    private func drawSolarSystem(in rect: NSRect) {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let sunSize = min(rect.width, rect.height) * 0.14
        let planets: [(orbitX: CGFloat, orbitY: CGFloat, size: CGFloat, speed: CGFloat, color: NSColor)] = [
            (0.11, 0.07, 0.018, 2.4, NSColor(calibratedRed: 0.74, green: 0.68, blue: 0.58, alpha: 1)),
            (0.16, 0.10, 0.024, 1.9, NSColor(calibratedRed: 0.94, green: 0.72, blue: 0.42, alpha: 1)),
            (0.22, 0.14, 0.026, 1.45, NSColor(calibratedRed: 0.20, green: 0.55, blue: 0.92, alpha: 1)),
            (0.28, 0.18, 0.022, 1.13, NSColor(calibratedRed: 0.88, green: 0.32, blue: 0.24, alpha: 1)),
            (0.36, 0.23, 0.056, 0.82, NSColor(calibratedRed: 0.90, green: 0.66, blue: 0.42, alpha: 1)),
            (0.45, 0.29, 0.050, 0.62, NSColor(calibratedRed: 0.86, green: 0.74, blue: 0.50, alpha: 1)),
            (0.52, 0.34, 0.036, 0.46, NSColor(calibratedRed: 0.48, green: 0.84, blue: 0.86, alpha: 1)),
            (0.59, 0.38, 0.034, 0.34, NSColor(calibratedRed: 0.34, green: 0.44, blue: 0.86, alpha: 1))
        ]

        for planet in planets {
            let orbit = NSRect(
                x: center.x - rect.width * planet.orbitX,
                y: center.y - rect.height * planet.orbitY,
                width: rect.width * planet.orbitX * 2,
                height: rect.height * planet.orbitY * 2
            )
            NSColor.white.withAlphaComponent(0.065).setStroke()
            let path = NSBezierPath(ovalIn: orbit)
            path.lineWidth = 1.2
            path.stroke()
        }

        drawSun(at: center, size: sunSize)

        for (index, planet) in planets.enumerated() {
            let phase = animationPhase * planet.speed + CGFloat(index) * 0.78
            let point = NSPoint(
                x: center.x + cos(phase) * rect.width * planet.orbitX,
                y: center.y + sin(phase) * rect.height * planet.orbitY
            )
            let size = min(rect.width, rect.height) * planet.size
            drawSolarPlanet(at: point, size: size, color: planet.color, hasRing: index == 5)
        }
    }

    private func drawSun(at point: NSPoint, size: CGFloat) {
        for index in (0..<4).reversed() {
            let glow = size + CGFloat(index) * size * 0.45
            NSColor(calibratedRed: 1.0, green: 0.68, blue: 0.14, alpha: 0.06 + CGFloat(3 - index) * 0.025).setFill()
            NSBezierPath(ovalIn: NSRect(x: point.x - glow / 2, y: point.y - glow / 2, width: glow, height: glow)).fill()
        }
        NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.24, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)).fill()
        NSColor(calibratedRed: 1.0, green: 0.95, blue: 0.54, alpha: 0.85).setFill()
        NSBezierPath(ovalIn: NSRect(x: point.x - size * 0.18, y: point.y + size * 0.06, width: size * 0.24, height: size * 0.24)).fill()
    }

    private func drawSolarPlanet(at point: NSPoint, size: CGFloat, color: NSColor, hasRing: Bool) {
        if hasRing {
            NSColor(calibratedRed: 0.92, green: 0.82, blue: 0.58, alpha: 0.50).setStroke()
            let ring = NSBezierPath(ovalIn: NSRect(x: point.x - size * 1.15, y: point.y - size * 0.30, width: size * 2.30, height: size * 0.60))
            ring.lineWidth = max(2, size * 0.12)
            ring.stroke()
        }

        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)).fill()
        NSColor.white.withAlphaComponent(0.28).setFill()
        NSBezierPath(ovalIn: NSRect(x: point.x - size * 0.18, y: point.y + size * 0.06, width: size * 0.22, height: size * 0.22)).fill()
    }

    private func drawRainyHorizon(in rect: NSRect) {
        let groundY = rect.height * 0.22
        NSColor(calibratedRed: 0.07, green: 0.18, blue: 0.16, alpha: 0.70).setFill()
        NSBezierPath(rect: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: groundY)).fill()

        let hills = NSBezierPath()
        hills.move(to: NSPoint(x: rect.minX, y: groundY))
        stride(from: rect.minX, through: rect.maxX + 90, by: 90).forEach { x in
            let crest = groundY + rect.height * (0.04 + unitNoise(x * 0.013) * 0.07)
            hills.curve(to: NSPoint(x: x + 90, y: groundY), controlPoint1: NSPoint(x: x + 26, y: crest), controlPoint2: NSPoint(x: x + 58, y: crest))
        }
        hills.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        hills.line(to: NSPoint(x: rect.minX, y: rect.minY))
        hills.close()
        NSColor(calibratedRed: 0.10, green: 0.27, blue: 0.23, alpha: 0.82).setFill()
        hills.fill()
    }

    private func drawRainClouds(in rect: NSRect) {
        for index in 0..<5 {
            let width = rect.width * (0.20 + CGFloat(index % 2) * 0.08)
            let height = rect.height * 0.09
            let x = rect.width * unitNoise(CGFloat(index) * 19.4) - width * 0.18 + sin(animationPhase * 0.32 + CGFloat(index)) * 18
            let y = rect.height * (0.72 + unitNoise(CGFloat(index) * 7.9) * 0.18)
            drawCloud(in: NSRect(x: x, y: y, width: width, height: height), alpha: 0.24 + CGFloat(index % 2) * 0.08)
        }
    }

    private func drawCloud(in rect: NSRect, alpha: CGFloat) {
        NSColor(calibratedRed: 0.78, green: 0.85, blue: 0.88, alpha: alpha).setFill()
        NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.58), xRadius: rect.height * 0.28, yRadius: rect.height * 0.28).fill()
        NSBezierPath(ovalIn: NSRect(x: rect.minX + rect.width * 0.14, y: rect.minY + rect.height * 0.18, width: rect.width * 0.26, height: rect.height * 0.74)).fill()
        NSBezierPath(ovalIn: NSRect(x: rect.minX + rect.width * 0.34, y: rect.minY + rect.height * 0.10, width: rect.width * 0.30, height: rect.height * 0.84)).fill()
        NSBezierPath(ovalIn: NSRect(x: rect.minX + rect.width * 0.58, y: rect.minY + rect.height * 0.18, width: rect.width * 0.24, height: rect.height * 0.68)).fill()
    }

    private func drawPuddles(in rect: NSRect) {
        for index in 0..<5 {
            let width = rect.width * (0.10 + CGFloat(index % 3) * 0.035)
            let x = rect.width * unitNoise(CGFloat(index) * 23.1)
            let y = rect.height * (0.05 + unitNoise(CGFloat(index) * 9.3) * 0.13)
            NSColor(calibratedRed: 0.55, green: 0.76, blue: 0.82, alpha: 0.20).setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: y, width: width, height: width * 0.16)).fill()
        }
    }

    private func drawRain(in rect: NSRect) {
        for index in 0..<95 {
            let x = unitNoise(CGFloat(index) * 9.7) * rect.width
            let y = (unitNoise(CGFloat(index) * 17.1) * rect.height - animationPhase * CGFloat(220 + index % 7 * 12)).truncatingRemainder(dividingBy: rect.height + 120)
            let path = NSBezierPath()
            path.move(to: NSPoint(x: x, y: y))
            path.line(to: NSPoint(x: x + 14, y: y - 42))
            path.lineWidth = 1.4
            NSColor.white.withAlphaComponent(0.22).setStroke()
            path.stroke()
        }
    }

    private func drawArcadeGrid(in rect: NSRect) {
        drawGrid(in: rect, alpha: 0.08)
    }

    private func drawArcadeBlocks(in rect: NSRect) {
        for index in 0..<18 {
            let x = unitNoise(CGFloat(index) * 12.1) * rect.width
            let y = unitNoise(CGFloat(index) * 4.9) * rect.height
            colorForIndex(index, alpha: 0.22).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 34 + CGFloat(index % 4) * 16, height: 18), xRadius: 4, yRadius: 4).fill()
        }
    }

    private func drawPulseRings(in rect: NSRect) {
        let center = NSPoint(x: rect.width * 0.50, y: rect.height * 0.50)
        for index in 0..<5 {
            let radius = CGFloat(120 + index * 90) + (animationPhase * 38).truncatingRemainder(dividingBy: 80)
            let ring = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            ring.lineWidth = 2
            NSColor(calibratedRed: 0.98, green: 0.21, blue: 0.70, alpha: 0.16).setStroke()
            ring.stroke()
        }
    }

    private func drawPaperTexture(in rect: NSRect) {
        for index in 0..<22 {
            let y = CGFloat(index) * 54 + (animationPhase * 2).truncatingRemainder(dividingBy: 54)
            NSColor.white.withAlphaComponent(0.07).setStroke()
            let line = NSBezierPath()
            line.move(to: NSPoint(x: 0, y: y))
            line.line(to: NSPoint(x: rect.width, y: y))
            line.lineWidth = 1
            line.stroke()
        }
    }

    private func drawPinnedNotes(in rect: NSRect) {
        for index in 0..<7 {
            let x = unitNoise(CGFloat(index) * 22.2) * rect.width
            let y = unitNoise(CGFloat(index) * 31.5) * rect.height
            colorForIndex(index, alpha: 0.56).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 110, height: 84), xRadius: 8, yRadius: 8).fill()
        }
    }

    private func drawSynthSun(in rect: NSRect) {
        let sun = NSRect(x: rect.midX - 150, y: rect.height * 0.54, width: 300, height: 300)
        NSColor(calibratedRed: 1.00, green: 0.38, blue: 0.40, alpha: 0.48).setFill()
        NSBezierPath(ovalIn: sun).fill()
    }

    private func drawPerspectiveGrid(in rect: NSRect) {
        let horizon = rect.height * 0.42
        let path = NSBezierPath()
        for index in -12...12 {
            path.move(to: NSPoint(x: rect.midX, y: horizon))
            path.line(to: NSPoint(x: rect.midX + CGFloat(index) * rect.width * 0.12, y: 0))
        }
        for index in 0..<16 {
            let y = horizon - pow(CGFloat(index) / 16, 1.7) * horizon
            path.move(to: NSPoint(x: 0, y: y))
            path.line(to: NSPoint(x: rect.width, y: y))
        }
        path.lineWidth = 1.2
        NSColor(calibratedRed: 0.20, green: 0.82, blue: 0.92, alpha: 0.24).setStroke()
        path.stroke()
    }

    private func drawMountains(in rect: NSRect) {
        let left = NSBezierPath()
        left.move(to: NSPoint(x: 0, y: rect.height * 0.38))
        left.line(to: NSPoint(x: rect.width * 0.18, y: rect.height * 0.54))
        left.line(to: NSPoint(x: rect.width * 0.35, y: rect.height * 0.38))
        left.close()
        NSColor.black.withAlphaComponent(0.30).setFill()
        left.fill()
    }

    private func colorForIndex(_ index: Int, alpha: CGFloat) -> NSColor {
        switch index % 5 {
        case 0:
            NSColor(calibratedRed: 0.98, green: 0.84, blue: 0.28, alpha: alpha)
        case 1:
            NSColor(calibratedRed: 0.16, green: 0.80, blue: 0.75, alpha: alpha)
        case 2:
            NSColor(calibratedRed: 1.00, green: 0.36, blue: 0.55, alpha: alpha)
        case 3:
            NSColor(calibratedRed: 0.59, green: 0.50, blue: 1.00, alpha: alpha)
        default:
            NSColor.white.withAlphaComponent(alpha)
        }
    }

    private func unitNoise(_ value: CGFloat) -> CGFloat {
        let raw = sin(value) * 43758.5453
        return raw - floor(raw)
    }
}

private struct AwayoStickyNote {
    let author: String
    let message: String
    let colorIndex: Int
    let position: NSPoint
}

@MainActor
private final class SnapshotPrankCardView: NSView {
    private let image: NSImage?
    private let focusPoint: NSPoint?
    private let timestamp: Date
    private let detail: String
    private let index: Int

    init(image: NSImage?, focusPoint: NSPoint?, timestamp: Date, detail: String, index: Int) {
        self.image = image
        self.focusPoint = focusPoint
        self.timestamp = timestamp
        self.detail = detail
        self.index = index
        super.init(frame: .zero)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.34
        layer?.shadowRadius = 24
        layer?.shadowOffset = NSSize(width: 0, height: -10)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let card = bounds.insetBy(dx: 4, dy: 4)
        let paper = NSBezierPath(roundedRect: card, xRadius: 6, yRadius: 6)
        NSColor(calibratedRed: 0.96, green: 0.91, blue: 0.78, alpha: 0.98).setFill()
        paper.fill()

        NSColor(calibratedRed: 0.30, green: 0.20, blue: 0.10, alpha: 0.16).setStroke()
        paper.lineWidth = 1
        paper.stroke()

        drawPaperFlecks(in: card)

        let photoRect = NSRect(
            x: card.minX + 14,
            y: card.minY + 88,
            width: card.width - 28,
            height: card.height - 116
        )
        drawVintageSnapshot(in: photoRect)
        drawStamp(in: photoRect)

        drawText(
            "NICE TRY!",
            in: NSRect(x: card.minX + 18, y: card.minY + 42, width: card.width - 36, height: 34),
            font: NSFont(name: "Copperplate-Bold", size: 25) ?? .systemFont(ofSize: 25, weight: .black),
            color: NSColor(calibratedRed: 0.34, green: 0.15, blue: 0.08, alpha: 0.92)
        )

        let caption = "attempt \(String(format: "%02d", index + 1))  -  \(timestamp.formatted(date: .omitted, time: .shortened))"
        drawText(
            caption,
            in: NSRect(x: card.minX + 18, y: card.minY + 21, width: card.width - 36, height: 18),
            font: .monospacedSystemFont(ofSize: 10, weight: .bold),
            color: NSColor(calibratedRed: 0.30, green: 0.17, blue: 0.08, alpha: 0.82)
        )
    }

    private func drawVintageSnapshot(in rect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).addClip()

        if let image {
            let source = sourceRect(for: image.size, targetAspect: rect.width / max(1, rect.height))
            image.draw(in: rect, from: source, operation: .sourceOver, fraction: 0.96)
            NSColor(calibratedRed: 0.78, green: 0.56, blue: 0.22, alpha: 0.09).setFill()
            rect.fill(using: .sourceAtop)
        } else {
            NSGradient(colors: [
                NSColor(calibratedRed: 0.36, green: 0.31, blue: 0.24, alpha: 1),
                NSColor(calibratedRed: 0.14, green: 0.12, blue: 0.10, alpha: 1)
            ])?.draw(in: rect, angle: -35)
        }

        NSColor.black.withAlphaComponent(0.03).setFill()
        rect.fill(using: .sourceAtop)

        NSColor.white.withAlphaComponent(0.06).setStroke()
        for line in 0..<9 {
            let y = rect.minY + CGFloat(line) * rect.height / 8
            let path = NSBezierPath()
            path.move(to: NSPoint(x: rect.minX, y: y))
            path.line(to: NSPoint(x: rect.maxX, y: y + CGFloat(line % 2 == 0 ? 1 : -1)))
            path.lineWidth = 1
            path.stroke()
        }

        NSGraphicsContext.restoreGraphicsState()

        NSColor(calibratedRed: 0.22, green: 0.14, blue: 0.08, alpha: 0.32).setStroke()
        let border = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        border.lineWidth = 1.5
        border.stroke()
    }

    private func drawStamp(in rect: NSRect) {
        let stamp = NSRect(x: rect.maxX - 124, y: rect.minY + 12, width: 108, height: 34)

        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: stamp.midX, yBy: stamp.midY)
        transform.rotate(byDegrees: -11)
        transform.translateX(by: -stamp.midX, yBy: -stamp.midY)
        transform.concat()

        let path = NSBezierPath(roundedRect: stamp, xRadius: 4, yRadius: 4)
        NSColor(calibratedRed: 0.64, green: 0.08, blue: 0.05, alpha: 0.08).setFill()
        path.fill()
        NSColor(calibratedRed: 0.70, green: 0.06, blue: 0.04, alpha: 0.74).setStroke()
        path.lineWidth = 2
        path.stroke()
        drawText(
            "NICE TRY!",
            in: stamp.insetBy(dx: 6, dy: 8),
            font: .monospacedSystemFont(ofSize: 14, weight: .black),
            color: NSColor(calibratedRed: 0.72, green: 0.06, blue: 0.04, alpha: 0.82)
        )

        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawPaperFlecks(in rect: NSRect) {
        for fleck in 0..<38 {
            let seed = CGFloat(fleck)
            let x = rect.minX + unitNoise(seed * 9.1) * rect.width
            let y = rect.minY + unitNoise(seed * 17.7) * rect.height
            let size = CGFloat(0.8 + Double(fleck % 3) * 0.55)
            NSColor(calibratedRed: 0.33, green: 0.21, blue: 0.12, alpha: 0.07).setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: y, width: size, height: size)).fill()
        }
    }

    private func sourceRect(for imageSize: NSSize, targetAspect: CGFloat) -> NSRect {
        var width = min(imageSize.width, imageSize.height * targetAspect)
        var height = width / max(0.01, targetAspect)

        if height > imageSize.height {
            height = imageSize.height
            width = height * targetAspect
        }

        let focus = focusPoint ?? NSPoint(x: imageSize.width / 2, y: imageSize.height / 2)
        let x = min(max(focus.x - width / 2, 0), max(0, imageSize.width - width))
        let y = min(max(focus.y - height / 2, 0), max(0, imageSize.height - height))
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func drawText(_ text: String, in rect: NSRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        text.draw(in: rect, withAttributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
    }

    private func unitNoise(_ value: CGFloat) -> CGFloat {
        let raw = sin(value) * 43758.5453
        return raw - floor(raw)
    }
}

@MainActor
private final class SnapshotPrankCountdownView: NSView {
    var remainingSeconds = 3 {
        didSet {
            needsDisplay = true
        }
    }

    var statusText = "visible camera snap" {
        didSet {
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.36
        layer?.shadowRadius = 28
        layer?.shadowOffset = NSSize(width: 0, height: -10)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let card = bounds.insetBy(dx: 4, dy: 4)
        let path = NSBezierPath(roundedRect: card, xRadius: 12, yRadius: 12)
        NSColor(calibratedRed: 0.08, green: 0.06, blue: 0.05, alpha: 0.68).setFill()
        path.fill()

        NSColor(calibratedRed: 0.98, green: 0.85, blue: 0.52, alpha: 0.28).setStroke()
        path.lineWidth = 1
        path.stroke()

        drawCameraIcon(in: NSRect(x: card.minX + 18, y: card.midY - 16, width: 54, height: 34))

        drawText(
            "nice try",
            in: NSRect(x: card.minX + 82, y: card.midY + 2, width: card.width - 104, height: 24),
            font: .systemFont(ofSize: 17, weight: .black),
            color: NSColor(calibratedRed: 1.0, green: 0.88, blue: 0.54, alpha: 0.84)
        )

        let countdown = remainingSeconds > 0 ? "\(remainingSeconds)" : "snap"
        drawText(
            countdown,
            in: NSRect(x: card.minX + 82, y: card.midY - 24, width: card.width - 104, height: 24),
            font: .monospacedSystemFont(ofSize: 16, weight: .heavy),
            color: NSColor.white.withAlphaComponent(0.72)
        )
    }

    private func drawCameraIcon(in rect: NSRect) {
        NSColor(calibratedRed: 0.98, green: 0.85, blue: 0.52, alpha: 0.88).setFill()
        NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.76), xRadius: 10, yRadius: 10).fill()
        NSBezierPath(roundedRect: NSRect(x: rect.minX + 18, y: rect.maxY - 20, width: 34, height: 16), xRadius: 5, yRadius: 5).fill()

        NSColor(calibratedRed: 0.12, green: 0.08, blue: 0.06, alpha: 0.92).setFill()
        NSBezierPath(ovalIn: NSRect(x: rect.midX - 17, y: rect.minY + 7, width: 34, height: 34)).fill()
        NSColor(calibratedRed: 0.98, green: 0.85, blue: 0.52, alpha: 0.92).setStroke()
        let lens = NSBezierPath(ovalIn: NSRect(x: rect.midX - 24, y: rect.minY, width: 48, height: 48))
        lens.lineWidth = 4
        lens.stroke()

        NSColor(calibratedRed: 0.96, green: 0.10, blue: 0.08, alpha: 0.95).setFill()
        NSBezierPath(ovalIn: NSRect(x: rect.maxX - 20, y: rect.maxY - 22, width: 11, height: 11)).fill()
    }

    private func drawText(_ text: String, in rect: NSRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        text.draw(in: rect, withAttributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
    }
}

private final class AwayoCameraSnapshotter: NSObject, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private struct SnapshotResult: @unchecked Sendable {
        let imageData: Data?
    }

    private let completion: @MainActor (NSImage?) -> Void
    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "app.awayo.camera-snapshot", qos: .userInitiated)
    private let ciContext = CIContext()
    private var didFinish = false
    private var firstVideoFrameData: Data?

    init(completion: @escaping @MainActor (NSImage?) -> Void) {
        self.completion = completion
        super.init()
    }

    func capture() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndCapture()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else {
                    return
                }

                if granted {
                    self.configureAndCapture()
                } else {
                    self.finishOnQueue(with: nil)
                }
            }
        case .denied, .restricted:
            finishOnQueue(with: nil)
        @unknown default:
            finishOnQueue(with: nil)
        }
    }

    private func configureAndCapture() {
        queue.async { [weak self] in
            guard let self else {
                return
            }

            self.session.beginConfiguration()
            self.session.sessionPreset = .medium

            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
                    ?? AVCaptureDevice.default(for: .video),
                let input = try? AVCaptureDeviceInput(device: device),
                self.session.canAddInput(input),
                self.session.canAddOutput(self.photoOutput)
            else {
                self.session.commitConfiguration()
                self.finishOnQueue(with: nil)
                return
            }

            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.setSampleBufferDelegate(self, queue: self.queue)

            self.session.addInput(input)
            self.session.addOutput(self.photoOutput)
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
            }
            self.session.commitConfiguration()
            self.session.startRunning()

            self.queue.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.capturePhotoOnQueue()
            }

            self.queue.asyncAfter(deadline: .now() + 8) { [weak self] in
                guard let self else {
                    return
                }

                self.finishOnQueue(with: self.firstVideoFrameData)
            }
        }
    }

    private func capturePhotoOnQueue() {
        guard !didFinish else {
            return
        }

        let settings: AVCapturePhotoSettings
        if photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        } else {
            settings = AVCapturePhotoSettings()
        }

        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let imageData = error == nil ? photo.fileDataRepresentation() : nil
        queue.async { [weak self, imageData] in
            guard let self else {
                return
            }

            self.finishOnQueue(with: imageData ?? self.firstVideoFrameData)
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from _: AVCaptureConnection
    ) {
        guard !didFinish, let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        guard firstVideoFrameData == nil else {
            return
        }

        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        firstVideoFrameData = bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: 0.86]
        )
    }

    private func finishOnQueue(with imageData: Data?) {
        queue.async { [weak self, imageData] in
            self?.finishNowOnQueue(with: imageData)
        }
    }

    private func finishNowOnQueue(with imageData: Data?) {
        guard !didFinish else {
            return
        }

        didFinish = true
        videoOutput.setSampleBufferDelegate(nil, queue: nil)

        let result = SnapshotResult(imageData: imageData)
        DispatchQueue.main.async { [completion, result] in
            completion(result.imageData.flatMap(NSImage.init(data:)))
        }

        queue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }
}

@MainActor
private final class StickyNoteComposerView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.28
        layer?.shadowRadius = 20
        layer?.shadowOffset = NSSize(width: 0, height: -8)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let note = bounds.insetBy(dx: 4, dy: 4)
        NSColor(calibratedRed: 1.0, green: 0.88, blue: 0.25, alpha: 0.98).setFill()
        NSBezierPath(roundedRect: note, xRadius: 7, yRadius: 7).fill()

        NSColor.black.withAlphaComponent(0.10).setStroke()
        let edge = NSBezierPath(roundedRect: note, xRadius: 7, yRadius: 7)
        edge.lineWidth = 1
        edge.stroke()

        NSColor.white.withAlphaComponent(0.62).setFill()
        NSBezierPath(roundedRect: NSRect(x: note.midX - 36, y: note.maxY - 13, width: 72, height: 18), xRadius: 4, yRadius: 4).fill()

        NSColor.black.withAlphaComponent(0.12).setStroke()
        for index in 0..<6 {
            let y = note.minY + 45 + CGFloat(index) * 21
            guard y < note.maxY - 24 else {
                continue
            }

            let line = NSBezierPath()
            line.move(to: NSPoint(x: note.minX + 18, y: y))
            line.line(to: NSPoint(x: note.maxX - 18, y: y + CGFloat(index % 2 == 0 ? 1 : -1)))
            line.lineWidth = 1.2
            line.stroke()
        }
    }
}

@MainActor
private final class StickyNoteCardView: NSView {
    private let note: AwayoStickyNote
    private let style: AwayoNoteStyle

    init(note: AwayoStickyNote, style: AwayoNoteStyle, usesConstraints: Bool = true) {
        self.note = note
        self.style = style
        super.init(frame: NSRect(x: 0, y: 0, width: 238, height: 206))
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = !usesConstraints
        if usesConstraints {
            widthAnchor.constraint(equalToConstant: 282).isActive = true
            heightAnchor.constraint(greaterThanOrEqualToConstant: 168).isActive = true
        }
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.cornerRadius = style == .glassCard ? 10 : 7
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = style == .glassCard ? 0.26 : 0.30
        layer?.shadowRadius = style == .glassCard ? 16 : 12
        layer?.shadowOffset = NSSize(width: 0, height: -5)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: style == .tapedPaper ? 20 : 13, left: 14, bottom: 12, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let author = NSTextField(labelWithString: "from \(note.author)")
        author.font = authorFont
        author.textColor = secondaryTextColor

        let message = NSTextField(labelWithString: note.message)
        message.font = messageFont
        message.textColor = primaryTextColor
        message.maximumNumberOfLines = 7
        message.lineBreakMode = .byWordWrapping
        message.preferredMaxLayoutWidth = 210

        stack.addArrangedSubview(author)
        stack.addArrangedSubview(message)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    override func draw(_ dirtyRect: NSRect) {
        let note = bounds.insetBy(dx: 3, dy: 3)

        if style == .stickyStack {
            cardColor.withAlphaComponent(0.78).setFill()
            NSBezierPath(roundedRect: note.offsetBy(dx: 7, dy: -7), xRadius: 7, yRadius: 7).fill()
            NSColor(calibratedRed: 1.0, green: 0.38, blue: 0.57, alpha: 0.86).setFill()
            NSBezierPath(roundedRect: note.offsetBy(dx: 13, dy: -13), xRadius: 7, yRadius: 7).fill()
        }

        cardColor.setFill()
        NSBezierPath(roundedRect: note, xRadius: style == .glassCard ? 10 : 7, yRadius: style == .glassCard ? 10 : 7).fill()
        NSColor.black.withAlphaComponent(style == .glassCard ? 0.04 : 0.13).setStroke()
        let edge = NSBezierPath(roundedRect: note, xRadius: style == .glassCard ? 10 : 7, yRadius: style == .glassCard ? 10 : 7)
        edge.lineWidth = 1
        edge.stroke()

        switch style {
        case .tapedPaper:
            drawTape()
        case .stickyStack:
            drawRuledLines()
        case .glassCard:
            drawGlassSheen()
        case .markerCard:
            drawMarkerStroke()
            drawFoldedCorner()
        case .hidden:
            break
        }
    }

    private var cardColor: NSColor {
        switch style {
        case .glassCard:
            return NSColor.white.withAlphaComponent(0.22)
        case .markerCard:
            return NSColor(calibratedWhite: 0.98, alpha: 0.96)
        case .tapedPaper, .stickyStack, .hidden:
            break
        }

        switch note.colorIndex % 5 {
        case 0:
            return NSColor(calibratedRed: 1.00, green: 0.89, blue: 0.38, alpha: 0.96)
        case 1:
            return NSColor(calibratedRed: 0.63, green: 0.94, blue: 0.86, alpha: 0.96)
        case 2:
            return NSColor(calibratedRed: 1.00, green: 0.68, blue: 0.78, alpha: 0.96)
        case 3:
            return NSColor(calibratedRed: 0.77, green: 0.72, blue: 1.00, alpha: 0.96)
        default:
            return NSColor(calibratedRed: 0.95, green: 0.95, blue: 0.86, alpha: 0.96)
        }
    }

    private var authorFont: NSFont {
        switch style {
        case .markerCard:
            .systemFont(ofSize: 12, weight: .black)
        case .tapedPaper:
            .systemFont(ofSize: 12, weight: .heavy)
        case .stickyStack, .glassCard, .hidden:
            .systemFont(ofSize: 12, weight: .bold)
        }
    }

    private var messageFont: NSFont {
        switch style {
        case .markerCard:
            .systemFont(ofSize: 14, weight: .bold)
        case .tapedPaper:
            .systemFont(ofSize: 13, weight: .semibold)
        case .stickyStack:
            .systemFont(ofSize: 13, weight: .bold)
        case .glassCard, .hidden:
            .systemFont(ofSize: 13, weight: .semibold)
        }
    }

    private var primaryTextColor: NSColor {
        style == .glassCard ? .white : NSColor.black.withAlphaComponent(0.82)
    }

    private var secondaryTextColor: NSColor {
        style == .glassCard ? NSColor.white.withAlphaComponent(0.72) : NSColor.black.withAlphaComponent(0.60)
    }

    private func drawTape() {
        NSColor.white.withAlphaComponent(0.64).setFill()
        NSBezierPath(roundedRect: NSRect(x: bounds.midX - 39, y: bounds.maxY - 16, width: 78, height: 19), xRadius: 4, yRadius: 4).fill()
        drawRuledLines()
    }

    private func drawRuledLines() {
        NSColor.black.withAlphaComponent(0.12).setStroke()
        for index in 0..<7 {
            let y = bounds.minY + 24 + CGFloat(index) * 18
            guard y < bounds.maxY - 26 else {
                continue
            }

            let path = NSBezierPath()
            path.move(to: NSPoint(x: bounds.minX + 16, y: y))
            path.line(to: NSPoint(x: bounds.maxX - 16, y: y + CGFloat(index % 2 == 0 ? 1 : -1)))
            path.lineWidth = 1.2
            path.stroke()
        }
    }

    private func drawGlassSheen() {
        NSColor.white.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: NSRect(x: 14, y: bounds.maxY - 24, width: bounds.width - 28, height: 2), xRadius: 1, yRadius: 1).fill()
    }

    private func drawMarkerStroke() {
        NSColor.black.withAlphaComponent(0.18).setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 14, y: 18))
        path.line(to: NSPoint(x: bounds.width - 18, y: 22))
        path.lineWidth = 3
        path.stroke()
    }

    private func drawFoldedCorner() {
        NSColor.black.withAlphaComponent(0.08).setFill()
        let fold = NSBezierPath()
        fold.move(to: NSPoint(x: bounds.maxX - 26, y: bounds.maxY - 3))
        fold.line(to: NSPoint(x: bounds.maxX - 3, y: bounds.maxY - 26))
        fold.line(to: NSPoint(x: bounds.maxX - 3, y: bounds.maxY - 3))
        fold.close()
        fold.fill()
    }
}
