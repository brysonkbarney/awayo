import AppKit
@preconcurrency import AVFoundation
import CoreGraphics

@MainActor
final class AwayoSettingsWindowController: NSWindowController, NSTextFieldDelegate {
    private enum Layout {
        static let sidebarWidth: CGFloat = 210
        static let pageWidth: CGFloat = 760
        static let setupCardWidth: CGFloat = 370
        static let setupCardSpacing: CGFloat = 14
        static let previewTileWidth: CGFloat = 238
        static let previewTileHeight: CGFloat = 138
        static let previewTileSpacing: CGFloat = 14
        static let previewGridColumns = 3
        static let previewGridWidth = previewTileWidth * CGFloat(previewGridColumns) + previewTileSpacing * CGFloat(previewGridColumns - 1)
        static let permissionItemWidth: CGFloat = 356
    }

    private enum SettingsPage: Int, CaseIterable {
        case start
        case lockScreen
        case display
        case notes
        case permissions

        var title: String {
            switch self {
            case .start:
                "Start"
            case .lockScreen:
                "Lock Screen"
            case .display:
                "Timer & Display"
            case .notes:
                "Notes"
            case .permissions:
                "Permissions"
            }
        }

        var subtitle: String {
            switch self {
            case .start:
                "Set the passcode and keyboard shortcut you use every day."
            case .lockScreen:
                "Choose the scene people see when Awayo Lock is active."
            case .display:
                "Control how much the countdown and dashboard show up."
            case .notes:
                "Decide whether visitors can leave sticky notes and how they look."
            case .permissions:
                "Check the macOS access needed for Screen Snapshot and the optional camera gag."
            }
        }

        var navSubtitle: String {
            switch self {
            case .start:
                "passcode + hotkey"
            case .lockScreen:
                "background scene"
            case .display:
                "timer + dashboard"
            case .notes:
                "away note + stickies"
            case .permissions:
                "macOS access"
            }
        }

        var symbolName: String {
            switch self {
            case .start:
                "play.circle.fill"
            case .lockScreen:
                "lock.rectangle.stack.fill"
            case .display:
                "timer"
            case .notes:
                "note.text"
            case .permissions:
                "checkmark.shield.fill"
            }
        }
    }

    private let settingsStore: AwayoSettingsStore
    private let passcodeStore: PasscodeStore
    private let onSettingsChange: () -> Void

    private var backgroundTiles: [AwayoPreviewTile] = []
    private var timerTiles: [AwayoPreviewTile] = []
    private var dashboardTiles: [AwayoPreviewTile] = []
    private var noteTiles: [AwayoPreviewTile] = []
    private let backgroundColorSwatch = AwayoColorSwatchView()
    private var passcodeStatusLabel = NSTextField(labelWithString: "")
    private let passcodeButton = NSButton(title: "Set Passcode", target: nil, action: nil)
    private let awayNoteToggle = NSButton(checkboxWithTitle: "Show away note", target: nil, action: nil)
    private let awayNoteField = NSTextField(string: "")
    private let hotKeyStatusLabel = NSTextField(labelWithString: "")
    private let hotKeyButton = NSButton(title: "Set Hotkey", target: nil, action: nil)
    private let hotKeyClearButton = NSButton(title: "Clear", target: nil, action: nil)
    private let cameraGagToggle = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    private let screenRecordingStatusLabel = NSTextField(labelWithString: "")
    private let cameraPermissionStatusLabel = NSTextField(labelWithString: "")
    private let pageTitleLabel = NSTextField(labelWithString: "")
    private let pageSubtitleLabel = NSTextField(labelWithString: "")
    private let pageContentContainer = NSView()
    private var pageButtons: [SettingsPage: AwayoSidebarButton] = [:]
    private var pageViews: [SettingsPage: NSView] = [:]
    private var selectedPage: SettingsPage = .start
    private var modalButtonTargets: [ModalButtonTarget] = []
    private var onboarding = false

    init(
        settingsStore: AwayoSettingsStore,
        passcodeStore: PasscodeStore,
        onSettingsChange: @escaping () -> Void
    ) {
        self.settingsStore = settingsStore
        self.passcodeStore = passcodeStore
        self.onSettingsChange = onSettingsChange

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1020, height: 700),
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
        refreshSelections()
        refreshPasscodeStatus()
        refreshAwayNoteControls()
        refreshHotKeyControls()
        refreshCameraGagControls()
        refreshPermissionControls()
        selectPage(onboarding ? .start : selectedPage)
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildContentView() -> NSView {
        let root = NSVisualEffectView()
        root.material = .windowBackground
        root.blendingMode = .behindWindow
        root.state = .active

        let sidebar = sidebarView()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(sidebar)

        let main = NSView()
        main.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(main)

        let header = mainHeaderView()
        header.translatesAutoresizingMaskIntoConstraints = false
        main.addSubview(header)

        pageContentContainer.translatesAutoresizingMaskIntoConstraints = false
        main.addSubview(pageContentContainer)

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: Layout.sidebarWidth),

            main.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            main.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            main.topAnchor.constraint(equalTo: root.topAnchor),
            main.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            header.leadingAnchor.constraint(equalTo: main.leadingAnchor, constant: 26),
            header.topAnchor.constraint(equalTo: main.topAnchor, constant: 24),
            header.widthAnchor.constraint(equalToConstant: Layout.pageWidth),

            pageContentContainer.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            pageContentContainer.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 16),
            pageContentContainer.bottomAnchor.constraint(equalTo: main.bottomAnchor, constant: -22),
            pageContentContainer.widthAnchor.constraint(equalToConstant: Layout.pageWidth)
        ])

        pageViews = [
            .start: pageScrollView(startPage()),
            .lockScreen: pageScrollView(lockScreenPage()),
            .display: pageScrollView(displayPage()),
            .notes: pageScrollView(notesPage()),
            .permissions: pageScrollView(permissionsPage())
        ]

        SettingsPage.allCases.forEach { page in
            guard let view = pageViews[page] else {
                return
            }

            view.translatesAutoresizingMaskIntoConstraints = false
            pageContentContainer.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: pageContentContainer.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: pageContentContainer.trailingAnchor),
                view.topAnchor.constraint(equalTo: pageContentContainer.topAnchor),
                view.bottomAnchor.constraint(equalTo: pageContentContainer.bottomAnchor)
            ])
        }

        selectPage(.start)

        return root
    }

    private func sidebarView() -> NSView {
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.state = .active

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 14, bottom: 18, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(stack)

        let brand = NSTextField(labelWithString: "Awayo")
        brand.font = .systemFont(ofSize: 24, weight: .black)
        brand.textColor = .labelColor

        let tagline = NSTextField(labelWithString: "don't let your agents die")
        tagline.font = .systemFont(ofSize: 11, weight: .semibold)
        tagline.textColor = .secondaryLabelColor

        stack.addArrangedSubview(brand)
        stack.addArrangedSubview(tagline)
        stack.addArrangedSubview(sidebarSpacer(height: 10))

        SettingsPage.allCases.forEach { page in
            let button = AwayoSidebarButton(title: page.title, subtitle: page.navSubtitle, symbolName: page.symbolName)
            button.tag = page.rawValue
            button.target = self
            button.action = #selector(selectPageFromSidebar(_:))
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: Layout.sidebarWidth - 28).isActive = true
            button.heightAnchor.constraint(equalToConstant: 42).isActive = true
            pageButtons[page] = button
            stack.addArrangedSubview(button)
        }

        stack.addArrangedSubview(NSView())

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            stack.topAnchor.constraint(equalTo: sidebar.topAnchor),
            stack.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor)
        ])

        return sidebar
    }

    private func mainHeaderView() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 18

        let copy = NSStackView()
        copy.orientation = .vertical
        copy.alignment = .leading
        copy.spacing = 4

        pageTitleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        pageTitleLabel.textColor = .labelColor

        pageSubtitleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        pageSubtitleLabel.textColor = .secondaryLabelColor
        pageSubtitleLabel.maximumNumberOfLines = 2
        pageSubtitleLabel.preferredMaxLayoutWidth = 560

        copy.addArrangedSubview(pageTitleLabel)
        copy.addArrangedSubview(pageSubtitleLabel)

        let close = NSButton(title: "Close Settings", target: self, action: #selector(done))
        close.bezelStyle = .rounded
        close.controlSize = .regular
        close.font = .systemFont(ofSize: 13, weight: .semibold)

        row.addArrangedSubview(copy)
        row.addArrangedSubview(NSView())
        row.addArrangedSubview(close)

        return row
    }

    private func pageScrollView(_ content: NSView) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true

        let document = AwayoFlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(content)
        scrollView.documentView = document

        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            content.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            content.topAnchor.constraint(equalTo: document.topAnchor),
            content.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            content.widthAnchor.constraint(equalToConstant: Layout.pageWidth)
        ])

        return scrollView
    }

    private func pageStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 18, right: 0)
        return stack
    }

    private func startPage() -> NSView {
        let stack = pageStack()
        stack.addArrangedSubview(twoColumnRow(passcodeSection(), hotKeySection()))
        stack.addArrangedSubview(sectionTitle("Message", "Set what Awayo Lock says, or leave it blank."))
        stack.addArrangedSubview(awayNoteSection())
        return stack
    }

    private func lockScreenPage() -> NSView {
        let stack = pageStack()
        stack.addArrangedSubview(sectionTitle("Background", "Pick the main scene or pattern for Awayo Lock."))
        stack.addArrangedSubview(customColorControl())
        stack.addArrangedSubview(tileGrid(for: .background))
        return stack
    }

    private func displayPage() -> NSView {
        let stack = pageStack()
        stack.addArrangedSubview(sectionTitle("Timer", "Show a big countdown, a quieter clock, or no timer at all."))
        stack.addArrangedSubview(tileGrid(for: .timer))
        stack.addArrangedSubview(sectionTitle("Dashboard", "Choose the center display style people see from across the room."))
        stack.addArrangedSubview(tileGrid(for: .dashboard))
        return stack
    }

    private func notesPage() -> NSView {
        let stack = pageStack()
        stack.addArrangedSubview(sectionTitle("Sticky Notes", "Choose how notes from friends show up on the lock screen."))
        stack.addArrangedSubview(tileGrid(for: .note))
        return stack
    }

    private func permissionsPage() -> NSView {
        let stack = pageStack()
        stack.addArrangedSubview(permissionSection())
        stack.addArrangedSubview(sectionTitle("Optional Camera Gag", "Only used when Screen Snapshot mode and NICE TRY Camera are both enabled."))
        stack.addArrangedSubview(cameraGagSection())
        return stack
    }

    private func twoColumnRow(_ leading: NSView, _ trailing: NSView) -> NSView {
        let row = NSStackView(views: [leading, trailing])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = Layout.setupCardSpacing
        return row
    }

    private func sidebarSpacer(height: CGFloat) -> NSView {
        let view = NSView()
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }

    @objc private func selectPageFromSidebar(_ sender: NSButton) {
        guard let page = SettingsPage(rawValue: sender.tag) else {
            return
        }

        selectPage(page)
    }

    private func selectPage(_ page: SettingsPage) {
        selectedPage = page
        pageTitleLabel.stringValue = page.title
        pageSubtitleLabel.stringValue = page.subtitle

        pageButtons.forEach { candidate, button in
            button.isPicked = candidate == page
        }

        pageViews.forEach { candidate, view in
            view.isHidden = candidate != page
        }
    }

    private func passcodeSection() -> NSView {
        let card = cardView()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

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
        passcodeStatusLabel.maximumNumberOfLines = 2
        passcodeStatusLabel.preferredMaxLayoutWidth = 310
        passcodeStatusLabel.lineBreakMode = .byWordWrapping
        passcodeStatusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        copy.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        copy.addArrangedSubview(title)
        copy.addArrangedSubview(passcodeStatusLabel)

        passcodeButton.target = self
        passcodeButton.action = #selector(setPasscode)
        passcodeButton.bezelStyle = .rounded
        passcodeButton.controlSize = .large
        passcodeButton.font = .systemFont(ofSize: 14, weight: .bold)
        passcodeButton.widthAnchor.constraint(equalToConstant: 132).isActive = true

        let topRow = NSStackView(views: [icon, copy])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 16

        let actionRow = NSStackView(views: [NSView(), passcodeButton])
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.widthAnchor.constraint(equalToConstant: Layout.setupCardWidth - 36).isActive = true

        stack.addArrangedSubview(topRow)
        stack.addArrangedSubview(actionRow)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 58),
            icon.heightAnchor.constraint(equalToConstant: 58),

            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18),
            card.widthAnchor.constraint(equalToConstant: Layout.setupCardWidth)
        ])

        refreshPasscodeStatus()
        return card
    }

    private func awayNoteSection() -> NSView {
        let card = cardView()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        let title = NSTextField(labelWithString: "Away Note")
        title.font = .systemFont(ofSize: 17, weight: .bold)
        title.textColor = .labelColor

        let subtitle = NSTextField(labelWithString: "Set the note once here, or turn it off for a quieter lock screen.")
        subtitle.font = .systemFont(ofSize: 13, weight: .medium)
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 2
        subtitle.preferredMaxLayoutWidth = Layout.pageWidth - 36

        awayNoteToggle.target = self
        awayNoteToggle.action = #selector(awayNoteToggled(_:))
        awayNoteToggle.font = .systemFont(ofSize: 13, weight: .semibold)

        awayNoteField.placeholderString = AwayoSettingsStore.defaultAwayMessage
        awayNoteField.font = .systemFont(ofSize: 15, weight: .semibold)
        awayNoteField.bezelStyle = .roundedBezel
        awayNoteField.target = self
        awayNoteField.action = #selector(awayNoteChanged(_:))
        awayNoteField.delegate = self
        awayNoteField.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(subtitle)
        stack.addArrangedSubview(awayNoteToggle)
        stack.addArrangedSubview(awayNoteField)

        NSLayoutConstraint.activate([
            awayNoteField.widthAnchor.constraint(equalToConstant: Layout.pageWidth - 36),

            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18),
            card.widthAnchor.constraint(equalToConstant: Layout.pageWidth)
        ])

        refreshAwayNoteControls()
        return card
    }

    private func hotKeySection() -> NSView {
        let card = cardView()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        let icon = NSTextField(labelWithString: "⌘")
        icon.font = .systemFont(ofSize: 30, weight: .black)
        icon.alignment = .center
        icon.textColor = NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.12, alpha: 1)
        icon.wantsLayer = true
        icon.layer?.backgroundColor = NSColor(calibratedRed: 0.66, green: 0.86, blue: 1.0, alpha: 1).cgColor
        icon.layer?.cornerRadius = 18
        icon.translatesAutoresizingMaskIntoConstraints = false

        let copy = NSStackView()
        copy.orientation = .vertical
        copy.alignment = .leading
        copy.spacing = 4

        let title = NSTextField(labelWithString: "Awayo Lock Hotkey")
        title.font = .systemFont(ofSize: 17, weight: .bold)
        title.textColor = .labelColor

        hotKeyStatusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        hotKeyStatusLabel.textColor = .secondaryLabelColor
        hotKeyStatusLabel.maximumNumberOfLines = 2
        hotKeyStatusLabel.preferredMaxLayoutWidth = 310
        hotKeyStatusLabel.lineBreakMode = .byWordWrapping
        hotKeyStatusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        copy.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        copy.addArrangedSubview(title)
        copy.addArrangedSubview(hotKeyStatusLabel)

        hotKeyButton.target = self
        hotKeyButton.action = #selector(setHotKey)
        hotKeyButton.bezelStyle = .rounded
        hotKeyButton.controlSize = .large
        hotKeyButton.font = .systemFont(ofSize: 14, weight: .bold)
        hotKeyButton.widthAnchor.constraint(equalToConstant: 132).isActive = true

        hotKeyClearButton.target = self
        hotKeyClearButton.action = #selector(clearHotKey)
        hotKeyClearButton.bezelStyle = .rounded
        hotKeyClearButton.controlSize = .large
        hotKeyClearButton.font = .systemFont(ofSize: 14, weight: .semibold)
        hotKeyClearButton.widthAnchor.constraint(equalToConstant: 64).isActive = true

        let topRow = NSStackView(views: [icon, copy])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 16

        let actionRow = NSStackView(views: [NSView(), hotKeyClearButton, hotKeyButton])
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 10
        actionRow.widthAnchor.constraint(equalToConstant: Layout.setupCardWidth - 36).isActive = true

        stack.addArrangedSubview(topRow)
        stack.addArrangedSubview(actionRow)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 58),
            icon.heightAnchor.constraint(equalToConstant: 58),

            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18),
            card.widthAnchor.constraint(equalToConstant: Layout.setupCardWidth)
        ])

        refreshHotKeyControls()
        return card
    }

    private func cameraGagSection() -> NSView {
        let card = cardView()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        let icon = NSTextField(labelWithString: "!")
        icon.font = .monospacedSystemFont(ofSize: 30, weight: .black)
        icon.alignment = .center
        icon.textColor = NSColor(calibratedRed: 0.22, green: 0.08, blue: 0.04, alpha: 1)
        icon.wantsLayer = true
        icon.layer?.backgroundColor = NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.42, alpha: 1).cgColor
        icon.layer?.cornerRadius = 18
        icon.translatesAutoresizingMaskIntoConstraints = false

        let copy = NSStackView()
        copy.orientation = .vertical
        copy.alignment = .leading
        copy.spacing = 4

        let title = NSTextField(labelWithString: "NICE TRY Camera")
        title.font = .systemFont(ofSize: 17, weight: .bold)
        title.textColor = .labelColor

        let subtitle = NSTextField(labelWithString: "Optional visible camera gag for Screen Snapshot mode.")
        subtitle.font = .systemFont(ofSize: 13, weight: .medium)
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 2
        subtitle.preferredMaxLayoutWidth = 310
        subtitle.lineBreakMode = .byWordWrapping

        cameraGagToggle.target = self
        cameraGagToggle.action = #selector(cameraGagToggled(_:))
        cameraGagToggle.font = .systemFont(ofSize: 13, weight: .semibold)

        copy.addArrangedSubview(title)
        copy.addArrangedSubview(subtitle)

        let topRow = NSStackView(views: [icon, copy])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 16

        let actionRow = NSStackView(views: [NSView(), cameraGagToggle])
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.widthAnchor.constraint(equalToConstant: Layout.setupCardWidth - 36).isActive = true

        stack.addArrangedSubview(topRow)
        stack.addArrangedSubview(actionRow)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 58),
            icon.heightAnchor.constraint(equalToConstant: 58),

            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18),
            card.widthAnchor.constraint(equalToConstant: Layout.setupCardWidth)
        ])

        refreshCameraGagControls()
        return card
    }

    private func permissionSection() -> NSView {
        let card = cardView()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 10

        let title = NSTextField(labelWithString: "Permissions")
        title.font = .systemFont(ofSize: 17, weight: .bold)
        title.textColor = .labelColor

        let note = NSTextField(labelWithString: "macOS may ask you to quit and reopen Awayo after Screen Recording changes.")
        note.font = .systemFont(ofSize: 12, weight: .medium)
        note.textColor = .secondaryLabelColor

        header.addArrangedSubview(title)
        header.addArrangedSubview(NSView())
        header.addArrangedSubview(note)

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 14

        row.addArrangedSubview(permissionItem(
            icon: "screen",
            title: "Screen Snapshot",
            body: "Required for the screen-as-background mode.",
            statusLabel: screenRecordingStatusLabel,
            buttonTitle: "Open Settings",
            action: #selector(requestScreenRecordingPermissionFromSettings)
        ))
        row.addArrangedSubview(permissionItem(
            icon: "camera",
            title: "NICE TRY Camera",
            body: "Needed only when the camera gag is enabled.",
            statusLabel: cameraPermissionStatusLabel,
            buttonTitle: "Camera Settings",
            action: #selector(openCameraPrivacySettings)
        ))

        stack.addArrangedSubview(header)
        stack.addArrangedSubview(row)

        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: Layout.pageWidth),

            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18)
        ])

        refreshPermissionControls()
        return card
    }

    private func permissionItem(
        icon: String,
        title: String,
        body: String,
        statusLabel: NSTextField,
        buttonTitle: String,
        action: Selector
    ) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.34).cgColor
        view.layer?.cornerRadius = 10
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.28).cgColor
        view.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        let top = NSStackView()
        top.orientation = .horizontal
        top.alignment = .centerY
        top.spacing = 8

        let iconLabel = NSTextField(labelWithString: icon)
        iconLabel.font = .monospacedSystemFont(ofSize: 12, weight: .black)
        iconLabel.textColor = NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.22, alpha: 1)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .bold)
        titleLabel.textColor = .labelColor

        top.addArrangedSubview(iconLabel)
        top.addArrangedSubview(titleLabel)

        let bodyLabel = NSTextField(labelWithString: body)
        bodyLabel.font = .systemFont(ofSize: 12, weight: .medium)
        bodyLabel.textColor = .secondaryLabelColor
        bodyLabel.maximumNumberOfLines = 2
        bodyLabel.preferredMaxLayoutWidth = Layout.permissionItemWidth - 28
        bodyLabel.lineBreakMode = .byWordWrapping

        statusLabel.font = .monospacedSystemFont(ofSize: 11, weight: .heavy)
        statusLabel.textColor = .secondaryLabelColor

        let button = NSButton(title: buttonTitle, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.font = .systemFont(ofSize: 12, weight: .semibold)
        button.widthAnchor.constraint(equalToConstant: 132).isActive = true

        stack.addArrangedSubview(top)
        stack.addArrangedSubview(bodyLabel)
        stack.addArrangedSubview(statusLabel)
        stack.addArrangedSubview(button)

        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: Layout.permissionItemWidth),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14)
        ])

        return view
    }

    private func sectionTitle(_ title: String, _ subtitle: String) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        titleLabel.textColor = .labelColor

        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        subtitleLabel.textColor = .secondaryLabelColor

        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(subtitleLabel)
        return stack
    }

    private func tileGrid(for category: AwayoPreviewCategory) -> NSView {
        let grid = NSStackView()
        grid.orientation = .vertical
        grid.alignment = .leading
        grid.spacing = Layout.previewTileSpacing
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.widthAnchor.constraint(equalToConstant: Layout.previewGridWidth).isActive = true
        grid.setContentHuggingPriority(.required, for: .horizontal)
        grid.setContentCompressionResistancePriority(.required, for: .horizontal)

        let tiles = makeTiles(for: category)
        tiles.chunked(into: Layout.previewGridColumns).forEach { rowTiles in
            let row = NSStackView(views: rowTiles)
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = Layout.previewTileSpacing
            row.setContentHuggingPriority(.required, for: .horizontal)
            grid.addArrangedSubview(row)
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
            let backgroundOrder: [AwayoLockStyle] = [
                .solidColor,
                .softWash,
                .stripes,
                .polkaDots,
                .screenSnapshot,
                .duckPond,
                .offlineRunner,
                .cosmicDesk,
                .rainyWindow,
                .arcadePulse,
                .paperNotes,
                .synthwave,
                .neonFlow
            ]
            return backgroundOrder.map { tile(category: category, rawValue: $0.rawValue, title: $0.title) }
        case .timer:
            return AwayoTimerStyle.allCases.map { tile(category: category, rawValue: $0.rawValue, title: $0.title) }
        case .dashboard:
            return AwayoDashboardStyle.allCases.map { tile(category: category, rawValue: $0.rawValue, title: $0.title) }
        case .note:
            return AwayoNoteStyle.allCases.map { tile(category: category, rawValue: $0.rawValue, title: $0.title) }
        }
    }

    private func tile(category: AwayoPreviewCategory, rawValue: String, title: String) -> AwayoPreviewTile {
        let tile = AwayoPreviewTile(category: category, rawValue: rawValue, title: title)
        tile.target = self
        tile.action = #selector(selectTile(_:))
        tile.translatesAutoresizingMaskIntoConstraints = false
        tile.widthAnchor.constraint(equalToConstant: Layout.previewTileWidth).isActive = true
        tile.heightAnchor.constraint(equalToConstant: Layout.previewTileHeight).isActive = true
        return tile
    }

    private func customColorControl() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 0, right: 0)
        row.setContentHuggingPriority(.required, for: .horizontal)

        let label = NSTextField(labelWithString: "Custom color")
        label.font = .systemFont(ofSize: 13, weight: .bold)
        label.textColor = .secondaryLabelColor

        let choose = NSButton(title: "Choose Color...", target: self, action: #selector(chooseSolidBackgroundColor))
        choose.bezelStyle = .rounded
        choose.controlSize = .regular
        choose.font = .systemFont(ofSize: 13, weight: .semibold)

        row.addArrangedSubview(label)
        row.addArrangedSubview(backgroundColorSwatch)
        row.addArrangedSubview(choose)

        return row
    }

    @objc private func awayNoteToggled(_ sender: NSButton) {
        settingsStore.saveShowsAwayMessage(sender.state == .on)
        refreshAwayNoteControls()
    }

    @objc private func awayNoteChanged(_ sender: NSTextField) {
        settingsStore.saveAwayMessage(sender.stringValue)
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, field === awayNoteField else {
            return
        }

        settingsStore.saveAwayMessage(field.stringValue)
    }

    @objc private func cameraGagToggled(_ sender: NSButton) {
        guard sender.state == .on else {
            settingsStore.saveCameraGagEnabled(false)
            refreshCameraGagControls()
            refreshPermissionControls()
            return
        }

        requestCameraPermissionThenEnableGag()
    }

    @objc private func setHotKey() {
        guard let hotKey = promptForHotKey() else {
            return
        }

        settingsStore.saveHotKey(hotKey)
        refreshHotKeyControls()
        onSettingsChange()
    }

    @objc private func clearHotKey() {
        settingsStore.saveHotKey(nil)
        refreshHotKeyControls()
        onSettingsChange()
    }

    @objc private func selectTile(_ sender: AwayoPreviewTile) {
        switch sender.category {
        case .background:
            if let value = AwayoLockStyle(rawValue: sender.rawValue) {
                settingsStore.saveBackgroundStyle(value)
                if value == .solidColor {
                    showSolidColorPanel()
                } else if value == .screenSnapshot {
                    requestScreenSnapshotPermission()
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
        refreshPermissionControls()
    }

    private func requestCameraPermissionThenEnableGag() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            settingsStore.saveCameraGagEnabled(true)
            refreshCameraGagControls()
            refreshPermissionControls()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }

                    self.settingsStore.saveCameraGagEnabled(granted)
                    self.refreshCameraGagControls()
                    self.refreshPermissionControls()
                    if !granted {
                        self.showError("Camera access was not granted, so the NICE TRY camera snap stayed off.")
                    }
                }
            }
        case .denied, .restricted:
            settingsStore.saveCameraGagEnabled(false)
            refreshCameraGagControls()
            refreshPermissionControls()
            showError("Camera access is off for Awayo. Enable it in System Settings > Privacy & Security > Camera, then turn this setting on again.")
        @unknown default:
            settingsStore.saveCameraGagEnabled(false)
            refreshCameraGagControls()
            refreshPermissionControls()
        }
    }

    private func requestScreenSnapshotPermission() {
        guard !CGPreflightScreenCaptureAccess() else {
            refreshPermissionControls()
            return
        }

        if !CGRequestScreenCaptureAccess() {
            showError("Screen Snapshot needs Screen Recording permission. macOS may ask now; if it asks you to reopen Awayo, quit and open Awayo once.")
        }
        refreshPermissionControls()
    }

    @objc private func requestScreenRecordingPermissionFromSettings() {
        requestScreenSnapshotPermission()
        openPrivacyPane("Privacy_ScreenCapture")
    }

    @objc private func openCameraPrivacySettings() {
        openPrivacyPane("Privacy_Camera")
    }

    private func openPrivacyPane(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    @objc private func chooseSolidBackgroundColor() {
        settingsStore.saveBackgroundStyle(.solidColor)
        refreshSelections()
        showSolidColorPanel()
    }

    @objc private func solidBackgroundColorChanged(_ sender: Any?) {
        let color = (sender as? NSColorPanel)?.color ?? NSColorPanel.shared.color
        settingsStore.saveSolidBackgroundColor(AwayoColor(nsColor: color))
        settingsStore.saveBackgroundStyle(.solidColor)
        refreshSelections()
    }

    private func showSolidColorPanel() {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = settingsStore.appearance().solidBackgroundColor.nsColor
        panel.setTarget(self)
        panel.setAction(#selector(solidBackgroundColorChanged(_:)))
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
        settingsStore.saveShowsAwayMessage(values.noteEnabled)
        settingsStore.saveAwayMessage(values.note)
        onSettingsChange()
        refreshPasscodeStatus()
        refreshAwayNoteControls()
    }

    private func promptForHotKey() -> AwayoHotKey? {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 262),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.title = "Set Awayo Hotkey"
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
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 26, bottom: 22, right: 26)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        let title = NSTextField(labelWithString: "Press a Hotkey")
        title.font = .systemFont(ofSize: 22, weight: .black)
        title.textColor = .labelColor

        let subtitle = NSTextField(labelWithString: "Use at least Command, Control, or Option. Press once to lock, then press again to unlock.")
        subtitle.font = .systemFont(ofSize: 13, weight: .medium)
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 2
        subtitle.preferredMaxLayoutWidth = 370

        let captureView = AwayoHotKeyCaptureView()
        captureView.translatesAutoresizingMaskIntoConstraints = false
        captureView.widthAnchor.constraint(equalToConstant: 370).isActive = true
        captureView.heightAnchor.constraint(equalToConstant: 74).isActive = true

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 10
        buttonRow.widthAnchor.constraint(equalToConstant: 370).isActive = true

        let cancel = NSButton(title: "Cancel", target: nil, action: nil)
        cancel.bezelStyle = .rounded
        cancel.controlSize = .large

        let cancelTarget = ModalButtonTarget {
            NSApp.stopModal(withCode: .cancel)
        }
        modalButtonTargets = [cancelTarget]
        cancel.target = cancelTarget
        cancel.action = #selector(ModalButtonTarget.fire)

        buttonRow.addArrangedSubview(NSView())
        buttonRow.addArrangedSubview(cancel)

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(subtitle)
        stack.addArrangedSubview(captureView)
        stack.addArrangedSubview(buttonRow)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        var capturedHotKey: AwayoHotKey?
        captureView.onCapture = { hotKey in
            capturedHotKey = hotKey
            NSApp.stopModal(withCode: .OK)
        }
        captureView.onCancel = {
            NSApp.stopModal(withCode: .cancel)
        }

        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(captureView)
        let response = NSApp.runModal(for: panel)
        panel.orderOut(nil)
        modalButtonTargets.removeAll()

        guard response == .OK else {
            return nil
        }

        return capturedHotKey
    }

    private func promptForPasscode() -> (passcode: String, confirmation: String, noteEnabled: Bool, note: String)? {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 372),
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

        let noteToggle = NSButton(checkboxWithTitle: "Show away note", target: nil, action: nil)
        noteToggle.font = .systemFont(ofSize: 13, weight: .semibold)
        noteToggle.state = settingsStore.showsAwayMessage() ? .on : .off

        let noteField = NSTextField(string: settingsStore.awayMessage())
        noteField.placeholderString = AwayoSettingsStore.defaultAwayMessage
        noteField.font = .systemFont(ofSize: 14, weight: .semibold)
        noteField.bezelStyle = .roundedBezel
        noteField.widthAnchor.constraint(equalToConstant: 360).isActive = true

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
        stack.addArrangedSubview(noteToggle)
        stack.addArrangedSubview(noteField)
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

        return (
            passcodeField.stringValue,
            confirmationField.stringValue,
            noteToggle.state == .on,
            noteField.stringValue
        )
    }

    @objc private func done() {
        settingsStore.saveAwayMessage(awayNoteField.stringValue)

        if onboarding && !passcodeStore.hasPasscode() {
            showError("Set an Awayo Lock passcode to finish setup.")
            return
        }

        settingsStore.markFirstRunComplete()
        close()
    }

    private func refreshSelections() {
        let appearance = settingsStore.appearance()
        backgroundColorSwatch.color = appearance.solidBackgroundColor.nsColor
        backgroundTiles.forEach { $0.isSelected = $0.rawValue == appearance.backgroundStyle.rawValue }
        backgroundTiles.forEach { $0.customSolidColor = appearance.solidBackgroundColor.nsColor }
        timerTiles.forEach { $0.isSelected = $0.rawValue == appearance.timerStyle.rawValue }
        dashboardTiles.forEach { $0.isSelected = $0.rawValue == appearance.dashboardStyle.rawValue }
        noteTiles.forEach { $0.isSelected = $0.rawValue == appearance.noteStyle.rawValue }
    }

    private func refreshAwayNoteControls() {
        let showsAwayMessage = settingsStore.showsAwayMessage()
        awayNoteToggle.state = showsAwayMessage ? .on : .off
        awayNoteField.stringValue = settingsStore.awayMessage()
        awayNoteField.isEnabled = showsAwayMessage
        awayNoteField.alphaValue = showsAwayMessage ? 1 : 0.55
    }

    private func refreshCameraGagControls() {
        cameraGagToggle.state = settingsStore.cameraGagEnabled() ? .on : .off
    }

    private func refreshPermissionControls() {
        let readyColor = NSColor(calibratedRed: 0.46, green: 0.92, blue: 0.55, alpha: 1)
        let needsColor = NSColor(calibratedRed: 1.0, green: 0.73, blue: 0.26, alpha: 1)

        if CGPreflightScreenCaptureAccess() {
            screenRecordingStatusLabel.stringValue = "READY"
            screenRecordingStatusLabel.textColor = readyColor
        } else {
            screenRecordingStatusLabel.stringValue = "NEEDS SCREEN RECORDING"
            screenRecordingStatusLabel.textColor = needsColor
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraPermissionStatusLabel.stringValue = "READY"
            cameraPermissionStatusLabel.textColor = readyColor
        case .notDetermined:
            cameraPermissionStatusLabel.stringValue = "ASKS WHEN ENABLED"
            cameraPermissionStatusLabel.textColor = needsColor
        case .denied, .restricted:
            cameraPermissionStatusLabel.stringValue = "NEEDS CAMERA ACCESS"
            cameraPermissionStatusLabel.textColor = needsColor
        @unknown default:
            cameraPermissionStatusLabel.stringValue = "UNKNOWN"
            cameraPermissionStatusLabel.textColor = .secondaryLabelColor
        }
    }

    private func refreshHotKeyControls() {
        if let hotKey = settingsStore.hotKey() {
            hotKeyStatusLabel.stringValue = "\(hotKey.displayString) locks and unlocks Awayo."
            hotKeyButton.title = "Change Hotkey"
            hotKeyClearButton.isEnabled = true
            hotKeyClearButton.alphaValue = 1
        } else {
            hotKeyStatusLabel.stringValue = "No hotkey set. Add one to lock and unlock from anywhere."
            hotKeyButton.title = "Set Hotkey"
            hotKeyClearButton.isEnabled = false
            hotKeyClearButton.alphaValue = 0.45
        }
    }

    private func refreshPasscodeStatus() {
        passcodeStatusLabel.stringValue = passcodeStore.hasPasscode()
            ? "Awayo Lock is ready. Agents can keep running behind it."
            : "Set this once before starting Awayo Lock."
        passcodeButton.title = passcodeStore.hasPasscode() ? "Change Passcode" : "Set Passcode"
    }

    private func cardView() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.48).cgColor
        view.layer?.cornerRadius = 10
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        return view
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Awayo"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

@MainActor
private final class AwayoFlippedView: NSView {
    override var isFlipped: Bool {
        true
    }
}

@MainActor
private final class AwayoSidebarButton: NSButton {
    var isPicked = false {
        didSet {
            needsDisplay = true
        }
    }

    private let itemTitle: String
    private let itemSubtitle: String
    private let symbolName: String

    override var isFlipped: Bool {
        true
    }

    init(title: String, subtitle: String, symbolName: String) {
        self.itemTitle = title
        self.itemSubtitle = subtitle
        self.symbolName = symbolName
        super.init(frame: .zero)

        self.title = ""
        isBordered = false
        setButtonType(.momentaryChange)
        wantsLayer = true
        toolTip = title
        setAccessibilityLabel(title)
        setAccessibilityHelp(subtitle)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0, dy: 1)
        if isPicked {
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.16).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9).fill()

            NSColor.controlAccentColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.minY + 8, width: 3, height: rect.height - 16), xRadius: 1.5, yRadius: 1.5).fill()
        } else if cell?.isHighlighted == true {
            NSColor.labelColor.withAlphaComponent(0.06).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9).fill()
        }

        let titleColor = isPicked ? NSColor.labelColor : NSColor.secondaryLabelColor
        let subtitleColor = isPicked ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor

        itemTitle.draw(
            in: NSRect(x: rect.minX + 14, y: rect.minY + 6, width: rect.width - 24, height: 18),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: titleColor
            ]
        )

        itemSubtitle.draw(
            in: NSRect(x: rect.minX + 14, y: rect.minY + 24, width: rect.width - 24, height: 14),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: subtitleColor
            ]
        )
    }
}

@MainActor
private final class AwayoColorSwatchView: NSView {
    var color = AwayoColor.defaultSolidBackground.nsColor {
        didSet {
            needsDisplay = true
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 34, height: 24)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        color.setFill()
        path.fill()

        NSColor.white.withAlphaComponent(0.30).setStroke()
        let highlight = NSBezierPath()
        highlight.move(to: NSPoint(x: rect.minX + 7, y: rect.maxY - 7))
        highlight.line(to: NSPoint(x: rect.maxX - 7, y: rect.maxY - 7))
        highlight.lineWidth = 2
        highlight.stroke()

        NSColor.separatorColor.withAlphaComponent(0.75).setStroke()
        path.lineWidth = 1
        path.stroke()
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
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).addClip()

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

        NSGraphicsContext.restoreGraphicsState()
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
        case .screenSnapshot:
            drawMiniScreenSnapshot(in: rect)
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
        case .hidden:
            roundedGradient(in: rect, colors: [
                NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.11, alpha: 1),
                NSColor(calibratedRed: 0.02, green: 0.02, blue: 0.03, alpha: 1)
            ])
            drawPill(in: NSRect(x: rect.midX - 50, y: rect.midY - 9, width: 100, height: 18), color: NSColor.white.withAlphaComponent(0.12))
            drawText("no timer", in: NSRect(x: rect.midX - 54, y: rect.midY - 8, width: 108, height: 18), font: .systemFont(ofSize: 13, weight: .bold), color: .white.withAlphaComponent(0.84))
        }
    }

    private func drawDashboardPreview(in rect: NSRect) {
        let style = AwayoDashboardStyle(rawValue: rawValue) ?? .centerStage
        switch style {
        case .centerStage:
            roundedGradient(in: rect, colors: [
                NSColor(calibratedRed: 0.12, green: 0.11, blue: 0.24, alpha: 1),
                NSColor(calibratedRed: 0.35, green: 0.18, blue: 0.55, alpha: 1)
            ])
            NSColor.white.withAlphaComponent(0.14).setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.midX - 70, y: rect.minY + 18, width: 140, height: 36)).fill()
            drawPill(in: NSRect(x: rect.midX - 58, y: rect.midY + 10, width: 116, height: 18), color: NSColor(calibratedRed: 0.98, green: 0.86, blue: 0.30, alpha: 0.94))
            drawText("AWAYO", in: NSRect(x: rect.midX - 50, y: rect.midY + 10, width: 100, height: 18), font: .monospacedSystemFont(ofSize: 11, weight: .heavy), color: .black)
            drawText("14m", in: NSRect(x: rect.midX - 42, y: rect.midY - 28, width: 84, height: 30), font: .systemFont(ofSize: 25, weight: .black), color: .white)
        case .paperDesk:
            roundedGradient(in: rect, colors: [
                NSColor(calibratedRed: 0.48, green: 0.35, blue: 0.22, alpha: 1),
                NSColor(calibratedRed: 0.24, green: 0.18, blue: 0.13, alpha: 1)
            ])
            let paper = rect.insetBy(dx: 34, dy: 12)
            drawPaper(in: paper, color: NSColor(calibratedRed: 1.0, green: 0.91, blue: 0.58, alpha: 1))
            drawPill(in: NSRect(x: paper.midX - 26, y: paper.maxY - 8, width: 52, height: 12), color: .white.withAlphaComponent(0.65))
            drawText("brb", in: NSRect(x: paper.minX + 14, y: paper.midY - 4, width: paper.width - 28, height: 26), font: handwrittenFont(size: 24, weight: .bold), color: NSColor(calibratedRed: 0.24, green: 0.15, blue: 0.08, alpha: 1))
            NSColor(calibratedRed: 0.52, green: 0.34, blue: 0.16, alpha: 0.55).setStroke()
            let pencil = NSBezierPath()
            pencil.move(to: NSPoint(x: paper.maxX - 48, y: paper.minY + 18))
            pencil.line(to: NSPoint(x: paper.maxX - 12, y: paper.minY + 30))
            pencil.lineWidth = 5
            pencil.stroke()
        case .minimalBadge:
            roundedGradient(in: rect, colors: [
                NSColor(calibratedRed: 0.02, green: 0.03, blue: 0.04, alpha: 1),
                NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.10, alpha: 1)
            ])
            drawPill(in: NSRect(x: rect.midX - 38, y: rect.midY - 10, width: 76, height: 20), color: .white.withAlphaComponent(0.92))
            drawText("away", in: NSRect(x: rect.midX - 31, y: rect.midY - 7, width: 62, height: 16), font: .systemFont(ofSize: 11, weight: .bold), color: .black)
            drawPill(in: NSRect(x: rect.midX - 52, y: rect.midY - 34, width: 104, height: 6), color: .white.withAlphaComponent(0.18))
        case .commandCenter:
            roundedGradient(in: rect, colors: [
                NSColor(calibratedRed: 0.02, green: 0.09, blue: 0.14, alpha: 1),
                NSColor(calibratedRed: 0.03, green: 0.02, blue: 0.08, alpha: 1)
            ])
            let panel = rect.insetBy(dx: 14, dy: 14)
            drawPill(in: panel, color: .black.withAlphaComponent(0.48))
            strokePill(in: panel, color: NSColor(calibratedRed: 0.2, green: 0.82, blue: 0.9, alpha: 0.30))
            drawTinyStatusDots(in: panel)
            drawText("$ alive", in: panel.insetBy(dx: 18, dy: 28), font: .monospacedSystemFont(ofSize: 20, weight: .bold), color: NSColor(calibratedRed: 0.47, green: 1.0, blue: 0.63, alpha: 1), alignment: .left)
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
        case .hidden:
            drawPill(in: NSRect(x: rect.midX - 56, y: rect.midY - 12, width: 112, height: 24), color: NSColor.white.withAlphaComponent(0.14))
            drawText("no notes", in: NSRect(x: rect.midX - 54, y: rect.midY - 9, width: 108, height: 18), font: .systemFont(ofSize: 13, weight: .bold), color: .white.withAlphaComponent(0.84))
        }
    }

    private func roundedGradient(in rect: NSRect, colors: [NSColor]) {
        NSGraphicsContext.saveGraphicsState()
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        path.addClip()
        NSGradient(colors: colors)?.draw(in: rect, angle: -35)
        NSGraphicsContext.restoreGraphicsState()
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
            NSColor(calibratedRed: 0.01, green: 0.01, blue: 0.05, alpha: 1),
            NSColor(calibratedRed: 0.09, green: 0.03, blue: 0.18, alpha: 1),
            NSColor(calibratedRed: 0.00, green: 0.09, blue: 0.15, alpha: 1)
        ])
        drawStars(in: rect, count: 44)
        let center = NSPoint(x: rect.midX, y: rect.midY)
        NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.22, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - 20, y: center.y - 20, width: 40, height: 40)).fill()
        let colors: [NSColor] = [.systemGray, .systemOrange, .systemBlue, .systemRed, .systemBrown, .systemYellow, .systemCyan]
        for index in 0..<7 {
            let orbitX = CGFloat(34 + index * 18)
            let orbitY = CGFloat(17 + index * 10)
            NSColor.white.withAlphaComponent(0.10).setStroke()
            NSBezierPath(ovalIn: NSRect(x: center.x - orbitX, y: center.y - orbitY, width: orbitX * 2, height: orbitY * 2)).stroke()
            let angle = CGFloat(index) * 0.82 + 0.4
            let size = CGFloat(7 + index % 3 * 3)
            let point = NSPoint(x: center.x + cos(angle) * orbitX, y: center.y + sin(angle) * orbitY)
            colors[index].setFill()
            NSBezierPath(ovalIn: NSRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)).fill()
        }
    }

    private func drawMiniRainyWindow(in rect: NSRect) {
        roundedGradient(in: rect, colors: [
            NSColor(calibratedRed: 0.48, green: 0.58, blue: 0.65, alpha: 1),
            NSColor(calibratedRed: 0.14, green: 0.28, blue: 0.33, alpha: 1)
        ])
        NSColor(calibratedRed: 0.08, green: 0.22, blue: 0.18, alpha: 0.70).setFill()
        NSBezierPath(rect: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.22)).fill()
        drawPill(in: NSRect(x: rect.minX + 24, y: rect.maxY - 38, width: 82, height: 18), color: .white.withAlphaComponent(0.24))
        drawPill(in: NSRect(x: rect.minX + 74, y: rect.maxY - 46, width: 116, height: 22), color: .white.withAlphaComponent(0.20))
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

    private func drawMiniScreenSnapshot(in rect: NSRect) {
        roundedGradient(in: rect, colors: [
            NSColor(calibratedRed: 0.10, green: 0.24, blue: 0.34, alpha: 1),
            NSColor(calibratedRed: 0.05, green: 0.07, blue: 0.09, alpha: 1)
        ])

        let menu = NSRect(x: rect.minX, y: rect.maxY - 16, width: rect.width, height: 16)
        NSColor.black.withAlphaComponent(0.36).setFill()
        menu.fill()

        let window = NSRect(x: rect.minX + 28, y: rect.minY + 30, width: rect.width - 56, height: rect.height - 58)
        drawPill(in: window, color: NSColor.white.withAlphaComponent(0.16))
        strokePill(in: window, color: NSColor.white.withAlphaComponent(0.22))

        for index in 0..<4 {
            let y = window.maxY - 24 - CGFloat(index) * 16
            drawPill(in: NSRect(x: window.minX + 16, y: y, width: window.width - CGFloat(42 + index * 18), height: 5), color: NSColor.white.withAlphaComponent(0.28))
        }

        let input = NSRect(x: rect.midX - 34, y: rect.minY + 10, width: 68, height: 10)
        drawPill(in: input, color: NSColor.black.withAlphaComponent(0.34))
        strokePill(in: input, color: NSColor.white.withAlphaComponent(0.14))
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
private final class AwayoHotKeyCaptureView: NSView {
    var onCapture: ((AwayoHotKey) -> Void)?
    var onCancel: (() -> Void)?
    private var message = "Type a shortcut"

    override var acceptsFirstResponder: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.55).cgColor
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }

        guard let hotKey = AwayoHotKey(event: event), hotKey.isValidGlobalShortcut else {
            message = "Add Command, Control, or Option"
            needsDisplay = true
            NSSound.beep()
            return
        }

        onCapture?(hotKey)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        message.draw(
            in: bounds.insetBy(dx: 18, dy: 24),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 19, weight: .black),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ]
        )
    }
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
