import DesignSystem
import SwiftUI

enum ThreadBottomPanelMetrics {
    static let collapsedHeight: CGFloat = 42
    static let tabMinHeight = RBControlMetrics.compactHitTarget
    static let collapseButtonMinSize = RBControlMetrics.compactHitTarget
}

extension ThreadView {
    var hasBottomPanel: Bool {
        showsComposerPanel || showsBriefInBottomPanel
    }

    var resolvedBottomPanelTab: ThreadBottomPanelTab {
        let selected = ThreadBottomPanelTab(rawValue: bottomPanelTabRaw) ?? .draft
        switch selected {
        case .draft where showsComposerPanel:
            return .draft
        case .brief where showsBriefInBottomPanel:
            return .brief
        case .draft:
            return showsBriefInBottomPanel ? .brief : .draft
        case .brief:
            return showsComposerPanel ? .draft : .brief
        }
    }

    var bottomWorkPanel: some View {
        VStack(spacing: 0) {
            bottomPanelChrome
            if !bottomPanelCollapsed {
                bottomPanelContent
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(height: bottomPanelCollapsed ? ThreadBottomPanelMetrics.collapsedHeight : 318, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(Color.rbBgCanvas)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.rbStroke1)
                .frame(height: 1)
        }
        .animation(.easeInOut(duration: 0.18), value: bottomPanelCollapsed)
        .animation(.easeInOut(duration: 0.18), value: bottomPanelTabRaw)
    }

    private var bottomPanelChrome: some View {
        HStack(spacing: 8) {
            if showsComposerPanel {
                bottomPanelTabButton(.draft)
            }
            if showsBriefInBottomPanel {
                bottomPanelTabButton(.brief)
            }

            Spacer(minLength: 12)

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    bottomPanelCollapsed.toggle()
                }
            } label: {
                Label(
                    bottomPanelCollapsed
                        ? String(localized: "thread.bottomPanel.expand", defaultValue: "Expand bottom panel")
                        : String(localized: "thread.bottomPanel.collapse", defaultValue: "Collapse bottom panel"),
                    systemImage: bottomPanelCollapsed ? "chevron.up" : "chevron.down"
                )
                .labelStyle(.iconOnly)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(
                        minWidth: ThreadBottomPanelMetrics.collapseButtonMinSize,
                        minHeight: ThreadBottomPanelMetrics.collapseButtonMinSize
                    )
            }
            .buttonStyle(.rbGhost)
            .accessibilityLabel(bottomPanelCollapsed
                ? String(localized: "thread.bottomPanel.expand", defaultValue: "Expand bottom panel")
                : String(localized: "thread.bottomPanel.collapse", defaultValue: "Collapse bottom panel")
            )
            .help(bottomPanelCollapsed
                ? String(localized: "thread.bottomPanel.expand", defaultValue: "Expand bottom panel")
                : String(localized: "thread.bottomPanel.collapse", defaultValue: "Collapse bottom panel")
            )
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }

    private func bottomPanelTabButton(_ tab: ThreadBottomPanelTab) -> some View {
        let selected = resolvedBottomPanelTab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                bottomPanelTabRaw = tab.rawValue
                bottomPanelCollapsed = false
            }
        } label: {
            Label(tabTitle(tab), systemImage: tabIcon(tab))
                .font(.rbGeist(12, weight: selected ? .medium : .regular))
                .foregroundStyle(selected ? Color.rbFg1 : Color.rbFg3)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(minHeight: ThreadBottomPanelMetrics.tabMinHeight, alignment: .center)
                .contentShape(RoundedRectangle(cornerRadius: RBRadius.sm))
                .background(selected ? Color.rbBgElev2 : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: RBRadius.sm))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tabTitle(tab))
        .help(tabTitle(tab))
    }

    @ViewBuilder
    private var bottomPanelContent: some View {
        switch resolvedBottomPanelTab {
        case .draft:
            composerContent
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        case .brief:
            briefContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func tabTitle(_ tab: ThreadBottomPanelTab) -> String {
        switch tab {
        case .draft:
            return String(localized: "thread.bottomPanel.draft", defaultValue: "Draft")
        case .brief:
            return String(localized: "thread.bottomPanel.brief", defaultValue: "Brief")
        }
    }

    private func tabIcon(_ tab: ThreadBottomPanelTab) -> String {
        switch tab {
        case .draft:
            return "square.and.pencil"
        case .brief:
            return "sparkles"
        }
    }
}
