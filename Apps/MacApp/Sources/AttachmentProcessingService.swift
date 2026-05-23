import AttachmentRAG
import Foundation
import InboxFeature
import ThreadFeature

struct AttachmentProcessingService: Sendable {
    private let replaceActiveMessageHandler: @Sendable (_ accountId: String, _ messageId: String) async throws -> Int
    private let cancelAllHandler: @Sendable () async -> Void
    private let prioritizeAttachmentHandler: @Sendable (_ attachment: AttachmentInfo) async throws -> Void

    init(
        replaceActiveMessage: @escaping @Sendable (_ accountId: String, _ messageId: String) async throws -> Int,
        cancelAll: @escaping @Sendable () async -> Void,
        prioritizeAttachment: @escaping @Sendable (_ attachment: AttachmentInfo) async throws -> Void
    ) {
        self.replaceActiveMessageHandler = replaceActiveMessage
        self.cancelAllHandler = cancelAll
        self.prioritizeAttachmentHandler = prioritizeAttachment
    }

    init(queue: LocalAttachmentProcessingQueue) {
        self.init(
            replaceActiveMessage: { accountId, messageId in
                try await queue.replaceActiveMessage(accountId: accountId, messageId: messageId)
            },
            cancelAll: {
                await queue.cancelAll()
            },
            prioritizeAttachment: { attachment in
                try await queue.prioritizeAttachment(
                    accountId: attachment.accountId,
                    messageId: attachment.messageId,
                    attachmentId: attachment.id
                )
            }
        )
    }

    @discardableResult
    func replaceActiveMessage(accountId: String, messageId: String) async throws -> Int {
        try await replaceActiveMessageHandler(accountId, messageId)
    }

    func cancelAll() async {
        await cancelAllHandler()
    }

    func prioritizeAttachment(_ attachment: AttachmentInfo) async throws {
        try await prioritizeAttachmentHandler(attachment)
    }
}

enum AttachmentProcessingActionRouter {
    static let startFailureMessage = "Attachment processing could not start."
    static let retryFailureMessage = "Attachment processing could not be retried."

    @MainActor
    static func selectedThreadTask(
        selectedThreadID: String?,
        threads: [ThreadRow],
        service: AttachmentProcessingService,
        onFailure: @escaping @MainActor @Sendable (String) -> Void
    ) -> Task<Void, Never> {
        guard let selectedThreadID,
              let thread = threads.first(where: { $0.id == selectedThreadID }) else {
            return Task { [service] in
                await service.cancelAll()
            }
        }

        let message = startFailureMessage
        return Task { [service] in
            do {
                _ = try await service.replaceActiveMessage(
                    accountId: thread.accountId,
                    messageId: thread.id
                )
            } catch {
                guard !Task.isCancelled else { return }
                await onFailure(message)
            }
        }
    }

    @MainActor
    static func prioritizeAttachmentTask(
        attachment: AttachmentInfo,
        service: AttachmentProcessingService,
        onFailure: @escaping @MainActor @Sendable (String) -> Void
    ) -> Task<Void, Never> {
        let message = retryFailureMessage
        return Task { [service] in
            do {
                try await service.prioritizeAttachment(attachment)
            } catch {
                guard !Task.isCancelled else { return }
                await onFailure(message)
            }
        }
    }
}
