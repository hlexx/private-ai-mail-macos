import AppKit
import SwiftUI
import Testing
@testable import MacApp

@Suite("RBSidebar — builds and lays out in both themes")
struct RBSidebarTests {

    private func makeSidebar(withAccounts: Bool = true) -> some View {
        var folders = FolderItem.defaultFolders
        folders[0].count = 12
        folders[1].count = 4
        folders[2].count = 3

        let accounts: [AccountRow] = withAccounts ? [
            AccountRow(id: "g1", email: "alex@studio.eu", dotColor: .rbCobalt400),
            AccountRow(id: "m1", email: "a.chen@partners.io", dotColor: .rbViolet500),
        ] : []

        return RBSidebar(
            folders: folders,
            accounts: accounts,
            activeFolder: .constant("inbox")
        )
        .frame(width: 240, height: 600)
        .background(Color.rbBgDeep)
    }

    @MainActor
    @Test func sidebarDarkWithAccounts() {
        let view = makeSidebar(withAccounts: true)
            .preferredColorScheme(.dark)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 240, height: 600)
        host.layout()
    }

    @MainActor
    @Test func sidebarLightWithAccounts() {
        let view = makeSidebar(withAccounts: true)
            .preferredColorScheme(.light)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 240, height: 600)
        host.layout()
    }

    @MainActor
    @Test func sidebarDarkNoAccounts() {
        let view = makeSidebar(withAccounts: false)
            .preferredColorScheme(.dark)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 240, height: 600)
        host.layout()
    }

    @MainActor
    @Test func sidebarLightNoAccounts() {
        let view = makeSidebar(withAccounts: false)
            .preferredColorScheme(.light)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 240, height: 600)
        host.layout()
    }

    @Test func folderItemDefaultCount() {
        let folders = FolderItem.defaultFolders
        #expect(folders.count == 8)
        #expect(folders[0].id == "inbox")
        #expect(folders[7].id == "arch")
    }

    @Test func accountRowDeterministicColor() {
        let color1 = AccountRow.deterministicColor(for: "test-id-1")
        let color2 = AccountRow.deterministicColor(for: "test-id-1")
        #expect(color1 == color2)
    }
}
