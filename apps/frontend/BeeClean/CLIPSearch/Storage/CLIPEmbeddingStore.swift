import Foundation
import SQLite3

/// Thread-safe SQLite store for on-device CLIP embeddings.
/// Database lives at  Application Support/CLIPSearch/clip.sqlite
/// and is completely separate from any other BeeClean database.
final class CLIPEmbeddingStore: @unchecked Sendable {

    static let shared = CLIPEmbeddingStore()

    /// Posted after embeddings are written so the search engine can invalidate its cache.
    static let didWriteNotification = Notification.Name("CLIPEmbeddingStore.didWrite")

    private let db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.beeclean.clip.embeddingstore", qos: .utility)

    // MARK: - Init

    init(path: String? = nil) {
        let resolvedPath: String?
        if let path {
            resolvedPath = path
        } else if let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first {
            let dir = appSupport.appendingPathComponent("CLIPSearch", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            resolvedPath = dir.appendingPathComponent("clip.sqlite").path
        } else {
            // Sandboxed / locked AppSupport — CLIP search degrades to "unavailable"
            // rather than crashing. CLIPSearchEngine's existing empty-result
            // fallback handles the runtime path; AskAIView can still route to
            // backend search.
            print("[CLIPEmbeddingStore] Failed to access Application Support directory — CLIP search unavailable")
            resolvedPath = nil
        }

        var handle: OpaquePointer?
        if let dbPath = resolvedPath {
            let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
            if sqlite3_open_v2(dbPath, &handle, flags, nil) != SQLITE_OK {
                print("[CLIPEmbeddingStore] Failed to open database at \(dbPath) — CLIP search unavailable")
                if handle != nil { sqlite3_close(handle); handle = nil }
            }
        }
        self.db = handle

        // Only initialize schema if the database actually opened. exec/prepare
        // are guarded too, but skipping the chatty no-ops here keeps the log clean.
        if handle != nil {
            exec("PRAGMA journal_mode=WAL")
            exec("""
                CREATE TABLE IF NOT EXISTS clip_embeddings (
                    asset_id      TEXT    PRIMARY KEY,
                    embedding     BLOB    NOT NULL,
                    model_version TEXT    NOT NULL,
                    indexed_at    INTEGER NOT NULL
                )
            """)
            exec("CREATE INDEX IF NOT EXISTS idx_clip_model_version ON clip_embeddings(model_version)")
        }
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Public API

    /// Insert or replace an embedding for the given asset.
    /// Embedding is stored as contiguous little-endian Float32 bytes.
    func upsert(assetId: String, embedding: [Float]) {
        guard db != nil else { return }
        queue.sync {
            let sql = """
                INSERT INTO clip_embeddings (asset_id, embedding, model_version, indexed_at)
                VALUES (?1, ?2, ?3, ?4)
                ON CONFLICT(asset_id) DO UPDATE SET
                    embedding     = excluded.embedding,
                    model_version = excluded.model_version,
                    indexed_at    = excluded.indexed_at
            """
            let stmt = prepare(sql)
            defer { sqlite3_finalize(stmt) }

            let blob = embedding.withUnsafeBufferPointer { buf in
                Data(buffer: buf)
            }
            let now = Int64(Date().timeIntervalSince1970)

            sqlite3_bind_text(stmt, 1, assetId, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_blob(stmt, 2, (blob as NSData).bytes, Int32(blob.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(stmt, 3, CLIPConfig.clipModelVersion, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_int64(stmt, 4, now)

            if sqlite3_step(stmt) != SQLITE_DONE {
                print("[CLIPEmbeddingStore] upsert failed: \(errorMessage)")
            }
        }
        NotificationCenter.default.post(name: Self.didWriteNotification, object: nil)
    }

    /// Fetch every stored embedding. Returns tuples of (assetId, embedding vector).
    func fetchAll() async -> [(assetId: String, embedding: [Float])] {
        await withCheckedContinuation { cont in
            queue.async { [weak self] in
                guard let self, let db = self.db else {
                    cont.resume(returning: [])
                    return
                }
                var results = [(assetId: String, embedding: [Float])]()

                let sql = "SELECT asset_id, embedding FROM clip_embeddings WHERE model_version = ?1"
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                    cont.resume(returning: [])
                    return
                }
                defer { sqlite3_finalize(stmt) }

                sqlite3_bind_text(stmt, 1, CLIPConfig.clipModelVersion, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

                while sqlite3_step(stmt) == SQLITE_ROW {
                    guard let idCStr = sqlite3_column_text(stmt, 0) else { continue }
                    let assetId = String(cString: idCStr)

                    let blobPtr = sqlite3_column_blob(stmt, 1)
                    let blobLen = Int(sqlite3_column_bytes(stmt, 1))
                    let floatCount = blobLen / MemoryLayout<Float>.size

                    var vec = [Float](repeating: 0, count: floatCount)
                    if let blobPtr {
                        memcpy(&vec, blobPtr, blobLen)
                    }

                    results.append((assetId: assetId, embedding: vec))
                }
                cont.resume(returning: results)
            }
        }
    }

    /// Returns the subset of `candidates` that do NOT have an embedding
    /// stored for the current model version.
    func missingAssetIds(from candidates: [String]) -> Set<String> {
        queue.sync {
            guard !candidates.isEmpty else { return [] }

            // Build a temp table for efficient set-difference
            exec("CREATE TEMP TABLE IF NOT EXISTS _candidates (id TEXT PRIMARY KEY)")
            exec("DELETE FROM _candidates")

            let insertSQL = "INSERT OR IGNORE INTO _candidates (id) VALUES (?1)"
            let stmt = prepare(insertSQL)
            defer { sqlite3_finalize(stmt) }

            for id in candidates {
                sqlite3_reset(stmt)
                sqlite3_bind_text(stmt, 1, id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                sqlite3_step(stmt)
            }

            let diffSQL = """
                SELECT c.id FROM _candidates c
                LEFT JOIN clip_embeddings e
                    ON e.asset_id = c.id AND e.model_version = ?1
                WHERE e.asset_id IS NULL
            """
            var diffStmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, diffSQL, -1, &diffStmt, nil) == SQLITE_OK else {
                return Set(candidates)
            }
            defer { sqlite3_finalize(diffStmt) }

            sqlite3_bind_text(diffStmt, 1, CLIPConfig.clipModelVersion, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

            var missing = Set<String>()
            while sqlite3_step(diffStmt) == SQLITE_ROW {
                if let cStr = sqlite3_column_text(diffStmt, 0) {
                    missing.insert(String(cString: cStr))
                }
            }

            exec("DROP TABLE IF EXISTS _candidates")
            return missing
        }
    }

    /// Total number of embeddings stored for the current model version.
    func count() -> Int {
        queue.sync {
            let sql = "SELECT COUNT(*) FROM clip_embeddings WHERE model_version = ?1"
            let stmt = prepare(sql)
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, CLIPConfig.clipModelVersion, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int64(stmt, 0)) : 0
        }
    }

    /// Most recent `indexed_at` timestamp for the current model version, or nil if empty.
    func lastIndexedTimestamp() -> Date? {
        queue.sync {
            let sql = "SELECT MAX(indexed_at) FROM clip_embeddings WHERE model_version = ?1"
            let stmt = prepare(sql)
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, CLIPConfig.clipModelVersion, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            let epoch = sqlite3_column_int64(stmt, 0)
            guard epoch > 0 else { return nil }
            return Date(timeIntervalSince1970: TimeInterval(epoch))
        }
    }

    /// Remove all rows whose model_version != `currentVersion`.
    func purgeStaleVersions(keeping currentVersion: String) {
        queue.sync {
            let sql = "DELETE FROM clip_embeddings WHERE model_version != ?1"
            let stmt = prepare(sql)
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, currentVersion, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            if sqlite3_step(stmt) != SQLITE_DONE {
                print("[CLIPEmbeddingStore] purge failed: \(errorMessage)")
            }
            let removed = sqlite3_changes(db)
            if removed > 0 {
                print("[CLIPEmbeddingStore] Purged \(removed) stale embeddings")
            }
        }
    }

    // MARK: - Helpers

    private func exec(_ sql: String) {
        guard db != nil else { return }
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            print("[CLIPEmbeddingStore] exec failed: \(errorMessage) — \(sql)")
        }
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        guard db != nil else { return nil }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            print("[CLIPEmbeddingStore] prepare failed: \(errorMessage) — \(sql)")
        }
        return stmt
    }

    private var errorMessage: String {
        db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "no db"
    }
}
