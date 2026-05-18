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

            Section(
                String(localized: "settings.ai.howItWorks", defaultValue: "How it works")
            ) {
                LabeledContent(
                    String(localized: "settings.ai.briefReply", defaultValue: "Brief + Reply")
                ) {
                    Text("Gemma 4 (on-device, MLX)")
                        .foregroundStyle(.secondary)
                }
                LabeledContent(
                    String(localized: "settings.ai.translation", defaultValue: "Translation")
                ) {
                    Text("Apple Translation framework (on-device)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            queue.refreshCounts()
        }
    }
}
