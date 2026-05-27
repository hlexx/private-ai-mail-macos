import GRDB

extension AttachmentSummaryOrchestrator {
    static func tableColumns(_ table: String, db: Database) throws -> Set<String> {
        let rows = try Row.fetchAll(db, sql: "PRAGMA table_info(\(table.sqlIdentifier))")
        return Set(rows.compactMap { $0["name"] as String? })
    }

    static func append(
        _ values: inout [(String, DatabaseValueConvertible?)],
        _ column: String,
        _ value: DatabaseValueConvertible?,
        ifPresentIn columns: Set<String>
    ) {
        guard columns.contains(column) else { return }
        values.append((column, value))
    }

    static func insertOrReplace(
        into table: String,
        values: [(String, DatabaseValueConvertible?)],
        db: Database
    ) throws {
        let columns = values.map { $0.0.sqlIdentifier }.joined(separator: ", ")
        let placeholders = Array(repeating: "?", count: values.count).joined(separator: ", ")
        try db.execute(
            sql: "INSERT OR REPLACE INTO \(table.sqlIdentifier) (\(columns)) VALUES (\(placeholders))",
            arguments: StatementArguments(values.map { $0.1 })
        )
    }
}

extension String {
    var sqlIdentifier: String {
        "\"\(replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
