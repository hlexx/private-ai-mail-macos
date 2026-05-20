import DesignSystem
import SwiftUI
@preconcurrency import Translation

// MARK: - Pending batch model for multi-session translation

struct PendingBatch: Identifiable, Sendable {
    var id: String { "\(messageId)_\(sourceLanguage)" }
    let messageId: String
    let sourceLanguage: String
    let nodes: [(id: String, text: String)]
    let generation: Int
}

// MARK: - Hidden view that hosts a single .translationTask per batch

private struct BatchTranslationHost: View {
    let batch: PendingBatch
    let targetLanguage: String
    let onTranslate: @Sendable (PendingBatch, TranslationSession) async -> Void

    @State private var config: TranslationSession.Configuration?

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .translationTask(config) { session in
                await onTranslate(batch, session)
            }
            .task(id: batch.id) {
                config = TranslationSession.Configuration(
                    source: Locale.Language(identifier: batch.sourceLanguage),
                    target: Locale.Language(identifier: targetLanguage)
                )
            }
    }
}

// MARK: - Main toggle view

public struct TranslationToggleView: View {
    @Bindable var store: TranslationStore
    let detectedLanguage: String?
    let preferredLanguage: String
    let autoTranslate: Bool
    let messages: [(id: String, text: String)]
    let htmlMessageIds: Set<String>

    @State private var plainTextConfig: TranslationSession.Configuration?
    @State private var pendingBatches: [PendingBatch] = []

    private var messageFingerprint: String {
        messages.map(\.id).joined(separator: ",")
    }

    public init(
        store: TranslationStore,
        detectedLanguage: String?,
        preferredLanguage: String,
        autoTranslate: Bool = false,
        messages: [(id: String, text: String)],
        htmlMessageIds: Set<String> = []
    ) {
        self.store = store
        self.detectedLanguage = detectedLanguage
        self.preferredLanguage = preferredLanguage
        self.autoTranslate = autoTranslate
        self.messages = messages
        self.htmlMessageIds = htmlMessageIds
    }

    private var effectivePreferredLanguage: String {
        if preferredLanguage.isEmpty {
            return Locale.current.language.languageCode?.identifier ?? "en"
        }
        return preferredLanguage
    }

    private var shouldShow: Bool {
        guard detectedLanguage != nil else { return false }
        // For HTML messages, always show — per-node detection may find
        // foreign-language nodes even when dominant matches preferred.
        if !htmlMessageIds.isEmpty { return true }
        return detectedLanguage != effectivePreferredLanguage
    }

    public var body: some View {
        if shouldShow {
            HStack(spacing: RBSpace.s2) {
                segmentedControl
                if store.isTranslating {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 8)
            .translationTask(plainTextConfig) { session in
                await translatePlainText(session: session)
            }
            .overlay {
                ForEach(pendingBatches) { batch in
                    BatchTranslationHost(
                        batch: batch,
                        targetLanguage: effectivePreferredLanguage
                    ) { batch, session in
                        await translateBatch(batch, session: session)
                    }
                }
            }
            .onAppear {
                if autoTranslate && !store.showTranslated {
                    triggerTranslation()
                }
            }
            .onChange(of: messageFingerprint) { _, _ in
                if autoTranslate && !store.showTranslated {
                    triggerTranslation()
                }
            }
            .onChange(of: store.needsRetranslation) { _, needs in
                if needs && store.showTranslated {
                    store.needsRetranslation = false
                    triggerTranslation()
                }
            }
        }
    }

    private var segmentedControl: some View {
        HStack(spacing: 0) {
            segmentButton(
                title: String(localized: "translation.original", defaultValue: "Original"),
                isSelected: !store.showTranslated
            ) {
                store.showTranslated = false
            }
            segmentButton(
                title: String(localized: "translation.translated", defaultValue: "Translated"),
                isSelected: store.showTranslated
            ) {
                triggerTranslation()
            }
        }
        .padding(2)
        .background(Color.rbBgCanvas)
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: RBRadius.sm)
                .strokeBorder(Color.rbStroke1, lineWidth: 1)
        )
    }

    private func segmentButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.rbGeist(12, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? Color.rbFg1 : Color.rbFg3)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(isSelected ? Color.rbAccentSoft : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: RBRadius.xs))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Translation Trigger

    private func triggerTranslation() {
        store.showTranslated = true

        let target = effectivePreferredLanguage

        // Check if all messages are cached
        let allCached = messages.allSatisfy { msg in
            if htmlMessageIds.contains(msg.id) {
                return store.nodeTranslationComplete.contains(msg.id)
            }
            return store.translatedText(for: msg.id) != nil
        }
        if allCached { return }

        // --- Plain-text messages (non-HTML) ---
        let hasUncachedPlainText = messages.contains { msg in
            !htmlMessageIds.contains(msg.id) && store.translatedText(for: msg.id) == nil
        }
        if hasUncachedPlainText, let detected = detectedLanguage, detected != target {
            let source = Locale.Language(identifier: detected)
            let targetLang = Locale.Language(identifier: target)
            if plainTextConfig == nil {
                plainTextConfig = TranslationSession.Configuration(source: source, target: targetLang)
            } else {
                plainTextConfig?.invalidate()
            }
        }

        // --- HTML messages: per-node grouping ---
        var newBatches: [PendingBatch] = []
        for msgId in htmlMessageIds {
            guard !store.nodeTranslationComplete.contains(msgId) else { continue }
            guard let nodes = store.extractedNodes[msgId], !nodes.isEmpty else { continue }
            let generation = store.currentGeneration(for: msgId)

            let (batches, skipped) = TranslationGroupingService.group(
                nodes: nodes,
                preferredLanguage: target
            )

            // Store original text for skipped nodes immediately
            var skipResult: [String: String] = [:]
            for node in nodes where skipped.contains(node.id) {
                skipResult[node.id] = node.text
            }
            if !skipResult.isEmpty {
                store.mergeNodeTranslations(for: msgId, nodes: skipResult)
            }

            if batches.isEmpty {
                // All nodes skipped — mark complete
                store.markNodeTranslationComplete(for: msgId)
            } else {
                for batch in batches {
                    newBatches.append(PendingBatch(
                        messageId: msgId,
                        sourceLanguage: batch.sourceLanguage,
                        nodes: batch.nodes,
                        generation: generation
                    ))
                }
            }
        }

        if !newBatches.isEmpty {
            pendingBatches = newBatches
        }
    }

    // MARK: - Plain-text translation (single session, thread-level language)

    @MainActor
    private func translatePlainText(session: TranslationSession) async {
        store.incrementInflight()
        defer { store.decrementInflight() }

        do {
            for msg in messages where !htmlMessageIds.contains(msg.id) {
                guard store.translatedText(for: msg.id) == nil else { continue }
                let translated = try await session.translate(msg.text)
                store.setTranslation(for: msg.id, text: translated.targetText)
            }
        } catch {
            store.setError(error)
        }
    }

    // MARK: - Per-batch HTML node translation

    @MainActor
    private func translateBatch(_ batch: PendingBatch, session: TranslationSession) async {
        store.incrementInflight()
        defer {
            store.decrementInflight()
            // Check if all batches for this message are done
            let remaining = pendingBatches.contains { $0.messageId == batch.messageId && $0.sourceLanguage != batch.sourceLanguage }
            // Only mark complete if this was the last active batch for the message
            // (other batches either finished or this is the only one)
            if !remaining || !store.isTranslating {
                checkAndFinalizeBatches(messageId: batch.messageId)
            }
        }

        let msgId = batch.messageId
        let generation = batch.generation

        do {
            let requests = batch.nodes.map {
                TranslationSession.Request(sourceText: $0.text, clientIdentifier: $0.id)
            }
            var result: [String: String] = [:]
            let responses = session.translate(batch: requests)
            for try await response in responses {
                guard store.currentGeneration(for: msgId) == generation else { break }
                if let nodeId = response.clientIdentifier {
                    result[nodeId] = response.targetText
                }
            }
            guard store.currentGeneration(for: msgId) == generation else { return }
            store.mergeNodeTranslations(for: msgId, nodes: result)

            // Remove this batch from pending
            pendingBatches.removeAll { $0.id == batch.id }
        } catch {
            store.setError(error)
            // Remove failed batch from pending
            pendingBatches.removeAll { $0.id == batch.id }
        }
    }

    private func checkAndFinalizeBatches(messageId: String) {
        let hasPending = pendingBatches.contains { $0.messageId == messageId }
        if !hasPending {
            store.markNodeTranslationComplete(for: messageId)
        }
    }
}
