import Foundation
import Testing
@testable import IntegrationDomain

@Suite("IntegrationDomain")
struct IntegrationDomainTests {
    @Test func moduleNameIsExported() {
        #expect(IntegrationDomain.moduleName == "IntegrationDomain")
    }

    @Test func actionKindsExposeStableRawValues() {
        let expected: [(ActionKind, String)] = [
            (.draftReply, "draftReply"),
            (.sendReply, "sendReply"),
            (.archiveThread, "archiveThread"),
            (.starThread, "starThread"),
            (.markRead, "markRead"),
            (.trashThread, "trashThread"),
            (.snoozeThread, "snoozeThread"),
            (.sendToSlack, "sendToSlack"),
            (.createNotionPage, "createNotionPage"),
            (.logToCRM, "logToCRM"),
        ]

        #expect(ActionKind.allCases.count == expected.count)
        for (kind, rawValue) in expected {
            #expect(kind.rawValue == rawValue)
            #expect(ActionKind(rawValue: rawValue) == kind)
        }
    }

    @Test func defaultApprovalPolicyMatchesActionRisk() {
        for kind in [ActionKind.draftReply, .archiveThread, .starThread, .markRead, .snoozeThread] {
            #expect(ActionPolicy.defaultApprovalRequirement(for: kind) == .notRequired)
        }

        #expect(ActionPolicy.defaultApprovalRequirement(for: .sendReply) == .explicitUserApproval)
        #expect(ActionPolicy.defaultApprovalRequirement(for: .trashThread) == .explicitConfirm)
        #expect(ActionPolicy.defaultApprovalRequirement(for: .sendToSlack) == .previewAndConfirm)
        #expect(ActionPolicy.defaultApprovalRequirement(for: .createNotionPage) == .previewAndConfirm)
        #expect(ActionPolicy.defaultApprovalRequirement(for: .logToCRM) == .previewAndConfirm)
        #expect(
            ActionPolicy.defaultApprovalRequirement(
                for: .archiveThread,
                sensitivity: .sensitive
            ) == .explicitConfirm
        )
    }

    @Test func approvalStatesSatisfyOnlyAllowedRequirements() {
        #expect(ApprovalState.notRequired.satisfies(.notRequired))
        #expect(ApprovalState.approved.satisfies(.previewAndConfirm))
        #expect(!ApprovalState.pending.satisfies(.explicitUserApproval))
        #expect(!ApprovalState.rejected.satisfies(.explicitConfirm))
        #expect(ApprovalState.initial(for: .notRequired) == .notRequired)
        #expect(ApprovalState.initial(for: .previewAndConfirm) == .pending)
    }

    @Test func statusTransitionsAreExplicit() {
        #expect(ActionStatus.initial(for: .notRequired) == .ready)
        #expect(ActionStatus.initial(for: .pending) == .pending)
        #expect(ActionStatus.pending.canTransition(to: .ready))
        #expect(!ActionStatus.pending.canTransition(to: .executing))
        #expect(ActionStatus.ready.canTransition(to: .executing))
        #expect(ActionStatus.executing.canTransition(to: .succeeded))
        #expect(ActionStatus.executing.canTransition(to: .failed))
        #expect(ActionStatus.failed.canTransition(to: .ready))
        #expect(ActionStatus.blocked.canTransition(to: .cancelled))
        #expect(ActionStatus.succeeded.isTerminal)
        #expect(!ActionStatus.succeeded.canTransition(to: .failed))
    }

    @Test func actionTargetCasesRoundTrip() throws {
        let targets: [ActionTarget] = [
            .thread(accountId: "acct-1", threadId: "thread-1"),
            .message(accountId: "acct-1", threadId: "thread-1", messageId: "msg-1"),
            .attachment(accountId: "acct-1", messageId: "msg-1", attachmentId: "att-1"),
            .integrationDestination(accountId: "acct-1", destinationKind: .slack, destinationId: "dest-1"),
        ]

        for target in targets {
            let decoded = try roundTrip(target)
            #expect(decoded == target)
            #expect(decoded.accountId == "acct-1")
        }
    }

    @Test func payloadCommandResultAndAuditRoundTrip() throws {
        struct EncodablePayload: Codable, Equatable {
            let noteId: String
            let urgent: Bool
        }

        let encodedPayload = try ActionPayload(
            encoding: EncodablePayload(noteId: "note-1", urgent: true)
        )
        let payload = ActionPayload(
            body: .object([
                "label": .string("follow-up"),
                "metadata": .object(["source": .string("user-action")]),
            ])
        )
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let command = ActionCommand(
            opId: "op-1",
            accountId: "acct-1",
            target: .thread(accountId: "acct-1", threadId: "thread-1"),
            kind: .archiveThread,
            payload: payload,
            userActionId: "click-1",
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let result = ActionResult(
            status: .succeeded,
            externalResultId: "provider-result-1",
            completedAt: timestamp,
            metadata: .object(["result": .string("archived")])
        )
        let event = ActionAuditEvent(
            opId: command.opId,
            kind: .executionSucceeded,
            actor: .executor,
            occurredAt: timestamp,
            metadata: .object(["status": .string(ActionStatus.succeeded.rawValue)])
        )

        #expect(encodedPayload.body == .object(["noteId": .string("note-1"), "urgent": .bool(true)]))
        #expect(try roundTrip(payload) == payload)
        #expect(try roundTrip(command) == command)
        #expect(try roundTrip(result) == result)
        #expect(try roundTrip(event) == event)
    }

    @Test func idempotencyKeyIsStableAndDoesNotEmbedSensitiveInputs() {
        let target = ActionTarget.message(accountId: "acct-1", threadId: "thread-1", messageId: "msg-1")
        let sensitiveUserActionId = "do-not-embed-body-text"
        let first = ActionIdempotencyKey.make(
            accountId: "acct-1",
            kind: .sendReply,
            target: target,
            userActionId: sensitiveUserActionId
        )
        let second = ActionIdempotencyKey.make(
            accountId: "acct-1",
            kind: .sendReply,
            target: target,
            userActionId: sensitiveUserActionId
        )
        let changed = ActionIdempotencyKey.make(
            accountId: "acct-1",
            kind: .archiveThread,
            target: target,
            userActionId: sensitiveUserActionId
        )

        #expect(first == second)
        #expect(first != changed)
        #expect(!first.rawValue.contains(sensitiveUserActionId))
        #expect(!first.rawValue.contains("thread-1"))
        #expect(!first.rawValue.contains("msg-1"))
        #expect(first.rawValue.hasPrefix("action_v1_"))
        #expect(first.rawValue.count == 74)
    }

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
