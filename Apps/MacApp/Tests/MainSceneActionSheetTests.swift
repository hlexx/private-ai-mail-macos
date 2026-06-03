import ActionsFeature
import InboxFeature
import Persistence
import Testing
@testable import PrivateAIMail

@Suite("MainScene action sheet")
struct MainSceneActionSheetTests {

    @MainActor
    @Test func gmailSelectedThreadSupportsActionSheetExecution() {
        let availability = MainScene.actionSheetExecutionAvailability(
            selectedThreadID: "thread-gmail",
            threads: [
                thread(id: "thread-gmail", accountId: "gmail-1"),
                thread(id: "thread-outlook", accountId: "outlook-1"),
            ],
            accounts: [
                account(id: "gmail-1", provider: "gmail"),
                account(id: "outlook-1", provider: "outlook"),
            ]
        )

        #expect(availability == .supported)
    }

    @MainActor
    @Test func outlookSelectedThreadDisablesActionSheetExecution() {
        let availability = MainScene.actionSheetExecutionAvailability(
            selectedThreadID: "thread-outlook",
            threads: [
                thread(id: "thread-gmail", accountId: "gmail-1"),
                thread(id: "thread-outlook", accountId: "outlook-1"),
            ],
            accounts: [
                account(id: "gmail-1", provider: "gmail"),
                account(id: "outlook-1", provider: "outlook"),
            ]
        )

        #expect(availability == .unsupportedProvider)
    }

    @MainActor
    @Test func missingSelectedThreadDisablesActionSheetExecution() {
        let availability = MainScene.actionSheetExecutionAvailability(
            selectedThreadID: nil,
            threads: [thread(id: "thread-gmail", accountId: "gmail-1")],
            accounts: [account(id: "gmail-1", provider: "gmail")]
        )

        #expect(availability == .unsupportedProvider)
    }

    private func thread(id: String, accountId: String) -> ThreadRow {
        ThreadRow(record: ThreadRecord(
            id: id,
            accountId: accountId,
            subject: "Subject",
            lastMessageAt: 1,
            messageCount: 1
        ))
    }

    private func account(id: String, provider: String) -> AccountRecord {
        AccountRecord(
            id: id,
            provider: provider,
            email: "\(id)@example.com",
            createdAt: 1
        )
    }
}
