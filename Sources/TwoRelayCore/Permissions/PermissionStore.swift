import Foundation
import SQLite3

enum PermissionKind: String, CaseIterable, Identifiable {
    case microphone
    case accessibility

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .microphone:
            return "Microphone"
        case .accessibility:
            return "Accessibility"
        }
    }
}

enum PermissionState: String, Codable {
    case unknown
    case granted
    case denied
    case restricted
    case unrecognized

    var displayName: String {
        switch self {
        case .unknown:
            return "Not Determined"
        case .granted:
            return "Allowed"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .unrecognized:
            return "Unrecognized"
        }
    }
}

struct PermissionSnapshot {
    let kind: PermissionKind
    let state: PermissionState
    let updatedAt: Date
    let promptCount: Int
    let lastPromptAt: Date?
}

protocol PermissionStore {
    func loadSnapshot(for kind: PermissionKind) throws -> PermissionSnapshot?
    func saveState(_ state: PermissionState, for kind: PermissionKind) throws
    func incrementPromptCount(for kind: PermissionKind) throws
}

enum PermissionStoreError: LocalizedError {
    case openFailed(path: String)
    case prepareFailed(message: String)
    case executeFailed(message: String)

    var errorDescription: String? {
        switch self {
        case let .openFailed(path):
            return "Failed to open permissions database at \(path)."
        case let .prepareFailed(message):
            return "Failed to prepare SQL statement: \(message)"
        case let .executeFailed(message):
            return "Failed to execute SQL statement: \(message)"
        }
    }
}

final class SQLitePermissionStore: PermissionStore {
    private let db: OpaquePointer

    init(databaseURL: URL? = nil) throws {
        let fileManager = FileManager.default
        let resolvedURL: URL
        if let databaseURL {
            resolvedURL = databaseURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let directory = appSupport.appendingPathComponent("com.2relay", isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            resolvedURL = directory.appendingPathComponent("permissions.sqlite")
        }

        var rawDB: OpaquePointer?
        if sqlite3_open(resolvedURL.path, &rawDB) != SQLITE_OK || rawDB == nil {
            throw PermissionStoreError.openFailed(path: resolvedURL.path)
        }
        db = rawDB!

        do {
            try migrate()
        } catch {
            sqlite3_close(db)
            throw error
        }
    }

    deinit {
        sqlite3_close(db)
    }

    func loadSnapshot(for kind: PermissionKind) throws -> PermissionSnapshot? {
        let sql = """
        SELECT state, updated_at, prompt_count, last_prompt_at
        FROM permission_state
        WHERE name = ?
        LIMIT 1;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw PermissionStoreError.prepareFailed(message: sqliteErrorMessage())
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, kind.rawValue, -1, SQLITE_TRANSIENT)
        let step = sqlite3_step(statement)
        if step == SQLITE_DONE {
            return nil
        }
        guard step == SQLITE_ROW else {
            throw PermissionStoreError.executeFailed(message: sqliteErrorMessage())
        }

        guard let stateCString = sqlite3_column_text(statement, 0),
              let state = PermissionState(rawValue: String(cString: stateCString)) else {
            return nil
        }

        let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 1))
        let promptCount = Int(sqlite3_column_int(statement, 2))
        let lastPromptAt: Date?
        if sqlite3_column_type(statement, 3) == SQLITE_NULL {
            lastPromptAt = nil
        } else {
            lastPromptAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
        }

        return PermissionSnapshot(
            kind: kind,
            state: state,
            updatedAt: updatedAt,
            promptCount: promptCount,
            lastPromptAt: lastPromptAt
        )
    }

    func saveState(_ state: PermissionState, for kind: PermissionKind) throws {
        let existing = try loadSnapshot(for: kind)
        try upsert(
            kind: kind,
            state: state,
            updatedAt: Date(),
            promptCount: existing?.promptCount ?? 0,
            lastPromptAt: existing?.lastPromptAt
        )
    }

    func incrementPromptCount(for kind: PermissionKind) throws {
        let existing = try loadSnapshot(for: kind)
        try upsert(
            kind: kind,
            state: existing?.state ?? .unknown,
            updatedAt: Date(),
            promptCount: (existing?.promptCount ?? 0) + 1,
            lastPromptAt: Date()
        )
    }

    private func migrate() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS permission_state (
            name TEXT PRIMARY KEY,
            state TEXT NOT NULL,
            updated_at REAL NOT NULL,
            prompt_count INTEGER NOT NULL DEFAULT 0,
            last_prompt_at REAL
        );
        """
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw PermissionStoreError.executeFailed(message: sqliteErrorMessage())
        }
    }

    private func upsert(
        kind: PermissionKind,
        state: PermissionState,
        updatedAt: Date,
        promptCount: Int,
        lastPromptAt: Date?
    ) throws {
        let sql = """
        INSERT INTO permission_state (name, state, updated_at, prompt_count, last_prompt_at)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(name) DO UPDATE SET
            state = excluded.state,
            updated_at = excluded.updated_at,
            prompt_count = excluded.prompt_count,
            last_prompt_at = excluded.last_prompt_at;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw PermissionStoreError.prepareFailed(message: sqliteErrorMessage())
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, kind.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, state.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 3, updatedAt.timeIntervalSince1970)
        sqlite3_bind_int(statement, 4, Int32(promptCount))
        if let lastPromptAt {
            sqlite3_bind_double(statement, 5, lastPromptAt.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(statement, 5)
        }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw PermissionStoreError.executeFailed(message: sqliteErrorMessage())
        }
    }

    private func sqliteErrorMessage() -> String {
        guard let cString = sqlite3_errmsg(db) else {
            return "Unknown SQLite error"
        }
        return String(cString: cString)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
