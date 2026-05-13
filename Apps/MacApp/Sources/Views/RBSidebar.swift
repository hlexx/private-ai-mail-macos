import DesignSystem
import Persistence
import SwiftUI

// MARK: - Model types

struct FolderItem: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    var count: Int?

    static let defaultFolders: [FolderItem] = [
        FolderItem(id: "inbox", name: String(localized: "sidebar.folder.inbox", defaultValue: "Inbox"), icon: "tray"),
        FolderItem(id: "reply", name: String(localized: "sidebar.folder.needsReply", defaultValue: "Needs reply"), icon: "arrowshape.turn.up.left"),
        FolderItem(id: "due", name: String(localized: "sidebar.folder.hasDeadline", defaultValue: "Has deadline"), icon: "clock"),
        FolderItem(id: "att", name: String(localized: "sidebar.folder.attachments", defaultValue: "Attachments"), icon: "paperclip"),
        FolderItem(id: "logged", name: String(localized: "sidebar.folder.logged", defaultValue: "Logged"), icon: "checkmark.circle"),
        FolderItem(id: "starred", name: String(localized: "sidebar.folder.starred", defaultValue: "Starred"), icon: "star"),
        FolderItem(id: "sent", name: String(localized: "sidebar.folder.sent", defaultValue: "Sent"), icon: "paperplane"),
        FolderItem(id: "arch", name: String(localized: "sidebar.folder.archive", defaultValue: "Archive"), icon: "archivebox"),
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
        let hash = abs(id.hashValue)
        return palette[hash % palette.count]
    }
}

// MARK: - RBSidebar

struct RBSidebar: View {
    let folders: [FolderItem]
    let accounts: [AccountRow]
    @Binding var activeFolder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeader(String(localized: "sidebar.section.mail", defaultValue: "Mail"))

                    ForEach(folders) { folder in
                        folderRow(folder)
                    }

                    sectionHeader(String(localized: "sidebar.section.accounts", defaultValue: "Accounts"))
                        .padding(.top, RBSpace.s2)

                    ForEach(accounts) { account in
                        accountRow(account)
                    }

                    sectionHeader(String(localized: "sidebar.section.privacy", defaultValue: "Privacy"))
                        .padding(.top, RBSpace.s2)
                }
                .padding(.horizontal, RBSpace.s2)
                .padding(.vertical, RBSpace.s3)
            }

            Spacer(minLength: 0)

            footer
        }
        .frame(width: 240)
        .background(Color.clear)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.rbStroke1)
                .frame(width: 1)
        }
    }

    // MARK: - Section header

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.rbMono(10, weight: .medium))
            .tracking(0.14 * 10)
            .foregroundStyle(Color.rbFg3)
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 6)
    }

    // MARK: - Folder row

    private func folderRow(_ folder: FolderItem) -> some View {
        let isActive = folder.id == activeFolder
        return Button {
            activeFolder = folder.id
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
                        ? Color.rbCitron500.opacity(0.12).blended(with: Color.rbBgElev1)
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
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    // MARK: - Account row

    private func accountRow(_ account: AccountRow) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(account.dotColor)
                .frame(width: 8, height: 8)
            Text(account.email)
                .font(.rbGeist(12))
                .foregroundStyle(Color.rbFg2)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
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

// MARK: - Color blending helper

private extension Color {
    func blended(with other: Color) -> Color {
        // Approximate color-mix: overlay self on top of other
        // For simplicity, just return self since SwiftUI doesn't have native color-mix
        // The background handles the visual mixing
        self
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
        activeFolder: .constant("inbox")
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
        activeFolder: .constant("inbox")
    )
    .background(Color.rbBgDeep)
    .preferredColorScheme(.light)
}
#endif
