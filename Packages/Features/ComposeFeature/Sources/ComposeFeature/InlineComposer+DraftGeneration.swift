import AIKit
import Foundation

public struct InlineDraftGenerationRequest: Equatable, Sendable {
    public let id: UUID
    public let threadID: String
    public let accountId: String?

    public init(id: UUID = UUID(), threadID: String, accountId: String?) {
        self.id = id
        self.threadID = threadID
        self.accountId = accountId
    }

    func matches(threadID: String, accountId: String?) -> Bool {
        self.threadID == threadID && self.accountId == accountId
    }
}

extension InlineComposer {
    func handleDisplayIdentityChange() {
        let contextChanged = preparedContextIdentity != displayContextIdentity
        preparedContextIdentity = displayContextIdentity

        if contextChanged {
            draftGenerationRequested = false
            prepareDraftDisplay()
            handleExternalDraftRequestIfNeeded()
        } else if draftGenerationRequested {
            requestDraftGeneration(force: false)
        } else {
            prepareDraftDisplay()
            handleExternalDraftRequestIfNeeded()
        }
    }

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
        guard let draftRequest,
              draftRequest.id != handledDraftRequestID,
              draftRequest.matches(threadID: threadID, accountId: accountId)
        else { return }
        handledDraftRequestID = draftRequest.id
        requestDraftGeneration(force: false)
        onDraftRequestHandled(draftRequest.id)
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
