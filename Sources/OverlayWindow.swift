import AppKit
import SwiftUI

// =============================================================================
// OverlayWindow — transparent subtitle overlay
// =============================================================================
// Replaces Hammerspoon's canvas overlay with a native macOS window.
// Shows 1-2 lines of transcript text, subtitle-style, at the bottom
// of the screen. Supports click-to-correct for training data.

class OverlayWindow {
    private var window: NSWindow?
    private var hostingView: NSHostingView<OverlayView>?
    private var viewModel = OverlayViewModel()
    private var hideTimer: Timer?

    init() {
        setupWindow()
    }

    func showTranscript(_ text: String) {
        viewModel.addTranscript(text)
        window?.orderFront(nil)

        // Auto-hide after 5 seconds of no new transcripts
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }

    func hide() {
        hideTimer?.invalidate()
        window?.orderOut(nil)
        viewModel.clear()
    }

    private func setupWindow() {
        guard let screen = NSScreen.main else { return }

        let windowHeight: CGFloat = 80
        let bottomMargin: CGFloat = 100
        let windowFrame = NSRect(
            x: screen.frame.minX + 50,
            y: screen.frame.minY + bottomMargin,
            width: screen.frame.width - 100,
            height: windowHeight
        )

        let window = NSWindow(
            contentRect: windowFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.ignoresMouseEvents = false  // Allow clicks for correction
        window.hasShadow = false

        let hostingView = NSHostingView(rootView: OverlayView(viewModel: viewModel))
        window.contentView = hostingView

        self.window = window
        self.hostingView = hostingView
    }
}

// MARK: - SwiftUI Overlay View

class OverlayViewModel: ObservableObject {
    @Published var lines: [String] = []
    @Published var correctionTarget: String? = nil

    func addTranscript(_ text: String) {
        lines.append(text)
        // Keep last 2 lines (subtitle mode)
        if lines.count > 2 {
            lines.removeFirst(lines.count - 2)
        }
    }

    func clear() {
        lines = []
    }
}

struct OverlayView: View {
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            ForEach(Array(viewModel.lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                    .lineLimit(1)
                    .onTapGesture {
                        // TODO: Open correction popover for this line
                        // This is where the training data tagging happens
                        print("[Vigil] Tapped transcript for correction: \(line)")
                        viewModel.correctionTarget = line
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.5))
        )
    }
}
