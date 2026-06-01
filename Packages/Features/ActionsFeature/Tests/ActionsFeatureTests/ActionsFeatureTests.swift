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

    @Test func allActionsHaveEightItems() {
        #expect(ActionItem.all.count == 8)
    }

    @Test func actionIDsMatchExpected() {
        let ids = ActionItem.all.map(\.id)
        #expect(ids == [.reply, .snooze, .log, .task, .archive, .unsub, .rule, .share])
    }

    @Test func allActionIDCasesAreCovered() {
        let itemIDs = Set(ActionItem.all.map(\.id))
        let allCases = Set(ActionID.allCases)
        #expect(itemIDs == allCases)
    }

    @Test func onlyImplementedActionsAreExecutable() {
        #expect(ActionExecutionSupport.isEnabled(.reply))
        #expect(ActionExecutionSupport.isEnabled(.archive))
        #expect(!ActionExecutionSupport.isEnabled(.snooze))
        #expect(!ActionExecutionSupport.isEnabled(.log))
        #expect(!ActionExecutionSupport.isEnabled(.task))
        #expect(!ActionExecutionSupport.isEnabled(.unsub))
        #expect(!ActionExecutionSupport.isEnabled(.rule))
        #expect(!ActionExecutionSupport.isEnabled(.share))
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
