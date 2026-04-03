import Foundation

// =============================================================================
// SocketManager — Unix socket connection to voicedaemon
// =============================================================================
// Handles start/stop/status/cancel commands and receives pushed transcripts.
// Maintains a persistent connection for transcript streaming during recording.

enum DaemonState: String {
    case idle
    case recording
    case processing
}

@MainActor
class SocketManager: ObservableObject {
    @Published var state: DaemonState = .idle
    @Published var isConnected: Bool = false

    var onTranscript: ((String) -> Void)?

    private let socketPath: String
    private var connection: SocketConnection?

    init(socketPath: String = "/tmp/voice-daemon.sock") {
        self.socketPath = socketPath
    }

    // MARK: - Commands

    func start() {
        guard state == .idle else { return }

        // Check socket exists before attempting connection
        guard FileManager.default.fileExists(atPath: socketPath) else {
            print("[Vigil] Socket not found — is voicedaemon running?")
            return
        }

        let conn = SocketConnection(path: socketPath)
        conn.onMessage = { [weak self] message in
            self?.handleMessage(message)
        }

        guard conn.connect() else {
            print("[Vigil] Socket connect failed — daemon not responding")
            return
        }

        conn.send("start\n")
        connection = conn
        state = .recording
    }

    func stop() {
        // Allow stop from any non-idle state to recover from stuck states
        guard state != .idle else { return }

        // Try to send stop on a separate connection
        let stopConn = SocketConnection(path: socketPath)
        stopConn.onMessage = { [weak self] message in
            if message != "(empty)" && !message.isEmpty {
                self?.onTranscript?(message)
            }
        }
        if stopConn.connect() {
            stopConn.send("stop\n")
        }

        connection?.disconnect()
        connection = nil
        state = .idle
    }

    func cancel() {
        connection?.send("cancel\n")
        connection?.disconnect()
        connection = nil
        state = .idle
    }

    func toggle() {
        switch state {
        case .idle:
            start()
        case .recording:
            stop()
        case .processing:
            break // Wait for processing to finish
        }
    }

    func checkStatus() {
        let conn = SocketConnection(path: socketPath)
        conn.onMessage = { [weak self] message in
            if let newState = DaemonState(rawValue: message.trimmingCharacters(in: .whitespacesAndNewlines)) {
                DispatchQueue.main.async {
                    self?.state = newState
                }
            }
        }
        conn.connect()
        conn.send("status\n")
    }

    // MARK: - Message handling

    private func handleMessage(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed == "started" {
            DispatchQueue.main.async { self.state = .recording }
        } else if trimmed == "cancelled" {
            DispatchQueue.main.async { self.state = .idle }
        } else if trimmed.hasPrefix("transcript:") {
            let text = String(trimmed.dropFirst("transcript:".count))
            if !text.isEmpty {
                DispatchQueue.main.async {
                    self.onTranscript?(text)
                }
            }
        }
    }
}

// =============================================================================
// SocketConnection — low-level Unix domain socket wrapper
// =============================================================================

class SocketConnection: @unchecked Sendable {
    let path: String
    var onMessage: ((String) -> Void)?

    private var fileHandle: FileHandle?
    private var socketFD: Int32 = -1

    init(path: String) {
        self.path = path
    }

    @discardableResult
    func connect() -> Bool {
        socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else {
            print("[Vigil] Socket creation failed")
            return false
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8CString
        withUnsafeMutableBytes(of: &addr.sun_path) { rawBuf in
            let count = min(pathBytes.count, rawBuf.count)
            for i in 0..<count {
                rawBuf[i] = UInt8(bitPattern: pathBytes[i])
            }
        }

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Foundation.connect(socketFD, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard result == 0 else {
            print("[Vigil] Socket connect failed: \(String(cString: strerror(errno)))")
            close(socketFD)
            socketFD = -1
            return false
        }

        fileHandle = FileHandle(fileDescriptor: socketFD, closeOnDealloc: false)
        startReading()
        return true
    }

    func send(_ message: String) {
        guard let data = message.data(using: .utf8) else { return }
        fileHandle?.write(data)
    }

    func disconnect() {
        fileHandle = nil
        if socketFD >= 0 {
            close(socketFD)
            socketFD = -1
        }
    }

    private func startReading() {
        guard let fh = fileHandle else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            while let self = self, self.socketFD >= 0 {
                let data = fh.availableData
                if data.isEmpty { break } // EOF
                if let message = String(data: data, encoding: .utf8) {
                    // Split on newlines — daemon sends line-delimited messages
                    for line in message.split(separator: "\n", omittingEmptySubsequences: true) {
                        let msg = String(line)
                        DispatchQueue.main.async {
                            self.onMessage?(msg)
                        }
                    }
                }
            }
        }
    }
}
