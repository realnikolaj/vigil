import Foundation

// =============================================================================
// ProcessManager — voicedaemon child process lifecycle
// =============================================================================
// Launches voicedaemon as one or two child processes (STT-only, TTS-only).
// Captures stdout/stderr for log display. Handles restart on crash or
// device change.

@MainActor
class ProcessManager: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var recentLogs: [String] = []

    private var daemonProcess: Process?
    private var daemonBinaryPath: String

    // TODO: Support split mode (--stt-only / --tts-only)
    // private var sttProcess: Process?
    // private var ttsProcess: Process?

    init(binaryPath: String = "/Users/beskar/go/bin/voicedaemon") {
        self.daemonBinaryPath = binaryPath
    }

    // MARK: - Launch

    func launchDaemon(extraArgs: [String] = []) {
        guard !isRunning else {
            print("[Vigil] Daemon already running")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: daemonBinaryPath)

        var args = [
            "--speaches-url", ProcessInfo.processInfo.environment["VOICEDAEMON_STT_URL"]
                ?? "http://100.100.244.135:34151",
            "--stt-model", "deepdml/faster-whisper-large-v3-turbo-ct2",
            "--debug",
        ]
        args.append(contentsOf: extraArgs)
        process.arguments = args

        // Capture output
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                let lines = line.split(separator: "\n").map(String.init)
                self?.recentLogs.append(contentsOf: lines)
                // Keep last 100 lines
                if let count = self?.recentLogs.count, count > 100 {
                    self?.recentLogs.removeFirst(count - 100)
                }
            }
        }

        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.isRunning = false
                print("[Vigil] Daemon exited with code \(proc.terminationStatus)")
                // TODO: Auto-restart on unexpected termination
            }
        }

        do {
            try process.run()
            daemonProcess = process
            isRunning = true
            let msg = "[Vigil] Daemon launched (pid \(process.processIdentifier))"
            print(msg)
            recentLogs.append(msg)
        } catch {
            let msg = "[Vigil] Failed to launch daemon: \(error)"
            print(msg)
            recentLogs.append(msg)
        }
    }

    func stopDaemon() {
        guard let process = daemonProcess, process.isRunning else { return }
        process.terminate()
        daemonProcess = nil
        isRunning = false
        print("[Vigil] Daemon stopped")
    }

    func restartDaemon(extraArgs: [String] = []) {
        stopDaemon()
        // Small delay to let socket clean up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.launchDaemon(extraArgs: extraArgs)
        }
    }

    /// Restart with a specific input device
    func restartWithDevice(_ deviceName: String) {
        // TODO: voicedaemon needs a --input-device flag for this to work
        // For now, macOS default device selection applies
        print("[Vigil] Restarting daemon for device: \(deviceName)")
        restartDaemon()
    }
}
