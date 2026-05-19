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
    private let backgroundColorWell = NSColorWell()
    private var passcodeStatusLabel = NSTextField(labelWithString: "")
    private let passcodeButton = NSButton(title: "Set Passcode", target: nil, action: nil)
    private var modalButtonTargets: [ModalButtonTarget] = []
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
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 760),
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
        content.edgeInsets = NSEdgeInsets(top: 34, left: 40, bottom: 34, right: 40)
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
        content.addArrangedSubview(sectionTitle("Backgrounds", "Pick the scene or quiet pattern Awayo Lock uses every time it starts."))
        content.addArrangedSubview(tileGrid(for: .background))
        content.addArrangedSubview(backgroundColorRow())
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
            card.widthAnchor.constraint(equalToConstant: 940)
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
        tile.widthAnchor.constraint(equalToConstant: 222).isActive = true
        tile.heightAnchor.constraint(equalToConstant: 156).isActive = true
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
        row.widthAnchor.constraint(equalToConstant: 940).isActive = true
        return row
    }

    private func backgroundColorRow() -> NSView {
        let card = cardView()
        card.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)

        let copy = NSStackView()
        copy.orientation = .vertical
        copy.alignment = .leading
        copy.spacing = 3

        let title = NSTextField(labelWithString: "Custom Color Background")
        title.font = .systemFont(ofSize: 14, weight: .bold)
        title.textColor = .labelColor

        let subtitle = NSTextField(labelWithString: "Use the color well for the Custom Color tile.")
        subtitle.font = .systemFont(ofSize: 12, weight: .medium)
        subtitle.textColor = .secondaryLabelColor

        copy.addArrangedSubview(title)
        copy.addArrangedSubview(subtitle)

        backgroundColorWell.target = self
        backgroundColorWell.action = #selector(solidBackgroundColorChanged(_:))
        backgroundColorWell.controlSize = .large

        row.addArrangedSubview(backgroundColorWell)
        row.addArrangedSubview(copy)
        row.addArrangedSubview(NSView())

        NSLayoutConstraint.activate([
            backgroundColorWell.widthAnchor.constraint(equalToConstant: 44),
            backgroundColorWell.heightAnchor.constraint(equalToConstant: 32),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            card.widthAnchor.constraint(equalToConstant: 940)
        ])

        return card
    }

    @objc private func selectTile(_ sender: AwayoPreviewTile) {
        switch sender.category {
        case .background:
            if let value = AwayoLockStyle(rawValue: sender.rawValue) {
                settingsStore.saveBackgroundStyle(value)
                if value == .solidColor {
                    backgroundColorWell.activate(true)
                }
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

    @objc private func solidBackgroundColorChanged(_ sender: NSColorWell) {
        settingsStore.saveSolidBackgroundColor(AwayoColor(nsColor: sender.color))
        settingsStore.saveBackgroundStyle(.solidColor)
        refreshSelections()
    }

    @objc private func setPasscode() {
        guard let values = promptForPasscode() else {
            return
        }

        guard !values.passcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showError("Awayo Lock needs a passcode.")
            return
        }

        guard values.passcode == values.confirmation else {
            showError("The passcodes did not match.")
            return
        }

        passcodeStore.savePasscode(values.passcode)
        onPasscodeChange()
        refreshPasscodeStatus()
    }

    private func promptForPasscode() -> (passcode: String, confirmation: String)? {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 278),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.title = passcodeStore.hasPasscode() ? "Change Passcode" : "Set Passcode"
        panel.isReleasedWhenClosed = false
        panel.level = .floating

        if let parentFrame = window?.frame {
            panel.setFrameOrigin(NSPoint(
                x: parentFrame.midX - panel.frame.width / 2,
                y: parentFrame.midY - panel.frame.height / 2
            ))
        } else {
            panel.center()
        }

        let root = NSVisualEffectView()
        root.material = .popover
        root.blendingMode = .behindWindow
        root.state = .active
        panel.contentView = root

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 26, bottom: 22, right: 26)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        let title = NSTextField(labelWithString: "Awayo Lock Passcode")
        title.font = .systemFont(ofSize: 22, weight: .black)
        title.textColor = .labelColor

        let subtitle = NSTextField(labelWithString: "Stored as a salted local hash. It unlocks Awayo Lock without using Keychain.")
        subtitle.font = .systemFont(ofSize: 13, weight: .medium)
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 2
        subtitle.preferredMaxLayoutWidth = 360

        let passcodeField = NSSecureTextField()
        passcodeField.placeholderString = "New passcode"
        passcodeField.font = .systemFont(ofSize: 16, weight: .semibold)
        passcodeField.bezelStyle = .roundedBezel
        passcodeField.widthAnchor.constraint(equalToConstant: 360).isActive = true

        let confirmationField = NSSecureTextField()
        confirmationField.placeholderString = "Confirm passcode"
        confirmationField.font = .systemFont(ofSize: 16, weight: .semibold)
        confirmationField.bezelStyle = .roundedBezel
        confirmationField.widthAnchor.constraint(equalToConstant: 360).isActive = true

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 10
        buttonRow.widthAnchor.constraint(equalToConstant: 360).isActive = true

        let cancel = NSButton(title: "Cancel", target: nil, action: nil)
        cancel.bezelStyle = .rounded
        cancel.controlSize = .large

        let save = NSButton(title: "Save Passcode", target: nil, action: nil)
        save.bezelStyle = .rounded
        save.controlSize = .large
        save.keyEquivalent = "\r"

        let cancelTarget = ModalButtonTarget {
            NSApp.stopModal(withCode: .cancel)
        }
        let saveTarget = ModalButtonTarget {
            NSApp.stopModal(withCode: .OK)
        }
        modalButtonTargets = [cancelTarget, saveTarget]
        cancel.target = cancelTarget
        cancel.action = #selector(ModalButtonTarget.fire)
        save.target = saveTarget
        save.action = #selector(ModalButtonTarget.fire)

        buttonRow.addArrangedSubview(NSView())
        buttonRow.addArrangedSubview(cancel)
        buttonRow.addArrangedSubview(save)

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(subtitle)
        stack.addArrangedSubview(passcodeField)
        stack.addArrangedSubview(confirmationField)
        stack.addArrangedSubview(buttonRow)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(passcodeField)
        let response = NSApp.runModal(for: panel)
        panel.orderOut(nil)
        modalButtonTargets.removeAll()

        guard response == .OK else {
            return nil
        }

        return (passcodeField.stringValue, confirmationField.stringValue)
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
        backgroundColorWell.color = appearance.solidBackgroundColor.nsColor
        backgroundTiles.forEach { $0.isSelected = $0.rawValue == appearance.backgroundStyle.rawValue }
        backgroundTiles.forEach { $0.customSolidColor = appearance.solidBackgroundColor.nsColor }
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
    var customSolidColor = AwayoColor.defaultSolidBackground.nsColor {
        didSet {
            needsDisplay = true
        }
    }

    var isSelected = false {
        didSet {
            needsDisplay = true
        }
    }

    override var isFlipped: Bool {
        false
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
        NSColor(calibratedWhite: 0.12, alpha: 0.92).setFill()
        path.fill()

        let previewRect = NSRect(x: rect.minX + 10, y: rect.minY + 36, width: rect.width - 20, height: rect.height - 46)
        drawPreview(in: previewRect)

        let titleRect = NSRect(x: rect.minX + 12, y: rect.minY + 10, width: rect.width - 24, height: 20)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.92)
        ]
        displayTitle.draw(in: titleRect, withAttributes: attributes)

        if isSelected {
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 3
            path.stroke()

            let checkRect = NSRect(x: rect.maxX - 34, y: rect.maxY - 34, width: 22, height: 22)
            NSColor.controlAccentColor.setFill()
            NSBezierPath(ovalIn: checkRect).fill()
            drawCheckmark(in: checkRect.insetBy(dx: 5, dy: 6))
        } else {
            NSColor.white.withAlphaComponent(0.08).setStroke()
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

        switch style {
        case .duckPond:
            drawMiniDuckPond(in: rect)
        case .offlineRunner:
            drawMiniRunnerGame(in: rect)
        case .cosmicDesk:
            drawMiniCosmicDesk(in: rect)
        case .rainyWindow:
            drawMiniRainyWindow(in: rect)
        case .arcadePulse:
            drawMiniArcadePulse(in: rect)
        case .paperNotes:
            drawMiniPaperWall(in: rect)
        case .synthwave:
            drawMiniSynthwave(in: rect)
        case .neonFlow:
            drawMiniNeonFlow(in: rect)
        case .solidColor:
            drawMiniSolidColor(in: rect)
        case .softWash:
            drawMiniSoftWash(in: rect)
        case .stripes:
            drawMiniStripes(in: rect)
        case .polkaDots:
            drawMiniPolkaDots(in: rect)
        }
    }

    private func drawTimerPreview(in rect: NSRect) {
        let style = AwayoTimerStyle(rawValue: rawValue) ?? .heroCountdown

        switch style {
        case .heroCountdown:
            roundedGradient(in: rect, colors: [
                NSColor(calibratedRed: 0.03, green: 0.04, blue: 0.08, alpha: 1),
                NSColor(calibratedRed: 0.10, green: 0.13, blue: 0.22, alpha: 1)
            ])
            drawTinyStatusDots(in: rect)
            drawText("14m 32s", in: rect.insetBy(dx: 10, dy: 30), font: .monospacedDigitSystemFont(ofSize: 30, weight: .heavy), color: .white)
        case .paperClock:
            drawPaper(in: rect, color: NSColor(calibratedRed: 1.0, green: 0.91, blue: 0.58, alpha: 1))
            drawClockFace(in: NSRect(x: rect.minX + 16, y: rect.midY - 26, width: 52, height: 52))
            drawText("2:58 PM", in: NSRect(x: rect.minX + 72, y: rect.midY - 19, width: rect.width - 86, height: 34), font: .systemFont(ofSize: 23, weight: .black), color: NSColor(calibratedRed: 0.19, green: 0.13, blue: 0.08, alpha: 1))
        case .glassPill:
            roundedGradient(in: rect, colors: [
                NSColor(calibratedRed: 0.02, green: 0.38, blue: 0.45, alpha: 1),
                NSColor(calibratedRed: 0.08, green: 0.13, blue: 0.34, alpha: 1)
            ])
            drawPill(in: rect.insetBy(dx: 22, dy: 30), color: NSColor.white.withAlphaComponent(0.20))
            strokePill(in: rect.insetBy(dx: 22, dy: 30), color: NSColor.white.withAlphaComponent(0.28))
            drawText("14m 32s", in: rect.insetBy(dx: 22, dy: 34), font: .monospacedDigitSystemFont(ofSize: 23, weight: .bold), color: .white)
        case .terminalTicker:
            roundedGradient(in: rect, colors: [
                NSColor(calibratedRed: 0.01, green: 0.02, blue: 0.02, alpha: 1),
                NSColor(calibratedRed: 0.02, green: 0.07, blue: 0.05, alpha: 1)
            ])
            drawTerminalChrome(in: rect.insetBy(dx: 14, dy: 18))
            drawText("$ awayo --14m", in: rect.insetBy(dx: 24, dy: 42), font: .monospacedSystemFont(ofSize: 17, weight: .bold), color: NSColor(calibratedRed: 0.47, green: 1.0, blue: 0.63, alpha: 1), alignment: .left)
        }
    }

    private func drawDashboardPreview(in rect: NSRect) {
        let style = AwayoDashboardStyle(rawValue: rawValue) ?? .centerStage
        switch style {
        case .centerStage:
            roundedGradient(in: rect, colors: [.systemIndigo, .systemPurple])
            drawPill(in: NSRect(x: rect.midX - 54, y: rect.maxY - 26, width: 108, height: 13), color: .white.withAlphaComponent(0.34))
            drawPill(in: rect.insetBy(dx: 30, dy: 26), color: .white.withAlphaComponent(0.86))
            drawText("AWAY", in: rect.insetBy(dx: 34, dy: 42), font: .systemFont(ofSize: 16, weight: .heavy), color: NSColor.black.withAlphaComponent(0.70))
        case .paperDesk:
            roundedGradient(in: rect, colors: [
                NSColor(calibratedRed: 0.42, green: 0.33, blue: 0.22, alpha: 1),
                NSColor(calibratedRed: 0.19, green: 0.15, blue: 0.12, alpha: 1)
            ])
            drawPaper(in: rect.insetBy(dx: 22, dy: 15), color: NSColor(calibratedRed: 1.0, green: 0.93, blue: 0.66, alpha: 1))
            drawText("back soon", in: rect.insetBy(dx: 36, dy: 40), font: handwrittenFont(size: 18, weight: .bold), color: NSColor(calibratedRed: 0.22, green: 0.15, blue: 0.09, alpha: 1))
        case .minimalBadge:
            roundedGradient(in: rect, colors: [
                NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.12, alpha: 1),
                NSColor(calibratedRed: 0.02, green: 0.03, blue: 0.04, alpha: 1)
            ])
            drawPill(in: NSRect(x: rect.midX - 46, y: rect.midY - 15, width: 92, height: 30), color: .white.withAlphaComponent(0.88))
            drawText("ON", in: NSRect(x: rect.midX - 30, y: rect.midY - 9, width: 60, height: 18), font: .systemFont(ofSize: 13, weight: .black), color: .black)
        case .commandCenter:
            roundedGradient(in: rect, colors: [
                NSColor(calibratedRed: 0.02, green: 0.09, blue: 0.14, alpha: 1),
                NSColor(calibratedRed: 0.03, green: 0.02, blue: 0.08, alpha: 1)
            ])
            let panel = rect.insetBy(dx: 14, dy: 14)
            drawPill(in: panel, color: .black.withAlphaComponent(0.48))
            strokePill(in: panel, color: NSColor(calibratedRed: 0.2, green: 0.82, blue: 0.9, alpha: 0.30))
            drawHudLines(in: panel)
        }
    }

    private func drawNotePreview(in rect: NSRect) {
        roundedGradient(in: rect, colors: [
            NSColor(calibratedRed: 0.16, green: 0.19, blue: 0.20, alpha: 1),
            NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.12, alpha: 1)
        ])
        let style = AwayoNoteStyle(rawValue: rawValue) ?? .tapedPaper
        let noteRect = rect.insetBy(dx: 34, dy: 16)
        switch style {
        case .tapedPaper:
            drawStickyNote(in: noteRect, color: NSColor(calibratedRed: 1.0, green: 0.88, blue: 0.24, alpha: 1), tape: true, ruled: true)
        case .stickyStack:
            drawStickyNote(in: noteRect.offsetBy(dx: 10, dy: -9), color: NSColor(calibratedRed: 1.0, green: 0.38, blue: 0.58, alpha: 1), tape: false, ruled: false)
            drawStickyNote(in: noteRect.offsetBy(dx: 2, dy: -2), color: NSColor(calibratedRed: 0.42, green: 0.93, blue: 0.78, alpha: 1), tape: false, ruled: true)
            drawStickyNote(in: noteRect.offsetBy(dx: -6, dy: 6), color: NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.18, alpha: 1), tape: false, ruled: true)
        case .glassCard:
            drawPill(in: noteRect, color: .white.withAlphaComponent(0.22))
            strokePill(in: noteRect, color: .white.withAlphaComponent(0.35))
            drawText("from CX", in: noteRect.insetBy(dx: 12, dy: 12), font: .systemFont(ofSize: 11, weight: .bold), color: .white, alignment: .left)
        case .markerCard:
            drawStickyNote(in: noteRect, color: .white, tape: false, ruled: false)
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

    private func drawMiniDuckPond(in rect: NSRect) {
        roundedGradient(in: rect, colors: [
            NSColor(calibratedRed: 0.64, green: 0.88, blue: 0.94, alpha: 1),
            NSColor(calibratedRed: 0.08, green: 0.47, blue: 0.56, alpha: 1)
        ])
        NSColor(calibratedRed: 1.0, green: 0.80, blue: 0.32, alpha: 0.92).setFill()
        NSBezierPath(ovalIn: NSRect(x: rect.minX + 16, y: rect.maxY - 42, width: 34, height: 34)).fill()
        drawRippleLines(in: rect, color: .white.withAlphaComponent(0.24))
        drawDuck(in: NSPoint(x: rect.midX - 6, y: rect.midY - 2), scale: 0.50)
        drawDuck(in: NSPoint(x: rect.midX - 54, y: rect.midY - 24), scale: 0.28)
        drawDuck(in: NSPoint(x: rect.midX - 86, y: rect.midY - 12), scale: 0.24)
    }

    private func drawMiniRunnerGame(in rect: NSRect) {
        roundedGradient(in: rect, colors: [
            NSColor(calibratedRed: 0.96, green: 0.91, blue: 0.78, alpha: 1),
            NSColor(calibratedRed: 0.89, green: 0.74, blue: 0.50, alpha: 1)
        ])
        let groundY = rect.minY + 25
        NSColor(calibratedRed: 0.19, green: 0.16, blue: 0.14, alpha: 0.70).setStroke()
        let ground = NSBezierPath()
        ground.move(to: NSPoint(x: rect.minX + 8, y: groundY))
        ground.line(to: NSPoint(x: rect.maxX - 8, y: groundY))
        ground.lineWidth = 3
        ground.stroke()
        drawPixelDino(at: NSPoint(x: rect.minX + 44, y: groundY + 2), scale: 2.1)
        drawMiniCactus(at: NSPoint(x: rect.maxX - 56, y: groundY), scale: 1.0)
        drawMiniCloud(in: NSRect(x: rect.midX + 8, y: rect.maxY - 38, width: 48, height: 16))
    }

    private func drawMiniCosmicDesk(in rect: NSRect) {
        roundedGradient(in: rect, colors: [
            NSColor(calibratedRed: 0.02, green: 0.02, blue: 0.09, alpha: 1),
            NSColor(calibratedRed: 0.15, green: 0.06, blue: 0.28, alpha: 1),
            NSColor(calibratedRed: 0.00, green: 0.18, blue: 0.23, alpha: 1)
        ])
        drawStars(in: rect, count: 40)
        let planet = NSRect(x: rect.maxX - 72, y: rect.maxY - 68, width: 48, height: 48)
        NSColor(calibratedRed: 0.94, green: 0.42, blue: 0.35, alpha: 0.88).setFill()
        NSBezierPath(ovalIn: planet).fill()
        NSColor(calibratedRed: 0.57, green: 0.90, blue: 0.93, alpha: 0.42).setStroke()
        let ring = NSBezierPath(ovalIn: planet.insetBy(dx: -20, dy: 15))
        ring.lineWidth = 4
        ring.stroke()
    }

    private func drawMiniRainyWindow(in rect: NSRect) {
        roundedGradient(in: rect, colors: [
            NSColor(calibratedRed: 0.04, green: 0.06, blue: 0.08, alpha: 1),
            NSColor(calibratedRed: 0.12, green: 0.18, blue: 0.22, alpha: 1)
        ])
        let window = rect.insetBy(dx: 28, dy: 16)
        drawPill(in: window, color: .white.withAlphaComponent(0.08))
        strokePill(in: window, color: .white.withAlphaComponent(0.18))
        for index in 0..<18 {
            let x = rect.minX + CGFloat(index) * rect.width / 18
            let path = NSBezierPath()
            path.move(to: NSPoint(x: x, y: rect.maxY - 10))
            path.line(to: NSPoint(x: x + 9, y: rect.minY + 16))
            path.lineWidth = 1.2
            NSColor.white.withAlphaComponent(0.20).setStroke()
            path.stroke()
        }
    }

    private func drawMiniArcadePulse(in rect: NSRect) {
        roundedGradient(in: rect, colors: [
            NSColor(calibratedRed: 0.02, green: 0.00, blue: 0.08, alpha: 1),
            NSColor(calibratedRed: 0.15, green: 0.02, blue: 0.22, alpha: 1)
        ])
        drawGridLines(in: rect, spacing: 18, color: NSColor(calibratedRed: 0.13, green: 0.82, blue: 0.90, alpha: 0.16))
        for index in 0..<7 {
            let w = CGFloat(20 + (index % 3) * 12)
            let x = rect.minX + CGFloat(index) * 25 + 12
            let y = rect.minY + CGFloat(20 + (index % 4) * 13)
            drawPill(in: NSRect(x: x, y: y, width: w, height: 12), color: tileColor(index, alpha: 0.72))
        }
    }

    private func drawMiniPaperWall(in rect: NSRect) {
        roundedGradient(in: rect, colors: [
            NSColor(calibratedRed: 0.70, green: 0.64, blue: 0.52, alpha: 1),
            NSColor(calibratedRed: 0.36, green: 0.42, blue: 0.39, alpha: 1)
        ])
        for index in 0..<4 {
            let color = [NSColor.systemYellow, NSColor.systemPink, NSColor.systemMint, NSColor.white][index]
            let x = rect.minX + 20 + CGFloat(index % 2) * 72
            let y = rect.minY + 20 + CGFloat(index / 2) * 38
            drawStickyNote(in: NSRect(x: x, y: y, width: 56, height: 38), color: color.withAlphaComponent(0.9), tape: index == 0, ruled: index != 1)
        }
    }

    private func drawMiniSynthwave(in rect: NSRect) {
        roundedGradient(in: rect, colors: [
            NSColor(calibratedRed: 0.04, green: 0.01, blue: 0.11, alpha: 1),
            NSColor(calibratedRed: 0.23, green: 0.04, blue: 0.31, alpha: 1),
            NSColor(calibratedRed: 0.00, green: 0.14, blue: 0.20, alpha: 1)
        ])
        NSColor(calibratedRed: 1.0, green: 0.35, blue: 0.41, alpha: 0.62).setFill()
        NSBezierPath(ovalIn: NSRect(x: rect.midX - 34, y: rect.midY - 2, width: 68, height: 68)).fill()
        drawPerspectiveGrid(in: rect, color: NSColor(calibratedRed: 0.22, green: 0.85, blue: 0.94, alpha: 0.28))
    }

    private func drawMiniNeonFlow(in rect: NSRect) {
        roundedGradient(in: rect, colors: [
            NSColor(calibratedRed: 0.01, green: 0.03, blue: 0.05, alpha: 1),
            NSColor(calibratedRed: 0.02, green: 0.23, blue: 0.24, alpha: 1),
            NSColor(calibratedRed: 0.22, green: 0.04, blue: 0.20, alpha: 1)
        ])
        for index in 0..<3 {
            let y = rect.midY + CGFloat(index - 1) * 22
            let path = NSBezierPath()
            path.move(to: NSPoint(x: rect.minX - 10, y: y))
            path.curve(to: NSPoint(x: rect.maxX + 10, y: y + CGFloat(index - 1) * 8), controlPoint1: NSPoint(x: rect.minX + 44, y: y + 28), controlPoint2: NSPoint(x: rect.maxX - 52, y: y - 28))
            path.lineWidth = 10
            tileColor(index, alpha: 0.42).setStroke()
            path.stroke()
        }
    }

    private func drawMiniSolidColor(in rect: NSRect) {
        customSolidColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()

        NSColor.white.withAlphaComponent(0.18).setStroke()
        let shine = NSBezierPath()
        shine.move(to: NSPoint(x: rect.minX + 18, y: rect.maxY - 24))
        shine.line(to: NSPoint(x: rect.maxX - 18, y: rect.maxY - 24))
        shine.lineWidth = 3
        shine.stroke()
    }

    private func drawMiniSoftWash(in rect: NSRect) {
        roundedGradient(in: rect, colors: [
            customSolidColor.blended(withFraction: 0.38, of: .white) ?? customSolidColor,
            customSolidColor,
            customSolidColor.blended(withFraction: 0.34, of: .black) ?? customSolidColor
        ])
        drawSoftWashRings(in: rect)
    }

    private func drawMiniStripes(in rect: NSRect) {
        customSolidColor.blended(withFraction: 0.10, of: .black)?.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).addClip()
        for index in -4..<12 {
            let stripe = NSBezierPath()
            let x = rect.minX + CGFloat(index) * 34
            stripe.move(to: NSPoint(x: x, y: rect.minY))
            stripe.line(to: NSPoint(x: x + 60, y: rect.maxY))
            stripe.lineWidth = 18
            let stripeColor = (index.isMultiple(of: 2)
                ? customSolidColor.blended(withFraction: 0.25, of: .white)
                : customSolidColor.blended(withFraction: 0.18, of: .black)
            ) ?? customSolidColor
            stripeColor.withAlphaComponent(0.95).setStroke()
            stripe.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawMiniPolkaDots(in rect: NSRect) {
        customSolidColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        let dotColor = customSolidColor.blended(withFraction: 0.62, of: .white) ?? .white
        dotColor.withAlphaComponent(0.72).setFill()
        for row in 0..<4 {
            for column in 0..<7 {
                let x = rect.minX + 18 + CGFloat(column) * 29 + CGFloat(row % 2) * 14
                let y = rect.minY + 18 + CGFloat(row) * 22
                NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 8, height: 8)).fill()
            }
        }
    }

    private func drawPill(in rect: NSRect, color: NSColor) {
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
    }

    private func drawSoftWashRings(in rect: NSRect) {
        for index in 0..<4 {
            let inset = CGFloat(index) * 18
            let ring = NSRect(
                x: rect.minX + inset - 18,
                y: rect.minY + inset - 10,
                width: rect.width - inset * 2 + 36,
                height: rect.height - inset * 2 + 20
            )
            NSColor.white.withAlphaComponent(0.08 + CGFloat(index) * 0.035).setStroke()
            let path = NSBezierPath(ovalIn: ring)
            path.lineWidth = 2
            path.stroke()
        }
    }

    private func strokePill(in rect: NSRect, color: NSColor) {
        color.setStroke()
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        path.lineWidth = 1.5
        path.stroke()
    }

    private func drawPaper(in rect: NSRect, color: NSColor) {
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
        NSColor.black.withAlphaComponent(0.12).setStroke()
        for index in 1..<4 {
            let y = rect.minY + CGFloat(index) * rect.height / 4
            let line = NSBezierPath()
            line.move(to: NSPoint(x: rect.minX + 12, y: y))
            line.line(to: NSPoint(x: rect.maxX - 12, y: y + CGFloat(index % 2 == 0 ? 1 : -1)))
            line.lineWidth = 1
            line.stroke()
        }
    }

    private func drawStickyNote(in rect: NSRect, color: NSColor, tape: Bool, ruled: Bool) {
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        NSColor.black.withAlphaComponent(0.12).setStroke()
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).stroke()
        if tape {
            drawPill(in: NSRect(x: rect.midX - 22, y: rect.maxY - 6, width: 44, height: 10), color: .white.withAlphaComponent(0.66))
        }
        if ruled {
            NSColor.black.withAlphaComponent(0.16).setStroke()
            for index in 0..<3 {
                let y = rect.minY + 13 + CGFloat(index) * 9
                let path = NSBezierPath()
                path.move(to: NSPoint(x: rect.minX + 10, y: y))
                path.line(to: NSPoint(x: rect.maxX - 10, y: y + CGFloat(index % 2 == 0 ? 1 : -1)))
                path.lineWidth = 1.2
                path.stroke()
            }
        }
    }

    private func drawDuck(in point: NSPoint, scale: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: point.x, yBy: point.y)
        transform.scale(by: scale)
        transform.concat()
        NSColor(calibratedRed: 1.0, green: 0.80, blue: 0.18, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: -42, y: -18, width: 86, height: 38)).fill()
        NSBezierPath(ovalIn: NSRect(x: 14, y: 8, width: 34, height: 32)).fill()
        NSColor(calibratedRed: 0.95, green: 0.63, blue: 0.09, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: -14, y: -7, width: 40, height: 21)).fill()
        NSColor(calibratedRed: 1.0, green: 0.40, blue: 0.10, alpha: 1).setFill()
        let beak = NSBezierPath()
        beak.move(to: NSPoint(x: 45, y: 24))
        beak.line(to: NSPoint(x: 67, y: 18))
        beak.line(to: NSPoint(x: 45, y: 13))
        beak.close()
        beak.fill()
        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(ovalIn: NSRect(x: 34, y: 25, width: 4, height: 4)).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawPixelDino(at point: NSPoint, scale: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: point.x, yBy: point.y)
        transform.scale(by: scale)
        transform.concat()
        NSColor(calibratedRed: 0.14, green: 0.13, blue: 0.12, alpha: 0.9).setFill()
        let s: CGFloat = 3
        [
            NSRect(x: 0, y: 6, width: s * 7, height: s * 7),
            NSRect(x: 15, y: 21, width: s * 6, height: s * 5),
            NSRect(x: 30, y: 18, width: s * 2, height: s * 2),
            NSRect(x: -6, y: 12, width: s * 4, height: s * 2),
            NSRect(x: 5, y: 0, width: s * 2, height: s * 4),
            NSRect(x: 18, y: 0, width: s * 2, height: s * 4)
        ].forEach { $0.fill() }
        NSColor(calibratedRed: 0.96, green: 0.91, blue: 0.78, alpha: 1).setFill()
        NSRect(x: 27, y: 31, width: 3, height: 3).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawMiniCactus(at point: NSPoint, scale: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: point.x, yBy: point.y)
        transform.scale(by: scale)
        transform.concat()
        NSColor(calibratedRed: 0.10, green: 0.38, blue: 0.25, alpha: 0.82).setFill()
        NSBezierPath(roundedRect: NSRect(x: -5, y: 0, width: 10, height: 38), xRadius: 5, yRadius: 5).fill()
        NSBezierPath(roundedRect: NSRect(x: -17, y: 17, width: 8, height: 19), xRadius: 4, yRadius: 4).fill()
        NSBezierPath(roundedRect: NSRect(x: 9, y: 12, width: 8, height: 20), xRadius: 4, yRadius: 4).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawMiniCloud(in rect: NSRect) {
        NSColor.white.withAlphaComponent(0.54).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        NSBezierPath(roundedRect: NSRect(x: rect.minX + 12, y: rect.minY + 7, width: 22, height: 14), xRadius: 7, yRadius: 7).fill()
    }

    private func drawClockFace(in rect: NSRect) {
        NSColor.white.withAlphaComponent(0.50).setFill()
        NSBezierPath(ovalIn: rect).fill()
        NSColor.black.withAlphaComponent(0.28).setStroke()
        NSBezierPath(ovalIn: rect).stroke()
        let hand = NSBezierPath()
        hand.move(to: NSPoint(x: rect.midX, y: rect.midY))
        hand.line(to: NSPoint(x: rect.midX, y: rect.midY + 14))
        hand.move(to: NSPoint(x: rect.midX, y: rect.midY))
        hand.line(to: NSPoint(x: rect.midX + 13, y: rect.midY - 6))
        hand.lineWidth = 2
        hand.stroke()
    }

    private func drawTerminalChrome(in rect: NSRect) {
        drawPill(in: rect, color: .black.withAlphaComponent(0.62))
        strokePill(in: rect, color: NSColor.white.withAlphaComponent(0.10))
        for index in 0..<3 {
            tileColor(index, alpha: 0.86).setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.minX + 10 + CGFloat(index) * 13, y: rect.maxY - 18, width: 7, height: 7)).fill()
        }
    }

    private func drawTinyStatusDots(in rect: NSRect) {
        for index in 0..<3 {
            tileColor(index, alpha: 0.82).setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.minX + 12 + CGFloat(index) * 10, y: rect.maxY - 18, width: 5, height: 5)).fill()
        }
    }

    private func drawHudLines(in rect: NSRect) {
        for index in 0..<4 {
            let y = rect.maxY - 22 - CGFloat(index) * 15
            drawPill(in: NSRect(x: rect.minX + 16, y: y, width: rect.width - CGFloat(56 + index * 14), height: 5), color: NSColor(calibratedRed: 0.34, green: 0.90, blue: 0.88, alpha: 0.46))
        }
    }

    private func drawRippleLines(in rect: NSRect, color: NSColor) {
        color.setStroke()
        for index in 0..<4 {
            let y = rect.minY + 22 + CGFloat(index) * 14
            let path = NSBezierPath()
            path.move(to: NSPoint(x: rect.minX + 10, y: y))
            path.curve(to: NSPoint(x: rect.maxX - 10, y: y + 2), controlPoint1: NSPoint(x: rect.midX - 34, y: y + 7), controlPoint2: NSPoint(x: rect.midX + 34, y: y - 7))
            path.lineWidth = 1.2
            path.stroke()
        }
    }

    private func drawStars(in rect: NSRect, count: Int) {
        NSColor.white.withAlphaComponent(0.64).setFill()
        for index in 0..<count {
            let x = rect.minX + unitNoise(CGFloat(index) * 11.7) * rect.width
            let y = rect.minY + unitNoise(CGFloat(index) * 31.2) * rect.height
            NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 1.8, height: 1.8)).fill()
        }
    }

    private func drawGridLines(in rect: NSRect, spacing: CGFloat, color: NSColor) {
        color.setStroke()
        let path = NSBezierPath()
        stride(from: rect.minX, through: rect.maxX, by: spacing).forEach { x in
            path.move(to: NSPoint(x: x, y: rect.minY))
            path.line(to: NSPoint(x: x, y: rect.maxY))
        }
        stride(from: rect.minY, through: rect.maxY, by: spacing).forEach { y in
            path.move(to: NSPoint(x: rect.minX, y: y))
            path.line(to: NSPoint(x: rect.maxX, y: y))
        }
        path.lineWidth = 1
        path.stroke()
    }

    private func drawPerspectiveGrid(in rect: NSRect, color: NSColor) {
        color.setStroke()
        let horizon = rect.minY + rect.height * 0.42
        let path = NSBezierPath()
        for index in -5...5 {
            path.move(to: NSPoint(x: rect.midX, y: horizon))
            path.line(to: NSPoint(x: rect.midX + CGFloat(index) * rect.width * 0.18, y: rect.minY))
        }
        for index in 0..<8 {
            let y = horizon - pow(CGFloat(index) / 8, 1.55) * (horizon - rect.minY)
            path.move(to: NSPoint(x: rect.minX, y: y))
            path.line(to: NSPoint(x: rect.maxX, y: y))
        }
        path.lineWidth = 1
        path.stroke()
    }

    private func drawText(_ text: String, in rect: NSRect, font: NSFont, color: NSColor, alignment: NSTextAlignment = .center) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        text.draw(in: rect, withAttributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
    }

    private func drawCheckmark(in rect: NSRect) {
        NSColor.white.setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: rect.midY))
        path.line(to: NSPoint(x: rect.midX - 1, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        path.lineWidth = 2.4
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    private func handwrittenFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        NSFont(name: "Marker Felt", size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    private func tileColor(_ index: Int, alpha: CGFloat) -> NSColor {
        switch index % 5 {
        case 0:
            NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.22, alpha: alpha)
        case 1:
            NSColor(calibratedRed: 0.18, green: 0.84, blue: 0.78, alpha: alpha)
        case 2:
            NSColor(calibratedRed: 1.0, green: 0.32, blue: 0.55, alpha: alpha)
        case 3:
            NSColor(calibratedRed: 0.58, green: 0.50, blue: 1.0, alpha: alpha)
        default:
            NSColor.white.withAlphaComponent(alpha)
        }
    }

    private func unitNoise(_ value: CGFloat) -> CGFloat {
        let raw = sin(value) * 43758.5453
        return raw - floor(raw)
    }
}

private func centeredParagraph() -> NSParagraphStyle {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    return paragraph
}

@MainActor
private final class ModalButtonTarget: NSObject {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @objc func fire() {
        action()
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
