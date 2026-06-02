import BriefFeature
import DesignSystem
import SwiftUI

struct AITab: View {
    let queue: BriefBackgroundQueue
    let modelController: AIModelController

    var body: some View {
        Form {
            Section {
                Toggle(
                    String(localized: "settings.ai.enableLocalAI", defaultValue: "Enable local AI"),
                    isOn: Binding(
                        get: { modelController.isAIEnabled },
                        set: { enabled in
                            if enabled {
                                modelController.enableAI()
                            } else {
                                modelController.disableAI()
                            }
                        }
                    )
                )

                LabeledContent(
                    String(localized: "settings.ai.modelStatus", defaultValue: "Model")
                ) {
                    Text(modelStatus)
                        .foregroundStyle(modelController.isAIReady ? .primary : .secondary)
                }

                if !modelController.isModelInstalled {
                    modelDownloadControl
                }

                if let error = modelController.installErrorMessage {
                    Text(error)
                        .foregroundStyle(Color.rbToneCoral400)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text(String(localized: "settings.ai.localAI.header", defaultValue: "Local AI"))
            } footer: {
                Text(String(
                    localized: "settings.ai.localAI.footer",
                    defaultValue: "Local AI runs briefs, reply drafts, and attachment summaries on this Mac. The first model download is about 3.6 GB."
                ))
            }

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
            } footer: {
                if !modelController.isAIReady {
                    Text(String(
                        localized: "settings.ai.backgroundBriefs.disabled",
                        defaultValue: "Background brief generation starts after local AI is enabled and the model is installed."
                    ))
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
            await modelController.refreshInstalledStatus()
        }
    }

    private var modelStatus: String {
        if modelController.isModelInstalled && modelController.isAIEnabled {
            return String(localized: "settings.ai.model.ready", defaultValue: "Installed and enabled")
        }
        if modelController.isModelInstalled {
            return String(localized: "settings.ai.model.installed", defaultValue: "Installed")
        }
        if modelController.isInstalling {
            return String(localized: "settings.ai.model.downloading", defaultValue: "Downloading")
        }
        return String(localized: "settings.ai.model.missing", defaultValue: "Not downloaded")
    }

    @ViewBuilder
    private var modelDownloadControl: some View {
        if modelController.isInstalling {
            VStack(alignment: .leading, spacing: RBSpace.s2) {
                ProgressView(value: modelController.downloadFraction)
                    .progressViewStyle(.linear)
                Text(modelController.byteCountLabel)
                    .font(.rbMono(12))
                    .foregroundStyle(.secondary)
                Button(String(localized: "settings.ai.continueWithoutAI", defaultValue: "Stop and continue without AI")) {
                    modelController.continueWithoutAI()
                }
            }
        } else {
            Button {
                modelController.startInstall()
            } label: {
                Label(downloadButtonTitle, systemImage: "arrow.down.circle")
            }
        }
    }

    private var downloadButtonTitle: String {
        if modelController.isAIEnabled {
            return String(localized: "settings.ai.downloadModel", defaultValue: "Download model")
        }
        return String(localized: "settings.ai.enableAndDownload", defaultValue: "Enable AI and download model")
    }
}
