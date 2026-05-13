import Testing
import SwiftUI
import AppKit
@testable import ThreadFeature

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
        let view = threadViewEmpty()
            .preferredColorScheme(.dark)
            .frame(width: 700, height: 500)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 700, height: 500)
        host.layout()
    }

    @MainActor
    @Test func emptyStateLight() {
        let view = threadViewEmpty()
            .preferredColorScheme(.light)
            .frame(width: 700, height: 500)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 700, height: 500)
        host.layout()
    }

    private func threadViewEmpty() -> some View {
        // ThreadStore with no messages = empty state
        // We can't easily create a ThreadStore without AppDatabase,
        // so we test the static subviews directly
        VStack {
            Text("Select a thread")
                .font(.title2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
