import DesignSystem
import SwiftUI

struct AIOnboardingScene: View {
    let modelController: AIModelController

    var body: some View {
        if modelController.isInstalling || modelController.installErrorMessage != nil {
            ModelSetupScene(
                modelController: modelController,
                completeOnboardingBeforeInstall: false
            )
        } else {
            choiceView
        }
    }

    private var choiceView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: RBSpace.s6) {
                Text("Re:")
                    .font(.rbSerifItalic(52))
                    .foregroundStyle(Color.rbCitron500)

                VStack(alignment: .leading, spacing: RBSpace.s3) {
                    Text("LOCAL AI IS OPTIONAL")
                        .rbTextStyle(.eyebrow)
                        .foregroundStyle(Color.rbFg3)

                    Text("Download the local AI model?")
                        .rbTextStyle(.h1)
                        .foregroundStyle(Color.rbFg1)

                    Text("Re:Box can run briefs, reply drafts, and attachment summaries on this Mac. The first download is about 3.6 GB, so it can take a while. After it is cached, AI works offline and your mailbox content is not sent to a cloud AI service for these features.")
                        .rbTextStyle(.bodyLG)
                        .foregroundStyle(Color.rbFg2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: RBSpace.s3) {
                    benefitRow(icon: "lock.shield", title: "Private by default", detail: "The AI model and local index stay on this Mac.")
                    benefitRow(icon: "bolt", title: "Useful when you live in email", detail: "Generate local thread briefs, reply drafts, and attachment summaries.")
                    benefitRow(icon: "clock", title: "One-time wait", detail: "The large download only happens before local AI is first used.")
                }

                HStack(spacing: RBSpace.s3) {
                    Button {
                        modelController.startInstall(completeOnboardingImmediately: false)
                    } label: {
                        Label("Enable AI and download model", systemImage: "sparkles")
                    }
                    .buttonStyle(.rbPrimary)

                    Button {
                        modelController.continueWithoutAI()
                    } label: {
                        Text("Continue without AI")
                    }
                    .buttonStyle(.rbSecondary)
                }
            }
            .frame(maxWidth: 560, alignment: .leading)

            Spacer()
        }
        .padding(RBSpace.s8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.rbBgDeep)
    }

    private func benefitRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: RBSpace.s3) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.rbCitron500)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: RBSpace.s1) {
                Text(title)
                    .rbTextStyle(.bodySM)
                    .foregroundStyle(Color.rbFg1)
                Text(detail)
                    .rbTextStyle(.bodySM)
                    .foregroundStyle(Color.rbFg3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
