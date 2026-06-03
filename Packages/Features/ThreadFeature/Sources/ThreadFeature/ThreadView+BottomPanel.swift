import DesignSystem
import SwiftUI

enum ThreadBottomPanelLayout {
    static let chromeVerticalPadding: CGFloat = 8
    static let collapsedHeight = RBControlMetrics.compactHitTarget + chromeVerticalPadding * 2
    static let expandedHeight: CGFloat = 318
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
        .frame(
            height: bottomPanelCollapsed
                ? ThreadBottomPanelLayout.collapsedHeight
                : ThreadBottomPanelLayout.expandedHeight,
            alignment: .top
        )
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
        let collapseTitle = bottomPanelCollapsed
            ? String(localized: "thread.bottomPanel.expand", defaultValue: "Expand bottom panel")
            : String(localized: "thread.bottomPanel.collapse", defaultValue: "Collapse bottom panel")

        return HStack(spacing: 8) {
            if showsComposerPanel {
                bottomPanelTabButton(.draft)
            }
            if showsBriefInBottomPanel {
                bottomPanelTabButton(.brief)
            }

            Spacer(minLength: 12)

            RBIconButton(
                systemName: bottomPanelCollapsed ? "chevron.up" : "chevron.down",
                accessibilityLabel: collapseTitle
            ) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    bottomPanelCollapsed.toggle()
                }
            }
            .help(collapseTitle)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, ThreadBottomPanelLayout.chromeVerticalPadding)
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
                .frame(minHeight: RBControlMetrics.compactHitTarget, alignment: .center)
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
