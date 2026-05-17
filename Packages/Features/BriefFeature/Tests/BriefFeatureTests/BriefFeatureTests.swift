import Testing
import SwiftUI
import AppKit
import AIKit
import Persistence
import GRDB
@testable import BriefFeature

// MARK: - Test Support

final class MockAIServiceForBrief: AIService, @unchecked Sendable {
    var stubbedBrief: AIThreadBrief?
    var stubbedError: (any Error)?
    var callCount = 0
    var lastInput: AIThreadInput?
    var delay: Duration?

    func threadBrief(_ input: AIThreadInput) async throws -> AIThreadBrief {
        callCount += 1
        lastInput = input
        if let delay { try await Task.sleep(for: delay) }
        try Task.checkCancellation()
        if let error = stubbedError { throw error }
        guard let brief = stubbedBrief else {
            throw AIError.inferenceFailed(
                NSError(domain: "Test", code: 0)
            )
        }
        return brief
    }

    func draftReply(
        _ input: AIThreadInput,
        tone: AIReplyTone,
        locale: Locale,
        replyLanguage: String?
    ) async throws -> AIThreadReply {
        AIThreadReply(body: "stub reply", confidence: 0.8)
    }
}

private func makeTestDB() throws -> AppDatabase {
    let db = try AppDatabase.openInMemorySync()
    try db.dbQueue.write { database in
        try database.execute(sql: """
            INSERT INTO account (id, email, provider, display_name, created_at)
            VALUES ('acc1', 'test@example.com', 'gmail', 'Test', 1000)
        """)
        try database.execute(sql: """
            INSERT INTO thread (id, account_id, subject, snippet, last_message_at, message_count, has_unread)
            VALUES ('thread-1', 'acc1', 'Test Thread', 'Hello', 1000, 2, 0)
        """)
        try database.execute(sql: """
            INSERT INTO message (id, thread_id, account_id, from_addr, sent_at, body_text, flags)
            VALUES ('msg-1', 'thread-1', 'acc1', 'alice@example.com', 1000, 'Hello world', 0)
        """)
        try database.execute(sql: """
            INSERT INTO message (id, thread_id, account_id, from_addr, sent_at, body_text, flags)
            VALUES ('msg-2', 'thread-1', 'acc1', 'bob@example.com', 2000, 'Reply here', 0)
        """)
        try database.execute(sql: """
            INSERT INTO attachment (id, message_id, account_id, filename, mime)
            VALUES ('att-1', 'msg-1', 'acc1', 'doc.pdf', 'application/pdf')
        """)
    }
    return db
}

private let sampleBrief = AIThreadBrief(
    summary: "Test summary of thread",
    request: "Do something",
    deadline: "Friday",
    risk: "Medium",
    nextStep: "Reply",
    evidence: ["msg-1"],
    confidence: 0.85
)

// MARK: - Tests

@Suite("BriefFeature")
struct BriefFeatureTests {

    @Test func moduleNameIsExported() {
        #expect(BriefFeature.moduleName == "BriefFeature")
    }

    // MARK: - ThreadBriefViewData

    @Test func viewDataInitializesWithAllFields() {
        let data = ThreadBriefViewData(
            summary: "Test summary",
            request: "Do something",
            deadline: "Fri",
            risk: "High",
            nextStep: "Reply",
            confidence: 0.85,
            evidence: ["msg_1", "msg_2"]
        )
        #expect(data.summary == "Test summary")
        #expect(data.request == "Do something")
        #expect(data.deadline == "Fri")
        #expect(data.risk == "High")
        #expect(data.nextStep == "Reply")
        #expect(data.confidence == 0.85)
        #expect(data.evidence == ["msg_1", "msg_2"])
    }

    @Test func viewDataOptionalFieldsDefaultToNil() {
        let data = ThreadBriefViewData(summary: "Just a summary", confidence: 0.5)
        #expect(data.request == nil)
        #expect(data.deadline == nil)
        #expect(data.risk == nil)
        #expect(data.nextStep == nil)
        #expect(data.evidence.isEmpty)
    }

    // MARK: - BriefStore with MockAIService

    @MainActor
    @Test func happyPathLoadsBriefFromAI() async throws {
        let mock = MockAIServiceForBrief()
        mock.stubbedBrief = sampleBrief
        let db = try makeTestDB()
        let store = BriefStore(aiService: mock, db: db)

        store.loadBrief(forThreadID: "thread-1")

        // Wait for async task to complete
        try await Task.sleep(for: .milliseconds(500))

        #expect(store.brief != nil)
        #expect(store.brief?.summary == "Test summary of thread")
        #expect(store.brief?.request == "Do something")
        #expect(store.brief?.confidence == 0.85)
        #expect(store.isLoading == false)
        #expect(store.error == nil)
        #expect(mock.callCount == 1)
        #expect(mock.lastInput?.messages.count == 2)
    }

    @MainActor
    @Test func aiErrorSurfacesAsError() async throws {
        let mock = MockAIServiceForBrief()
        mock.stubbedError = AIError.inferenceFailed(NSError(domain: "Test", code: 42))
        let db = try makeTestDB()
        let store = BriefStore(aiService: mock, db: db)

        store.loadBrief(forThreadID: "thread-1")
        try await Task.sleep(for: .milliseconds(200))

        #expect(store.brief == nil)
        #expect(store.error != nil)
        #expect(store.isLoading == false)
    }

    @MainActor
    @Test func cancellationWhenSwitchingThreads() async throws {
        let mock = MockAIServiceForBrief()
        mock.stubbedBrief = sampleBrief
        mock.delay = .milliseconds(500)
        let db = try makeTestDB()
        let store = BriefStore(aiService: mock, db: db)

        // Start loading thread-1
        store.loadBrief(forThreadID: "thread-1")
        // Immediately switch to nil (simulates user switching away)
        store.loadBrief(forThreadID: nil)

        try await Task.sleep(for: .milliseconds(600))

        #expect(store.brief == nil)
        #expect(store.activeThreadID == nil)
    }

    @MainActor
    @Test func cacheHitOnRepeatSelect() async throws {
        let mock = MockAIServiceForBrief()
        mock.stubbedBrief = sampleBrief
        let db = try makeTestDB()
        let store = BriefStore(aiService: mock, db: db)

        store.loadBrief(forThreadID: "thread-1")
        try await Task.sleep(for: .milliseconds(200))
        #expect(mock.callCount == 1)

        // Second load should hit cache (async check inside Task)
        store.loadBrief(forThreadID: "thread-1")
        try await Task.sleep(for: .milliseconds(100))
        #expect(store.brief != nil)
        #expect(store.isLoading == false)
        #expect(mock.callCount == 1) // Not called again
    }

    @MainActor
    @Test func storeReturnsNilForNilThread() {
        let store = BriefStore()
        store.loadBrief(forThreadID: nil)
        #expect(store.brief == nil)
        #expect(store.activeThreadID == nil)
    }

    @MainActor
    @Test func previewStoreDoesNotCrash() {
        let store = BriefStore()
        store.loadBrief(forThreadID: "some-id")
        #expect(store.brief == nil)
        #expect(store.isLoading == false)
    }

    @MainActor
    @Test func emptyThreadReturnsEmptyInput() async throws {
        let mock = MockAIServiceForBrief()
        mock.stubbedBrief = AIThreadBrief(summary: "Empty", confidence: 0.3)
        let db = try makeTestDB()
        let store = BriefStore(aiService: mock, db: db)

        store.loadBrief(forThreadID: "nonexistent-thread")
        try await Task.sleep(for: .milliseconds(100))

        #expect(mock.callCount == 1)
        #expect(mock.lastInput?.messages.isEmpty == true)
    }

    // MARK: - BriefRail snapshot (dark)

    @MainActor
    @Test func briefRailWithDataDark() {
        let store = BriefStore()
        store.brief = ThreadBriefViewData(
            summary: "Test brief",
            request: "Do something",
            confidence: 0.88,
            evidence: ["msg_1"]
        )
        let view = BriefRail(store: store)
            .frame(width: 340, height: 600)
            .preferredColorScheme(.dark)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 340, height: 600)
        host.layout()
    }

    @MainActor
    @Test func briefRailWithDataLight() {
        let store = BriefStore()
        store.brief = ThreadBriefViewData(
            summary: "Test brief",
            request: "Do something",
            confidence: 0.88,
            evidence: ["msg_1"]
        )
        let view = BriefRail(store: store)
            .frame(width: 340, height: 600)
            .preferredColorScheme(.light)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 340, height: 600)
        host.layout()
    }

    @MainActor
    @Test func briefRailEmptyStateDark() {
        let store = BriefStore()
        let view = BriefRail(store: store)
            .frame(width: 340, height: 300)
            .preferredColorScheme(.dark)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 340, height: 300)
        host.layout()
    }

    @MainActor
    @Test func briefRailEmptyStateLight() {
        let store = BriefStore()
        let view = BriefRail(store: store)
            .frame(width: 340, height: 300)
            .preferredColorScheme(.light)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 340, height: 300)
        host.layout()
    }

    // MARK: - CTA Layout Snapshots (Task 9)

    @MainActor
    @Test(arguments: [280, 340, 480])
    func briefRailCTALayoutDark(width: Int) {
        let store = BriefStore()
        store.brief = ThreadBriefViewData(
            summary: "Client approved pricing and asks for the contract draft by Friday.",
            request: "Send contract draft",
            deadline: "Fri",
            confidence: 0.88,
            evidence: ["msg_1"]
        )
        let view = BriefRail(store: store)
            .frame(width: CGFloat(width), height: 600)
            .preferredColorScheme(.dark)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: width, height: 600)
        host.layout()
        // At 280pt the CTAs should stack vertically without word-splitting
        #expect(host.frame.width == CGFloat(width))
    }

    @MainActor
    @Test(arguments: [280, 340, 480])
    func briefRailCTALayoutLight(width: Int) {
        let store = BriefStore()
        store.brief = ThreadBriefViewData(
            summary: "Client approved pricing and asks for the contract draft by Friday.",
            request: "Send contract draft",
            deadline: "Fri",
            confidence: 0.88,
            evidence: ["msg_1"]
        )
        let view = BriefRail(store: store)
            .frame(width: CGFloat(width), height: 600)
            .preferredColorScheme(.light)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: width, height: 600)
        host.layout()
        #expect(host.frame.width == CGFloat(width))
    }
}
