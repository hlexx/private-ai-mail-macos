import AppKit
import SwiftUI
import Testing
@testable import PrivateAIMail

@Suite("RBToolbar — builds and lays out in both themes")
struct RBToolbarTests {

    @MainActor
    private func makeToolbar() -> some View {
        RBToolbar(
            accounts: [],
            activeAccountID: nil,
            onCycleAccount: {},
            onToggleTheme: {},
            onOpenSettings: {},
            onCompose: {},
            onOpenActionSheet: {}
        )
        .frame(width: 1200, height: 56)
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
