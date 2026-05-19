import DesignSystem
import InboxFeature
import Persistence
import SwiftUI

// MARK: - Model types

struct FolderItem: Identifiable, Hashable {
    let id: FolderID
    let name: String
    let icon: String
    var count: Int?

    static let defaultFolders: [FolderItem] = [
        FolderItem(id: .inbox, name: String(localized: "sidebar.folder.inbox", defaultValue: "Inbox"), icon: "tray"),
        FolderItem(id: .needsReply, name: String(localized: "sidebar.folder.needsReply", defaultValue: "Needs reply"), icon: "arrowshape.turn.up.left"),
        FolderItem(id: .hasDeadline, name: String(localized: "sidebar.folder.hasDeadline", defaultValue: "Has deadline"), icon: "clock"),
        FolderItem(id: .attachments, name: String(localized: "sidebar.folder.attachments", defaultValue: "Attachments"), icon: "paperclip"),
        FolderItem(id: .logged, name: String(localized: "sidebar.folder.logged", defaultValue: "Logged"), icon: "checkmark.circle"),
        FolderItem(id: .starred, name: String(localized: "sidebar.folder.starred", defaultValue: "Starred"), icon: "star"),
        FolderItem(id: .sent, name: String(localized: "sidebar.folder.sent", defaultValue: "Sent"), icon: "paperplane"),
        FolderItem(id: .archive, name: String(localized: "sidebar.folder.archive", defaultValue: "Archive"), icon: "archivebox"),
    ]
}

struct AccountRow: Identifiable, Hashable {
    let id: String
    let email: String
    let dotColor: Color

    init(account: AccountRecord) {
        self.id = account.id
        self.email = account.email
        self.dotColor = Self.deterministicColor(for: account.id)
    }

    init(id: String, email: String, dotColor: Color) {
        self.id = id
        self.email = email
        self.dotColor = dotColor
    }

    private static let palette: [Color] = [
        .rbCobalt400, .rbViolet500, .rbCitron500,
        .rbToneJade400, .rbToneCoral400, .rbToneIce400,
    ]

    static func deterministicColor(for id: String) -> Color {
        let hash = id.utf8.reduce(0) { ($0 &* 31) &+ Int($1) }
        return palette[Int(hash.magnitude) % palette.count]
    }
}

// MARK: - RBSidebar

struct RBSidebar: View {
    let folders: [FolderItem]
    let accounts: [AccountRow]
    @Binding var selection: SidebarSelection
    var jumpPulse: SidebarSelection? = nil

    // Per-section collapse state. Persisted across launches so layout
    // memory survives quitting the app, matching Mail.app behavior.
    @AppStorage("rb-sidebar-mail-collapsed") private var mailCollapsed = false
    @AppStorage("rb-sidebar-accounts-collapsed") private var accountsCollapsed = false
    @AppStorage("rb-sidebar-privacy-collapsed") private var privacyCollapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeader(
                        title: String(localized: "sidebar.section.mail", defaultValue: "Mail"),
                        isCollapsed: mailCollapsed,
                        onToggle: { mailCollapsed.toggle() }
                    )

                    if !mailCollapsed {
                        ForEach(folders) { folder in
                            folderRow(folder)
                        }
                    }

                    sectionHeader(
                        title: String(localized: "sidebar.section.accounts", defaultValue: "Accounts"),
                        isCollapsed: accountsCollapsed,
                        onToggle: { accountsCollapsed.toggle() }
                    )
                    .padding(.top, RBSpace.s2)

                    if !accountsCollapsed {
                        if accounts.count > 1 {
                            allAccountsRow
                        }
                        ForEach(accounts) { account in
                            accountRow(account)
                        }
                    }

                    sectionHeader(
                        title: String(localized: "sidebar.section.privacy", defaultValue: "Privacy"),
                        isCollapsed: privacyCollapsed,
                        onToggle: { privacyCollapsed.toggle() }
                    )
                    .padding(.top, RBSpace.s2)
                }
                .padding(.horizontal, RBSpace.s2)
                .padding(.vertical, RBSpace.s3)
            }

            Spacer(minLength: 0)

            footer
        }
        .background(Color.clear)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.rbStroke1)
                .frame(width: 1)
        }
    }

    // MARK: - Section header

    private func sectionHeader(
        title: String,
        isCollapsed: Bool,
        onToggle: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(.easeOut(duration: RBDuration.d1)) {
                onToggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.rbFg3)
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                Text(title.uppercased())
                    .font(.rbMono(10, weight: .medium))
                    .tracking(0.14 * 10)
                    .foregroundStyle(Color.rbFg3)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Folder row

    private func folderRow(_ folder: FolderItem) -> some View {
        let isActive: Bool = {
            if case .folder(let fid) = selection { return fid == folder.id }
            return false
        }()
        let isPulsing: Bool = {
            if case .folder(let fid) = jumpPulse { return fid == folder.id }
            return false
        }()
        return Button {
            selection = .folder(folder.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: folder.icon)
                    .font(.system(size: 13))
                    .frame(width: 16)
                Text(folder.name)
                    .font(.rbGeist(13))
                Spacer()
                if let count = folder.count {
                    Text("\(count)")
                        .font(.rbMono(11))
                        .foregroundStyle(isActive ? Color.rbCitron500 : Color.rbFg3)
                }
            }
            .foregroundStyle(isActive ? Color.rbFg1 : Color.rbFg2)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: RBRadius.sm)
                    .fill(isActive
                        ? Color.rbCitron500.opacity(isPulsing ? 0.28 : 0.12)
                        : Color.clear)
            )
            .overlay(alignment: .leading) {
                if isActive {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.rbCitron500)
                        .frame(width: 2)
                        .padding(.vertical, 6)
                }
            }
            .animation(.easeOut(duration: 0.18), value: isPulsing)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    // MARK: - All Accounts row

    private var allAccountsRow: some View {
        let isActive: Bool = {
            if case .allAccountsAllFolders = selection { return true }
            if case .folder = selection { return false }
            return false
        }()
        let isPulsing: Bool = {
            if case .allAccountsAllFolders = jumpPulse { return true }
            return false
        }()
        return Button {
            selection = .allAccountsAllFolders
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "person.2")
                    .font(.system(size: 12))
                    .frame(width: 16)
                Text(String(localized: "sidebar.allAccounts", defaultValue: "All Accounts"))
                    .font(.rbGeist(12))
                    .foregroundStyle(isActive ? Color.rbFg1 : Color.rbFg2)
                    .lineLimit(1)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: RBRadius.sm)
                    .fill(isActive ? Color.rbCobalt400.opacity(isPulsing ? 0.28 : 0.12) : Color.clear)
            )
            .animation(.easeOut(duration: 0.18), value: isPulsing)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    // MARK: - Account row

    private func accountRow(_ account: AccountRow) -> some View {
        let isActive: Bool = {
            if case .account(let aid) = selection { return aid == account.id }
            return false
        }()
        return Button {
            selection = .account(account.id)
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(account.dotColor)
                    .frame(width: 8, height: 8)
                Text(account.email)
                    .font(.rbGeist(12))
                    .foregroundStyle(isActive ? Color.rbFg1 : Color.rbFg2)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: RBRadius.sm)
                    .fill(isActive
                        ? Color.rbCobalt400.opacity(0.12)
                        : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.rbStroke1)
                .frame(height: 1)
            HStack {
                LocalAIPill()
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
        }
    }
}

#if DEBUG
#Preview("RBSidebar – Dark") {
    RBSidebar(
        folders: FolderItem.defaultFolders.enumerated().map { idx, f in
            var folder = f
            if idx == 0 { folder.count = 12 }
            if idx == 1 { folder.count = 4 }
            if idx == 2 { folder.count = 3 }
            return folder
        },
        accounts: [
            AccountRow(id: "g1", email: "alex@studio.eu", dotColor: .rbCobalt400),
            AccountRow(id: "m1", email: "a.chen@partners.io", dotColor: .rbViolet500),
        ],
        selection: .constant(.folder(.inbox)),
        jumpPulse: nil
    )
    .background(Color.rbBgDeep)
    .preferredColorScheme(.dark)
}

#Preview("RBSidebar – Light") {
    RBSidebar(
        folders: FolderItem.defaultFolders.enumerated().map { idx, f in
            var folder = f
            if idx == 0 { folder.count = 12 }
            return folder
        },
        accounts: [
            AccountRow(id: "g1", email: "alex@studio.eu", dotColor: .rbCobalt400),
        ],
        selection: .constant(.folder(.inbox)),
        jumpPulse: nil
    )
    .background(Color.rbBgDeep)
    .preferredColorScheme(.light)
}
#endif
