import Foundation
import SQLite3
import Testing
import PreviewContracts
import PreviewFormats
@testable import PreviewCore

/// The SQLite schema grid: columns, defaults, keys, foreign keys and indexes read through the four
/// introspection pragmas on the private read-only snapshot.
@Suite("SQLite schema grid", .serialized)
struct SQLiteSchemaGridTests {
    private let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations)

    private func makeDatabase(_ statements: String, in folder: URL, name: String = "schema.sqlite") throws -> URL {
        let url = folder.appendingPathComponent(name)
        var connection: OpaquePointer?
        #expect(sqlite3_open(url.path, &connection) == SQLITE_OK)
        defer { sqlite3_close(connection) }
        #expect(sqlite3_exec(connection, statements, nil, nil, nil) == SQLITE_OK)
        return url
    }

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private static let schema = """
    CREATE TABLE teams(id INTEGER PRIMARY KEY, name TEXT NOT NULL);
    CREATE TABLE users(
      id INTEGER PRIMARY KEY,
      email TEXT NOT NULL DEFAULT 'nobody@example.com',
      api_token TEXT DEFAULT 'synthetic-secret-value',
      team_id INTEGER REFERENCES teams(id) ON DELETE CASCADE,
      note TEXT DEFAULT 'password=synthetic-secret-value',
      score REAL DEFAULT 0.5);
    CREATE INDEX users_email ON users(email);
    CREATE UNIQUE INDEX users_team_email ON users(team_id, email);
    CREATE TABLE memberships(user_id INTEGER, team_id INTEGER, PRIMARY KEY(user_id, team_id),
      FOREIGN KEY(user_id) REFERENCES users(id));
    CREATE TABLE user_tokens(value TEXT DEFAULT 'synthetic-secret-value');
    CREATE VIEW active_users AS SELECT * FROM users;
    INSERT INTO teams VALUES (1, 'core');
    INSERT INTO users(email, api_token, team_id) VALUES ('a@example.com', 'synthetic-secret-value', 1);
    """

    private func grid(_ presentation: TextPresentation) throws -> [String: [String: String]] {
        let object = try #require(try JSONSerialization.jsonObject(with: Data(presentation.text.utf8)) as? [String: Any])
        let table = try #require(object["table"] as? [String: Any])
        let columns = try #require(table["columns"] as? [String])
        let rows = try #require(table["rows"] as? [[Any]])
        #expect(columns == ["table", "column", "declaredType", "notNull", "defaultValue", "primaryKey", "foreignKey", "indexes"])
        var result: [String: [String: String]] = [:]
        for row in rows {
            let cells = row.map { cell -> String in
                if let text = cell as? String { return text }
                if let parts = cell as? [String] { return parts.joined() }
                return "\(cell)"
            }
            result[cells[0] + "." + cells[1]] = Dictionary(uniqueKeysWithValues: zip(columns, cells))
        }
        return result
    }

    @Test func tablesGetOneRowPerColumnWithTypeNullabilityDefaultKeyReferenceAndIndexes() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeDatabase(Self.schema, in: directory)
        guard case .ready(let presentation) = await pipeline.preview(url: url) else { Issue.record("Expected a preview"); return }
        let rows = try grid(presentation)
        #expect(rows["teams.id"]?["primaryKey"] == "1" && rows["teams.id"]?["notNull"] == "false")
        #expect(rows["teams.name"]?["notNull"] == "true" && rows["teams.name"]?["declaredType"] == "TEXT")
        #expect(rows["users.email"]?["defaultValue"] == "'nobody@example.com'")
        #expect(rows["users.score"]?["defaultValue"] == "0.5" && rows["users.score"]?["declaredType"] == "REAL")
        #expect(rows["users.team_id"]?["foreignKey"] == "teams(id)")
        #expect(Set((rows["users.email"]?["indexes"] ?? "").components(separatedBy: ", ")) == ["users_email", "users_team_email"])
        #expect(rows["users.team_id"]?["indexes"] == "users_team_email")
        #expect(rows["memberships.user_id"]?["primaryKey"] == "1" && rows["memberships.team_id"]?["primaryKey"] == "2")
        #expect(rows["memberships.user_id"]?["foreignKey"] == "users(id)")
        // Views and indexes are not tables; the earlier summary is still present.
        #expect(rows.keys.allSatisfy { !$0.hasPrefix("active_users.") })
        #expect(presentation.text.contains("\"databaseFormat\"") && presentation.text.contains("\"pages\""))
    }

    @Test func defaultsOfSecretLookingColumnsAndTablesAreConcealed() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeDatabase(Self.schema, in: directory)
        guard case .ready(let presentation) = await pipeline.preview(url: url) else { Issue.record("Expected a preview"); return }
        #expect(!presentation.text.contains(DataFixtures.secret))
        let rows = try grid(presentation)
        #expect(rows["users.api_token"]?["defaultValue"] == "••••")
        #expect(rows["users.note"]?["defaultValue"] == "••••")
        #expect(rows["user_tokens.value"]?["defaultValue"] == "••••")
        // A harmless default stays readable.
        #expect(rows["users.email"]?["defaultValue"] == "'nobody@example.com'")
        #expect(presentation.redactionCount >= 3)
    }

    @Test func theSnapshotAddsNoSidecarsAndTheDatabaseIsUnchanged() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeDatabase(Self.schema, in: directory)
        let before = try Data(contentsOf: url)
        let listing = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        let modified = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        for _ in 0..<2 { _ = await pipeline.preview(url: url) }
        #expect(try Data(contentsOf: url) == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() == listing)
        #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date == modified)
    }

    @Test func virtualTablesAreNeverInstantiatedAndLiveJournalsStayDeclined() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        // FTS5 may be absent from the system library; the test then covers only the ordinary table.
        let url = try makeDatabase("CREATE TABLE plain(a TEXT); CREATE VIRTUAL TABLE docs USING fts5(body);", in: directory)
        if case .ready(let presentation) = await pipeline.preview(url: url) {
            #expect(!presentation.text.contains("\"table\": \"docs\"") || presentation.text.contains("\"virtual\": true"))
            let rows = try grid(presentation)
            #expect(rows["plain.a"] != nil && rows.keys.allSatisfy { !$0.hasPrefix("docs.") })
        } else {
            Issue.record("Expected a preview of a database with a virtual table")
        }
        let live = try makeDatabase("PRAGMA journal_mode=WAL; CREATE TABLE t(a);", in: directory, name: "wal.sqlite")
        #expect(await pipeline.preview(url: live) == .unavailable(.unavailableContent))
    }

    @Test func manyTablesAreCutAtTheGridLimit() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        var statements = ""
        for index in 0..<120 { statements += "CREATE TABLE t\(index)(a INTEGER, b TEXT, c REAL, d BLOB);\n" }
        let url = try makeDatabase(statements, in: directory)
        guard case .ready(let presentation) = await pipeline.preview(url: url) else { Issue.record("Expected a preview"); return }
        let object = try #require(try JSONSerialization.jsonObject(with: Data(presentation.text.utf8)) as? [String: Any])
        let table = try #require(object["table"] as? [String: Any])
        #expect((table["rows"] as? [Any])?.count == 300 && table["truncated"] as? Bool == true)
        #expect(presentation.text.utf16.count < 262_144)
    }
}
