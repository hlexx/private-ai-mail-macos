import Testing
@testable import TranslationFeature

@Suite("Multi-batch translation pipeline")
@MainActor
struct MultiBatchTests {

    // MARK: - Inflight counter

    @Test("inflightBatches increments and decrements correctly")
    func inflightCounter() {
        let store = TranslationStore()
        #expect(store.isTranslating == false)
        #expect(store.inflightBatches == 0)

        store.incrementInflight()
        #expect(store.isTranslating == true)
        #expect(store.inflightBatches == 1)

        store.incrementInflight()
        #expect(store.inflightBatches == 2)
        #expect(store.isTranslating == true)

        store.decrementInflight()
        #expect(store.inflightBatches == 1)
        #expect(store.isTranslating == true)

        store.decrementInflight()
        #expect(store.inflightBatches == 0)
        #expect(store.isTranslating == false)
    }

    @Test("decrementInflight does not go below zero")
    func decrementFloor() {
        let store = TranslationStore()
        store.decrementInflight()
        #expect(store.inflightBatches == 0)
    }

    // MARK: - Merge node translations

    @Test("mergeNodeTranslations creates dict when none exists")
    func mergeCreatesNew() {
        let store = TranslationStore()
        store.mergeNodeTranslations(for: "msg1", nodes: ["n0": "Hello"])
        #expect(store.nodeTranslations(for: "msg1") == ["n0": "Hello"])
    }

    @Test("mergeNodeTranslations appends to existing dict")
    func mergeAppends() {
        let store = TranslationStore()
        store.mergeNodeTranslations(for: "msg1", nodes: ["n0": "Hello"])
        store.mergeNodeTranslations(for: "msg1", nodes: ["n1": "World"])
        #expect(store.nodeTranslations(for: "msg1") == ["n0": "Hello", "n1": "World"])
    }

    @Test("mergeNodeTranslations overwrites existing keys")
    func mergeOverwrites() {
        let store = TranslationStore()
        store.mergeNodeTranslations(for: "msg1", nodes: ["n0": "Original"])
        store.mergeNodeTranslations(for: "msg1", nodes: ["n0": "Updated"])
        #expect(store.nodeTranslations(for: "msg1") == ["n0": "Updated"])
    }

    // MARK: - Node translation complete tracking

    @Test("markNodeTranslationComplete and clearNodeTranslations")
    func nodeTranslationComplete() {
        let store = TranslationStore()
        #expect(store.nodeTranslationComplete.contains("msg1") == false)

        store.markNodeTranslationComplete(for: "msg1")
        #expect(store.nodeTranslationComplete.contains("msg1") == true)

        store.clearNodeTranslations(for: "msg1")
        #expect(store.nodeTranslationComplete.contains("msg1") == false)
    }

    @Test("clearCache resets nodeTranslationComplete and inflightBatches")
    func clearCacheResetsNew() {
        let store = TranslationStore()
        store.incrementInflight()
        store.markNodeTranslationComplete(for: "msg1")
        store.clearCache()
        #expect(store.inflightBatches == 0)
        #expect(store.nodeTranslationComplete.isEmpty)
    }

    // MARK: - Grouping integration for Lazada-shaped input

    @Test("Lazada shape: Thai nodes grouped, English nodes skipped")
    func lazadaGrouping() {
        let thaiNodes: [(id: String, text: String)] = [
            ("n0", "เติมเงิน & ดีลออนไลน์"),
            ("n1", "คูปองลดจัดเต็ม"),
            ("n2", "สินค้าชั้นนำจากต่างประเทศ"),
            ("n3", "โปรดแจ้งให้เราทราบ"),
        ]
        let englishNodes: [(id: String, text: String)] = [
            ("n4", "Your order has been delivered successfully"),
            ("n5", "Thank you for shopping with Lazada"),
            ("n6", "What's next? Leave a review for the seller"),
        ]
        let allNodes = thaiNodes + englishNodes

        let (batches, skipped) = TranslationGroupingService.group(
            nodes: allNodes,
            preferredLanguage: "en"
        )

        #expect(batches.count == 1)
        #expect(batches[0].sourceLanguage == "th")
        #expect(batches[0].nodes.count == 4)

        // English nodes are skipped (same as preferred)
        for node in englishNodes {
            #expect(skipped.contains(node.id))
        }
    }

    @Test("Simulated multi-batch: skipped + translated merge correctly")
    func multiBatchMerge() {
        let store = TranslationStore()

        let nodes: [(id: String, text: String)] = [
            ("n0", "Your order has been delivered"),
            ("n1", "เติมเงิน & ดีลออนไลน์"),
            ("n2", "Thank you for shopping"),
            ("n3", "คูปองลดจัดเต็ม"),
        ]
        store.setExtractedNodes(for: "msg1", nodes: nodes)

        let (batches, skipped) = TranslationGroupingService.group(
            nodes: nodes,
            preferredLanguage: "en"
        )

        // Store skipped nodes with original text
        var skipResult: [String: String] = [:]
        for node in nodes where skipped.contains(node.id) {
            skipResult[node.id] = node.text
        }
        store.mergeNodeTranslations(for: "msg1", nodes: skipResult)

        // Simulate batch translation completing
        #expect(batches.count == 1)
        let translatedNodes: [String: String] = [
            "n1": "Top up & Online deals",
            "n3": "Discount Coupons",
        ]
        store.mergeNodeTranslations(for: "msg1", nodes: translatedNodes)
        store.markNodeTranslationComplete(for: "msg1")

        // Verify final state
        let result = store.nodeTranslations(for: "msg1")!
        #expect(result["n0"] == "Your order has been delivered") // skipped, kept original
        #expect(result["n1"] == "Top up & Online deals") // translated
        #expect(result["n2"] == "Thank you for shopping") // skipped, kept original
        #expect(result["n3"] == "Discount Coupons") // translated
        #expect(store.nodeTranslationComplete.contains("msg1"))
    }

    @Test("All-English nodes with preferred en: zero batches, all skipped")
    func allEnglishSkipped() {
        let nodes: [(id: String, text: String)] = [
            ("n0", "Welcome to our newsletter"),
            ("n1", "Click here to learn more about our products"),
            ("n2", "Thank you for subscribing to our service"),
        ]

        let (batches, skipped) = TranslationGroupingService.group(
            nodes: nodes,
            preferredLanguage: "en"
        )

        #expect(batches.isEmpty)
        #expect(skipped.count == 3)
    }

    @Test("Three-language email produces separate batches")
    func threeLanguageBatches() {
        let nodes: [(id: String, text: String)] = [
            ("n0", "Hello, welcome to our service and thank you"),
            ("n1", "Здравствуйте, ваш заказ доставлен успешно"),
            ("n2", "Hallo, dies ist eine Testnachricht auf Deutsch"),
        ]

        let (batches, skipped) = TranslationGroupingService.group(
            nodes: nodes,
            preferredLanguage: "en"
        )

        // English node is skipped
        #expect(skipped.contains("n0"))
        // Russian and German should be in separate batches
        #expect(batches.count == 2)
        let languages = Set(batches.map(\.sourceLanguage))
        #expect(languages.contains("ru"))
        #expect(languages.contains("de"))
    }
}
