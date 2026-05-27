import GRDB

struct M014ColumnInfo {
    var name: String
    var type: String
    var isNotNull: Bool
    var defaultSQL: String?
}

struct M014ColumnSchema {
    var name: String
    var definition: String
}

let m014ExtractionColumns: [M014ColumnSchema] = [
    m014Column("account_id", "TEXT NOT NULL"),
    m014Column("message_id", "TEXT NOT NULL"),
    m014Column("attachment_id", "TEXT NOT NULL"),
    m014Column("extraction_version", "TEXT NOT NULL"),
    m014Column("status", "TEXT NOT NULL"),
    m014Column("content_hash", "TEXT"),
    m014Column("mime", "TEXT"),
    m014Column("filename", "TEXT"),
    m014Column("byte_count", "INTEGER"),
    m014Column("created_at", "INTEGER NOT NULL"),
    m014Column("updated_at", "INTEGER NOT NULL"),
    m014Column("completed_at", "INTEGER"),
    m014Column("error_code", "TEXT"),
    m014Column("error_message", "TEXT"),
]

let m014ChunkColumns: [M014ColumnSchema] = [
    m014Column("account_id", "TEXT NOT NULL"),
    m014Column("message_id", "TEXT NOT NULL"),
    m014Column("attachment_id", "TEXT NOT NULL"),
    m014Column("extraction_version", "TEXT NOT NULL"),
    m014Column("chunk_index", "INTEGER NOT NULL"),
    m014Column("content_text", "TEXT NOT NULL"),
    m014Column("source_reference", "TEXT"),
    m014Column("page_number", "INTEGER"),
    m014Column("source_start", "INTEGER"),
    m014Column("source_end", "INTEGER"),
    m014Column("token_count", "INTEGER"),
    m014Column("created_at", "INTEGER NOT NULL"),
]

let m014ArtifactColumns: [M014ColumnSchema] = [
    m014Column("account_id", "TEXT NOT NULL"),
    m014Column("message_id", "TEXT NOT NULL"),
    m014Column("attachment_id", "TEXT NOT NULL"),
    m014Column("extraction_version", "TEXT NOT NULL"),
    m014Column("artifact_kind", "TEXT NOT NULL"),
    m014Column("artifact_version", "INTEGER NOT NULL"),
    m014Column("model_id", "TEXT"),
    m014Column("content_hash", "TEXT"),
    m014Column("payload_json", "TEXT NOT NULL"),
    m014Column("created_at", "INTEGER NOT NULL"),
    m014Column("updated_at", "INTEGER NOT NULL"),
]

let m014ExtractionCompatibilityColumns: Set<String> = [
    "text",
    "unsupported_reason",
    "generated_at",
]

let m014ChunkCompatibilityColumns: Set<String> = [
    "text",
    "source_offset",
]

let m014ArtifactCompatibilityColumns: Set<String> = [
    "content_json",
    "task_id",
    "prompt_version",
    "schema_version",
    "input_fingerprint",
    "generated_at",
]

func m014CreateTable(
    _ db: Database,
    table: String,
    columns: [M014ColumnSchema],
    constraints: [String]
) throws {
    let definitions = (columns.map(\.definition) + constraints).joined(separator: ",\n")
    try db.execute(sql: """
        CREATE TABLE \(table.m014SQLIdentifier) (
        \(definitions)
        )
        """)
}

func m014ColumnsWithCompatibilityExtras(
    _ canonicalColumns: [M014ColumnSchema],
    previousColumns: [M014ColumnInfo],
    allowedExtras: Set<String>
) -> [M014ColumnSchema] {
    let canonicalNames = Set(canonicalColumns.map(\.name))
    let extraColumns = previousColumns
        .filter { !canonicalNames.contains($0.name) && allowedExtras.contains($0.name) }
        .map { M014ColumnSchema(name: $0.name, definition: m014ColumnDefinition($0)) }
    return canonicalColumns + extraColumns
}

func m014TableInfo(_ db: Database, table: String) throws -> [M014ColumnInfo] {
    try Row.fetchAll(db, sql: "PRAGMA table_info(\(table.m014SQLIdentifier))").compactMap { row in
        guard let name = row["name"] as String? else { return nil }
        return M014ColumnInfo(
            name: name,
            type: row["type"] as String? ?? "",
            isNotNull: (row["notnull"] as Int? ?? 0) != 0,
            defaultSQL: row["dflt_value"] as String?
        )
    }
}

func m014CopyToTempTable(_ db: Database, table: String, tempTable: String) throws {
    try m014DropTempTable(db, tempTable: tempTable)
    try db.execute(sql: """
        CREATE TEMP TABLE \(tempTable.m014SQLIdentifier) AS
        SELECT * FROM \(table.m014SQLIdentifier)
        """)
}

func m014DropTempTable(_ db: Database, tempTable: String) throws {
    try db.execute(sql: "DROP TABLE IF EXISTS \(tempTable.m014SQLIdentifier)")
}

func m014CopyRows(
    _ db: Database,
    from tempTable: String,
    to table: String,
    targetColumns: [M014ColumnSchema],
    sourceColumns: Set<String>,
    expressions: [String: String]
) throws {
    let copiedColumns = targetColumns
        .filter { sourceColumns.contains($0.name) || expressions[$0.name] != nil }
    guard !copiedColumns.isEmpty else { return }

    let insertColumns = copiedColumns.map { $0.name.m014SQLIdentifier }.joined(separator: ", ")
    let selectExpressions = copiedColumns.map { column -> String in
        expressions[column.name] ?? column.name.m014SQLIdentifier
    }.joined(separator: ", ")
    try db.execute(sql: """
        INSERT INTO \(table.m014SQLIdentifier) (\(insertColumns))
        SELECT \(selectExpressions) FROM \(tempTable.m014SQLIdentifier)
        """)
}

func m014CoalescingExpression(
    primary: String,
    fallback: String,
    sourceColumns: Set<String>
) -> String? {
    if sourceColumns.contains(primary), sourceColumns.contains(fallback) {
        return "COALESCE(\(primary.m014SQLIdentifier), \(fallback.m014SQLIdentifier))"
    }
    if sourceColumns.contains(fallback) {
        return fallback.m014SQLIdentifier
    }
    return nil
}

private func m014Column(_ name: String, _ definition: String) -> M014ColumnSchema {
    M014ColumnSchema(name: name, definition: "\(name.m014SQLIdentifier) \(definition)")
}

private func m014ColumnDefinition(_ column: M014ColumnInfo) -> String {
    var definition = "\(column.name.m014SQLIdentifier) \(column.type.isEmpty ? "TEXT" : column.type)"
    if column.isNotNull {
        definition += " NOT NULL"
    }
    if let defaultSQL = column.defaultSQL {
        definition += " DEFAULT \(defaultSQL)"
    }
    return definition
}

func m014TextExtractionVersionExpression() -> String {
    "CAST(\("extraction_version".m014SQLIdentifier) AS TEXT)"
}

extension String {
    var m014SQLIdentifier: String {
        "\"\(replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

extension Array where Element == String {
    var m014SQLIdentifierList: String {
        map(\.m014SQLIdentifier).joined(separator: ", ")
    }
}
