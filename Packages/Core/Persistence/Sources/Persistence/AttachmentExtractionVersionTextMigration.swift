import GRDB

enum M014_AttachmentExtractionVersionText {
    static func migrate(_ db: Database) throws {
        try m014MigrateAttachmentExtractionVersionText(db)
    }
}

private struct M014ColumnInfo {
    var name: String
    var type: String
    var isNotNull: Bool
    var defaultSQL: String?
}

private struct M014ColumnSchema {
    var name: String
    var definition: String
}

private let m014ExtractionColumns: [M014ColumnSchema] = [
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

private let m014ChunkColumns: [M014ColumnSchema] = [
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

private let m014ArtifactColumns: [M014ColumnSchema] = [
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

private let m014ExtractionCompatibilityColumns: Set<String> = [
    "text",
    "unsupported_reason",
    "generated_at",
]

private let m014ChunkCompatibilityColumns: Set<String> = [
    "text",
    "source_offset",
]

private let m014ArtifactCompatibilityColumns: Set<String> = [
    "content_json",
    "task_id",
    "prompt_version",
    "schema_version",
    "input_fingerprint",
    "generated_at",
]

private func m014MigrateAttachmentExtractionVersionText(_ db: Database) throws {
    guard try m014NeedsRebuild(db) else { return }

    let extractionInfo = try m014TableInfo(db, table: "attachment_extraction")
    let chunkInfo = try m014TableInfo(db, table: "attachment_chunk")
    let artifactInfo = try m014TableInfo(db, table: "attachment_ai_artifact")

    let extractionTemp = "m014_attachment_extraction_rows"
    let chunkTemp = "m014_attachment_chunk_rows"
    let artifactTemp = "m014_attachment_ai_artifact_rows"

    try m014CopyToTempTable(db, table: "attachment_extraction", tempTable: extractionTemp)
    try m014CopyToTempTable(db, table: "attachment_chunk", tempTable: chunkTemp)
    try m014CopyToTempTable(db, table: "attachment_ai_artifact", tempTable: artifactTemp)

    try db.drop(table: "attachment_ai_artifact")
    try db.drop(table: "attachment_chunk")
    try db.drop(table: "attachment_extraction")

    try m014CreateExtractionTable(db, previousColumns: extractionInfo)
    try m014CreateChunkTable(db, previousColumns: chunkInfo)
    try m014CreateArtifactTable(db, previousColumns: artifactInfo)

    try m014CopyExtractionRows(db, tempTable: extractionTemp, previousColumns: extractionInfo)
    try m014CopyChunkRows(db, tempTable: chunkTemp, previousColumns: chunkInfo)
    try m014CopyArtifactRows(db, tempTable: artifactTemp, previousColumns: artifactInfo)

    try m014DropTempTable(db, tempTable: artifactTemp)
    try m014DropTempTable(db, tempTable: chunkTemp)
    try m014DropTempTable(db, tempTable: extractionTemp)

    try m014CreateIndexes(db)
}

private func m014NeedsRebuild(_ db: Database) throws -> Bool {
    for table in ["attachment_extraction", "attachment_chunk", "attachment_ai_artifact"] {
        let versionColumn = try m014TableInfo(db, table: table)
            .first { $0.name == "extraction_version" }
        if versionColumn?.type.uppercased() != "TEXT" {
            return true
        }
    }
    return false
}

private func m014CreateExtractionTable(_ db: Database, previousColumns: [M014ColumnInfo]) throws {
    try m014CreateTable(
        db,
        table: "attachment_extraction",
        columns: m014ColumnsWithCompatibilityExtras(
            m014ExtractionColumns,
            previousColumns: previousColumns,
            allowedExtras: m014ExtractionCompatibilityColumns
        ),
        constraints: [
            """
            PRIMARY KEY (
                \(["account_id", "message_id", "attachment_id", "extraction_version"].m014SQLIdentifierList)
            )
            """,
            """
            FOREIGN KEY (\(["account_id", "message_id", "attachment_id"].m014SQLIdentifierList))
            REFERENCES \("attachment".m014SQLIdentifier)(\(["account_id", "message_id", "id"].m014SQLIdentifierList))
            ON DELETE CASCADE
            """,
        ]
    )
}

private func m014CreateChunkTable(_ db: Database, previousColumns: [M014ColumnInfo]) throws {
    try m014CreateTable(
        db,
        table: "attachment_chunk",
        columns: m014ColumnsWithCompatibilityExtras(
            m014ChunkColumns,
            previousColumns: previousColumns,
            allowedExtras: m014ChunkCompatibilityColumns
        ),
        constraints: [
            """
            PRIMARY KEY (
                \(["account_id", "message_id", "attachment_id", "extraction_version", "chunk_index"].m014SQLIdentifierList)
            )
            """,
            """
            FOREIGN KEY (\(["account_id", "message_id", "attachment_id", "extraction_version"].m014SQLIdentifierList))
            REFERENCES \("attachment_extraction".m014SQLIdentifier)(
                \(["account_id", "message_id", "attachment_id", "extraction_version"].m014SQLIdentifierList)
            )
            ON DELETE CASCADE
            """,
        ]
    )
}

private func m014CreateArtifactTable(_ db: Database, previousColumns: [M014ColumnInfo]) throws {
    try m014CreateTable(
        db,
        table: "attachment_ai_artifact",
        columns: m014ColumnsWithCompatibilityExtras(
            m014ArtifactColumns,
            previousColumns: previousColumns,
            allowedExtras: m014ArtifactCompatibilityColumns
        ),
        constraints: [
            """
            PRIMARY KEY (
                \([
                    "account_id", "message_id", "attachment_id", "extraction_version",
                    "artifact_kind", "artifact_version",
                ].m014SQLIdentifierList)
            )
            """,
            """
            FOREIGN KEY (\(["account_id", "message_id", "attachment_id", "extraction_version"].m014SQLIdentifierList))
            REFERENCES \("attachment_extraction".m014SQLIdentifier)(
                \(["account_id", "message_id", "attachment_id", "extraction_version"].m014SQLIdentifierList)
            )
            ON DELETE CASCADE
            """,
        ]
    )
}

private func m014CreateIndexes(_ db: Database) throws {
    try db.create(
        index: "idx_attachment_extraction_attachment",
        on: "attachment_extraction",
        columns: ["account_id", "message_id", "attachment_id"],
        ifNotExists: true
    )
    try db.create(
        index: "idx_attachment_chunk_attachment",
        on: "attachment_chunk",
        columns: ["account_id", "message_id", "attachment_id", "extraction_version"],
        ifNotExists: true
    )
    try db.create(
        index: "idx_attachment_ai_artifact_attachment",
        on: "attachment_ai_artifact",
        columns: ["account_id", "message_id", "attachment_id", "extraction_version"],
        ifNotExists: true
    )
    try db.create(
        index: "idx_attachment_ai_artifact_lookup",
        on: "attachment_ai_artifact",
        columns: ["account_id", "message_id", "attachment_id"],
        ifNotExists: true
    )
}

private func m014CopyExtractionRows(
    _ db: Database,
    tempTable: String,
    previousColumns: [M014ColumnInfo]
) throws {
    try m014CopyRows(
        db,
        from: tempTable,
        to: "attachment_extraction",
        targetColumns: m014ColumnsWithCompatibilityExtras(
            m014ExtractionColumns,
            previousColumns: previousColumns,
            allowedExtras: m014ExtractionCompatibilityColumns
        ),
        sourceColumns: Set(previousColumns.map(\.name)),
        expressions: ["extraction_version": m014TextExtractionVersionExpression()]
    )
}

private func m014CopyChunkRows(
    _ db: Database,
    tempTable: String,
    previousColumns: [M014ColumnInfo]
) throws {
    let sourceColumns = Set(previousColumns.map(\.name))
    var expressions = ["extraction_version": m014TextExtractionVersionExpression()]
    if let expression = m014CoalescingExpression(
        primary: "content_text",
        fallback: "text",
        sourceColumns: sourceColumns
    ) {
        expressions["content_text"] = expression
    }
    try m014CopyRows(
        db,
        from: tempTable,
        to: "attachment_chunk",
        targetColumns: m014ColumnsWithCompatibilityExtras(
            m014ChunkColumns,
            previousColumns: previousColumns,
            allowedExtras: m014ChunkCompatibilityColumns
        ),
        sourceColumns: sourceColumns,
        expressions: expressions
    )
}

private func m014CopyArtifactRows(
    _ db: Database,
    tempTable: String,
    previousColumns: [M014ColumnInfo]
) throws {
    let sourceColumns = Set(previousColumns.map(\.name))
    var expressions = ["extraction_version": m014TextExtractionVersionExpression()]
    if let expression = m014CoalescingExpression(
        primary: "payload_json",
        fallback: "content_json",
        sourceColumns: sourceColumns
    ) {
        expressions["payload_json"] = expression
    }
    try m014CopyRows(
        db,
        from: tempTable,
        to: "attachment_ai_artifact",
        targetColumns: m014ColumnsWithCompatibilityExtras(
            m014ArtifactColumns,
            previousColumns: previousColumns,
            allowedExtras: m014ArtifactCompatibilityColumns
        ),
        sourceColumns: sourceColumns,
        expressions: expressions
    )
}

private func m014CreateTable(
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

private func m014ColumnsWithCompatibilityExtras(
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

private func m014TableInfo(_ db: Database, table: String) throws -> [M014ColumnInfo] {
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

private func m014CopyToTempTable(_ db: Database, table: String, tempTable: String) throws {
    try m014DropTempTable(db, tempTable: tempTable)
    try db.execute(sql: """
        CREATE TEMP TABLE \(tempTable.m014SQLIdentifier) AS
        SELECT * FROM \(table.m014SQLIdentifier)
        """)
}

private func m014DropTempTable(_ db: Database, tempTable: String) throws {
    try db.execute(sql: "DROP TABLE IF EXISTS \(tempTable.m014SQLIdentifier)")
}

private func m014CopyRows(
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

private func m014CoalescingExpression(
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

private func m014TextExtractionVersionExpression() -> String {
    "CAST(\("extraction_version".m014SQLIdentifier) AS TEXT)"
}

private extension String {
    var m014SQLIdentifier: String {
        "\"\(replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

private extension Array where Element == String {
    var m014SQLIdentifierList: String {
        map(\.m014SQLIdentifier).joined(separator: ", ")
    }
}
