import DesignSystem
import SwiftUI

struct InboxThreadRowView: View {
    let thread: ThreadRow
    let isActive: Bool

    private static let timeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(name: thread.senderName, size: 32)

            VStack(alignment: .leading, spacing: 3) {
                fromLine
                subjectLine
                previewLine
                chipsRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 5) {
                Text(Self.timeFormatter.localizedString(for: thread.lastMessageAt, relativeTo: .now))
                    .font(.rbMono(10.5))
                    .foregroundStyle(Color.rbFg3)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, RBSpace.s4)
        .padding(.vertical, 12)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            if isActive {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.rbCitron500)
                    .frame(width: 3)
                    .padding(.vertical, 12)
            }
        }
        .overlay(alignment: .bottom) {
            Color.rbStroke1.frame(height: 1)
        }
    }

    private var fromLine: some View {
        HStack(spacing: 0) {
            if thread.hasUnread {
                Circle()
                    .fill(Color.rbCitron500)
                    .frame(width: 6, height: 6)
                    .padding(.trailing, 6)
            }
            Text(thread.senderName)
                .font(.rbGeist(13, weight: .semibold))
                .foregroundStyle(Color.rbFg1)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(Self.extractDomain(from: thread.senderAddr))
                .font(.rbMono(10.5))
                .foregroundStyle(Color.rbFg3)
                .lineLimit(1)
        }
    }

    private var subjectLine: some View {
        Text(thread.subject)
            .font(.rbGeist(13, weight: .medium))
            .foregroundStyle(Color.rbFg1)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var previewLine: some View {
        Text(thread.snippet)
            .font(.rbGeist(12.5))
            .foregroundStyle(Color.rbFg3)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    @ViewBuilder
    private var chipsRow: some View {
        let chips = deriveChips()
        if !chips.isEmpty {
            HStack(spacing: 6) {
                ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                    SignalChip(kind: chip)
                }
            }
            .padding(.top, 4)
        }
    }

    private func deriveChips() -> [SignalChip.Kind] {
        var chips: [SignalChip.Kind] = []
        if thread.attachmentCount > 0 {
            chips.append(.att(pages: nil))
        }
        if thread.isRemoteSearchResult {
            chips.append(.ai(label: "remote"))
        }
        if thread.messageCount > 1 {
            // Show message count as a subtle indicator.
        }
        return chips
    }

    private static func extractDomain(from addr: String) -> String {
        let bare: String
        if let lt = addr.firstIndex(of: "<"), let gt = addr.firstIndex(of: ">"), lt < gt {
            bare = String(addr[addr.index(after: lt)..<gt])
        } else {
            bare = addr
        }
        return bare.split(separator: "@").last.map(String.init) ?? ""
    }

    private var rowBackground: Color {
        if isActive {
            return Color.rbCitron500.opacity(0.09)
        } else if thread.hasUnread {
            return Color.rbGraphite50.opacity(0.02)
        } else {
            return Color.clear
        }
    }
}
