import AppKit

@MainActor
final class AwayoSettingsWindowController: NSWindowController {
    private let settingsStore: AwayoSettingsStore
    private let passcodeStore: PasscodeStore
    private let onPasscodeChange: () -> Void

    private var backgroundTiles: [AwayoPreviewTile] = []
    private var timerTiles: [AwayoPreviewTile] = []
    private var dashboardTiles: [AwayoPreviewTile] = []
    private var noteTiles: [AwayoPreviewTile] = []
    private let headerTitleLabel = NSTextField(labelWithString: "")
    private let headerSubtitleLabel = NSTextField(labelWithString: "")
    private var passcodeStatusLabel = NSTextField(labelWithString: "")
    private let passcodeButton = NSButton(title: "Set Passcode", target: nil, action: nil)
    private var onboarding = false

    init(
        settingsStore: AwayoSettingsStore,
        passcodeStore: PasscodeStore,
        onPasscodeChange: @escaping () -> Void
    ) {
        self.settingsStore = settingsStore
        self.passcodeStore = passcodeStore
        self.onPasscodeChange = onPasscodeChange

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 720),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Awayo Settings"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)

        window.contentView = buildContentView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(onboarding: Bool) {
        self.onboarding = onboarding
        window?.title = onboarding ? "Set Up Awayo" : "Awayo Settings"
        refreshHeader()
        refreshSelections()
        refreshPasscodeStatus()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildContentView() -> NSView {
        let root = NSVisualEffectView()
        root.material = .windowBackground
        root.blendingMode = .behindWindow
        root.state = .active

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scrollView)

        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 22
        content.edgeInsets = NSEdgeInsets(top: 30, left: 34, bottom: 30, right: 34)
        content.translatesAutoresizingMaskIntoConstraints = false

        let document = NSView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(content)
        scrollView.documentView = document

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            content.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            content.topAnchor.constraint(equalTo: document.topAnchor),
            content.bottomAnchor.constraint(equalTo: document.bottomAnchor)
        ])

        content.addArrangedSubview(headerView())
        content.addArrangedSubview(passcodeSection())
        content.addArrangedSubview(sectionTitle("Backgrounds", "Pick the scene Awayo Lock uses every time it starts."))
        content.addArrangedSubview(tileGrid(for: .background))
        content.addArrangedSubview(sectionTitle("Timer", "Choose the way the countdown feels."))
        content.addArrangedSubview(tileGrid(for: .timer))
        content.addArrangedSubview(sectionTitle("Dashboard", "Choose how much presence the center display has."))
        content.addArrangedSubview(tileGrid(for: .dashboard))
        content.addArrangedSubview(sectionTitle("Sticky Notes", "Choose how notes from visitors should look."))
        content.addArrangedSubview(tileGrid(for: .note))
        content.addArrangedSubview(doneRow())

        return root
    }

    private func headerView() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8

        let eyebrow = NSTextField(labelWithString: "AWAYO")
        eyebrow.font = .monospacedSystemFont(ofSize: 12, weight: .heavy)
        eyebrow.textColor = NSColor(calibratedRed: 0.98, green: 0.84, blue: 0.28, alpha: 1)

        headerTitleLabel.font = .systemFont(ofSize: 34, weight: .black)
        headerTitleLabel.textColor = .labelColor

        headerSubtitleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        headerSubtitleLabel.textColor = .secondaryLabelColor
        headerSubtitleLabel.maximumNumberOfLines = 2
        headerSubtitleLabel.preferredMaxLayoutWidth = 820
        refreshHeader()

        stack.addArrangedSubview(eyebrow)
        stack.addArrangedSubview(headerTitleLabel)
        stack.addArrangedSubview(headerSubtitleLabel)
        return stack
    }

    private func passcodeSection() -> NSView {
        let card = cardView()

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 18
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)

        let icon = NSTextField(labelWithString: "A")
        icon.font = .systemFont(ofSize: 30, weight: .black)
        icon.alignment = .center
        icon.textColor = .black
        icon.wantsLayer = true
        icon.layer?.backgroundColor = NSColor(calibratedRed: 0.98, green: 0.84, blue: 0.28, alpha: 1).cgColor
        icon.layer?.cornerRadius = 18
        icon.translatesAutoresizingMaskIntoConstraints = false

        let copy = NSStackView()
        copy.orientation = .vertical
        copy.alignment = .leading
        copy.spacing = 4

        let title = NSTextField(labelWithString: "Awayo Lock Passcode")
        title.font = .systemFont(ofSize: 17, weight: .bold)
        title.textColor = .labelColor

        passcodeStatusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        passcodeStatusLabel.textColor = .secondaryLabelColor

        copy.addArrangedSubview(title)
        copy.addArrangedSubview(passcodeStatusLabel)

        passcodeButton.target = self
        passcodeButton.action = #selector(setPasscode)
        passcodeButton.bezelStyle = .rounded
        passcodeButton.controlSize = .large
        passcodeButton.font = .systemFont(ofSize: 14, weight: .bold)

        row.addArrangedSubview(icon)
        row.addArrangedSubview(copy)
        row.addArrangedSubview(NSView())
        row.addArrangedSubview(passcodeButton)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 58),
            icon.heightAnchor.constraint(equalToConstant: 58),

            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18),
            card.widthAnchor.constraint(equalToConstant: 900)
        ])

        refreshPasscodeStatus()
        return card
    }

    private func sectionTitle(_ title: String, _ subtitle: String) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 20, weight: .black)
        titleLabel.textColor = .labelColor

        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        subtitleLabel.textColor = .secondaryLabelColor

        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(subtitleLabel)
        return stack
    }

    private func tileGrid(for category: AwayoPreviewCategory) -> NSView {
        let grid = NSGridView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 14
        grid.columnSpacing = 14

        let tiles = makeTiles(for: category)
        tiles.chunked(into: 4).forEach { rowTiles in
            let padded = rowTiles + Array(repeating: NSView(), count: max(0, 4 - rowTiles.count))
            grid.addRow(with: padded)
        }

        switch category {
        case .background:
            backgroundTiles = tiles
        case .timer:
            timerTiles = tiles
        case .dashboard:
            dashboardTiles = tiles
        case .note:
            noteTiles = tiles
        }

        return grid
    }

    private func makeTiles(for category: AwayoPreviewCategory) -> [AwayoPreviewTile] {
        switch category {
        case .background:
            AwayoLockStyle.allCases.map { tile(category: category, rawValue: $0.rawValue, title: $0.title) }
        case .timer:
            AwayoTimerStyle.allCases.map { tile(category: category, rawValue: $0.rawValue, title: $0.title) }
        case .dashboard:
            AwayoDashboardStyle.allCases.map { tile(category: category, rawValue: $0.rawValue, title: $0.title) }
        case .note:
            AwayoNoteStyle.allCases.map { tile(category: category, rawValue: $0.rawValue, title: $0.title) }
        }
    }

    private func tile(category: AwayoPreviewCategory, rawValue: String, title: String) -> AwayoPreviewTile {
        let tile = AwayoPreviewTile(category: category, rawValue: rawValue, title: title)
        tile.target = self
        tile.action = #selector(selectTile(_:))
        tile.translatesAutoresizingMaskIntoConstraints = false
        tile.widthAnchor.constraint(equalToConstant: 208).isActive = true
        tile.heightAnchor.constraint(equalToConstant: 138).isActive = true
        return tile
    }

    private func doneRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12

        let spacer = NSView()
        let done = NSButton(title: "Done", target: self, action: #selector(done))
        done.bezelStyle = .rounded
        done.controlSize = .large
        done.font = .systemFont(ofSize: 14, weight: .bold)

        row.addArrangedSubview(spacer)
        row.addArrangedSubview(done)
        row.widthAnchor.constraint(equalToConstant: 900).isActive = true
        return row
    }

    @objc private func selectTile(_ sender: AwayoPreviewTile) {
        switch sender.category {
        case .background:
            if let value = AwayoLockStyle(rawValue: sender.rawValue) {
                settingsStore.saveBackgroundStyle(value)
            }
        case .timer:
            if let value = AwayoTimerStyle(rawValue: sender.rawValue) {
                settingsStore.saveTimerStyle(value)
            }
        case .dashboard:
            if let value = AwayoDashboardStyle(rawValue: sender.rawValue) {
                settingsStore.saveDashboardStyle(value)
            }
        case .note:
            if let value = AwayoNoteStyle(rawValue: sender.rawValue) {
                settingsStore.saveNoteStyle(value)
            }
        }

        refreshSelections()
    }

    @objc private func setPasscode() {
        let alert = NSAlert()
        alert.messageText = passcodeStore.hasPasscode() ? "Change Awayo Lock Passcode" : "Set Awayo Lock Passcode"
        alert.informativeText = "This passcode unlocks Awayo Lock. Awayo stores a salted local hash, not the passcode itself."
        alert.alertStyle = .informational

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let passcodeField = NSSecureTextField()
        passcodeField.placeholderString = "New passcode"
        passcodeField.frame.size.width = 340

        let confirmationField = NSSecureTextField()
        confirmationField.placeholderString = "Confirm passcode"
        confirmationField.frame.size.width = 340

        stack.addArrangedSubview(label("New passcode"))
        stack.addArrangedSubview(passcodeField)
        stack.addArrangedSubview(label("Confirm passcode"))
        stack.addArrangedSubview(confirmationField)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 118))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        alert.accessoryView = container
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let passcode = passcodeField.stringValue
        let confirmation = confirmationField.stringValue

        guard !passcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showError("Awayo Lock needs a passcode.")
            return
        }

        guard passcode == confirmation else {
            showError("The passcodes did not match.")
            return
        }

        passcodeStore.savePasscode(passcode)
        onPasscodeChange()
        refreshPasscodeStatus()
    }

    @objc private func done() {
        if onboarding && !passcodeStore.hasPasscode() {
            showError("Set an Awayo Lock passcode to finish setup.")
            return
        }

        settingsStore.markFirstRunComplete()
        close()
    }

    private func refreshSelections() {
        let appearance = settingsStore.appearance()
        backgroundTiles.forEach { $0.isSelected = $0.rawValue == appearance.backgroundStyle.rawValue }
        timerTiles.forEach { $0.isSelected = $0.rawValue == appearance.timerStyle.rawValue }
        dashboardTiles.forEach { $0.isSelected = $0.rawValue == appearance.dashboardStyle.rawValue }
        noteTiles.forEach { $0.isSelected = $0.rawValue == appearance.noteStyle.rawValue }
    }

    private func refreshPasscodeStatus() {
        passcodeStatusLabel.stringValue = passcodeStore.hasPasscode()
            ? "Passcode is set. Awayo Lock is ready."
            : "Set this once before starting Awayo Lock."
        passcodeButton.title = passcodeStore.hasPasscode() ? "Change Passcode" : "Set Passcode"
    }

    private func refreshHeader() {
        if onboarding {
            headerTitleLabel.stringValue = "Set up your Awayo screen."
            headerSubtitleLabel.stringValue = "Pick the look once, set the passcode, and Awayo Lock will use these choices every time from the menu."
        } else {
            headerTitleLabel.stringValue = "Make your away screen feel alive."
            headerSubtitleLabel.stringValue = "Set your unlock passcode once, pick your style, then start Awayo Lock from the menu without choosing a background every time."
        }
    }

    private func cardView() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.68).cgColor
        view.layer?.cornerRadius = 8
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
        return view
    }

    private func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Awayo"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

enum AwayoPreviewCategory {
    case background
    case timer
    case dashboard
    case note
}

@MainActor
final class AwayoPreviewTile: NSButton {
    let category: AwayoPreviewCategory
    let rawValue: String
    private let displayTitle: String

    var isSelected = false {
        didSet {
            needsDisplay = true
        }
    }

    init(category: AwayoPreviewCategory, rawValue: String, title: String) {
        self.category = category
        self.rawValue = rawValue
        self.displayTitle = title
        super.init(frame: .zero)

        self.title = ""
        isBordered = false
        wantsLayer = true
        toolTip = title
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        NSColor.controlBackgroundColor.withAlphaComponent(0.72).setFill()
        path.fill()

        let previewRect = NSRect(x: rect.minX + 10, y: rect.minY + 40, width: rect.width - 20, height: rect.height - 50)
        drawPreview(in: previewRect)

        let titleRect = NSRect(x: rect.minX + 12, y: rect.minY + 12, width: rect.width - 24, height: 20)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .bold),
            .foregroundColor: NSColor.labelColor
        ]
        displayTitle.draw(in: titleRect, withAttributes: attributes)

        if isSelected {
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 4
            path.stroke()

            let checkRect = NSRect(x: rect.maxX - 32, y: rect.maxY - 32, width: 20, height: 20)
            NSColor.controlAccentColor.setFill()
            NSBezierPath(ovalIn: checkRect).fill()
            "OK".draw(
                in: checkRect.offsetBy(dx: 0, dy: -1),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 8, weight: .heavy),
                    .foregroundColor: NSColor.white,
                    .paragraphStyle: centeredParagraph()
                ]
            )
        } else {
            NSColor.separatorColor.withAlphaComponent(0.36).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    private func drawPreview(in rect: NSRect) {
        switch category {
        case .background:
            drawBackgroundPreview(in: rect)
        case .timer:
            drawTimerPreview(in: rect)
        case .dashboard:
            drawDashboardPreview(in: rect)
        case .note:
            drawNotePreview(in: rect)
        }
    }

    private func drawBackgroundPreview(in rect: NSRect) {
        guard let style = AwayoLockStyle(rawValue: rawValue) else {
            return
        }

        let colors: [NSColor]
        switch style {
        case .duckPond:
            colors = [.systemTeal, .systemBlue, .systemGreen]
        case .offlineRunner:
            colors = [.systemYellow, .systemOrange, .brown]
        case .cosmicDesk:
            colors = [.black, .systemPurple, .systemBlue]
        case .rainyWindow:
            colors = [.darkGray, .systemBlue, .black]
        case .arcadePulse:
            colors = [.black, .systemPink, .systemTeal]
        case .paperNotes:
            colors = [.systemYellow, .systemMint, .systemGray]
        case .synthwave:
            colors = [.black, .systemPink, .systemPurple]
        case .neonFlow:
            colors = [.black, .systemTeal, .systemPink]
        }

        roundedGradient(in: rect, colors: colors)

        switch style {
        case .duckPond:
            drawMiniDuck(in: rect)
        case .offlineRunner:
            drawMiniRunner(in: rect)
        case .paperNotes:
            drawMiniNotes(in: rect)
        default:
            drawMiniLines(in: rect)
        }
    }

    private func drawTimerPreview(in rect: NSRect) {
        roundedGradient(in: rect, colors: [.windowBackgroundColor, .controlBackgroundColor])
        let style = AwayoTimerStyle(rawValue: rawValue) ?? .heroCountdown
        let text = style == .terminalTicker ? "$ 14m 32s" : "14m 32s"
        let font: NSFont = switch style {
        case .heroCountdown:
            .monospacedDigitSystemFont(ofSize: 28, weight: .heavy)
        case .paperClock:
            .systemFont(ofSize: 24, weight: .black)
        case .glassPill:
            .monospacedDigitSystemFont(ofSize: 22, weight: .bold)
        case .terminalTicker:
            .monospacedSystemFont(ofSize: 20, weight: .bold)
        }
        text.draw(in: rect.insetBy(dx: 12, dy: 28), withAttributes: [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: centeredParagraph()
        ])
    }

    private func drawDashboardPreview(in rect: NSRect) {
        roundedGradient(in: rect, colors: [.systemBlue.withAlphaComponent(0.55), .systemPurple.withAlphaComponent(0.45)])
        let style = AwayoDashboardStyle(rawValue: rawValue) ?? .centerStage
        switch style {
        case .centerStage:
            drawPill(in: rect.insetBy(dx: 26, dy: 24), color: .white.withAlphaComponent(0.78))
        case .paperDesk:
            drawPill(in: rect.insetBy(dx: 18, dy: 18), color: .systemYellow.withAlphaComponent(0.82))
        case .minimalBadge:
            drawPill(in: NSRect(x: rect.midX - 38, y: rect.midY - 16, width: 76, height: 32), color: .white.withAlphaComponent(0.82))
        case .commandCenter:
            drawPill(in: rect.insetBy(dx: 12, dy: 14), color: .black.withAlphaComponent(0.52))
        }
    }

    private func drawNotePreview(in rect: NSRect) {
        roundedGradient(in: rect, colors: [.systemGray.withAlphaComponent(0.20), .systemTeal.withAlphaComponent(0.22)])
        let style = AwayoNoteStyle(rawValue: rawValue) ?? .tapedPaper
        let noteRect = rect.insetBy(dx: 32, dy: 18)
        switch style {
        case .tapedPaper:
            drawPill(in: noteRect, color: .systemYellow)
            drawPill(in: NSRect(x: noteRect.midX - 24, y: noteRect.maxY - 6, width: 48, height: 10), color: .white.withAlphaComponent(0.70))
        case .stickyStack:
            drawPill(in: noteRect.offsetBy(dx: 8, dy: -8), color: .systemPink)
            drawPill(in: noteRect, color: .systemYellow)
        case .glassCard:
            drawPill(in: noteRect, color: .white.withAlphaComponent(0.36))
        case .markerCard:
            drawPill(in: noteRect, color: .white)
            NSColor.black.withAlphaComponent(0.45).setStroke()
            let line = NSBezierPath()
            line.move(to: NSPoint(x: noteRect.minX + 14, y: noteRect.midY))
            line.line(to: NSPoint(x: noteRect.maxX - 14, y: noteRect.midY + 4))
            line.lineWidth = 4
            line.stroke()
        }
    }

    private func roundedGradient(in rect: NSRect, colors: [NSColor]) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        path.addClip()
        NSGradient(colors: colors)?.draw(in: rect, angle: -35)
    }

    private func drawMiniDuck(in rect: NSRect) {
        NSColor.systemYellow.setFill()
        NSBezierPath(ovalIn: NSRect(x: rect.midX - 34, y: rect.midY - 10, width: 64, height: 30)).fill()
        NSBezierPath(ovalIn: NSRect(x: rect.midX + 12, y: rect.midY + 10, width: 26, height: 24)).fill()
        NSColor.systemOrange.setFill()
        NSBezierPath(rect: NSRect(x: rect.midX + 36, y: rect.midY + 17, width: 18, height: 7)).fill()
    }

    private func drawMiniRunner(in rect: NSRect) {
        NSColor.black.withAlphaComponent(0.62).setFill()
        NSRect(x: rect.midX - 16, y: rect.midY - 6, width: 36, height: 28).fill()
        NSRect(x: rect.midX + 12, y: rect.midY + 18, width: 24, height: 12).fill()
        NSRect(x: rect.minX + 12, y: rect.minY + 18, width: rect.width - 24, height: 4).fill()
    }

    private func drawMiniNotes(in rect: NSRect) {
        [.systemYellow, .systemPink, .systemMint].enumerated().forEach { index, color in
            drawPill(in: NSRect(x: rect.minX + 24 + CGFloat(index * 34), y: rect.midY - CGFloat(index * 8), width: 62, height: 46), color: color)
        }
    }

    private func drawMiniLines(in rect: NSRect) {
        for index in 0..<4 {
            let y = rect.minY + 18 + CGFloat(index) * 16
            NSColor.white.withAlphaComponent(0.34).setStroke()
            let path = NSBezierPath()
            path.move(to: NSPoint(x: rect.minX + 14, y: y))
            path.line(to: NSPoint(x: rect.maxX - 14, y: y + CGFloat(index % 2 == 0 ? 8 : -8)))
            path.lineWidth = 5
            path.stroke()
        }
    }

    private func drawPill(in rect: NSRect, color: NSColor) {
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
    }
}

private func centeredParagraph() -> NSParagraphStyle {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    return paragraph
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
