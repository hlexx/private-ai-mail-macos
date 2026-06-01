import CryptoKit
import Foundation

public struct ActionIdempotencyKey: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func make(
        accountId: String,
        kind: ActionKind,
        target: ActionTarget,
        schemaVersion: Int = ActionPayload.currentSchemaVersion,
        userActionId: String? = nil
    ) -> ActionIdempotencyKey {
        let components = [
            "action",
            "v\(schemaVersion)",
            accountId,
            kind.rawValue,
        ] + target.stableComponents + [userActionId ?? ""]
        return ActionIdempotencyKey(rawValue: "action_v\(schemaVersion)_\(sha256Hex(components))")
    }

    private static func sha256Hex(_ components: [String]) -> String {
        let canonical = components
            .map { $0.replacingOccurrences(of: "\u{1f}", with: "") }
            .joined(separator: "\u{1f}")
        return SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
