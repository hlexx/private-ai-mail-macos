import Foundation

/// Layout dimensions for the macOS window chrome and primary panes.
///
/// Values are pulled verbatim from `design/re-box/project/app/app.css`
/// (see Re:Box handoff). Treat these as the source of truth; any view
/// that hard-codes a competing literal is a bug.
public enum RBLayout {
    // MARK: Window chrome

    /// `.rb-window { grid-template-rows: 56px 1fr }`
    public static let toolbarHeight: CGFloat = 56

    /// `.rb-window` min content width target.
    public static let windowMinWidth: CGFloat = 1000

    /// `.rb-window` min content height target.
    public static let windowMinHeight: CGFloat = 640

    // MARK: Three-pane layout

    /// `.rb-panes { grid-template-columns: 240px ... }`
    public static let sidebarWidth: CGFloat = 240

    /// `.rb-panes { grid-template-columns: ... 360px ... }`
    public static let threadListWidth: CGFloat = 360

    // MARK: Reading-pane inner split

    /// `.rb-read-body { grid-template-columns: minmax(0, 1fr) 340px }`
    public static let briefRailWidth: CGFloat = 340

    // MARK: Avatar / signal sizes

    /// `.rb-row .av { width: 32px; height: 32px }`
    public static let threadListAvatarSize: CGFloat = 32

    /// `.rb-msg-av { width: 28px; height: 28px }`
    public static let messageAvatarSize: CGFloat = 28

    /// `.rb-row.active::before { width: 3px }` — citron active-row indicator.
    public static let activeRowIndicatorWidth: CGFloat = 3

    // MARK: Settings window

    /// `SettingsScene` TabView. Matches the design system's intended dialog scale.
    public static let settingsWidth: CGFloat = 520
    public static let settingsHeight: CGFloat = 360
}
