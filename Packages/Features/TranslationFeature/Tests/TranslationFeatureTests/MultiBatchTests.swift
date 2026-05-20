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
        store.mergeNodeTranslations(for: "msg1", fragments: [
            "n0": TranslatedFragment(text: "Hello", source: "ru", target: "en"),
        ])
        #expect(store.nodeTranslations(for: "msg1", target: "en") == ["n0": "Hello"])
    }

    @Test("mergeNodeTranslations appends to existing dict")
    func mergeAppends() {
        let store = TranslationStore()
        store.mergeNodeTranslations(for: "msg1", fragments: [
            "n0": TranslatedFragment(text: "Hello", source: "ru", target: "en"),
        ])
        store.mergeNodeTranslations(for: "msg1", fragments: [
            "n1": TranslatedFragment(text: "World", source: "ru", target: "en"),
        ])
        #expect(store.nodeTranslations(for: "msg1", target: "en") == ["n0": "Hello", "n1": "World"])
    }

    @Test("mergeNodeTranslations overwrites existing keys")
    func mergeOverwrites() {
        let store = TranslationStore()
        store.mergeNodeTranslations(for: "msg1", fragments: [
            "n0": TranslatedFragment(text: "Original", source: "ru", target: "en"),
        ])
        store.mergeNodeTranslations(for: "msg1", fragments: [
            "n0": TranslatedFragment(text: "Updated", source: "ru", target: "en"),
        ])
        #expect(store.nodeTranslations(for: "msg1", target: "en") == ["n0": "Updated"])
    }

    // MARK: - Node translation complete tracking

    @Test("markNodeTranslationComplete and clearNodeTranslations")
    func nodeTranslationComplete() {
        let store = TranslationStore()
        #expect(store.isNodeTranslationComplete(for: "msg1", target: "en") == false)

        store.markNodeTranslationComplete(for: "msg1", target: "en")
        #expect(store.isNodeTranslationComplete(for: "msg1", target: "en") == true)
        #expect(store.isNodeTranslationComplete(for: "msg1", target: "ru") == false)

        store.clearNodeTranslations(for: "msg1")
        #expect(store.isNodeTranslationComplete(for: "msg1", target: "en") == false)
    }

    @Test("clearCache resets nodeTranslationComplete, inflightBatches, and needsRetranslation")
    func clearCacheResetsNew() {
        let store = TranslationStore()
        store.incrementInflight()
        store.markNodeTranslationComplete(for: "msg1", target: "en")
        store.needsRetranslation = true
        store.clearCache()
        #expect(store.inflightBatches == 0)
        #expect(store.nodeTranslationComplete.isEmpty)
        #expect(store.needsRetranslation == false)
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

        // Store skipped nodes with original text (source == target for skipped)
        var skipResult: [String: TranslatedFragment] = [:]
        for node in nodes where skipped.contains(node.id) {
            skipResult[node.id] = TranslatedFragment(text: node.text, source: "en", target: "en")
        }
        store.mergeNodeTranslations(for: "msg1", fragments: skipResult)

        // Simulate batch translation completing
        #expect(batches.count == 1)
        let translatedFragments: [String: TranslatedFragment] = [
            "n1": TranslatedFragment(text: "Top up & Online deals", source: "th", target: "en"),
            "n3": TranslatedFragment(text: "Discount Coupons", source: "th", target: "en"),
        ]
        store.mergeNodeTranslations(for: "msg1", fragments: translatedFragments)
        store.markNodeTranslationComplete(for: "msg1", target: "en")

        // Verify final state — filtered for target "en"
        let result = store.nodeTranslations(for: "msg1", target: "en")!
        #expect(result["n0"] == "Your order has been delivered") // skipped, kept original
        #expect(result["n1"] == "Top up & Online deals") // translated
        #expect(result["n2"] == "Thank you for shopping") // skipped, kept original
        #expect(result["n3"] == "Discount Coupons") // translated
        #expect(store.isNodeTranslationComplete(for: "msg1", target: "en"))
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

    // MARK: - Per-target cache filtering

    @Test("nodeTranslations filters by target language")
    func filterByTarget() {
        let store = TranslationStore()
        // Store fragments with different targets
        store.mergeNodeTranslations(for: "msg1", fragments: [
            "n0": TranslatedFragment(text: "Hello", source: "ru", target: "en"),
            "n1": TranslatedFragment(text: "Привет", source: "en", target: "ru"),
        ])

        let enResult = store.nodeTranslations(for: "msg1", target: "en")
        #expect(enResult == ["n0": "Hello"])

        let ruResult = store.nodeTranslations(for: "msg1", target: "ru")
        #expect(ruResult == ["n1": "Привет"])
    }

    @Test("nodeTranslations returns nil when all fragments are for a different target")
    func filterByTargetReturnsNil() {
        let store = TranslationStore()
        store.mergeNodeTranslations(for: "msg1", fragments: [
            "n0": TranslatedFragment(text: "Hello", source: "ru", target: "en"),
        ])
        // Querying for a target that has no fragments should return nil
        let result = store.nodeTranslations(for: "msg1", target: "fr")
        #expect(result == nil)
    }

    @Test("allTranslatedNodes filters all messages by target")
    func allTranslatedNodesFiltered() {
        let store = TranslationStore()
        store.mergeNodeTranslations(for: "msg1", fragments: [
            "n0": TranslatedFragment(text: "Hello", source: "ru", target: "en"),
        ])
        store.mergeNodeTranslations(for: "msg2", fragments: [
            "n0": TranslatedFragment(text: "Bonjour", source: "en", target: "fr"),
        ])

        let enNodes = store.allTranslatedNodes(target: "en")
        #expect(enNodes.count == 1)
        #expect(enNodes["msg1"] == ["n0": "Hello"])
        #expect(enNodes["msg2"] == nil)

        let frNodes = store.allTranslatedNodes(target: "fr")
        #expect(frNodes.count == 1)
        #expect(frNodes["msg2"] == ["n0": "Bonjour"])
    }

    @Test("isNodeTranslationComplete tracks multiple targets independently")
    func completionPerTarget() {
        let store = TranslationStore()
        store.markNodeTranslationComplete(for: "msg1", target: "en")

        #expect(store.isNodeTranslationComplete(for: "msg1", target: "en") == true)
        #expect(store.isNodeTranslationComplete(for: "msg1", target: "ru") == false)

        // Marking complete for a different target preserves the first
        store.markNodeTranslationComplete(for: "msg1", target: "ru")
        #expect(store.isNodeTranslationComplete(for: "msg1", target: "ru") == true)
        #expect(store.isNodeTranslationComplete(for: "msg1", target: "en") == true)

        // Clear removes all targets
        store.clearNodeTranslations(for: "msg1")
        #expect(store.isNodeTranslationComplete(for: "msg1", target: "en") == false)
        #expect(store.isNodeTranslationComplete(for: "msg1", target: "ru") == false)
    }

    @Test("Cache hit: fragments persist across tab toggles, no re-translation needed")
    func cacheHitRate() {
        let store = TranslationStore()

        // Simulate a translation run for a Lazada-shape message
        let thaiFragments: [String: TranslatedFragment] = [
            "n0": TranslatedFragment(text: "Top up & Online deals", source: "th", target: "en"),
            "n1": TranslatedFragment(text: "Discount Coupons", source: "th", target: "en"),
        ]
        let skippedFragments: [String: TranslatedFragment] = [
            "n2": TranslatedFragment(text: "Your order delivered", source: "en", target: "en"),
            "n3": TranslatedFragment(text: "Thank you for shopping", source: "en", target: "en"),
        ]
        store.mergeNodeTranslations(for: "msg1", fragments: thaiFragments)
        store.mergeNodeTranslations(for: "msg1", fragments: skippedFragments)
        store.markNodeTranslationComplete(for: "msg1", target: "en")

        // Simulate 5 tab switches: each time we check isComplete and get cached data
        for _ in 0..<5 {
            // This is what triggerTranslation checks
            let isComplete = store.isNodeTranslationComplete(for: "msg1", target: "en")
            #expect(isComplete == true)

            // This is what the view layer reads
            let nodes = store.nodeTranslations(for: "msg1", target: "en")
            #expect(nodes?.count == 4)
            #expect(nodes?["n0"] == "Top up & Online deals")
            #expect(nodes?["n1"] == "Discount Coupons")
            #expect(nodes?["n2"] == "Your order delivered")
            #expect(nodes?["n3"] == "Thank you for shopping")
        }
    }
}
