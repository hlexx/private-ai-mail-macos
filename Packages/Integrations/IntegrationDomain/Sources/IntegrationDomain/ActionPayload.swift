import Foundation

public struct ActionPayload: Codable, Equatable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let body: JSONValue

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        body: JSONValue = .object([:])
    ) {
        self.schemaVersion = schemaVersion
        self.body = body
    }

    public init<Body: Encodable>(
        schemaVersion: Int = Self.currentSchemaVersion,
        encoding body: Body
    ) throws {
        let data = try JSONEncoder().encode(body)
        self.schemaVersion = schemaVersion
        self.body = try JSONDecoder().decode(JSONValue.self, from: data)
    }
}
