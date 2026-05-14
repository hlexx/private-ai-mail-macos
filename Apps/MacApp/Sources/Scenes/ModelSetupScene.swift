import AIRuntime
import DesignSystem
import SwiftUI

struct ModelSetupScene: View {

    let modelManager: ModelManager
    let onComplete: () -> Void

    @State private var fraction: Double = 0
    @State private var bytesDownloaded: Int64 = 0
    @State private var totalBytes: Int64 = 0
    @State private var error: String?
    @State private var isDownloading = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: RBSpace.s6) {
                // Serif "Re:" mark
                Text("Re:")
                    .font(.rbSerifItalic(48))
                    .foregroundStyle(Color.rbCitron500)

                // Eyebrow
                Text("SETTING UP LOCAL AI · ONE-TIME")
                    .rbTextStyle(.eyebrow)
                    .foregroundStyle(Color.rbFg3)

                if let error {
                    errorView(error)
                } else {
                    progressView
                }
            }
            .frame(maxWidth: 400)

            Spacer()

            // Cancel button
            Button(action: cancelAndQuit) {
                Text("Cancel and quit")
                    .rbTextStyle(.bodySM)
                    .foregroundStyle(Color.rbFg3)
                    .padding(.horizontal, RBSpace.s4)
                    .padding(.vertical, RBSpace.s2)
            }
            .buttonStyle(.plain)
            .padding(.bottom, RBSpace.s8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.rbBgDeep)
        .task {
            await startInstall()
        }
    }

    private var progressView: some View {
        VStack(spacing: RBSpace.s3) {
            ProgressView(value: fraction)
                .tint(Color.rbCitron500)
                .progressViewStyle(.linear)

            Text(byteCountLabel)
                .rbTextStyle(.mono)
                .foregroundStyle(Color.rbFg3)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: RBSpace.s3) {
            Text(message)
                .rbTextStyle(.bodySM)
                .foregroundStyle(Color.rbToneCoral400)
                .multilineTextAlignment(.center)

            Button(action: { Task { await startInstall() } }) {
                Text("Retry")
                    .rbTextStyle(.bodySM)
                    .foregroundStyle(Color.rbCitron500)
                    .padding(.horizontal, RBSpace.s4)
                    .padding(.vertical, RBSpace.s2)
            }
            .buttonStyle(.plain)
        }
    }

    private var byteCountLabel: String {
        guard totalBytes > 0 else { return "Preparing download…" }
        let downloaded = ByteCountFormatter.string(fromByteCount: bytesDownloaded, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        return "\(downloaded) / \(total)"
    }

    private func startInstall() async {
        guard !isDownloading else { return }
        isDownloading = true
        error = nil

        // Check network reachability before attempting download
        if !NetworkReachability.isReachable {
            error = "No internet — required for one-time setup"
            isDownloading = false
            return
        }

        do {
            _ = try await modelManager.install { frac, downloaded, total in
                Task { @MainActor in
                    self.fraction = frac
                    self.bytesDownloaded = downloaded
                    self.totalBytes = total
                }
            }
            onComplete()
        } catch is CancellationError {
            // User cancelled
        } catch {
            self.error = "Download failed: \(error.localizedDescription)"
            isDownloading = false
        }
    }

    private func cancelAndQuit() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Network Reachability

enum NetworkReachability {
    static var isReachable: Bool {
        let url = URL(string: "https://huggingface.co")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.httpMethod = "HEAD"
        let semaphore = DispatchSemaphore(value: 0)
        var reachable = false
        let task = URLSession.shared.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode < 500 {
                reachable = true
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 5)
        return reachable
    }
}
