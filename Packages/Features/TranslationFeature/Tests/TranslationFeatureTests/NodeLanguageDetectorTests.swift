import Testing
@testable import TranslationFeature

@Suite("NodeLanguageDetector")
struct NodeLanguageDetectorTests {

    @Test("detects English text")
    func detectEnglish() {
        let result = NodeLanguageDetector.detect("Thanks for shopping with us!")
        #expect(result != nil)
        #expect(result?.bcp47 == "en")
        #expect((result?.confidence ?? 0) >= 0.6)
    }

    @Test("detects Thai text")
    func detectThai() {
        let result = NodeLanguageDetector.detect("เติมเงิน & ดีลออนไลน์")
        #expect(result != nil)
        #expect(result?.bcp47 == "th")
        #expect((result?.confidence ?? 0) >= 0.6)
    }

    @Test("detects Russian text")
    func detectRussian() {
        let result = NodeLanguageDetector.detect("Здравствуйте, ваш заказ")
        #expect(result != nil)
        #expect(result?.bcp47 == "ru")
        #expect((result?.confidence ?? 0) >= 0.6)
    }

    @Test("returns nil for short text 'Hi'")
    func shortTextHi() {
        let result = NodeLanguageDetector.detect("Hi")
        #expect(result == nil)
    }

    @Test("returns nil for short text 'OK'")
    func shortTextOK() {
        let result = NodeLanguageDetector.detect("OK")
        #expect(result == nil)
    }

    @Test("returns nil for empty string")
    func emptyString() {
        let result = NodeLanguageDetector.detect("")
        #expect(result == nil)
    }

    @Test("returns nil for whitespace-only string")
    func whitespaceOnly() {
        let result = NodeLanguageDetector.detect("   \n\t  ")
        #expect(result == nil)
    }

    @Test("returns nil or low confidence for numeric-only fragment")
    func shortAmbiguous() {
        let result = NodeLanguageDetector.detect("1234")
        // Numeric-only content should not be confidently detected as any language.
        // NLLanguageRecognizer may return nil or a low-confidence guess.
        let isAcceptable = result == nil || result!.confidence < 0.9
        #expect(isAcceptable, "Expected nil or confidence < 0.9, got \(String(describing: result))")
    }
}
