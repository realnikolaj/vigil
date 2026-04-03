import AppKit

// =============================================================================
// TouchBarController — Touch Bar integration
// =============================================================================
// Shows recording state, toggle button, and status indicators.
//
// TODO(copilot): Investigate NSTouchBar for non-NSWindow apps.
// The standard approach requires an NSWindow or NSResponder chain.
// For a menu bar app without windows, we may need to use
// NSApplication.touchBar or become first responder via a hidden window.
// FineTune's approach to menu-bar-only Touch Bar would be valuable here.

class TouchBarController: NSObject {
    private let socketManager: SocketManager

    // Touch Bar item identifiers
    private static let toggleID = NSTouchBarItem.Identifier("vigil.toggle")
    private static let statusID = NSTouchBarItem.Identifier("vigil.status")
    private static let timerID = NSTouchBarItem.Identifier("vigil.timer")

    private var recordingStartTime: Date?
    private var timerUpdateTimer: Timer?

    init(socketManager: SocketManager) {
        self.socketManager = socketManager
        super.init()
        setupTouchBar()
    }

    func flashTranscript() {
        // TODO: Brief green flash on the status indicator when transcript arrives
    }

    // MARK: - Setup

    private func setupTouchBar() {
        // TODO(copilot): This is the key question for Vigil.
        // How do we present a Touch Bar from a menu-bar-only app (no NSWindow)?
        //
        // Options to investigate:
        // 1. NSApplication.touchBar — set app-level Touch Bar
        // 2. Create a hidden NSWindow that becomes key to own the Touch Bar
        // 3. Use the NSTouchBarProvider protocol on NSApplication
        // 4. Check how FineTune handles this — they are also a menu bar app
        //
        // For now, stub the items so the structure is ready.

        print("[Vigil] Touch Bar controller initialized (pending implementation)")
    }
}

// MARK: - NSTouchBarDelegate

extension TouchBarController: NSTouchBarDelegate {

    func makeTouchBar() -> NSTouchBar {
        let touchBar = NSTouchBar()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [
            Self.toggleID,
            Self.statusID,
            Self.timerID,
        ]
        return touchBar
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case Self.toggleID:
            let item = NSCustomTouchBarItem(identifier: identifier)
            let button = NSButton(
                title: "🎤 Record",
                target: self,
                action: #selector(toggleRecording)
            )
            // Color based on state
            switch socketManager.state {
            case .idle:
                button.bezelColor = .systemGray
            case .recording:
                button.bezelColor = .systemRed
            case .processing:
                button.bezelColor = .systemYellow
            }
            item.view = button
            return item

        case Self.statusID:
            let item = NSCustomTouchBarItem(identifier: identifier)
            let label = NSTextField(labelWithString: socketManager.state.rawValue.uppercased())
            label.textColor = .white
            label.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
            item.view = label
            return item

        case Self.timerID:
            let item = NSCustomTouchBarItem(identifier: identifier)
            let label = NSTextField(labelWithString: "0:00")
            label.textColor = .secondaryLabelColor
            label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            item.view = label
            return item

        default:
            return nil
        }
    }

    @objc private func toggleRecording() {
        let mgr = socketManager
        Task { @MainActor in
            mgr.toggle()
        }
    }
}
