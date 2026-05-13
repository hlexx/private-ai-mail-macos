import SwiftUI

struct AddGmailFlow: View {
    let phase: AddAccountPhase
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        switch phase {
        case .idle:
            EmptyView()
        case .authorizing:
            phaseView(
                systemImage: "globe",
                title: String(localized: "addgmail.authorizing.title", defaultValue: "Authorizing"),
                subtitle: String(localized: "addgmail.authorizing.subtitle", defaultValue: "Complete the sign-in in your browser."),
                showProgress: true
            )
        case .fetchingProfile:
            phaseView(
                systemImage: "person.crop.circle",
                title: String(localized: "addgmail.fetching.title", defaultValue: "Fetching Profile"),
                subtitle: String(localized: "addgmail.fetching.subtitle", defaultValue: "Getting your account information..."),
                showProgress: true
            )
        case .bootstrapping(let progress):
            VStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                Text(String(localized: "addgmail.syncing.title", defaultValue: "Syncing"))
                    .font(.headline)
                ProgressView(value: progress)
                    .frame(width: 200)
                Text(String(localized: "addgmail.syncing.subtitle", defaultValue: "Downloading your recent messages..."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding()
        case .done:
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.green)
                Text(String(localized: "addgmail.done.title", defaultValue: "Account Added"))
                    .font(.headline)
                Button(String(localized: "addgmail.done.dismiss", defaultValue: "Done")) {
                    onDismiss()
                }
            }
            .padding()
        case .error(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.red)
                Text(String(localized: "addgmail.error.title", defaultValue: "Something went wrong"))
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                HStack(spacing: 12) {
                    Button(String(localized: "addgmail.error.retry", defaultValue: "Try Again")) {
                        onRetry()
                    }
                    Button(String(localized: "addgmail.error.dismiss", defaultValue: "Cancel")) {
                        onDismiss()
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding()
        }
    }

    private func phaseView(
        systemImage: String,
        title: String,
        subtitle: String,
        showProgress: Bool
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.tint)
            Text(title)
                .font(.headline)
            if showProgress {
                ProgressView()
            }
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
