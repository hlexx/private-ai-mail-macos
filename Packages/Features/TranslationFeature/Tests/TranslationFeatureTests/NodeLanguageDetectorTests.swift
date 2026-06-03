import Testing
@testable import TranslationFeature

@Suite("NodeLanguageDetector")
struct NodeLanguageDetectorTests {

    @Test("detects English text")
    func detectEnglish() {
        let result = NodeLanguageDetector.detect("Thanks for shopping with us today!")
        #expect(result != nil)
        #expect(result?.bcp47 == "en")
        #expect((result?.confidence ?? 0) >= 0.8)
    }

    @Test("detects Thai text")
    func detectThai() {
        let result = NodeLanguageDetector.detect("เติมเงินและดีลออนไลน์สำหรับลูกค้าทุกคน")
        #expect(result != nil)
        #expect(result?.bcp47 == "th")
        #expect((result?.confidence ?? 0) >= 0.8)
    }

    @Test("detects Russian text")
    func detectRussian() {
        let result = NodeLanguageDetector.detect("Здравствуйте, ваш заказ был успешно оформлен")
        #expect(result != nil)
        #expect(result?.bcp47 == "ru")
        #expect((result?.confidence ?? 0) >= 0.8)
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
        #expect(result == nil)
    }
}
