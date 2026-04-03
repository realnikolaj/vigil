import Foundation
import SQLite3

// =============================================================================
// TranscriptStore — SQLite database for transcripts and corrections
// =============================================================================
// Every transcript is stored with timestamp, session ID, and optional
// correction data. This is the training data pipeline: speak → transcribe →
// correct → export for LoRA fine-tuning.

struct Transcript: Identifiable {
    let id: Int64
    let timestamp: Date
    let text: String
    let correction: String?   // nil if correct, corrected text if tagged
    let sessionID: String
    let audioFile: String?    // path to training recording WAV
    let audioOffsetMs: Int?   // offset into the audio file
    let durationMs: Int?      // duration of this segment
}

@MainActor
class TranscriptStore: ObservableObject {
    @Published var recentTranscripts: [Transcript] = []
    @Published var correctionCount: Int = 0

    private var db: OpaquePointer?
    private let dbPath: String
    private var currentSessionID: String

    init(dbPath: String? = nil) {
        self.dbPath = dbPath ?? {
            let dir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".vigil")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appendingPathComponent("transcripts.db").path
        }()
        self.currentSessionID = ISO8601DateFormatter().string(from: Date())
        openDatabase()
        createTable()
        loadRecent()
    }

    func close() {
        sqlite3_close(db)
        db = nil
    }

    // MARK: - Public API

    func add(_ text: String, audioFile: String? = nil, audioOffsetMs: Int? = nil, durationMs: Int? = nil) {
        let sql = """
            INSERT INTO transcripts (timestamp, text, session_id, audio_file, audio_offset_ms, duration_ms)
            VALUES (?, ?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        let now = Date().timeIntervalSince1970
        sqlite3_bind_double(stmt, 1, now)
        sqlite3_bind_text(stmt, 2, (text as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (currentSessionID as NSString).utf8String, -1, nil)
        if let af = audioFile {
            sqlite3_bind_text(stmt, 4, (af as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        if let offset = audioOffsetMs { sqlite3_bind_int(stmt, 5, Int32(offset)) }
        else { sqlite3_bind_null(stmt, 5) }
        if let dur = durationMs { sqlite3_bind_int(stmt, 6, Int32(dur)) }
        else { sqlite3_bind_null(stmt, 6) }

        if sqlite3_step(stmt) == SQLITE_DONE {
            let id = sqlite3_last_insert_rowid(db)
            let transcript = Transcript(
                id: id, timestamp: Date(), text: text, correction: nil,
                sessionID: currentSessionID, audioFile: audioFile,
                audioOffsetMs: audioOffsetMs, durationMs: durationMs
            )
            DispatchQueue.main.async {
                self.recentTranscripts.append(transcript)
                // Keep last 50
                if self.recentTranscripts.count > 50 {
                    self.recentTranscripts.removeFirst(self.recentTranscripts.count - 50)
                }
            }
        }
    }

    /// Tag a word correction for training data
    func correct(id: Int64, correctedText: String) {
        let sql = "UPDATE transcripts SET correction = ? WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (correctedText as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(stmt, 2, id)

        if sqlite3_step(stmt) == SQLITE_DONE {
            DispatchQueue.main.async {
                self.correctionCount += 1
                if let idx = self.recentTranscripts.firstIndex(where: { $0.id == id }) {
                    let old = self.recentTranscripts[idx]
                    self.recentTranscripts[idx] = Transcript(
                        id: old.id, timestamp: old.timestamp, text: old.text,
                        correction: correctedText, sessionID: old.sessionID,
                        audioFile: old.audioFile, audioOffsetMs: old.audioOffsetMs,
                        durationMs: old.durationMs
                    )
                }
            }
        }
    }

    /// Export corrections for LoRA fine-tuning
    func exportTrainingData(to path: String) {
        let sql = "SELECT text, correction, audio_file, audio_offset_ms, duration_ms FROM transcripts WHERE correction IS NOT NULL"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        var entries: [[String: Any]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var entry: [String: Any] = [:]
            if let text = sqlite3_column_text(stmt, 0) { entry["original"] = String(cString: text) }
            if let corr = sqlite3_column_text(stmt, 1) { entry["corrected"] = String(cString: corr) }
            if let af = sqlite3_column_text(stmt, 2) { entry["audio_file"] = String(cString: af) }
            entry["audio_offset_ms"] = Int(sqlite3_column_int(stmt, 3))
            entry["duration_ms"] = Int(sqlite3_column_int(stmt, 4))
            entries.append(entry)
        }

        if let data = try? JSONSerialization.data(withJSONObject: entries, options: .prettyPrinted) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("[Vigil] Exported \(entries.count) corrections to \(path)")
        }
    }

    // MARK: - Private

    private func openDatabase() {
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            print("[Vigil] Failed to open database at \(dbPath)")
            return
        }
    }

    private func createTable() {
        let sql = """
            CREATE TABLE IF NOT EXISTS transcripts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp REAL NOT NULL,
                text TEXT NOT NULL,
                correction TEXT,
                session_id TEXT NOT NULL,
                audio_file TEXT,
                audio_offset_ms INTEGER,
                duration_ms INTEGER
            )
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func loadRecent() {
        let sql = "SELECT id, timestamp, text, correction, session_id, audio_file, audio_offset_ms, duration_ms FROM transcripts ORDER BY id DESC LIMIT 50"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        var transcripts: [Transcript] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            transcripts.append(Transcript(
                id: sqlite3_column_int64(stmt, 0),
                timestamp: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)),
                text: String(cString: sqlite3_column_text(stmt, 2)),
                correction: sqlite3_column_text(stmt, 3).map { String(cString: $0) },
                sessionID: String(cString: sqlite3_column_text(stmt, 4)),
                audioFile: sqlite3_column_text(stmt, 5).map { String(cString: $0) },
                audioOffsetMs: Int(sqlite3_column_int(stmt, 6)),
                durationMs: Int(sqlite3_column_int(stmt, 7))
            ))
        }
        recentTranscripts = transcripts.reversed()
        correctionCount = recentTranscripts.filter { $0.correction != nil }.count
    }
}
