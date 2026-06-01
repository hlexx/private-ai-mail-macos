import Foundation

public protocol ActionExecuting: Sendable {
    func execute(command: ActionCommand) async -> ActionResult
}

public struct LocalMVPActionExecutor: ActionExecuting {
    public init() {}

    public func execute(command: ActionCommand) async -> ActionResult {
        ActionResult(
            status: .failed,
            failureKind: .providerRejected,
            metadata: Self.metadata(
                command: command,
                result: "unsupportedExecutor"
            )
        )
    }

    private static func metadata(command: ActionCommand, result: String) -> JSONValue {
        .object([
            "actionKind": .string(command.kind.rawValue),
            "executor": .string("local"),
            "result": .string(result),
            "targetKind": .string(command.target.kind.rawValue),
        ])
    }
}

public extension ActionKind {
    var isTrustMVPLocalAction: Bool {
        switch self {
        case .draftReply, .archiveThread, .starThread, .markRead, .trashThread:
            true
        case .sendReply, .snoozeThread, .sendToSlack, .createNotionPage, .logToCRM:
            false
        }
    }
}
