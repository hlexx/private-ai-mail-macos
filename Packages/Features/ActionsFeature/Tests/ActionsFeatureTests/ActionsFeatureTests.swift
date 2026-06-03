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

        let mappedActions = ids.compactMap(\.trustMVPAction)
        #expect(mappedActions == TrustMVPAction.allCases)
        #expect(ActionItem.executable.map(\.label) == TrustMVPAction.allCases.map(\.title))
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

    @Test func onlyImplementedActionsAreExecutableForSupportedProvider() {
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

    @Test func unsupportedProviderDisablesAllTrustActions() {
        for item in ActionItem.executable {
            #expect(!ActionExecutionSupport.isEnabled(item.id, availability: .unsupportedProvider))
            #expect(ActionSheetPresentation.selectedTrustAction(
                item.id,
                availability: .unsupportedProvider
            ) == nil)
        }
        #expect(!ActionSheetPresentation.isPrimaryCTAEnabled(
            for: .archive,
            availability: .unsupportedProvider
        ))
        #expect(ActionSheetPresentation.previewText(
            for: .archive,
            availability: .unsupportedProvider
        ).contains("Gmail-only"))
    }

    @Test func futureActionsCannotResolveToExecutableSelections() {
        let futureActions = ActionItem.roadmap.map(\.id)
        #expect(!futureActions.isEmpty)

        for action in futureActions {
            #expect(!ActionExecutionSupport.isEnabled(action))
            #expect(ActionSheetPresentation.selectedTrustAction(action) == nil)
            #expect(!ActionSheetPresentation.isPrimaryCTAEnabled(for: action))
        }
    }

    @Test func enabledActionSheetItemsMapExactlyToTrustMVP() {
        let enabledIDs = ActionItem.executable.map(\.id)
        #expect(enabledIDs.compactMap(\.trustMVPAction) == TrustMVPAction.allCases)
    }

    @Test func actionSheetStartsWithoutExecutableSelection() {
        #expect(!ActionSheetPresentation.isPrimaryCTAEnabled(for: nil))
        #expect(ActionSheetPresentation.previewText(for: nil).contains("Select an available action"))
        #expect(ActionSheetPresentation.privacyText(for: nil).contains("No provider update runs"))
    }

    @Test func primaryCTAOnlyEnablesForExecutableSelections() {
        for item in ActionItem.executable {
            #expect(ActionSheetPresentation.isPrimaryCTAEnabled(for: item.id))
            #expect(ActionSheetPresentation.selectedTrustAction(item.id) == item.id.trustMVPAction)
        }

        for item in ActionItem.roadmap {
            #expect(!ActionSheetPresentation.isPrimaryCTAEnabled(for: item.id))
            #expect(ActionSheetPresentation.selectedTrustAction(item.id) == nil)
        }
    }

    @Test func selectedExecutableActionsEmitTrustMVPActions() throws {
        for item in ActionItem.executable {
            let trustAction = try #require(item.id.trustMVPAction)
            #expect(ActionSheetPresentation.selectedTrustAction(item.id) == trustAction)
        }
    }

    @Test func previewCopyIsOnlyOperationalForExecutableActions() throws {
        let expectedPreviews: [ActionID: String] = [
            .reply: "Draft reply opens a confirmation step before any Gmail draft is written.",
            .archive: "Archive queues a Gmail archive update for the selected thread.",
            .star: "Star queues a Gmail star update for the selected thread.",
            .markRead: "Mark read queues a Gmail read-state update for the selected thread.",
            .trash: "Trash opens a confirmation step before moving the thread to Gmail trash.",
        ]

        for item in ActionItem.executable {
            let preview = try #require(ActionExecutionSupport.preview(for: item.id))
            #expect(preview == expectedPreviews[item.id])
            #expect(ActionSheetPresentation.previewText(for: item.id) == expectedPreviews[item.id])
            #expect(!preview.localizedCaseInsensitiveContains("Re:Box will"))
        }

        for item in ActionItem.roadmap {
            #expect(ActionExecutionSupport.preview(for: item.id) == nil)
            #expect(ActionSheetPresentation.previewText(for: item.id).contains("Select an available action"))
        }
    }

    @Test func privacyCopyDoesNotClaimZeroUploadForProviderActions() {
        let selectedCopy = ActionSheetPresentation.privacyText(for: .archive)
        #expect(selectedCopy.contains("Gmail receives action metadata"))
        #expect(!selectedCopy.contains("0 bytes"))

        let unsupportedCopy = ActionSheetPresentation.privacyText(
            for: .archive,
            availability: .unsupportedProvider
        )
        #expect(unsupportedCopy.contains("No provider update will run"))
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
