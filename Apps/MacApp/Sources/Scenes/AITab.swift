import BriefFeature
import SwiftUI

struct AITab: View {
    let queue: BriefBackgroundQueue

    var body: some View {
        Form {
            Section {
                LabeledContent(
                    String(localized: "settings.ai.backgroundBriefs", defaultValue: "Background briefs")
                ) {
                    Text("\(queue.generatedCount) / \(queue.totalCount) generated")
                        .monospacedDigit()
                }

                if queue.isRunning {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(String(localized: "settings.ai.generating", defaultValue: "Generating..."))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task {
            queue.refreshCounts()
        }
    }
}
