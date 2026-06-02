import DesignSystem
import SwiftUI

struct AIUnavailableRail: View {
    let modelController: AIModelController
    let openSettings: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RBSpace.s3) {
                HStack {
                    EyebrowLabel("Re:Box brief")
                    Spacer()
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.rbFg3)
                }

                Text(title)
                    .font(.rbGeist(15, weight: .medium))
                    .foregroundStyle(Color.rbFg1)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detail)
                    .rbTextStyle(.bodySM)
                    .foregroundStyle(Color.rbFg3)
                    .fixedSize(horizontal: false, vertical: true)

                if modelController.isInstalling {
                    ProgressView(value: modelController.downloadFraction)
                        .progressViewStyle(.linear)
                    Text(modelController.byteCountLabel)
                        .font(.rbMono(12))
                        .foregroundStyle(Color.rbFg3)
                } else {
                    HStack(spacing: RBSpace.s2) {
                        Button {
                            openSettings()
                        } label: {
                            Label("AI settings", systemImage: "gearshape")
                        }
                        .buttonStyle(.rbSecondary)

                        if !modelController.isModelInstalled {
                            Button {
                                modelController.startInstall()
                            } label: {
                                Label("Download model", systemImage: "arrow.down.circle")
                            }
                            .buttonStyle(.rbGhost)
                        }
                    }
                }
            }
            .padding(16)
            .background(Color.rbBgElev1)
            .clipShape(RoundedRectangle(cornerRadius: RBRadius.lg))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .background(Color.rbBgCanvas)
    }

    private var title: String {
        if modelController.isAIEnabled {
            return "Local AI model is not installed"
        }
        return "Local AI is off"
    }

    private var detail: String {
        if modelController.isAIEnabled {
            return "Download the model to enable local briefs, reply drafts, and attachment summaries."
        }
        return "Email sync, search, compose, and account workflows keep working. Enable local AI later from Settings."
    }
}
