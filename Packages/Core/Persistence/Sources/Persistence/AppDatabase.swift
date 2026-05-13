import Foundation
import GRDB

public struct AppDatabase: Sendable {
    public let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public static func openSync(at path: String) throws -> AppDatabase {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let dbQueue = try DatabaseQueue(path: path)
        try Migrator.migrate(dbQueue)
        return AppDatabase(dbQueue: dbQueue)
    }

    public static func openInMemorySync() throws -> AppDatabase {
        let dbQueue = try DatabaseQueue(configuration: .init())
        try Migrator.migrate(dbQueue)
        return AppDatabase(dbQueue: dbQueue)
    }

    @DatabaseActor
    public static func open(at path: String) throws -> AppDatabase {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let dbQueue = try DatabaseQueue(path: path)
        try Migrator.migrate(dbQueue)
        return AppDatabase(dbQueue: dbQueue)
    }

    @DatabaseActor
    public static func openInMemory() throws -> AppDatabase {
        let dbQueue = try DatabaseQueue(configuration: .init())
        try Migrator.migrate(dbQueue)
        return AppDatabase(dbQueue: dbQueue)
    }

    @DatabaseActor
    public func write<T: Sendable>(_ updates: @Sendable @escaping (Database) throws -> T) throws -> T {
        try dbQueue.write(updates)
    }

    public func read<T: Sendable>(_ value: @Sendable @escaping (Database) throws -> T) throws -> T {
        try dbQueue.read(value)
    }
}
