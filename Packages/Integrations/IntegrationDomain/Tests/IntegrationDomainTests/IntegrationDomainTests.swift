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

    @Test func localMVPExecutorSupportsOnlyTrustMVPActionKinds() async throws {
        let executor = LocalMVPActionExecutor()
        let target = ActionTarget.thread(accountId: "acct-1", threadId: "thread-1")

        for kind in [ActionKind.draftReply, .archiveThread, .starThread, .markRead, .trashThread] {
            let command = try ActionCommand(
                opId: "op-\(kind.rawValue)",
                accountId: "acct-1",
                target: target,
                kind: kind,
                approvalRequirement: kind == .trashThread ? .explicitConfirm : nil,
                approvalState: kind == .trashThread ? .approved : nil,
                status: .ready
            )

            let result = await executor.execute(command: command)

            #expect(kind.isTrustMVPLocalAction)
            #expect(result.status == .succeeded)
            #expect(result.failureKind == nil)
            #expect(result.externalResultId == "local:\(command.opId)")
        }

        let unsupported = try ActionCommand(
            opId: "op-send",
            accountId: "acct-1",
            target: .message(accountId: "acct-1", threadId: "thread-1", messageId: "message-1"),
            kind: .sendReply,
            approvalState: .approved,
            status: .ready
        )
        let unsupportedResult = await executor.execute(command: unsupported)

        #expect(!ActionKind.sendReply.isTrustMVPLocalAction)
        #expect(unsupportedResult.status == .failed)
        #expect(unsupportedResult.failureKind == .validationFailed)
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
                for: .sendToSlack,
                sensitivity: .sensitive
            ) == .previewAndConfirm
        )
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

    @Test func approvalRequirementsPreserveExternalPreviewRequirement() {
        #expect(!ApprovalRequirement.explicitConfirm.isAtLeastAsStrict(as: .previewAndConfirm))
        #expect(ApprovalRequirement.previewAndConfirm.isAtLeastAsStrict(as: .explicitConfirm))
        #expect(ApprovalRequirement.previewAndConfirm.isAtLeastAsStrict(as: .explicitUserApproval))
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
        let command = try ActionCommand(
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

    @Test func commandRejectsMismatchedAccountAndTargetAccount() throws {
        #expect(throws: ActionCommandValidationError.accountMismatch(
            commandAccountId: "acct-2",
            targetAccountId: "acct-1"
        )) {
            try ActionCommand(
                opId: "op-1",
                accountId: "acct-2",
                target: .thread(accountId: "acct-1", threadId: "thread-1"),
                kind: .archiveThread
            )
        }
    }

    @Test func commandRejectsApprovalRequirementWeakerThanDefaultPolicy() throws {
        #expect(throws: ActionCommandValidationError.approvalRequirementTooWeak(
            kind: .sendReply,
            minimum: .explicitUserApproval,
            provided: .notRequired
        )) {
            try ActionCommand(
                opId: "op-1",
                accountId: "acct-1",
                target: .message(accountId: "acct-1", threadId: "thread-1", messageId: "msg-1"),
                kind: .sendReply,
                approvalRequirement: .notRequired,
                approvalState: .notRequired,
                status: .ready
            )
        }
    }

    @Test func commandRejectsExecutableStatusWithoutSatisfiedApproval() throws {
        #expect(throws: ActionCommandValidationError.statusRequiresSatisfiedApproval(
            status: .ready,
            requirement: .explicitUserApproval,
            state: .pending
        )) {
            try ActionCommand(
                opId: "op-1",
                accountId: "acct-1",
                target: .message(accountId: "acct-1", threadId: "thread-1", messageId: "msg-1"),
                kind: .sendReply,
                approvalRequirement: .explicitUserApproval,
                approvalState: .pending,
                status: .ready
            )
        }
    }

    @Test func commandAllowsStricterApprovalRequirement() throws {
        let command = try ActionCommand(
            opId: "op-1",
            accountId: "acct-1",
            target: .message(accountId: "acct-1", threadId: "thread-1", messageId: "msg-1"),
            kind: .sendReply,
            approvalRequirement: .previewAndConfirm
        )

        #expect(command.approvalRequirement == .previewAndConfirm)
        #expect(command.approvalState == .pending)
        #expect(command.status == .pending)
    }

    @Test func commandRejectsExternalWriteWithoutPreviewRequirement() throws {
        #expect(throws: ActionCommandValidationError.approvalRequirementTooWeak(
            kind: .sendToSlack,
            minimum: .previewAndConfirm,
            provided: .explicitConfirm
        )) {
            try ActionCommand(
                opId: "op-1",
                accountId: "acct-1",
                target: .integrationDestination(
                    accountId: "acct-1",
                    destinationKind: .slack,
                    destinationId: "slack-1"
                ),
                kind: .sendToSlack,
                approvalRequirement: .explicitConfirm,
                approvalState: .approved,
                status: .ready
            )
        }
    }

    @Test func commandUsesSensitivityWhenValidatingApprovalPolicy() throws {
        #expect(throws: ActionCommandValidationError.approvalRequirementTooWeak(
            kind: .archiveThread,
            minimum: .explicitConfirm,
            provided: .notRequired
        )) {
            try ActionCommand(
                opId: "op-1",
                accountId: "acct-1",
                target: .thread(accountId: "acct-1", threadId: "thread-1"),
                kind: .archiveThread,
                sensitivity: .sensitive,
                approvalRequirement: .notRequired,
                approvalState: .notRequired,
                status: .ready
            )
        }

        let command = try ActionCommand(
            opId: "op-2",
            accountId: "acct-1",
            target: .thread(accountId: "acct-1", threadId: "thread-1"),
            kind: .archiveThread,
            sensitivity: .sensitive
        )
        #expect(command.sensitivity == .sensitive)
        #expect(command.approvalRequirement == .explicitConfirm)
        #expect(command.approvalState == .pending)
        #expect(command.status == .pending)
    }

    @Test func commandDecodeRejectsMismatchedAccountAndTargetAccount() throws {
        let payload = """
        {
          "opId": "op-1",
          "accountId": "acct-2",
          "target": {
            "thread": {
              "accountId": "acct-1",
              "threadId": "thread-1"
            }
          },
          "kind": "archiveThread",
          "schemaVersion": 1,
          "payload": {
            "schemaVersion": 1,
            "body": {}
          },
          "idempotencyKey": {
            "rawValue": "action_v1_test"
          },
          "approvalRequirement": "notRequired",
          "approvalState": "notRequired",
          "status": "ready",
          "attemptCount": 0,
          "createdAt": 0,
          "updatedAt": 0
        }
        """.data(using: .utf8)!

        #expect(throws: ActionCommandValidationError.accountMismatch(
            commandAccountId: "acct-2",
            targetAccountId: "acct-1"
        )) {
            try JSONDecoder().decode(ActionCommand.self, from: payload)
        }
    }

    @Test func commandDecodeRejectsWeakenedApprovalPolicy() throws {
        let payload = """
        {
          "opId": "op-1",
          "accountId": "acct-1",
          "target": {
            "message": {
              "accountId": "acct-1",
              "threadId": "thread-1",
              "messageId": "msg-1"
            }
          },
          "kind": "sendReply",
          "schemaVersion": 1,
          "payload": {
            "schemaVersion": 1,
            "body": {}
          },
          "idempotencyKey": {
            "rawValue": "action_v1_test"
          },
          "approvalRequirement": "notRequired",
          "approvalState": "notRequired",
          "status": "ready",
          "attemptCount": 0,
          "createdAt": 0,
          "updatedAt": 0
        }
        """.data(using: .utf8)!

        #expect(throws: ActionCommandValidationError.approvalRequirementTooWeak(
            kind: .sendReply,
            minimum: .explicitUserApproval,
            provided: .notRequired
        )) {
            try JSONDecoder().decode(ActionCommand.self, from: payload)
        }
    }

    @Test func commandDecodeRejectsExternalWriteWithoutPreviewRequirement() throws {
        let payload = """
        {
          "opId": "op-1",
          "accountId": "acct-1",
          "target": {
            "integrationDestination": {
              "accountId": "acct-1",
              "destinationKind": "slack",
              "destinationId": "slack-1"
            }
          },
          "kind": "sendToSlack",
          "schemaVersion": 1,
          "payload": {
            "schemaVersion": 1,
            "body": {}
          },
          "idempotencyKey": {
            "rawValue": "action_v1_test"
          },
          "approvalRequirement": "explicitConfirm",
          "approvalState": "approved",
          "status": "ready",
          "attemptCount": 0,
          "createdAt": 0,
          "updatedAt": 0
        }
        """.data(using: .utf8)!

        #expect(throws: ActionCommandValidationError.approvalRequirementTooWeak(
            kind: .sendToSlack,
            minimum: .previewAndConfirm,
            provided: .explicitConfirm
        )) {
            try JSONDecoder().decode(ActionCommand.self, from: payload)
        }
    }

    @Test func commandDefaultIdempotencyUsesOperationIdentityForRepeatableActions() throws {
        let target = ActionTarget.message(accountId: "acct-1", threadId: "thread-1", messageId: "msg-1")
        let first = try ActionCommand(
            opId: "op-1",
            accountId: "acct-1",
            target: target,
            kind: .sendReply
        )
        let second = try ActionCommand(
            opId: "op-2",
            accountId: "acct-1",
            target: target,
            kind: .sendReply
        )
        let retriedFirst = try ActionCommand(
            opId: "op-1",
            accountId: "acct-1",
            target: target,
            kind: .sendReply
        )

        #expect(first.idempotencyKey != second.idempotencyKey)
        #expect(first.idempotencyKey == retriedFirst.idempotencyKey)
        #expect(!first.idempotencyKey.rawValue.contains("op-1"))
        #expect(!second.idempotencyKey.rawValue.contains("op-2"))
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
