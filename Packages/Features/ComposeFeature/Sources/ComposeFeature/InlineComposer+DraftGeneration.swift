import AIKit
import Foundation

extension InlineComposer {
    func prepareDraftDisplay() {
        let hasExistingDraft = replyStore.prepareForDisplay(
            threadID: threadID,
            accountId: accountId,
            tone: tone,
            replyLanguage: effectiveLanguage
        )
        if hasExistingDraft {
            syncDisplayedDraftFromStore()
        } else {
            draftGenerationRequested = false
            draftText = ""
            detectedLanguage = nil
            isEditorFocused = false
        }
    }

    func syncDisplayedDraftFromStore() {
        guard let reply = replyStore.reply, ReplyStore.isDisplayableDraft(reply.body) else { return }
        draftText = reply.body
        detectedLanguage = reply.detectedReplyLanguage
        draftGenerationRequested = true
        isEditorFocused = true
    }

    func requestDraftGeneration(force: Bool) {
        draftGenerationRequested = true
        if force {
            replyStore.regenerate(
                threadID: threadID,
                accountId: accountId,
                tone: tone,
                replyLanguage: effectiveLanguage,
                locale: effectiveLocale
            )
        } else {
            replyStore.generateIfNeeded(
                threadID: threadID,
                accountId: accountId,
                tone: tone,
                replyLanguage: effectiveLanguage,
                locale: effectiveLocale
            )
        }
    }

    func handleExternalDraftRequestIfNeeded() {
        guard draftRequestID > 0, draftRequestID != handledDraftRequestID else { return }
        handledDraftRequestID = draftRequestID
        requestDraftGeneration(force: false)
    }

    func handleToneChange(_ newTone: AIReplyTone) {
        if draftGenerationRequested {
            replyStore.regenerate(
                threadID: threadID,
                accountId: accountId,
                tone: newTone,
                replyLanguage: effectiveLanguage,
                locale: effectiveLocale
            )
        } else {
            prepareDraftDisplay()
        }
    }

    func handleLanguageSelection(_ languageCode: String) {
        languageOverride = languageCode
        showLanguagePicker = false
        if draftGenerationRequested {
            replyStore.regenerate(
                threadID: threadID,
                accountId: accountId,
                tone: tone,
                replyLanguage: languageCode,
                locale: effectiveLocale
            )
        } else {
            let hasExistingDraft = replyStore.prepareForDisplay(
                threadID: threadID,
                accountId: accountId,
                tone: tone,
                replyLanguage: languageCode
            )
            if hasExistingDraft {
                syncDisplayedDraftFromStore()
            } else {
                draftText = ""
                detectedLanguage = nil
            }
        }
    }
}
