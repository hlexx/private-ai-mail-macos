import AIKit
@testable import ComposeFeature
import Foundation
import Persistence
import Testing

// MARK: - Recording Mock

private final class RecordingAIService: AIService, @unchecked Sendable {
    private(set) var calls: [(tone: AIReplyTone, replyLanguage: String?)] = []

    func threadBrief(_ input: AIThreadInput) async throws -> AIThreadBrief {
        AIThreadBrief(summary: "test", confidence: 0.9)
    }

    func draftReply(
        _ input: AIThreadInput,
        tone: AIReplyTone,
        locale: Locale,
        replyLanguage: String?
    ) async throws -> AIThreadReply {
        calls.append((tone: tone, replyLanguage: replyLanguage))
        return AIThreadReply(
            body: "Reply in \(replyLanguage ?? "default")",
            evidenceMessageIDs: [],
            detectedReplyLanguage: replyLanguage ?? "en",
            confidence: 0.9
        )
    }
}

// MARK: - Tests

@Suite("Reply Language Routing")
struct ReplyLanguageRoutingTests {

    private func makeDB(messages: [(from: String, body: String)]) async throws -> AppDatabase {
        try await DatabaseActor.shared.run {
            let db = try AppDatabase.openInMemory()
            try db.write { database in
                try AccountRecord(id: "acc1", email: "me@test.com", createdAt: 1000).insert(database)
                try database.execute(sql: """
                    INSERT INTO thread (id, account_id, subject, snippet, last_message_at, message_count)
                    VALUES ('t1', 'acc1', 'Test', 'snippet', 1000, \(messages.count))
                """)
                for (idx, msg) in messages.enumerated() {
                    try database.execute(sql: """
                        INSERT INTO message (id, thread_id, account_id, from_addr, snippet, sent_at, flags, body_text)
                        VALUES ('msg\(idx)', 't1', 'acc1', :from, :body, \(1000 + idx), 0, :body)
                    """, arguments: ["from": msg.from, "body": msg.body])
                }
            }
            return db
        }
    }

    @MainActor
    @Test func russianThreadPassesRuLanguage() async throws {
        let ai = RecordingAIService()
        let db = try await makeDB(messages: [
            (from: "other@test.com", body: "Привет, отправьте пожалуйста документ по проекту"),
        ])
        let store = ReplyStore(aiService: ai, db: db)

        store.generate(threadID: "t1", tone: .warm, replyLanguage: "ru")
        try await Task.sleep(for: .milliseconds(300))

        #expect(ai.calls.count == 1)
        #expect(ai.calls[0].replyLanguage == "ru")
    }

    @MainActor
    @Test func englishThreadPassesEnLanguage() async throws {
        let ai = RecordingAIService()
        let db = try await makeDB(messages: [
            (from: "other@test.com", body: "Hi, please send me the project document"),
        ])
        let store = ReplyStore(aiService: ai, db: db)

        store.generate(threadID: "t1", tone: .concise, replyLanguage: "en")
        try await Task.sleep(for: .milliseconds(300))

        #expect(ai.calls.count == 1)
        #expect(ai.calls[0].replyLanguage == "en")
    }

    @MainActor
    @Test func mixedThreadLastMessageInDePassesDe() async throws {
        let ai = RecordingAIService()
        let db = try await makeDB(messages: [
            (from: "other@test.com", body: "Hello, let's discuss the project"),
            (from: "me@test.com", body: "Sure, sounds good"),
            (from: "other@test.com", body: "Vielen Dank fuer die schnelle Antwort, bitte senden Sie mir die Unterlagen"),
        ])
        let store = ReplyStore(aiService: ai, db: db)

        store.generate(threadID: "t1", tone: .direct, replyLanguage: "de")
        try await Task.sleep(for: .milliseconds(300))

        #expect(ai.calls.count == 1)
        #expect(ai.calls[0].replyLanguage == "de")
    }

    @MainActor
    @Test func nilLanguagePassesNil() async throws {
        let ai = RecordingAIService()
        let db = try await makeDB(messages: [
            (from: "other@test.com", body: "Hey"),
        ])
        let store = ReplyStore(aiService: ai, db: db)

        store.generate(threadID: "t1", tone: .warm, replyLanguage: nil)
        try await Task.sleep(for: .milliseconds(300))

        #expect(ai.calls.count == 1)
        #expect(ai.calls[0].replyLanguage == nil)
    }

    @MainActor
    @Test func toneChangePreservesLanguage() async throws {
        let ai = RecordingAIService()
        let db = try await makeDB(messages: [
            (from: "other@test.com", body: "Привет, как дела?"),
        ])
        let store = ReplyStore(aiService: ai, db: db)

        store.generate(threadID: "t1", tone: .warm, replyLanguage: "ru")
        try await Task.sleep(for: .milliseconds(300))

        store.generate(threadID: "t1", tone: .direct, replyLanguage: "ru")
        try await Task.sleep(for: .milliseconds(300))

        #expect(ai.calls.count == 2)
        #expect(ai.calls[0].replyLanguage == "ru")
        #expect(ai.calls[1].replyLanguage == "ru")
    }

    @MainActor
    @Test func regeneratePreservesLanguage() async throws {
        let ai = RecordingAIService()
        let db = try await makeDB(messages: [
            (from: "other@test.com", body: "Привет, отправьте документ"),
        ])
        let store = ReplyStore(aiService: ai, db: db)

        store.generate(threadID: "t1", tone: .warm, replyLanguage: "ru")
        try await Task.sleep(for: .milliseconds(300))

        store.regenerate(threadID: "t1", tone: .warm, replyLanguage: "ru")
        try await Task.sleep(for: .milliseconds(300))

        #expect(ai.calls.count == 2)
        #expect(ai.calls[0].replyLanguage == "ru")
        #expect(ai.calls[1].replyLanguage == "ru")
    }

    @MainActor
    @Test func languageOverrideChangesPassedLanguage() async throws {
        let ai = RecordingAIService()
        let db = try await makeDB(messages: [
            (from: "other@test.com", body: "Привет, отправьте документ"),
        ])
        let store = ReplyStore(aiService: ai, db: db)

        store.generate(threadID: "t1", tone: .warm, replyLanguage: "ru")
        try await Task.sleep(for: .milliseconds(300))

        // User overrides to English
        store.generate(threadID: "t1", tone: .warm, replyLanguage: "en")
        try await Task.sleep(for: .milliseconds(300))

        #expect(ai.calls.count == 2)
        #expect(ai.calls[0].replyLanguage == "ru")
        #expect(ai.calls[1].replyLanguage == "en")
    }
}
