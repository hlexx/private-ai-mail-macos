import AppKit
import InboxFeature
import Persistence
import SwiftUI
import Testing
@testable import PrivateAIMail

/// Wrapper that owns the @FocusState needed by RBToolbar.
private struct ToolbarTestHost: View {
    @FocusState private var searchFocused: Bool
    var filterMenu = RBToolbarFilterMenu(selectedFilter: .all, onSelect: { _ in })
    var accounts: [AccountRecord] = []
    var activeAccountID: String?
    var onCycleAccount: () -> Void = {}
    var onToggleTheme: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onCompose: () -> Void = {}
    var onToggleSidebar: (() -> Void)?
    var onToggleBrief: (() -> Void)?
    var briefPlacementIsBottom = false
    var onToggleBriefPlacement: (() -> Void)?
    var sidebarCollapsed = false

    init(
        filterMenu: RBToolbarFilterMenu = RBToolbarFilterMenu(selectedFilter: .all, onSelect: { _ in }),
        accounts: [AccountRecord] = [],
        activeAccountID: String? = nil,
        onCycleAccount: @escaping () -> Void = {},
        onToggleTheme: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {},
        onCompose: @escaping () -> Void = {},
        onToggleSidebar: (() -> Void)? = nil,
        onToggleBrief: (() -> Void)? = nil,
        briefPlacementIsBottom: Bool = false,
        onToggleBriefPlacement: (() -> Void)? = nil,
        sidebarCollapsed: Bool = false
    ) {
        self.filterMenu = filterMenu
        self.accounts = accounts
        self.activeAccountID = activeAccountID
        self.onCycleAccount = onCycleAccount
        self.onToggleTheme = onToggleTheme
        self.onOpenSettings = onOpenSettings
        self.onCompose = onCompose
        self.onToggleSidebar = onToggleSidebar
        self.onToggleBrief = onToggleBrief
        self.briefPlacementIsBottom = briefPlacementIsBottom
        self.onToggleBriefPlacement = onToggleBriefPlacement
        self.sidebarCollapsed = sidebarCollapsed
    }

    var body: some View {
        RBToolbar(
            accounts: accounts,
            activeAccountID: activeAccountID,
            onCycleAccount: onCycleAccount,
            onToggleTheme: onToggleTheme,
            onOpenSettings: onOpenSettings,
            onCompose: onCompose,
            onToggleSidebar: onToggleSidebar,
            onToggleBrief: onToggleBrief,
            briefPlacementIsBottom: briefPlacementIsBottom,
            onToggleBriefPlacement: onToggleBriefPlacement,
            sidebarCollapsed: sidebarCollapsed,
            filterMenu: filterMenu,
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
    private func makeToolbar(filterMenu: RBToolbarFilterMenu) -> some View {
        ToolbarTestHost(filterMenu: filterMenu)
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
    @Test func toolbarBuildsWithFilterMenu() {
        let view = makeToolbar(
            filterMenu: RBToolbarFilterMenu(selectedFilter: .needsReply, onSelect: { _ in })
        )
        .preferredColorScheme(.dark)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 1200, height: 56)
        host.layout()
    }

    @MainActor
    @Test func filterMenuSelectionUpdatesBoundInboxFilter() {
        var currentFilter = ThreadFilter.all
        let menu = RBToolbarFilterMenu(
            selectedFilter: currentFilter,
            onSelect: { currentFilter = $0 }
        )

        menu.select(.hasAttachment)

        #expect(currentFilter == .hasAttachment)
    }

    @MainActor
    @Test func collapsedSidebarToggleClickStaysInsideVisibleLeadingSection() {
        var toggleCount = 0
        let host = toolbarHost(
            ToolbarTestHost(
                onToggleSidebar: { toggleCount += 1 },
                sidebarCollapsed: true
            )
        )
        defer { host.window.close() }

        click(host.view, at: NSPoint(x: 28, y: 28))

        #expect(toggleCount == 1)
    }

    @MainActor
    @Test func toolbarPrimaryButtonsDispatchActions() {
        var cycleCount = 0
        var sidebarCount = 0
        var themeCount = 0
        var briefCount = 0
        var placementCount = 0
        var settingsCount = 0
        var composeCount = 0

        let account = AccountRecord(
            id: "acc-1",
            provider: "gmail",
            email: "alex@studio.eu",
            displayName: "Alex",
            createdAt: 0
        )
        let host = toolbarHost(
            ToolbarTestHost(
                accounts: [account],
                activeAccountID: account.id,
                onCycleAccount: { cycleCount += 1 },
                onToggleTheme: { themeCount += 1 },
                onOpenSettings: { settingsCount += 1 },
                onCompose: { composeCount += 1 },
                onToggleSidebar: { sidebarCount += 1 },
                onToggleBrief: { briefCount += 1 },
                onToggleBriefPlacement: { placementCount += 1 }
            )
        )
        defer { host.window.close() }

        click(host.view, at: NSPoint(x: 96, y: 28))
        click(host.view, at: NSPoint(x: 168, y: 28))
        click(host.view, at: NSPoint(x: 1_024, y: 28))
        click(host.view, at: NSPoint(x: 1_060, y: 28))
        click(host.view, at: NSPoint(x: 1_096, y: 28))
        click(host.view, at: NSPoint(x: 1_132, y: 28))
        click(host.view, at: NSPoint(x: 1_168, y: 28))

        #expect(sidebarCount == 1)
        #expect(cycleCount == 1)
        #expect(themeCount == 1)
        #expect(briefCount == 1)
        #expect(placementCount == 1)
        #expect(settingsCount == 1)
        #expect(composeCount == 1)
    }

    @MainActor
    private func toolbarHost(_ rootView: ToolbarTestHost) -> (window: NSWindow, view: NSHostingView<ToolbarTestHost>) {
        let view = NSHostingView(rootView: rootView)
        view.frame = NSRect(x: 0, y: 0, width: 1_200, height: 56)
        let window = NSWindow(
            contentRect: view.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        view.layoutSubtreeIfNeeded()
        return (window, view)
    }

    @MainActor
    private func click(_ view: NSView, at point: NSPoint) {
        guard let window = view.window else {
            Issue.record("Expected hosted toolbar to be attached to a window")
            return
        }
        let windowPoint = view.convert(point, to: nil)
        let eventBase = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: windowPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        )
        guard let mouseDown = eventBase else {
            Issue.record("Expected mouseDown event")
            return
        }
        window.sendEvent(mouseDown)

        guard let mouseUp = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: windowPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 2,
            clickCount: 1,
            pressure: 0
        ) else {
            Issue.record("Expected mouseUp event")
            return
        }
        window.sendEvent(mouseUp)
    }
}
