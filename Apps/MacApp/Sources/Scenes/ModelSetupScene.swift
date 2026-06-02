import DesignSystem
import SwiftUI

struct ModelSetupScene: View {

    let modelController: AIModelController
    var completeOnboardingBeforeInstall = true

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: RBSpace.s6) {
                // Serif "Re:" mark
                Text("Re:")
                    .font(.rbSerifItalic(48))
                    .foregroundStyle(Color.rbCitron500)

                // Eyebrow
                Text("SETTING UP LOCAL AI · ONE-TIME · ~3.6 GB")
                    .rbTextStyle(.eyebrow)
                    .foregroundStyle(Color.rbFg3)

                if let error = modelController.installErrorMessage {
                    errorView(error)
                } else {
                    progressView
                }
            }
            .frame(maxWidth: 400)

            Spacer()

            Button(action: modelController.continueWithoutAI) {
                Text("Continue without AI")
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
            if modelController.installErrorMessage == nil {
                modelController.startInstall(
                    completeOnboardingImmediately: completeOnboardingBeforeInstall
                )
            }
        }
    }

    private var progressView: some View {
        VStack(spacing: RBSpace.s3) {
            ProgressView(value: modelController.downloadFraction)
                .tint(Color.rbCitron500)
                .progressViewStyle(.linear)

            Text(modelController.byteCountLabel)
                .rbTextStyle(.mono)
                .foregroundStyle(Color.rbFg3)

            Text("The model stays on this Mac and powers briefs, reply drafts, and attachment summaries without sending mailbox content to a cloud AI service.")
                .rbTextStyle(.bodySM)
                .foregroundStyle(Color.rbFg3)
                .multilineTextAlignment(.center)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: RBSpace.s3) {
            Text(message)
                .rbTextStyle(.bodySM)
                .foregroundStyle(Color.rbToneCoral400)
                .multilineTextAlignment(.center)

            Button(
                action: {
                    modelController.startInstall(
                        completeOnboardingImmediately: completeOnboardingBeforeInstall
                    )
                },
                label: {
                    Text("Retry")
                        .rbTextStyle(.bodySM)
                        .foregroundStyle(Color.rbCitron500)
                        .padding(.horizontal, RBSpace.s4)
                        .padding(.vertical, RBSpace.s2)
                }
            )
            .buttonStyle(.plain)
        }
    }
}
