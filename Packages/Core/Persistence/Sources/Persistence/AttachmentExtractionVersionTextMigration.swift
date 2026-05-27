import GRDB

enum M014_AttachmentExtractionVersionText {
    static func migrate(_ db: Database) throws {
        try m014MigrateAttachmentExtractionVersionText(db)
    }
}

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
