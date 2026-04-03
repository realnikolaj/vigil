import AppKit
import SwiftUI

// =============================================================================
// Vigil — Native macOS control plane for voicedaemon
// =============================================================================
// Menu bar app that manages voicedaemon processes, audio devices,
// Touch Bar controls, transcript overlay, and training data recording.

@main
struct VigilApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

// =============================================================================
// App Delegate — owns the menu bar, Touch Bar, and child processes
// =============================================================================
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var socketManager: SocketManager!
    private var deviceManager: DeviceManager!
    private var processManager: ProcessManager!
    private var transcriptStore: TranscriptStore!
    private var overlayWindow: OverlayWindow?
    private var touchBarController: TouchBarController?
    private var capsLockMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon — menu bar only
        NSApp.setActivationPolicy(.accessory)

        // Core managers
        socketManager = SocketManager()
        deviceManager = DeviceManager()
        processManager = ProcessManager()
        transcriptStore = TranscriptStore()

        // Menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Vigil")
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Popover with SwiftUI content
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 480)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: VigilPopoverView(
                socketManager: socketManager,
                deviceManager: deviceManager,
                processManager: processManager,
                transcriptStore: transcriptStore
            )
        )

        // Overlay window for transcripts
        overlayWindow = OverlayWindow()

        // Touch Bar
        touchBarController = TouchBarController(socketManager: socketManager)

        // Device change monitoring
        deviceManager.onDeviceChanged = { [weak self] change in
            self?.handleDeviceChange(change)
        }

        // Transcript handling
        socketManager.onTranscript = { [weak self] text in
            self?.handleTranscript(text)
        }

        // Caps Lock toggle
        setupCapsLockMonitor()

        // Launch voicedaemon child processes
        processManager.launchDaemon()

        print("[Vigil] Ready")
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func handleDeviceChange(_ change: DeviceChange) {
        print("[Vigil] Device change: \(change)")
        // TODO: Auto-restart STT child process with new device
        // TODO: Update Touch Bar device indicator
        updateMenuBarIcon()
    }

    private func handleTranscript(_ text: String) {
        print("[Vigil] Transcript received: \(text.prefix(60))")
        transcriptStore.add(text)
        overlayWindow?.showTranscript(text)
        touchBarController?.flashTranscript()
        updateMenuBarIcon()
    }

    private var lastCapsLockTime: TimeInterval = 0

    private func setupCapsLockMonitor() {
        // Caps Lock fires flagsChanged on both press and release.
        // Only toggle on the transition TO capsLock being set (press, not release).
        // Debounce at 500ms to prevent double-fire.
        capsLockMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return }
            let hasCapsLock = event.modifierFlags.contains(.capsLock)
            let now = ProcessInfo.processInfo.systemUptime
            if hasCapsLock && (now - self.lastCapsLockTime) > 0.5 {
                self.lastCapsLockTime = now
                self.socketManager.toggle()
                self.updateMenuBarIcon()
            }
        }
    }

    private func updateMenuBarIcon() {
        guard let button = statusItem.button else { return }
        let symbolName: String
        switch socketManager.state {
        case .idle:
            symbolName = "mic.fill"
        case .recording:
            symbolName = "mic.badge.plus"
        case .processing:
            symbolName = "waveform"
        }
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Vigil")
    }
}
