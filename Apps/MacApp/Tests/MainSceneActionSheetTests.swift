import ActionsFeature
import InboxFeature
import Persistence
import Testing
@testable import PrivateAIMail

@Suite("MainScene action sheet")
struct MainSceneActionSheetTests {
    @Test func keyboardActionsRouteToExpectedAppShellHandlers() {
        #expect(MainSceneActionRouter.route(for: .reply) == .draftReply)
        #expect(MainSceneActionRouter.route(for: .replyAll) == .replyAll)
        #expect(MainSceneActionRouter.route(for: .forward) == .forward)
        #expect(MainSceneActionRouter.route(for: .archive) == .archiveSelectedThread)
        #expect(MainSceneActionRouter.route(for: .star) == .starSelectedThread)
        #expect(MainSceneActionRouter.route(for: .trash) == .trashSelectedThread)
        #expect(MainSceneActionRouter.route(for: .markRead) == .markReadSelectedThread)
        #expect(MainSceneActionRouter.route(for: .markUnread) == .markUnreadSelectedThread)
        #expect(MainSceneActionRouter.route(for: .threadNewer) == .threadNewer)
        #expect(MainSceneActionRouter.route(for: .threadOlder) == .threadOlder)
        #expect(MainSceneActionRouter.route(for: .folderInbox) == .folderInbox)
        #expect(MainSceneActionRouter.route(for: .folderStarred) == .folderStarred)
        #expect(MainSceneActionRouter.route(for: .folderSent) == .folderSent)
        #expect(MainSceneActionRouter.route(for: .folderArchive) == .folderArchive)
        #expect(MainSceneActionRouter.route(for: .folderAll) == .folderAll)
        #expect(MainSceneActionRouter.route(for: .pageDownOrNextUnread) == .pageDownOrNextUnread)
        #expect(MainSceneActionRouter.route(for: .focusSearch) == .focusSearch)
        #expect(MainSceneActionRouter.route(for: .showHelp) == .toggleKeyboardHelp)
        #expect(MainSceneActionRouter.route(for: .sendCompose) == .composeSendHandledByComposeWindow)
        #expect(MainSceneActionRouter.route(for: .newCompose) == .newCompose)
        #expect(MainSceneActionRouter.route(for: .refresh) == .refresh)
        #expect(MainSceneActionRouter.route(for: .actionSheet) == .toggleActionSheet)
    }

    @Test func actionSheetRoutesDraftReplyLocallyAndMailboxActionsThroughTrustPath() {
        #expect(MainSceneActionRouter.route(actionSheetAction: nil) == .none)
        #expect(MainSceneActionRouter.route(actionSheetAction: .draftReply) == .draftReply)
        #expect(
            MainSceneActionRouter.route(actionSheetAction: .archiveThread) == .trustAction(.archiveThread)
        )
        #expect(
            MainSceneActionRouter.route(actionSheetAction: .trashThread) == .trustAction(.trashThread)
        )
    }

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
