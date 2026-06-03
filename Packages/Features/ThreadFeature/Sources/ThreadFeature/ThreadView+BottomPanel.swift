import DesignSystem
import SwiftUI

enum ThreadBottomPanelLayout {
    static func height(availableHeight: CGFloat, isCollapsed: Bool) -> CGFloat {
        guard !isCollapsed else { return RBLayout.bottomPanelCollapsedHeight }
        guard availableHeight > 0 else { return RBLayout.bottomPanelExpandedHeight }
        return RBResponsiveLayoutPolicy.expandedBottomPanelHeight(availableHeight: availableHeight)
    }
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

    func bottomWorkPanel(availableHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            bottomPanelChrome
            if !bottomPanelCollapsed {
                bottomPanelContent
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(
            height: ThreadBottomPanelLayout.height(
                availableHeight: availableHeight,
                isCollapsed: bottomPanelCollapsed
            ),
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
                Image(systemName: bottomPanelCollapsed ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.rbGhost)
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
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(selected ? Color.rbBgElev2 : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: RBRadius.sm))
        }
        .buttonStyle(.plain)
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
