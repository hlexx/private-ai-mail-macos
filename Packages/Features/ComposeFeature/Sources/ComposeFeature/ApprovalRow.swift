import DesignSystem
import SwiftUI

public struct ApprovalRow: View {

    let recipientCount: Int
    let accountEmail: String
    let sendState: ComposeSendState
    let onCancel: () -> Void
    let onConfirmNow: () -> Void
    let onRetrySend: () -> Void
    let onReauthorize: () -> Void

    public init(
        recipientCount: Int,
        accountEmail: String,
        sendState: ComposeSendState,
        onCancel: @escaping () -> Void,
        onConfirmNow: @escaping () -> Void,
        onRetrySend: @escaping () -> Void,
        onReauthorize: @escaping () -> Void = {}
    ) {
        self.recipientCount = recipientCount
        self.accountEmail = accountEmail
        self.sendState = sendState
        self.onCancel = onCancel
        self.onConfirmNow = onConfirmNow
        self.onRetrySend = onRetrySend
        self.onReauthorize = onReauthorize
    }

    public var body: some View {
        switch sendState {
        case .idle:
            EmptyView()

        case .awaitingApproval(let deadline):
            approvalBar(deadline: deadline)
                .transition(.move(edge: .bottom).combined(with: .opacity))

        case .pending:
            queueBar(
                icon: "tray.and.arrow.up.fill",
                title: String(localized: "approval.pending", defaultValue: "Queued locally"),
                actionTitle: nil,
                action: nil
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))

        case .sending:
            sendingBar
                .transition(.move(edge: .bottom).combined(with: .opacity))

        case .retrying:
            queueBar(
                icon: "clock.arrow.circlepath",
                title: String(localized: "approval.retrying", defaultValue: "Retry scheduled"),
                actionTitle: String(localized: "approval.retryNow", defaultValue: "Retry now"),
                action: onRetrySend
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))

        case .needsReconsent:
            needsReconsentBar
                .transition(.move(edge: .bottom).combined(with: .opacity))

        case .sent:
            sentBar
                .transition(.move(edge: .bottom).combined(with: .opacity))

        case .failed(let error):
            failedBar(error: error)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Awaiting Approval

    private func approvalBar(deadline: Date) -> some View {
        HStack(spacing: RBSpace.s3) {
            Label {
                Text("Send to \(recipientCount) recipient(s) on \(accountEmail)")
                    .rbTextStyle(.bodySM)
                    .foregroundStyle(Color.rbFg1)
            } icon: {
                Image(systemName: "paperplane.fill")
                    .foregroundStyle(Color.rbAccent)
            }

            Spacer()

            CountdownText(deadline: deadline)

            Button(String(localized: "approval.cancel", defaultValue: "Cancel"), action: onCancel)
                .buttonStyle(.rbGhost)

            Button(String(localized: "approval.sendNow", defaultValue: "Send now"), action: onConfirmNow)
                .buttonStyle(.rbPrimary)
        }
        .padding(.horizontal, RBSpace.s5)
        .padding(.vertical, RBSpace.s3)
        .background(Color.rbAccentSoft)
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.sm))
    }

    // MARK: - Sending

    private var sendingBar: some View {
        HStack(spacing: RBSpace.s3) {
            ProgressView()
                .controlSize(.small)
            Text(String(localized: "approval.sending", defaultValue: "Sending\u{2026}"))
                .rbTextStyle(.bodySM)
                .foregroundStyle(Color.rbFg2)
            Spacer()
            Button(String(localized: "approval.cancel", defaultValue: "Cancel"), action: onCancel)
                .buttonStyle(.rbGhost)
        }
        .padding(.horizontal, RBSpace.s5)
        .padding(.vertical, RBSpace.s3)
        .background(Color.rbBgElev1)
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.sm))
    }

    private func queueBar(icon: String, title: String, actionTitle: String?, action: (() -> Void)?) -> some View {
        HStack(spacing: RBSpace.s3) {
            Image(systemName: icon)
                .foregroundStyle(Color.rbAccent)
            Text(title)
                .rbTextStyle(.bodySM)
                .foregroundStyle(Color.rbFg2)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.rbPrimary)
            }
            Button(String(localized: "approval.cancel", defaultValue: "Cancel"), action: onCancel)
                .buttonStyle(.rbGhost)
        }
        .padding(.horizontal, RBSpace.s5)
        .padding(.vertical, RBSpace.s3)
        .background(Color.rbBgElev1)
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.sm))
    }

    private var needsReconsentBar: some View {
        HStack(spacing: RBSpace.s3) {
            Image(systemName: "person.badge.key.fill")
                .foregroundStyle(Color.rbSignalDeadline)
            Text(Self.errorMessage(.needsReconsent))
                .rbTextStyle(.bodySM)
                .foregroundStyle(Color.rbFg1)
            Spacer()
            Button(String(localized: "approval.reauthorize", defaultValue: "Re-authorize"), action: onReauthorize)
                .buttonStyle(.rbPrimary)
            Button(String(localized: "approval.cancel", defaultValue: "Cancel"), action: onCancel)
                .buttonStyle(.rbGhost)
        }
        .padding(.horizontal, RBSpace.s5)
        .padding(.vertical, RBSpace.s3)
        .background(Color.rbSignalDeadlineBg)
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.sm))
    }

    private var sentBar: some View {
        HStack(spacing: RBSpace.s3) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.rbSignalSuccess)
            Text(String(localized: "approval.sent", defaultValue: "Sent"))
                .rbTextStyle(.bodySM)
                .foregroundStyle(Color.rbFg1)
            Spacer()
        }
        .padding(.horizontal, RBSpace.s5)
        .padding(.vertical, RBSpace.s3)
        .background(Color.rbBgElev1)
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.sm))
    }

    // MARK: - Failed

    private func failedBar(error: ComposeError) -> some View {
        HStack(spacing: RBSpace.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.rbSignalDeadline)

            Text(Self.errorMessage(error))
                .rbTextStyle(.bodySM)
                .foregroundStyle(Color.rbFg1)

            Spacer()

            if case .needsReconsent = error {
                Button(String(localized: "approval.reauthorize", defaultValue: "Re-authorize"), action: onReauthorize)
                    .buttonStyle(.rbPrimary)
            } else {
                Button(String(localized: "approval.retry", defaultValue: "Retry"), action: onRetrySend)
                    .buttonStyle(.rbPrimary)
            }

            Button(String(localized: "approval.cancel", defaultValue: "Cancel"), action: onCancel)
                .buttonStyle(.rbGhost)
        }
        .padding(.horizontal, RBSpace.s5)
        .padding(.vertical, RBSpace.s3)
        .background(Color.rbSignalDeadlineBg)
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.sm))
    }

    static func errorMessage(_ error: ComposeError) -> String {
        switch error {
        case .noRecipients:
            return String(localized: "approval.error.noRecipients", defaultValue: "No recipients specified")
        case .noAccount:
            return String(localized: "approval.error.noAccount", defaultValue: "No sending account selected")
        case .needsReconsent:
            return String(localized: "approval.error.needsReconsent", defaultValue: "This account hasn\u{2019}t granted send permission yet \u{2014} Re-authorize")
        case .send:
            return String(localized: "approval.error.generic", defaultValue: "Failed to send message. Please try again.")
        }
    }
}

// MARK: - Countdown Text

struct CountdownText: View {
    let deadline: Date

    @State private var remaining: Int = 5

    var body: some View {
        Text("\(remaining)s")
            .rbTextStyle(.bodySM)
            .foregroundStyle(Color.rbFg3)
            .monospacedDigit()
            .onAppear { updateRemaining() }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(0.5))
                    updateRemaining()
                }
            }
    }

    private func updateRemaining() {
        remaining = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
    }
}
