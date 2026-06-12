import ActionsFeature
import AppFoundation
import BriefFeature
import ComposeFeature
import DesignSystem
import GRDB
import InboxFeature
import MailDomain
import Persistence
import SwiftUI
import ThreadFeature

typealias BriefPanelPlacement = RBBriefPanelPlacement

// MainScene is the app composition root for the macOS shell. Keep feature
// semantics in their packages; app-local files may own only wiring, persisted
// shell preferences, and command routing between existing stores/views.
struct MainScene: View {

    let composition: CompositionRoot
    let keyboardDispatcher: KeyboardDispatcher

    @State var sidebarSelection: SidebarSelection = .default
    @State var threadListWrapPulse: Bool = false
    @State var folderJumpPulse: SidebarSelection?
    // keyboardDispatcher.showKeyboardHelp lives on keyboardDispatcher so the app-level Help menu can toggle it too
    @FocusState var searchFocused: Bool
    @State var accounts: [AccountRecord] = []
    // NOTE — these three were declared `private` initially; relaxed to
    // internal so MainSceneMutations (separate file in same target)
    // can read them when dispatching mutations.
    @State var threadScrollProxy: ScrollViewProxy?
    @State var threadScrolledToBottom: Bool = false
    @State var lastScrolledMessageIndex: Int = 0
    @AppStorage("pam.preferredLanguage") var preferredLanguage: String = ""
    @AppStorage("pam.autoTranslate") var autoTranslate: Bool = false
    @AppStorage(TranslationLanguagePreferences.storageKey) var translationLanguagesRaw: String = TranslationLanguagePreferences.defaultRawValue
    @AppStorage(MainSceneLayoutStorageKey.sidebarWidth) var sidebarWidth: Double = Double(RBLayout.sidebarWidth)
    @AppStorage(MainSceneLayoutStorageKey.threadListWidth) var threadlistWidth: Double =
        Double(RBLayout.threadListWidth)
    @AppStorage(MainSceneLayoutStorageKey.briefWidth) var briefWidth: Double = Double(RBLayout.briefRailWidth)
    @AppStorage(MainSceneLayoutStorageKey.sidebarCollapsed) var sidebarCollapsed: Bool = false
    @AppStorage(MainSceneLayoutStorageKey.briefCollapsed) var briefCollapsed: Bool = false
    @AppStorage(MainSceneLayoutStorageKey.briefPlacement) var briefPlacementRaw: String =
        BriefPanelPlacement.side.rawValue
    @AppStorage(MainSceneLayoutStorageKey.bottomPanelCollapsed) var bottomPanelCollapsed: Bool = false
    @AppStorage(MainSceneLayoutStorageKey.bottomPanelTab) var bottomPanelTabRaw: String = "draft"
    @State var draftGenerationRequest: InlineDraftGenerationRequest?
    @Environment(\.openSettings) var openSettings

    var body: some View {
        GeometryReader { geometry in
            let splitConfiguration = layoutState.splitConfiguration(
                availableWidth: geometry.size.width
            )

            syncBriefTabReveal(
                currentPlacement: splitConfiguration.effectiveBriefPlacement,
                availableWidth: geometry.size.width
            ) {
                VStack(spacing: 0) {
                    toolbar(briefPanelIsBottom: splitConfiguration.showsBottomBrief)
                    mainSplitContent(splitConfiguration: splitConfiguration)
                }
            }
        }
        // Extend our 56pt RBToolbar all the way to the top of the window,
        // under the (transparent) titlebar / traffic-light zone. Without
        // this, SwiftUI keeps a ~28pt top safe-area inset reserved for the
        // titlebar and the visible chrome ends up ~84pt tall.
        .ignoresSafeArea(.container, edges: .top)
        .background(Color.rbBgDeep)
        .overlay {
            if composition.showActionSheet {
                ActionSheetView(
                    threadSubject: threadStore.subject.isEmpty ? String(localized: "action.fallbackSubject", defaultValue: "Selected thread") : threadStore.subject,
                    executionAvailability: actionSheetExecutionAvailability,
                    onAction: { action in
                        composition.showActionSheet = false
                        handleActionSheet(action)
                    }
                )
            }
        }
        .overlay {
            if keyboardDispatcher.showKeyboardHelp {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { keyboardDispatcher.showKeyboardHelp = false }
                KeyboardHelpOverlay(isPresented: Bindable(keyboardDispatcher).showKeyboardHelp)
            }
        }
        .onChange(of: sidebarSelection) { _, newSelection in
            inboxStore.setSelection(newSelection)
            if case .account(let accountId) = newSelection {
                composition.activeAccountID = accountId
            }
        }
        .onChange(of: preferredLanguage) { _, _ in
            translationPreferencesDidChange()
        }
        .onChange(of: translationLanguagesRaw) { _, _ in
            translationPreferencesDidChange()
        }
        .onChange(of: inboxStore.selectedThreadID) { _, newValue in
            threadScrolledToBottom = false
            lastScrolledMessageIndex = 0
            selectedThreadTranslationDidChange()
            if let request = draftGenerationRequest, request.threadID != newValue {
                draftGenerationRequest = nil
            }
            if let threadId = newValue,
               let thread = threadRow(threadID: threadId) {
                let accountEmail = accounts.first(where: { $0.id == thread.accountId })?.email ?? ""
                threadStore.accountEmail = accountEmail
                threadStore.observe(threadId: threadId, accountId: thread.accountId)
                if aiReady {
                    briefStore.loadBrief(forThreadID: threadId, accountId: thread.accountId)
                } else {
                    briefStore.loadBrief(forThreadID: nil)
                }
            } else {
                threadStore.stopObserving()
                briefStore.loadBrief(forThreadID: nil)
            }
        }
        .onChange(of: bottomPanelCollapsed) { _, collapsed in
            if collapsed {
                draftGenerationRequest = nil
            }
        }
        .onChange(of: bottomPanelTabRaw) { _, tab in
            if tab != "draft" {
                draftGenerationRequest = nil
            }
        }
        .onChange(of: aiReady) { _, ready in
            guard let threadId = inboxStore.selectedThreadID,
                  let thread = inboxStore.threads.first(where: { $0.id == threadId })
            else {
                briefStore.loadBrief(forThreadID: nil)
                return
            }
            if ready {
                briefStore.loadBrief(forThreadID: threadId, accountId: thread.accountId)
            } else {
                briefStore.loadBrief(forThreadID: nil)
            }
        }
        .task {
            await observeAccounts()
        }
        .mailKeyboardShortcuts(dispatcher: keyboardDispatcher)
        .onAppear { wireDispatcher() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            updateTextInputFocusState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSTextView.didBeginEditingNotification)) { _ in
            keyboardDispatcher.isTextInputFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSTextView.didEndEditingNotification)) { _ in
            updateTextInputFocusState()
        }
        .overlay(alignment: .bottom) {
            if let toast = composition.toastMessage {
                toastBar(toast)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 16)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: composition.toastMessage)
    }
}

// MARK: - Main Split Content

extension MainScene {
    // Debt owner: mainscene-boundary-decomposition plan. Remove after app-local
    // layout/action/translation extraction brings this function under threshold.
    // swiftlint:disable function_body_length
    @ViewBuilder
    func mainSplitContent(splitConfiguration: MainSceneSplitConfiguration) -> some View {
        MainSplitController(
            sidebarCollapsed: $sidebarCollapsed,
            briefCollapsed: $briefCollapsed,
            forceBriefCollapsed: splitConfiguration.forceSideBriefCollapsed,
            sidebarWidth: $sidebarWidth,
            threadlistWidth: $threadlistWidth,
            briefWidth: $briefWidth,
            sidebar: {
                RBSidebar(
                    folders: sidebarFolders,
                    accounts: accounts.map { AccountRow(account: $0) },
                    selection: $sidebarSelection,
                    jumpPulse: folderJumpPulse
                )
            },
            threadlist: {
                InboxView(
                    store: inboxStore,
                    actionStore: composition.trustActionStore,
                    onDraftReply: { threadId, accountId in draftReply(threadID: threadId, accountId: accountId) },
                    onArchive: { threadId, accountId in
                        archiveThread(threadId, accountId: accountId)
                    },
                    onTrash: { threadId, accountId in
                        trashThread(threadId, accountId: accountId)
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.rbAccent.opacity(threadListWrapPulse ? 0.6 : 0), lineWidth: 2)
                )
                .animation(.easeOut(duration: 0.18), value: threadListWrapPulse)
            },
            reading: {
                ThreadView(
                    store: threadStore,
                    actionStore: composition.trustActionStore,
                    onArchive: { archiveSelectedThread() },
                    onStar: { starSelectedThread() },
                    onMarkRead: { markReadSelectedThread() },
                    onTrash: { trashSelectedThread() },
                    onDraftReply: { draftReply() },
                    showTranslated: translationStore.showTranslated,
                    translatedTexts: translationStore.translatedTexts,
                    translatedNodes: translatedThreadNodes,
                    onTextNodesExtracted: { messageId, nodes in
                        handleExtractedTranslationNodes(messageId: messageId, nodes: nodes)
                    },
                    onScrollProxy: { proxy in
                        threadScrollProxy = proxy
                    },
                    attachmentSummaryStore: aiReady ? composition.attachmentSummaryStore : nil,
                    showsComposerPanel: aiReady,
                    showsBriefInBottomPanel: splitConfiguration.showsBottomBrief,
                    composer: {
                        if aiReady, let threadID = inboxStore.selectedThreadID {
                            InlineComposer(
                                threadID: threadID,
                                accountId: draftGenerationRequest?.threadID == threadID
                                    ? draftGenerationRequest?.accountId
                                    : threadRow(threadID: threadID)?.accountId,
                                replyLanguage: detectReplyLanguage(),
                                draftRequest: draftGenerationRequest,
                                replyStore: composition.replyStore,
                                sendState: composition.composeViewModel.sendState,
                                onEditInFull: { draftText in
                                    prefillComposeForReply()
                                    composition.composeViewModel.bodyText = draftText
                                    composition.showCompose = true
                                },
                                onSend: { bodyText in
                                    prefillComposeForReply()
                                    composition.composeViewModel.bodyText = bodyText
                                    composition.composeViewModel.requestSend()
                                },
                                onCancelSend: { composition.composeViewModel.cancelSend() },
                                onRetrySend: { composition.composeViewModel.retrySend() },
                                onConfirmSendNow: { composition.composeViewModel.confirmSendNow() },
                                onReauthorize: { composition.composeViewModel.reauthorizeAndRetry() },
                                onDraftRequestHandled: { requestID in
                                    if draftGenerationRequest?.id == requestID {
                                        draftGenerationRequest = nil
                                    }
                                }
                            )
                        }
                    },
                    briefRail: {
                        if splitConfiguration.showsBottomBrief {
                            briefPanelContent
                        }
                    },
                    translationHeader: {
                        translationHeader()
                    }
                )
            },
            brief: {
                if !splitConfiguration.showsBottomBrief {
                    briefPanelContent
                } else {
                    Color.rbBgCanvas
                }
            }
        )
    }
    // swiftlint:enable function_body_length
}

// MARK: - Helpers

extension MainScene {
    func extractEmail(from addr: String?) -> String {
        guard let addr else { return "" }
        if let open = addr.firstIndex(of: "<"),
           let close = addr.firstIndex(of: ">"),
           close > open {
            return String(addr[addr.index(after: open)..<close])
        }
        return addr.trimmingCharacters(in: .whitespaces)
    }

    func observeAccounts() async {
        let observation = ValueObservation.tracking { db in
            try AccountRecord.fetchAll(db)
        }
        do {
            for try await records in observation.values(in: composition.db.dbQueue) {
                self.accounts = records
                if composition.activeAccountID == nil, let first = records.first {
                    composition.activeAccountID = first.id
                }
                composition.reconcileLabelsIfNeeded(accountIds: records.map(\.id))
            }
        } catch {
            // Observation ended
        }
    }

    func threadRow(threadID: String, accountId: String? = nil) -> ThreadRow? {
        let candidates = inboxStore.filteredThreads + inboxStore.threads
        if let accountId {
            return candidates.first { $0.id == threadID && $0.accountId == accountId }
        }
        return candidates.first { $0.id == threadID }
    }
}
