import AppKit
import SwiftUI
import Testing
@testable import ActionsFeature

@Suite("ActionsFeature")
struct ActionsFeatureTests {

    @Test func moduleNameIsExported() {
        #expect(ActionsFeature.moduleName == "ActionsFeature")
    }

    // MARK: - ActionItem

    @Test func executableActionsMatchTrustMVPSurface() {
        let ids = ActionItem.executable.map(\.id)
        #expect(ids == [.reply, .archive, .star, .markRead, .trash])

        let mappedActions = ids.map(\.trustMVPAction)
        #expect(!mappedActions.contains(nil))
        #expect(mappedActions.compactMap(\.self) == TrustMVPAction.allCases)
    }

    @Test func roadmapActionsAreSeparatedFromExecutableGrid() {
        let ids = ActionItem.roadmap.map(\.id)
        #expect(ids == [.snooze, .log, .task, .unsub, .rule, .share])
        #expect(ids.allSatisfy { $0.trustMVPAction == nil })
    }

    @Test func allActionIDCasesAreCovered() {
        let itemIDs = Set((ActionItem.executable + ActionItem.roadmap).map(\.id))
        let allCases = Set(ActionID.allCases)
        #expect(itemIDs == allCases)
    }

    @Test func onlyImplementedActionsAreExecutable() {
        #expect(ActionExecutionSupport.isEnabled(.reply))
        #expect(ActionExecutionSupport.isEnabled(.archive))
        #expect(ActionExecutionSupport.isEnabled(.star))
        #expect(ActionExecutionSupport.isEnabled(.markRead))
        #expect(ActionExecutionSupport.isEnabled(.trash))
        #expect(!ActionExecutionSupport.isEnabled(.snooze))
        #expect(!ActionExecutionSupport.isEnabled(.log))
        #expect(!ActionExecutionSupport.isEnabled(.task))
        #expect(!ActionExecutionSupport.isEnabled(.unsub))
        #expect(!ActionExecutionSupport.isEnabled(.rule))
        #expect(!ActionExecutionSupport.isEnabled(.share))
    }

    @Test func futureActionsCannotResolveToExecutableSelections() {
        let futureActions = ActionItem.roadmap.map(\.id)
        #expect(!futureActions.isEmpty)

        for action in futureActions {
            #expect(!ActionExecutionSupport.isEnabled(action))
            #expect(ActionSheetPresentation.selectedExecutableAction(action) == nil)
            #expect(!ActionSheetPresentation.isPrimaryCTAEnabled(for: action))
        }
    }

    @Test func enabledActionSheetItemsMapToTrustMVPOrDocumentedFallback() {
        let documentedFallbacks = Set<ActionID>()
        let enabledIDs = ActionItem.executable.map(\.id)

        for action in enabledIDs {
            let isTrustMVPAction = action.trustMVPAction != nil
            #expect(isTrustMVPAction || documentedFallbacks.contains(action))
        }

        #expect(documentedFallbacks.isEmpty)
        #expect(Set(enabledIDs.compactMap(\.trustMVPAction)) == Set(TrustMVPAction.allCases))
    }

    @Test func actionSheetStartsWithoutExecutableSelection() {
        #expect(ActionSheetPresentation.defaultSelection == nil)
        #expect(!ActionSheetPresentation.isPrimaryCTAEnabled(for: nil))
        #expect(ActionSheetPresentation.previewText(for: nil).contains("Select an available action"))
    }

    @Test func primaryCTAOnlyEnablesForExecutableSelections() {
        for item in ActionItem.executable {
            #expect(ActionSheetPresentation.isPrimaryCTAEnabled(for: item.id))
            #expect(ActionSheetPresentation.selectedExecutableAction(item.id) == item.id)
        }

        for item in ActionItem.roadmap {
            #expect(!ActionSheetPresentation.isPrimaryCTAEnabled(for: item.id))
            #expect(ActionSheetPresentation.selectedExecutableAction(item.id) == nil)
        }
    }

    @Test func previewCopyIsOnlyOperationalForExecutableActions() throws {
        for item in ActionItem.executable {
            let preview = try #require(ActionExecutionSupport.preview(for: item.id))
            #expect(!preview.isEmpty)
            #expect(!preview.localizedCaseInsensitiveContains("Re:Box will"))
        }

        for item in ActionItem.roadmap {
            #expect(ActionExecutionSupport.preview(for: item.id) == nil)
            #expect(ActionSheetPresentation.previewText(for: item.id).contains("Select an available action"))
        }
    }

    // MARK: - ActionSheetView snapshot (dark)

    @MainActor
    @Test func actionSheetDark() {
        let view = ActionSheetView(threadSubject: "Re: Contract draft — Acme GmbH") { _ in }
            .frame(width: 720, height: 480)
            .preferredColorScheme(.dark)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 720, height: 480)
        host.layout()
    }

    @MainActor
    @Test func actionSheetLight() {
        let view = ActionSheetView(threadSubject: "Re: Contract draft — Acme GmbH") { _ in }
            .frame(width: 720, height: 480)
            .preferredColorScheme(.light)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 720, height: 480)
        host.layout()
    }

    @MainActor
    @Test func actionSheetEmptySubjectDark() {
        let view = ActionSheetView(threadSubject: "") { _ in }
            .frame(width: 720, height: 480)
            .preferredColorScheme(.dark)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 720, height: 480)
        host.layout()
    }

    @MainActor
    @Test func actionSheetEmptySubjectLight() {
        let view = ActionSheetView(threadSubject: "") { _ in }
            .frame(width: 720, height: 480)
            .preferredColorScheme(.light)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 720, height: 480)
        host.layout()
    }
}
