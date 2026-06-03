import AppKit
import InboxFeature
import SwiftUI
import Testing
@testable import PrivateAIMail

/// Wrapper that owns the @FocusState needed by RBToolbar.
private struct ToolbarTestHost: View {
    @FocusState private var searchFocused: Bool
    var filterOptions: [RBToolbarFilterOption] = []
    var onSelectFilterOption: (RBToolbarFilterOption.ID) -> Void = { _ in }

    var body: some View {
        RBToolbar(
            accounts: [],
            activeAccountID: nil,
            onCycleAccount: {},
            onToggleTheme: {},
            onOpenSettings: {},
            onCompose: {},
            filterOptions: filterOptions,
            onSelectFilterOption: onSelectFilterOption,
            searchFocused: $searchFocused,
            searchText: .constant(""),
            onSubmitSearch: {}
        )
        .frame(width: 1200, height: 56)
    }
}

@Suite("RBToolbar — builds and lays out in both themes")
struct RBToolbarTests {

    @MainActor
    private func makeToolbar() -> some View {
        ToolbarTestHost()
    }

    @MainActor
    private func makeToolbar(filterOptions: [RBToolbarFilterOption]) -> some View {
        ToolbarTestHost(filterOptions: filterOptions)
    }

    @MainActor
    @Test func toolbarDarkNoAccounts() {
        let view = makeToolbar()
            .preferredColorScheme(.dark)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 1200, height: 56)
        host.layout()
    }

    @MainActor
    @Test func toolbarLightNoAccounts() {
        let view = makeToolbar()
            .preferredColorScheme(.light)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 1200, height: 56)
        host.layout()
    }

    @MainActor
    @Test func toolbarBuildsWithFilterOptions() {
        let view = makeToolbar(
            filterOptions: MainScene.toolbarFilterOptions(currentFilter: .needsReply)
        )
        .preferredColorScheme(.dark)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 1200, height: 56)
        host.layout()
    }

    @MainActor
    @Test func toolbarFilterOptionsMirrorThreadFilterSelection() {
        let options = MainScene.toolbarFilterOptions(currentFilter: .hasDeadline)
        #expect(options.count == ThreadFilter.allCases.count)
        #expect(options.first(where: \.isSelected)?.id == ThreadFilter.hasDeadline.rawValue)
        #expect(options.filter(\.isSelected).count == 1)
    }

    @MainActor
    @Test func toolbarFilterOptionsUseInboxFilterContract() {
        let options = MainScene.toolbarFilterOptions(currentFilter: .aiHandled)

        for filter in ThreadFilter.allCases {
            let option = options.first { $0.id == filter.rawValue }
            #expect(option?.label == filter.label)
            #expect(option?.isSelected == (filter == .aiHandled))
        }
    }

    @MainActor
    @Test func toolbarFilterOptionIDsRoundTripToInboxFilters() {
        for filter in ThreadFilter.allCases {
            let resolved = MainScene.threadFilter(forToolbarOptionID: filter.rawValue)
            #expect(resolved == filter)
        }
    }

    @MainActor
    @Test func unknownToolbarFilterOptionIsIgnored() {
        #expect(MainScene.threadFilter(forToolbarOptionID: "unknown") == nil)
    }
}
