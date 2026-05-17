import Foundation
import GRDB

public struct TrustedSenderRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "trusted_sender"

    public var accountId: String
    public var fromAddr: String

    public init(accountId: String, fromAddr: String) {
        self.accountId = accountId
        self.fromAddr = fromAddr
    }

    enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case fromAddr = "from_addr"
    }
}
