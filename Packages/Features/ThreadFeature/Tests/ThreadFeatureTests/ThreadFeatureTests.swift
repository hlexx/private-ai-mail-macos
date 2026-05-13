import Testing
import SwiftUI
import AppKit
@testable import ThreadFeature
import DesignSystem

@Suite("ThreadFeature")
struct ThreadFeatureTests {
    @Test func moduleNameIsExported() {
        #expect(ThreadFeature.moduleName == "ThreadFeature")
    }

    // MARK: - MessageRow

    @Test func messageRowExtractsNameFromDisplayFormat() {
        let name = MessageRow.extractName(from: "Marta Kowalski <marta@example.com>")
        #expect(name == "Marta Kowalski")
    }

    @Test func messageRowExtractsNameFromBareEmail() {
        let name = MessageRow.extractName(from: "alex@studio.eu")
        #expect(name == "alex")
    }

    @Test func messageRowExtractsNameFromEmptyString() {
        let name = MessageRow.extractName(from: "")
        #expect(name == "?")
    }

    @Test func messageRowExtractsNameWithQuotes() {
        let name = MessageRow.extractName(from: "\"Jonas R.\" <jonas@example.com>")
        #expect(name == "Jonas R.")
    }

    // MARK: - AttachmentInfo

    @Test func attachmentFormattedSizeKB() {
        let info = AttachmentInfo(id: "a1", filename: "test.pdf", sizeBytes: 284_000, mime: "application/pdf")
        #expect(info.formattedSize == "277 KB")
    }

    @Test func attachmentFormattedSizeMB() {
        let info = AttachmentInfo(id: "a2", filename: "large.zip", sizeBytes: 2_500_000, mime: nil)
        #expect(info.formattedSize == "2.4 MB")
    }

    @Test func attachmentFormattedSizeNil() {
        let info = AttachmentInfo(id: "a3", filename: "unknown", sizeBytes: nil, mime: nil)
        #expect(info.formattedSize == "")
    }
}

// MARK: - Snapshot Tests

@Suite("ThreadView Snapshots")
struct ThreadViewSnapshotTests {

    @MainActor
    @Test func emptyStateDark() {
        let view = emptyStateView()
            .preferredColorScheme(.dark)
            .frame(width: 700, height: 500)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 700, height: 500)
        host.layout()
    }

    @MainActor
    @Test func emptyStateLight() {
        let view = emptyStateView()
            .preferredColorScheme(.light)
            .frame(width: 700, height: 500)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 700, height: 500)
        host.layout()
    }

    @MainActor
    @Test func messageCardDark() {
        let view = messageCardView()
            .preferredColorScheme(.dark)
            .frame(width: 600, height: 200)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 200)
        host.layout()
    }

    @MainActor
    @Test func messageCardLight() {
        let view = messageCardView()
            .preferredColorScheme(.light)
            .frame(width: 600, height: 200)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 200)
        host.layout()
    }

    @MainActor
    @Test func attachmentBlockDark() {
        let view = attachmentBlockView()
            .preferredColorScheme(.dark)
            .frame(width: 600, height: 100)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 100)
        host.layout()
    }

    @MainActor
    @Test func attachmentBlockLight() {
        let view = attachmentBlockView()
            .preferredColorScheme(.light)
            .frame(width: 600, height: 100)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 100)
        host.layout()
    }

    @MainActor
    @Test func headSectionDark() {
        let view = headSectionView()
            .preferredColorScheme(.dark)
            .frame(width: 600, height: 140)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 140)
        host.layout()
    }

    @MainActor
    @Test func headSectionLight() {
        let view = headSectionView()
            .preferredColorScheme(.light)
            .frame(width: 600, height: 140)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 140)
        host.layout()
    }

    private func emptyStateView() -> some View {
        VStack(spacing: 8) {
            Text("Re:")
                .font(.rbSerifItalic(48))
                .foregroundStyle(Color.rbFg3)
            Text("Select a thread")
                .rbTextStyle(.h3)
                .foregroundStyle(Color.rbFg1)
            Text("Re:Box will brief you the moment you open it.")
                .rbTextStyle(.body)
                .foregroundStyle(Color.rbFg3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.rbBgCanvas)
    }

    private func messageCardView() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                AvatarView(name: "Marta Kowalski", size: 28)
                Text("Marta Kowalski")
                    .font(.rbGeist(13, weight: .semibold))
                    .foregroundStyle(Color.rbFg1)
                Spacer()
                Text("Mon 14:30")
                    .font(.rbMono(11))
                    .foregroundStyle(Color.rbFg3)
            }
            Text("Hi — yes, I'll send a clean draft by Friday EOD.")
                .font(.rbGeist(14))
                .foregroundStyle(Color.rbFg2)
                .lineSpacing(4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.rbBgElev1)
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: RBRadius.md)
                .strokeBorder(Color.rbStroke1, lineWidth: 1)
        )
        .padding(20)
        .background(Color.rbBgCanvas)
    }

    private func attachmentBlockView() -> some View {
        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: RBRadius.xs)
                .fill(Color.rbBgElev2)
                .frame(width: 38, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("contract.pdf")
                    .font(.rbGeist(13, weight: .medium))
                    .foregroundStyle(Color.rbFg1)
                Text("277 KB · summarized locally")
                    .font(.rbMono(11))
                    .foregroundStyle(Color.rbFg3)
            }
            Spacer()
            Button("Preview") {}
                .buttonStyle(.rbGhost)
            Button("Summarize") {}
                .buttonStyle(.rbSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.rbBgElev1)
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.md))
        .padding(20)
        .background(Color.rbBgCanvas)
    }

    private func headSectionView() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Re: Contract approval — Acme GmbH")
                .rbTextStyle(.h2)
                .foregroundStyle(Color.rbFg1)
            HStack(spacing: 8) {
                Text("Marta Kowalski").foregroundStyle(Color.rbFg2)
                Text("·").foregroundStyle(Color.rbFg3)
                Text("to alex@studio.eu").foregroundStyle(Color.rbFg2)
                Text("·").foregroundStyle(Color.rbFg3)
                Text("3 messages").foregroundStyle(Color.rbFg2)
            }
            .font(.rbMono(11))
            HStack(spacing: 8) {
                Spacer()
                Button {} label: { Label("Archive", systemImage: "archivebox") }.buttonStyle(.rbGhost)
                Button {} label: { Label("Snooze", systemImage: "clock") }.buttonStyle(.rbGhost)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .background(Color.rbBgCanvas)
    }
}
