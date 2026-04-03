import SwiftUI

// =============================================================================
// VigilPopoverView — Main menu bar popover UI
// =============================================================================
// Tabbed interface: Settings (model, VAD, silence), Transcripts (with
// correction), and Logs (daemon debug output). Controls for recording
// and process management.

struct VigilPopoverView: View {
    @ObservedObject var socketManager: SocketManager
    @ObservedObject var deviceManager: DeviceManager
    @ObservedObject var processManager: ProcessManager
    @ObservedObject var transcriptStore: TranscriptStore

    @State private var selectedTab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Header
            HStack {
                Image(systemName: stateIcon)
                    .foregroundColor(stateColor)
                Text("Vigil")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(processManager.isRunning ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(socketManager.state.rawValue.uppercased())
                    .font(.caption.monospaced())
                    .foregroundColor(stateColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(stateColor.opacity(0.15))
                    .cornerRadius(4)
            }

            // Record + Daemon controls
            HStack(spacing: 8) {
                Button(action: { socketManager.toggle() }) {
                    HStack {
                        Image(systemName: socketManager.state == .recording ? "stop.fill" : "record.circle")
                        Text(socketManager.state == .recording ? "Stop" : "Record")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(socketManager.state == .recording ? .red : .blue)
                .controlSize(.regular)

                Button(processManager.isRunning ? "Restart" : "Launch") {
                    if processManager.isRunning {
                        processManager.restartDaemon()
                    } else {
                        processManager.launchDaemon()
                    }
                }
                .controlSize(.regular)
            }

            Divider()

            // Tabbed content
            Picker("", selection: $selectedTab) {
                Text("Settings").tag(0)
                Text("Transcripts").tag(1)
                Text("Logs").tag(2)
            }
            .pickerStyle(.segmented)

            switch selectedTab {
            case 0:
                SettingsTab(
                    deviceManager: deviceManager,
                    processManager: processManager
                )
            case 1:
                TranscriptsTab(transcriptStore: transcriptStore)
            case 2:
                LogsTab(processManager: processManager, socketManager: socketManager)
            default:
                EmptyView()
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
        .frame(width: 340, height: 520)
    }

    private var stateColor: Color {
        switch socketManager.state {
        case .idle: return .secondary
        case .recording: return .red
        case .processing: return .yellow
        }
    }

    private var stateIcon: String {
        switch socketManager.state {
        case .idle: return "mic.fill"
        case .recording: return "mic.badge.plus"
        case .processing: return "waveform"
        }
    }
}

// =============================================================================
// Settings Tab — model, VAD, silence, devices
// =============================================================================

struct SettingsTab: View {
    @ObservedObject var deviceManager: DeviceManager
    @ObservedObject var processManager: ProcessManager

    @AppStorage("sttModel") private var sttModel = "deepdml/faster-whisper-large-v3-turbo-ct2"
    @AppStorage("vadThreshold") private var vadThreshold = 0.9
    @AppStorage("silenceGapMs") private var silenceGapMs = 550.0
    @AppStorage("sttUrl") private var sttUrl = "http://100.100.244.135:34151"

    private let modelOptions = [
        "deepdml/faster-whisper-large-v3-turbo-ct2",
        "Systran/faster-whisper-large-v2",
        "Systran/faster-whisper-large-v3",
        "BELLE-2/Belle-whisper-large-v3-zh",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                // STT Server
                GroupBox("STT Server") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("URL:")
                                .foregroundColor(.secondary)
                                .frame(width: 50, alignment: .trailing)
                            TextField("http://...", text: $sttUrl)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption.monospaced())
                        }
                        .font(.caption)

                        HStack {
                            Text("Model:")
                                .foregroundColor(.secondary)
                                .frame(width: 50, alignment: .trailing)
                            Picker("", selection: $sttModel) {
                                ForEach(modelOptions, id: \.self) { model in
                                    Text(model.split(separator: "/").last.map(String.init) ?? model)
                                        .tag(model)
                                }
                            }
                            .labelsHidden()
                        }
                        .font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // VAD Settings
                GroupBox("Voice Detection") {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("VAD Threshold:")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(String(format: "%.2f", vadThreshold))
                                    .font(.caption.monospaced())
                            }
                            .font(.caption)
                            Slider(value: $vadThreshold, in: 0.5...1.0, step: 0.05)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("Silence Gap:")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(Int(silenceGapMs))ms")
                                    .font(.caption.monospaced())
                            }
                            .font(.caption)
                            Slider(value: $silenceGapMs, in: 300...2000, step: 50)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Audio Devices
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

                // Apply button
                Button("Apply & Restart Daemon") {
                    processManager.restartDaemon(extraArgs: [
                        "--speaches-url", sttUrl,
                        "--stt-model", sttModel,
                        "--silence-gap", String(Int(silenceGapMs)),
                    ])
                }
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}

// =============================================================================
// Transcripts Tab — scrollable list with correction support
// =============================================================================

struct TranscriptsTab: View {
    @ObservedObject var transcriptStore: TranscriptStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(transcriptStore.recentTranscripts.count) transcripts")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(transcriptStore.correctionCount) corrections")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(transcriptStore.recentTranscripts) { transcript in
                            TranscriptRow(transcript: transcript) { corrected in
                                transcriptStore.correct(id: transcript.id, correctedText: corrected)
                            }
                            .id(transcript.id)
                        }
                    }
                }
                .onChange(of: transcriptStore.recentTranscripts.count) { _, _ in
                    if let last = transcriptStore.recentTranscripts.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

// =============================================================================
// Logs Tab — daemon stdout/stderr + connection events
// =============================================================================

struct LogsTab: View {
    @ObservedObject var processManager: ProcessManager
    @ObservedObject var socketManager: SocketManager

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(processManager.recentLogs.enumerated()), id: \.offset) { idx, line in
                        Text(line)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(logColor(line))
                            .lineLimit(2)
                            .textSelection(.enabled)
                            .id(idx)
                    }
                }
            }
            .onChange(of: processManager.recentLogs.count) { _, _ in
                if let last = processManager.recentLogs.indices.last {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }

    private func logColor(_ line: String) -> Color {
        if line.contains("error") || line.contains("Error") || line.contains("failed") {
            return .red
        } else if line.contains("rtc:") || line.contains("connected") {
            return .green
        } else if line.contains("transcript") {
            return .cyan
        } else if line.contains("speech") || line.contains("vad:") {
            return .yellow
        }
        return .secondary
    }
}

// =============================================================================
// Transcript Row with correction support
// =============================================================================

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
                    .textSelection(.enabled)
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
