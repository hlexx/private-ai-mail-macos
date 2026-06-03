import DesignSystem
import SwiftUI

enum ThreadBottomPanelLayout {
    static func presentation(
        availableHeight: CGFloat,
        isCollapsed: Bool
    ) -> ThreadBottomPanelPresentation {
        guard !isCollapsed else {
            let expandedHeight = RBResponsiveLayoutPolicy.expandedBottomPanelHeight(
                availableHeight: availableHeight
            )
            return ThreadBottomPanelPresentation(
                height: RBLayout.bottomPanelCollapsedHeight,
                showsContent: false,
                canShowContent: expandedHeight >= RBLayout.bottomPanelMinExpandedHeight
            )
        }

        let height = RBResponsiveLayoutPolicy.expandedBottomPanelHeight(
            availableHeight: availableHeight
        )
        let canShowContent = height >= RBLayout.bottomPanelMinExpandedHeight
        return ThreadBottomPanelPresentation(
            height: height,
            showsContent: canShowContent,
            canShowContent: canShowContent
        )
    }
}

struct ThreadBottomPanelPresentation {
    let height: CGFloat
    let showsContent: Bool
    let canShowContent: Bool
}

extension ThreadView {
    var hasBottomPanel: Bool {
        showsComposerPanel || showsBriefInBottomPanel
    }

    var resolvedBottomPanelTab: ThreadBottomPanelTab {
        ThreadBottomPanelTab.resolved(
            rawValue: bottomPanelTabRaw,
            showsComposerPanel: showsComposerPanel,
            showsBriefInBottomPanel: showsBriefInBottomPanel
        )
    }

    func bottomWorkPanel(availableHeight: CGFloat) -> some View {
        let presentation = ThreadBottomPanelLayout.presentation(
            availableHeight: availableHeight,
            isCollapsed: bottomPanelCollapsed
        )

        return VStack(spacing: 0) {
            bottomPanelChrome(presentation: presentation)
            if presentation.showsContent {
                bottomPanelContent
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(height: presentation.height, alignment: .top)
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

    private func bottomPanelChrome(presentation: ThreadBottomPanelPresentation) -> some View {
        HStack(spacing: 8) {
            if showsComposerPanel {
                bottomPanelTabButton(.draft, canShowContent: presentation.canShowContent)
            }
            if showsBriefInBottomPanel {
                bottomPanelTabButton(.brief, canShowContent: presentation.canShowContent)
            }

            Spacer(minLength: 12)

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    bottomPanelCollapsed = presentation.showsContent
                }
            } label: {
                Image(systemName: presentation.showsContent ? "chevron.down" : "chevron.up")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.rbGhost)
            .disabled(!presentation.canShowContent)
            .help(bottomPanelToggleHelp(presentation: presentation))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }

    private func bottomPanelTabButton(
        _ tab: ThreadBottomPanelTab,
        canShowContent: Bool
    ) -> some View {
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
        .disabled(!canShowContent)
        .help(tabTitle(tab))
    }

    private func bottomPanelToggleHelp(
        presentation: ThreadBottomPanelPresentation
    ) -> String {
        guard presentation.canShowContent else {
            return String(
                localized: "thread.bottomPanel.windowTooShort",
                defaultValue: "Window is too short to expand bottom panel"
            )
        }
        return presentation.showsContent
            ? String(localized: "thread.bottomPanel.collapse", defaultValue: "Collapse bottom panel")
            : String(localized: "thread.bottomPanel.expand", defaultValue: "Expand bottom panel")
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
