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
}
