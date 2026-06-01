import AppKit
import SwiftUI
import Testing
@testable import PrivateAIMail

/// Wrapper that owns the @FocusState needed by RBToolbar.
private struct ToolbarTestHost: View {
    @FocusState private var searchFocused: Bool
    var body: some View {
        RBToolbar(
            accounts: [],
            activeAccountID: nil,
            onCycleAccount: {},
            onToggleTheme: {},
            onOpenSettings: {},
            onCompose: {},
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
}
