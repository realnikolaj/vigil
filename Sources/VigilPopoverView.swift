import SwiftUI

// =============================================================================
// VigilPopoverView — Main menu bar popover UI
// =============================================================================
// Shows daemon status, device info, recent transcripts with correction
// capability, and controls for recording and process management.

struct VigilPopoverView: View {
    @ObservedObject var socketManager: SocketManager
    @ObservedObject var deviceManager: DeviceManager
    @ObservedObject var processManager: ProcessManager
    @ObservedObject var transcriptStore: TranscriptStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Header
            HStack {
                Image(systemName: "mic.fill")
                    .foregroundColor(stateColor)
                Text("Vigil")
                    .font(.headline)
                Spacer()
                Text(socketManager.state.rawValue.uppercased())
                    .font(.caption.monospaced())
                    .foregroundColor(stateColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(stateColor.opacity(0.15))
                    .cornerRadius(4)
            }

            Divider()

            // Record button
            Button(action: { socketManager.toggle() }) {
                HStack {
                    Image(systemName: socketManager.state == .recording ? "stop.fill" : "record.circle")
                    Text(socketManager.state == .recording ? "Stop Recording" : "Start Recording")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(socketManager.state == .recording ? .red : .blue)
            .controlSize(.large)

            // Device info
            GroupBox("Audio Devices") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "mic")
                        Text("Input:")
                            .foregroundColor(.secondary)
                        Text(deviceManager.defaultInput?.name ?? "None")
                            .lineLimit(1)
                    }
                    .font(.caption)

                    HStack {
                        Image(systemName: "speaker.wave.2")
                        Text("Output:")
                            .foregroundColor(.secondary)
                        Text(deviceManager.defaultOutput?.name ?? "None")
                            .lineLimit(1)
                    }
                    .font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Daemon status
            GroupBox("Daemon") {
                HStack {
                    Circle()
                        .fill(processManager.isRunning ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(processManager.isRunning ? "Running" : "Stopped")
                        .font(.caption)
                    Spacer()
                    Button(processManager.isRunning ? "Restart" : "Launch") {
                        if processManager.isRunning {
                            processManager.restartDaemon()
                        } else {
                            processManager.launchDaemon()
                        }
                    }
                    .controlSize(.small)
                }
            }

            // Recent transcripts (scrollable, tappable for correction)
            GroupBox("Recent (\(transcriptStore.correctionCount) corrections)") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(transcriptStore.recentTranscripts.suffix(10)) { transcript in
                            TranscriptRow(transcript: transcript) { corrected in
                                transcriptStore.correct(id: transcript.id, correctedText: corrected)
                            }
                        }
                    }
                }
                .frame(maxHeight: 150)
            }

            // Footer
            HStack {
                Button("Export Training Data") {
                    let path = FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent(".vigil/training-export.json").path
                    transcriptStore.exportTrainingData(to: path)
                }
                .controlSize(.small)
                Spacer()
                Button("Quit") {
                    processManager.stopDaemon()
                    NSApp.terminate(nil)
                }
                .controlSize(.small)
            }
        }
        .padding()
        .frame(width: 320)
    }

    private var stateColor: Color {
        switch socketManager.state {
        case .idle: return .secondary
        case .recording: return .red
        case .processing: return .yellow
        }
    }
}

// MARK: - Transcript Row with correction support

struct TranscriptRow: View {
    let transcript: Transcript
    let onCorrect: (String) -> Void

    @State private var isEditing = false
    @State private var editText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top) {
                Text(transcript.text)
                    .font(.caption)
                    .foregroundColor(transcript.correction != nil ? .orange : .primary)
                    .onTapGesture {
                        editText = transcript.correction ?? transcript.text
                        isEditing = true
                    }
                Spacer()
                Text(timeString)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if let correction = transcript.correction {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                    Text(correction)
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            if isEditing {
                HStack {
                    TextField("Corrected text", text: $editText)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    Button("Save") {
                        onCorrect(editText)
                        isEditing = false
                    }
                    .controlSize(.small)
                    Button("Cancel") {
                        isEditing = false
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: transcript.timestamp)
    }
}
