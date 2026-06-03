import Testing
@testable import TranslationFeature

@Suite("TranslationGroupingService")
struct TranslationGroupingServiceTests {

    // Lazada-shape: 4 Thai links + many EN nodes, preferred=en
    // Thai nodes should form 1 batch, EN nodes should all be skipped.
    @Test func lazadaShapedInput() {
        let thaiNodes: [(id: String, text: String)] = [
            ("n0", "เติมเงินและดีลออนไลน์สำหรับลูกค้าทุกคน"),
            ("n1", "คูปองลดจัดเต็มสำหรับคุณวันนี้เท่านั้น"),
            ("n2", "สินค้าชั้นนำจากต่างประเทศพร้อมส่งถึงบ้าน"),
            ("n3", "สินค้าแนะนำสำหรับคุณวันนี้พร้อมส่วนลดพิเศษ"),
        ]
        let enNodes: [(id: String, text: String)] = (4..<20).map { i in
            ("n\(i)", "Your order has been delivered successfully to the address on file")
        }
        let all = thaiNodes + enNodes

        let result = TranslationGroupingService.group(nodes: all, preferredLanguage: "en")

        #expect(result.batches.count == 1)
        #expect(result.batches.first?.sourceLanguage == "th")
        #expect(result.batches.first?.nodes.count == 4)
        // All EN nodes should be skipped (already preferred language)
        for i in 4..<20 {
            #expect(result.skipped.contains("n\(i)"))
        }
    }

    // Mixed EN/RU with preferred=en → 1 RU batch, EN nodes skipped
    @Test func mixedEnRuPreferredEnglish() {
        let nodes: [(id: String, text: String)] = [
            ("n0", "Thank you for your purchase today"),
            ("n1", "Please check your email for confirmation"),
            ("n2", "Здравствуйте, ваш заказ был успешно оформлен"),
            ("n3", "Спасибо за покупку в нашем магазине"),
        ]

        let result = TranslationGroupingService.group(nodes: nodes, preferredLanguage: "en")

        #expect(result.batches.count == 1)
        #expect(result.batches.first?.sourceLanguage == "ru")
        #expect(result.batches.first?.nodes.count == 2)
        #expect(result.skipped.contains("n0"))
        #expect(result.skipped.contains("n1"))
    }

    // All-English with preferred=en → 0 batches, all skipped
    @Test func allEnglishPreferredEnglish() {
        let nodes: [(id: String, text: String)] = [
            ("n0", "Welcome to our platform"),
            ("n1", "Your account has been created successfully"),
            ("n2", "Please verify your email address"),
        ]

        let result = TranslationGroupingService.group(nodes: nodes, preferredLanguage: "en")

        #expect(result.batches.isEmpty)
        #expect(result.skipped.count == 3)
    }

    // All-Thai with preferred=en → 1 batch (th)
    @Test func allThaiPreferredEnglish() {
        let nodes: [(id: String, text: String)] = [
            ("n0", "เติมเงินและดีลออนไลน์สำหรับลูกค้าทุกคน"),
            ("n1", "คูปองลดจัดเต็มสำหรับคุณวันนี้เท่านั้น"),
            ("n2", "สินค้าชั้นนำจากต่างประเทศพร้อมส่งถึงบ้าน"),
        ]

        let result = TranslationGroupingService.group(nodes: nodes, preferredLanguage: "en")

        #expect(result.batches.count == 1)
        #expect(result.batches.first?.sourceLanguage == "th")
        #expect(result.batches.first?.nodes.count == 3)
        #expect(result.skipped.isEmpty)
    }

    @Test func disallowedPolishSourceIsSkipped() {
        let nodes: [(id: String, text: String)] = [
            ("n0", "Dziękujemy za zakupy w naszym sklepie internetowym"),
            ("n1", "Здравствуйте, ваш заказ был успешно оформлен"),
        ]

        let result = TranslationGroupingService.group(
            nodes: nodes,
            preferredLanguage: "en",
            allowedSourceLanguages: ["en", "ru", "th"]
        )

        #expect(result.batches.count == 1)
        #expect(result.batches.first?.sourceLanguage == "ru")
        #expect(result.skipped.contains("n0"))
    }

    // Empty input → 0 batches, empty skipped
    @Test func emptyInput() {
        let result = TranslationGroupingService.group(nodes: [], preferredLanguage: "en")

        #expect(result.batches.isEmpty)
        #expect(result.skipped.isEmpty)
    }
}
