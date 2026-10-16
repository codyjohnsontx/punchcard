import Foundation
import GRDB

/// Applies the numbered SQL files in Resources/Migrations, using `PRAGMA user_version`
/// as the only record of progress so the Tauri app can share the same files and algorithm.
/// GRDB's DatabaseMigrator is deliberately not used: it keeps its own bookkeeping table.
enum Migrator {
    struct Migration {
        let version: Int
        let sql: String
    }

    static func migrate(_ queue: DatabaseQueue) throws {
        let migrations = try load()
        let latest = migrations.last?.version ?? 0
        try queue.writeWithoutTransaction { db in
            for migration in migrations {
                try db.inTransaction(.immediate) {
                    let current = try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
                    guard current <= latest else {
                        throw DatabaseOpenError.newerSchema(found: current, supported: latest)
                    }
                    if current < migration.version {
                        try db.execute(sql: migration.sql)
                        try db.execute(sql: "PRAGMA user_version = \(migration.version)")
                    }
                    return .commit
                }
            }
        }
    }

    /// Reads `NNNN_name.sql` files, sorted, and checks they are numbered 1, 2, 3...
    static func load() throws -> [Migration] {
        guard let directory = resourceBundle.url(forResource: "Migrations", withExtension: nil) else {
            throw MigrationError.missingMigrations
        }
        let files = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "sql" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !files.isEmpty else { throw MigrationError.missingMigrations }
        return try files.enumerated().map { index, url in
            let name = url.lastPathComponent
            guard let version = Int(name.prefix(4)), version == index + 1,
                  name.dropFirst(4).first == "_"
            else { throw MigrationError.badFileName(name) }
            return Migration(version: version, sql: try String(contentsOf: url, encoding: .utf8))
        }
    }

    /// The bundle holding Resources/Migrations. Inside Punchcard.app, build-app.sh copies it
    /// to Contents/Resources, where SwiftPM's `Bundle.module` does not look (it checks the
    /// .app root), so look there first and fall back to `Bundle.module` for `swift run`/tests.
    private static let resourceBundle: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Punchcard_PunchcardCore.bundle"),
           FileManager.default.fileExists(atPath: url.path),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return Bundle.module
    }()
}

enum MigrationError: Error {
    case missingMigrations
    case badFileName(String)
}
