import AppKit
import DesignSystem
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
    let forceBriefCollapsed: Bool

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
        forceBriefCollapsed: Bool = false,
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
        self.forceBriefCollapsed = forceBriefCollapsed
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
        // NOTE — NSSplitViewController installs ITSELF as its splitView's
        // delegate. Overwriting that throws an Obj-C exception at runtime
        // on macOS 26+ (observed crashing v0.1.8-alpha at launch). Listen
        // via NotificationCenter on `NSSplitView.didResizeSubviewsNotification`
        // instead — it fires on the same events the delegate method would,
        // and doesn't conflict with the controller's ownership of the
        // delegate slot.
        context.coordinator.observeSplitView(controller.splitView)

        let sidebarItem = NSSplitViewItem(
            sidebarWithViewController: NSHostingController(rootView: sidebar)
        )
        sidebarItem.minimumThickness = RBLayout.sidebarMinWidth
        sidebarItem.maximumThickness = RBLayout.sidebarMaxWidth
        sidebarItem.canCollapse = true
        sidebarItem.collapseBehavior = .preferResizingSplitViewWithFixedSiblings
        sidebarItem.holdingPriority = NSLayoutConstraint.Priority(rawValue: 251)
        sidebarItem.isCollapsed = sidebarCollapsed

        let threadlistItem = NSSplitViewItem(
            viewController: NSHostingController(rootView: threadlist)
        )
        threadlistItem.minimumThickness = RBLayout.threadListMinWidth
        threadlistItem.maximumThickness = RBLayout.threadListMaxWidth
        threadlistItem.canCollapse = false
        threadlistItem.holdingPriority = NSLayoutConstraint.Priority(rawValue: 252)

        let readingItem = NSSplitViewItem(
            viewController: NSHostingController(rootView: reading)
        )
        readingItem.minimumThickness = RBLayout.readingMinWidth
        readingItem.canCollapse = false
        readingItem.holdingPriority = NSLayoutConstraint.Priority(rawValue: 249)

        let briefItem = NSSplitViewItem(
            viewController: NSHostingController(rootView: brief)
        )
        briefItem.minimumThickness = RBLayout.briefRailMinWidth
        briefItem.maximumThickness = RBLayout.briefRailMaxWidth
        briefItem.canCollapse = true
        briefItem.collapseBehavior = .preferResizingSplitViewWithFixedSiblings
        briefItem.holdingPriority = NSLayoutConstraint.Priority(rawValue: 251)
        briefItem.isCollapsed = effectiveBriefCollapsed

        controller.addSplitViewItem(sidebarItem)
        controller.addSplitViewItem(threadlistItem)
        controller.addSplitViewItem(readingItem)
        controller.addSplitViewItem(briefItem)

        // Set initial widths from stored values once the split view
        // has a valid frame (non-zero width). DispatchQueue.main.async
        // may fire before the view is laid out, so guard on frame width.
        context.coordinator.pendingInitialLayout = { [sidebarCollapsed, effectiveBriefCollapsed] splitView in
            let totalWidth = Double(splitView.frame.width)
            guard totalWidth > 0 else { return false }
            let sWidth = sidebarCollapsed ? 0.0 : sidebarWidth.wrappedValue
            splitView.setPosition(CGFloat(sWidth), ofDividerAt: 0)
            splitView.setPosition(CGFloat(sWidth + threadlistWidth.wrappedValue), ofDividerAt: 1)
            if !effectiveBriefCollapsed {
                splitView.setPosition(CGFloat(totalWidth - briefWidth.wrappedValue), ofDividerAt: 2)
            }
            return true
        }

        configureCoordinatorCallbacks(context.coordinator)

        return controller
    }

    func updateNSViewController(_ controller: NSSplitViewController, context: Context) {
        let items = controller.splitViewItems
        guard items.count == 4 else { return }

        configureCoordinatorCallbacks(context.coordinator)

        // Update hosted views
        (items[0].viewController as? NSHostingController<Sidebar>)?.rootView = sidebar
        (items[1].viewController as? NSHostingController<Threadlist>)?.rootView = threadlist
        (items[2].viewController as? NSHostingController<Reading>)?.rootView = reading
        (items[3].viewController as? NSHostingController<Brief>)?.rootView = brief

        // Sync collapse state
        if items[0].isCollapsed != sidebarCollapsed {
            items[0].animator().isCollapsed = sidebarCollapsed
        }
        if items[3].isCollapsed != effectiveBriefCollapsed {
            let wasCollapsed = items[3].isCollapsed
            items[3].animator().isCollapsed = effectiveBriefCollapsed
            if wasCollapsed, !effectiveBriefCollapsed {
                context.coordinator.restoreBriefWidth(
                    in: controller.splitView,
                    storedBriefWidth: briefWidth.wrappedValue
                )
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    class Coordinator: NSObject {
        var onWidthsChanged: ((Double, Double, Double) -> Void)?
        var onCollapseChanged: ((Bool, Bool, Bool) -> Void)?
        var forceBriefCollapsed = false
        /// Deferred initial layout closure. Returns `true` when layout succeeded
        /// (frame had a valid non-zero width), `false` to retry on next resize.
        var pendingInitialLayout: ((NSSplitView) -> Bool)?
        private var debounceWorkItem: DispatchWorkItem?
        private weak var observedSplitView: NSSplitView?

        /// Subscribe to `NSSplitView.didResizeSubviewsNotification` for the
        /// given split view. Equivalent to being its delegate's
        /// `splitViewDidResizeSubviews(_:)`, but works around the AppKit
        /// rule that `NSSplitViewController.splitView.delegate` cannot be
        /// reassigned (controller is the delegate; assigning anything else
        /// throws on macOS 26+).
        func observeSplitView(_ splitView: NSSplitView) {
            observedSplitView = splitView
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleResize(_:)),
                name: NSSplitView.didResizeSubviewsNotification,
                object: splitView
            )
        }

        deinit {
            MainActor.assumeIsolated { [observedSplitView] in
                guard let splitView = observedSplitView else { return }
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSSplitView.didResizeSubviewsNotification,
                    object: splitView
                )
            }
        }

        @objc private func handleResize(_ notification: Notification) {
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
            let shouldPersistBriefCollapse = !forceBriefCollapsed

            // Debounce writes to UserDefaults — splitViewDidResizeSubviews
            // fires on every frame during drag.
            debounceWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.onWidthsChanged?(sWidth, tWidth, bWidth)
                self?.onCollapseChanged?(
                    sidebarIsCollapsed,
                    briefIsCollapsed,
                    shouldPersistBriefCollapse
                )
            }
            debounceWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
        }

        func restoreBriefWidth(in splitView: NSSplitView, storedBriefWidth: Double) {
            let clampedBriefWidth = min(
                max(CGFloat(storedBriefWidth), RBLayout.briefRailMinWidth),
                RBLayout.briefRailMaxWidth
            )
            DispatchQueue.main.async {
                let totalWidth = splitView.frame.width
                guard totalWidth > 0, splitView.subviews.count == 4 else { return }
                splitView.setPosition(totalWidth - clampedBriefWidth, ofDividerAt: 2)
            }
        }
    }
}

private extension MainSplitController {
    var effectiveBriefCollapsed: Bool {
        forceBriefCollapsed || briefCollapsed
    }

    func configureCoordinatorCallbacks(_ coordinator: Coordinator) {
        coordinator.forceBriefCollapsed = forceBriefCollapsed
        coordinator.onWidthsChanged = { sWidth, tWidth, bWidth in
            if sWidth > 0 { sidebarWidth.wrappedValue = sWidth }
            if tWidth > 0 { threadlistWidth.wrappedValue = tWidth }
            if bWidth > 0 { briefWidth.wrappedValue = bWidth }
        }

        coordinator.onCollapseChanged = { sidebarIsCollapsed, briefIsCollapsed, shouldPersistBriefCollapse in
            if _sidebarCollapsed.wrappedValue != sidebarIsCollapsed {
                _sidebarCollapsed.wrappedValue = sidebarIsCollapsed
            }
            guard shouldPersistBriefCollapse else { return }
            if _briefCollapsed.wrappedValue != briefIsCollapsed {
                _briefCollapsed.wrappedValue = briefIsCollapsed
            }
        }
    }
}
