import Testing
import SwiftUI
import AppKit
@testable import BriefFeature

@Suite("BriefFeature")
struct BriefFeatureTests {

    @Test func moduleNameIsExported() {
        #expect(BriefFeature.moduleName == "BriefFeature")
    }

    // MARK: - ThreadBriefViewData

    @Test func viewDataInitializesWithAllFields() {
        let data = ThreadBriefViewData(
            summary: "Test summary",
            request: "Do something",
            deadline: "Fri",
            risk: "High",
            nextStep: "Reply",
            confidence: 0.85,
            evidence: ["msg_1", "msg_2"]
        )
        #expect(data.summary == "Test summary")
        #expect(data.request == "Do something")
        #expect(data.deadline == "Fri")
        #expect(data.risk == "High")
        #expect(data.nextStep == "Reply")
        #expect(data.confidence == 0.85)
        #expect(data.evidence == ["msg_1", "msg_2"])
    }

    @Test func viewDataOptionalFieldsDefaultToNil() {
        let data = ThreadBriefViewData(summary: "Just a summary", confidence: 0.5)
        #expect(data.request == nil)
        #expect(data.deadline == nil)
        #expect(data.risk == nil)
        #expect(data.nextStep == nil)
        #expect(data.evidence.isEmpty)
    }

    // MARK: - BriefStore

    @MainActor
    @Test func storeReturnsNilForUnknownThread() {
        let store = BriefStore()
        store.loadBrief(forThreadID: "unknown-thread")
        #expect(store.brief == nil)
        #expect(store.activeThreadID == "unknown-thread")
    }

    @MainActor
    @Test func storeReturnsNilForNilThread() {
        let store = BriefStore()
        store.loadBrief(forThreadID: nil)
        #expect(store.brief == nil)
        #expect(store.activeThreadID == nil)
    }

    @MainActor
    @Test func storeReturnsBriefForT1() {
        let store = BriefStore()
        store.loadBrief(forThreadID: "t1")
        #expect(store.brief != nil)
        #expect(store.brief?.confidence == 0.88)
        #expect(store.brief?.request == "Send contract draft")
        #expect(store.brief?.evidence.count == 3)
    }

    @MainActor
    @Test func storeReturnsBriefForT2() {
        let store = BriefStore()
        store.loadBrief(forThreadID: "t2")
        #expect(store.brief != nil)
        #expect(store.brief?.confidence == 0.92)
        #expect(store.brief?.request == "Confirm seat count")
    }

    @MainActor
    @Test func storeMatchesSuffix() {
        let store = BriefStore()
        store.loadBrief(forThreadID: "prefix-t1")
        #expect(store.brief != nil)
        #expect(store.brief?.confidence == 0.88)
    }

    // MARK: - BriefRail snapshot (dark)

    @MainActor
    @Test func briefRailWithDataDark() {
        let store = BriefStore()
        store.loadBrief(forThreadID: "t1")
        let view = BriefRail(store: store)
            .frame(width: 340, height: 600)
            .preferredColorScheme(.dark)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 340, height: 600)
        host.layout()
    }

    @MainActor
    @Test func briefRailWithDataLight() {
        let store = BriefStore()
        store.loadBrief(forThreadID: "t1")
        let view = BriefRail(store: store)
            .frame(width: 340, height: 600)
            .preferredColorScheme(.light)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 340, height: 600)
        host.layout()
    }

    @MainActor
    @Test func briefRailEmptyStateDark() {
        let store = BriefStore()
        store.loadBrief(forThreadID: "no-brief")
        let view = BriefRail(store: store)
            .frame(width: 340, height: 300)
            .preferredColorScheme(.dark)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 340, height: 300)
        host.layout()
    }

    @MainActor
    @Test func briefRailEmptyStateLight() {
        let store = BriefStore()
        store.loadBrief(forThreadID: "no-brief")
        let view = BriefRail(store: store)
            .frame(width: 340, height: 300)
            .preferredColorScheme(.light)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 340, height: 300)
        host.layout()
    }

    @MainActor
    @Test func briefRailT2Dark() {
        let store = BriefStore()
        store.loadBrief(forThreadID: "t2")
        let view = BriefRail(store: store)
            .frame(width: 340, height: 600)
            .preferredColorScheme(.dark)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 340, height: 600)
        host.layout()
    }
}
