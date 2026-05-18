import AppKit
import SwiftUI

/// Wraps `NSSplitViewController` for the 4-pane main layout:
/// sidebar | threadlist | reading | brief.
///
/// Uses `NSSplitViewController` instead of SwiftUI `HSplitView` so we get:
/// - drag-end events via `splitViewDidResizeSubviews` for persisting widths
/// - per-pane `holdingPriority` controlling resize behaviour
/// - clean collapse/expand via `isCollapsed` on sidebar and brief items
struct MainSplitController<Sidebar: View, Threadlist: View, Reading: View, Brief: View>: NSViewControllerRepresentable {

    @Binding var sidebarCollapsed: Bool
    @Binding var briefCollapsed: Bool

    let sidebarWidth: Binding<Double>
    let threadlistWidth: Binding<Double>
    let briefWidth: Binding<Double>

    let sidebar: Sidebar
    let threadlist: Threadlist
    let reading: Reading
    let brief: Brief

    init(
        sidebarCollapsed: Binding<Bool>,
        briefCollapsed: Binding<Bool>,
        sidebarWidth: Binding<Double>,
        threadlistWidth: Binding<Double>,
        briefWidth: Binding<Double>,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder threadlist: () -> Threadlist,
        @ViewBuilder reading: () -> Reading,
        @ViewBuilder brief: () -> Brief
    ) {
        self._sidebarCollapsed = sidebarCollapsed
        self._briefCollapsed = briefCollapsed
        self.sidebarWidth = sidebarWidth
        self.threadlistWidth = threadlistWidth
        self.briefWidth = briefWidth
        self.sidebar = sidebar()
        self.threadlist = threadlist()
        self.reading = reading()
        self.brief = brief()
    }

    func makeNSViewController(context: Context) -> NSSplitViewController {
        let controller = NSSplitViewController()
        controller.splitView.isVertical = true
        controller.splitView.dividerStyle = .thin
        controller.splitView.delegate = context.coordinator

        let sidebarItem = NSSplitViewItem(
            sidebarWithViewController: NSHostingController(rootView: sidebar)
        )
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 320
        sidebarItem.canCollapse = true
        sidebarItem.collapseBehavior = .preferResizingSplitViewWithFixedSiblings
        sidebarItem.holdingPriority = NSLayoutConstraint.Priority(rawValue: 251)
        sidebarItem.isCollapsed = sidebarCollapsed

        let threadlistItem = NSSplitViewItem(
            viewController: NSHostingController(rootView: threadlist)
        )
        threadlistItem.minimumThickness = 280
        threadlistItem.maximumThickness = 480
        threadlistItem.canCollapse = false
        threadlistItem.holdingPriority = NSLayoutConstraint.Priority(rawValue: 252)

        let readingItem = NSSplitViewItem(
            viewController: NSHostingController(rootView: reading)
        )
        readingItem.minimumThickness = 480
        readingItem.canCollapse = false
        readingItem.holdingPriority = NSLayoutConstraint.Priority(rawValue: 249)

        let briefItem = NSSplitViewItem(
            viewController: NSHostingController(rootView: brief)
        )
        briefItem.minimumThickness = 280
        briefItem.maximumThickness = 420
        briefItem.canCollapse = true
        briefItem.collapseBehavior = .preferResizingSplitViewWithFixedSiblings
        briefItem.holdingPriority = NSLayoutConstraint.Priority(rawValue: 251)
        briefItem.isCollapsed = briefCollapsed

        controller.addSplitViewItem(sidebarItem)
        controller.addSplitViewItem(threadlistItem)
        controller.addSplitViewItem(readingItem)
        controller.addSplitViewItem(briefItem)

        // Set initial widths from stored values once the split view
        // has a valid frame (non-zero width). DispatchQueue.main.async
        // may fire before the view is laid out, so guard on frame width.
        context.coordinator.pendingInitialLayout = { [sidebarCollapsed, briefCollapsed] splitView in
            let totalWidth = Double(splitView.frame.width)
            guard totalWidth > 0 else { return false }
            let sWidth = sidebarCollapsed ? 0.0 : sidebarWidth.wrappedValue
            splitView.setPosition(CGFloat(sWidth), ofDividerAt: 0)
            splitView.setPosition(CGFloat(sWidth + threadlistWidth.wrappedValue), ofDividerAt: 1)
            if !briefCollapsed {
                splitView.setPosition(CGFloat(totalWidth - briefWidth.wrappedValue), ofDividerAt: 2)
            }
            return true
        }

        context.coordinator.onWidthsChanged = { sWidth, tWidth, bWidth in
            if sWidth > 0 { sidebarWidth.wrappedValue = sWidth }
            if tWidth > 0 { threadlistWidth.wrappedValue = tWidth }
            if bWidth > 0 { briefWidth.wrappedValue = bWidth }
        }

        return controller
    }

    func updateNSViewController(_ controller: NSSplitViewController, context: Context) {
        let items = controller.splitViewItems
        guard items.count == 4 else { return }

        // Update hosted views
        (items[0].viewController as? NSHostingController<Sidebar>)?.rootView = sidebar
        (items[1].viewController as? NSHostingController<Threadlist>)?.rootView = threadlist
        (items[2].viewController as? NSHostingController<Reading>)?.rootView = reading
        (items[3].viewController as? NSHostingController<Brief>)?.rootView = brief

        // Sync collapse state
        if items[0].isCollapsed != sidebarCollapsed {
            items[0].animator().isCollapsed = sidebarCollapsed
        }
        if items[3].isCollapsed != briefCollapsed {
            items[3].animator().isCollapsed = briefCollapsed
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, NSSplitViewDelegate {
        var onWidthsChanged: ((Double, Double, Double) -> Void)?
        /// Deferred initial layout closure. Returns `true` when layout succeeded
        /// (frame had a valid non-zero width), `false` to retry on next resize.
        var pendingInitialLayout: ((NSSplitView) -> Bool)?
        private var debounceWorkItem: DispatchWorkItem?

        func splitViewDidResizeSubviews(_ notification: Notification) {
            guard let splitView = notification.object as? NSSplitView,
                  splitView.subviews.count == 4 else { return }

            // Apply deferred initial layout once the frame is valid.
            if let layout = pendingInitialLayout {
                if layout(splitView) {
                    pendingInitialLayout = nil
                }
                return // Skip persisting during initial setup
            }

            // During collapse/expand animation, the collapsed pane's width
            // is redistributed and would overwrite the user's stored value.
            // Only skip persisting the collapsed pane; non-collapsed panes
            // are still user-draggable and should persist.
            let sidebarIsCollapsed = splitView.isSubviewCollapsed(splitView.subviews[0])
            let briefIsCollapsed = splitView.isSubviewCollapsed(splitView.subviews[3])

            let sWidth = sidebarIsCollapsed ? 0.0 : Double(splitView.subviews[0].frame.width)
            let tWidth = Double(splitView.subviews[1].frame.width)
            let bWidth = briefIsCollapsed ? 0.0 : Double(splitView.subviews[3].frame.width)

            // Debounce writes to UserDefaults — splitViewDidResizeSubviews
            // fires on every frame during drag.
            debounceWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.onWidthsChanged?(sWidth, tWidth, bWidth)
            }
            debounceWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
        }
    }
}
