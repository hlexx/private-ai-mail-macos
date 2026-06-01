import AppKit
import Foundation
import QuickLookUI

@MainActor
final class AttachmentQuickLookPresenter: NSObject, QLPreviewPanelDataSource {
    static let shared = AttachmentQuickLookPresenter()

    private var previewURL: URL?

    func preview(_ url: URL) {
        previewURL = url
        let panel = QLPreviewPanel.shared()
        panel?.dataSource = self
        panel?.reloadData()
        panel?.makeKeyAndOrderFront(nil)
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated {
            previewURL == nil ? 0 : 1
        }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated {
            previewURL as NSURL?
        }
    }
}
