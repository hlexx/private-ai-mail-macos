import Testing
@testable import TranslationFeature

@Suite("TranslationStore")
@MainActor
struct TranslationStoreTests {

    @Test("detect returns ru for Russian text")
    func detectRussian() {
        let store = TranslationStore()
        let result = store.detect(text: "Привет, это тестовое сообщение на русском языке для проверки определения языка")
        #expect(result == "ru")
    }

    @Test("detect returns en for English text")
    func detectEnglish() {
        let store = TranslationStore()
        let result = store.detect(text: "Hello, this is a test message in English to verify language detection works correctly")
        #expect(result == "en")
    }

    @Test("detect returns nil for empty text")
    func detectEmpty() {
        let store = TranslationStore()
        let result = store.detect(text: "")
        #expect(result == nil)
    }

    @Test("detectWithConfidence returns language and confidence")
    func detectWithConfidence() {
        let store = TranslationStore()
        let result = store.detectWithConfidence(text: "Привет, это тестовое сообщение на русском языке для проверки")
        #expect(result != nil)
        #expect(result?.language == "ru")
        #expect((result?.confidence ?? 0) > 0.5)
    }

    @Test("detect returns de for German text")
    func detectGerman() {
        let store = TranslationStore()
        let result = store.detect(text: "Hallo, dies ist eine Testnachricht auf Deutsch zur Überprüfung der Spracherkennung")
        #expect(result == "de")
    }

    @Test("translation cache stores and retrieves values")
    func translationCache() {
        let store = TranslationStore()
        store.setTranslation(for: "msg1", text: "Hello world")
        #expect(store.translatedText(for: "msg1") == "Hello world")
        #expect(store.translatedText(for: "msg2") == nil)
    }

    @Test("clearCache resets translated texts and showTranslated")
    func clearCache() {
        let store = TranslationStore()
        store.setTranslation(for: "msg1", text: "Hello")
        store.showTranslated = true
        store.clearCache()
        #expect(store.translatedText(for: "msg1") == nil)
        #expect(store.showTranslated == false)
    }

    // MARK: - Per-node Translation Cache

    @Test("node translations stores and retrieves per-message node maps")
    func nodeTranslationCache() {
        let store = TranslationStore()
        let fragments: [String: TranslatedFragment] = [
            "n0": TranslatedFragment(text: "Hello", source: "ru", target: "en"),
            "n1": TranslatedFragment(text: "World", source: "ru", target: "en"),
        ]
        store.setNodeTranslations(for: "msg1", fragments: fragments)
        #expect(store.nodeTranslations(for: "msg1", target: "en") == ["n0": "Hello", "n1": "World"])
        #expect(store.nodeTranslations(for: "msg2", target: "en") == nil)
    }

    @Test("extracted nodes stores pending extraction data")
    func extractedNodesCache() {
        let store = TranslationStore()
        let nodes: [(id: String, text: String)] = [("n0", "Hello"), ("n1", "World")]
        store.setExtractedNodes(for: "msg1", nodes: nodes)
        let stored = store.extractedNodes["msg1"]
        #expect(stored?.count == 2)
        #expect(stored?[0].id == "n0")
        #expect(stored?[0].text == "Hello")
        #expect(stored?[1].id == "n1")
        #expect(stored?[1].text == "World")
    }

    @Test("generation counter increments per message")
    func generationCounter() {
        let store = TranslationStore()
        #expect(store.currentGeneration(for: "msg1") == 0)
        let gen1 = store.nextGeneration(for: "msg1")
        #expect(gen1 == 1)
        #expect(store.currentGeneration(for: "msg1") == 1)
        let gen2 = store.nextGeneration(for: "msg1")
        #expect(gen2 == 2)
        // Different message has independent counter
        #expect(store.currentGeneration(for: "msg2") == 0)
    }

    @Test("clearCache resets node translations, extracted nodes, and generations")
    func clearCacheResetsAll() {
        let store = TranslationStore()
        store.setTranslation(for: "msg1", text: "Hello")
        store.setNodeTranslations(for: "msg1", fragments: [
            "n0": TranslatedFragment(text: "Hi", source: "ru", target: "en"),
        ])
        store.setExtractedNodes(for: "msg1", nodes: [("n0", "Hello")])
        let _ = store.nextGeneration(for: "msg1")
        store.showTranslated = true

        store.clearCache()

        #expect(store.translatedText(for: "msg1") == nil)
        #expect(store.nodeTranslations(for: "msg1", target: "en") == nil)
        #expect(store.extractedNodes["msg1"] == nil)
        #expect(store.currentGeneration(for: "msg1") == 0)
        #expect(store.showTranslated == false)
    }
}
