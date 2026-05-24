import AppKit
import DesignSystem
import SwiftUI

enum AppStartupState {
    case ready(id: UUID, CompositionRoot)
    case failed(id: UUID, AppStartupFailure)

    @MainActor
    static func bootstrap() -> AppStartupState {
        do {
            return .ready(id: UUID(), try CompositionRoot())
        } catch {
            return .failed(
                id: UUID(),
                AppStartupFailure(
                    dbPath: CompositionRoot.defaultDBPath(),
                    underlyingDescription: describe(error)
                )
            )
        }
    }

    var id: UUID {
        switch self {
        case .ready(let id, _), .failed(let id, _):
            return id
        }
    }

    var composition: CompositionRoot? {
        if case .ready(_, let composition) = self {
            return composition
        }
        return nil
    }

    var failure: AppStartupFailure? {
        if case .failed(_, let failure) = self {
            return failure
        }
        return nil
    }

    private static func describe(_ error: any Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription {
            return localized
        }
        return String(describing: error)
    }
}

struct AppStartupFailure: Sendable {
    let dbPath: String
    let underlyingDescription: String
}

struct StartupRecoveryScene: View {
    let failure: AppStartupFailure
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: RBSpace.s4) {
            VStack(alignment: .leading, spacing: RBSpace.s2) {
                Text(String(localized: "startup.failed.title", defaultValue: "Private AI Mail could not start"))
                    .rbTextStyle(.h2)
                    .foregroundStyle(Color.rbFg1)
                Text(failure.underlyingDescription)
                    .rbTextStyle(.body)
                    .foregroundStyle(Color.rbFg2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: RBSpace.s1) {
                Text(String(localized: "startup.failed.database", defaultValue: "Database"))
                    .rbTextStyle(.bodySM)
                    .foregroundStyle(Color.rbFg3)
                Text(failure.dbPath)
                    .font(.rbMono(12))
                    .foregroundStyle(Color.rbFg2)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            HStack(spacing: RBSpace.s2) {
                Button(String(localized: "startup.failed.retry", defaultValue: "Retry")) {
                    onRetry()
                }
                .buttonStyle(.rbPrimary)

                Button(String(localized: "startup.failed.reveal", defaultValue: "Reveal in Finder")) {
                    revealDatabase()
                }
                .buttonStyle(.rbSecondary)

                Spacer()

                Button(String(localized: "startup.failed.quit", defaultValue: "Quit")) {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.rbGhost)
            }
        }
        .padding(RBSpace.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(Color.rbBgCanvas)
    }

    private func revealDatabase() {
        let url = URL(fileURLWithPath: failure.dbPath)
        if FileManager.default.fileExists(atPath: failure.dbPath) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }
}
