import DesignSystem
import SwiftUI

extension InlineComposer {
    // MARK: - Send Status

    @ViewBuilder
    var inlineSendStatus: some View {
        switch sendState {
        case .idle:
            EmptyView()
        case .awaitingApproval:
            statusStrip(
                icon: "paperplane.fill",
                text: String(localized: "composer.send.awaiting", defaultValue: "Ready to send"),
                primaryTitle: String(localized: "approval.sendNow", defaultValue: "Send now"),
                primaryAction: onConfirmSendNow,
                secondaryTitle: String(localized: "approval.cancel", defaultValue: "Cancel"),
                secondaryAction: onCancelSend
            )
        case .pending:
            statusStrip(
                icon: "tray.and.arrow.up.fill",
                text: String(localized: "composer.send.pending", defaultValue: "Queued locally"),
                primaryTitle: nil,
                primaryAction: nil,
                secondaryTitle: String(localized: "approval.cancel", defaultValue: "Cancel"),
                secondaryAction: onCancelSend
            )
        case .sending:
            statusStrip(
                icon: "paperplane.fill",
                text: String(localized: "approval.sending", defaultValue: "Sending\u{2026}"),
                primaryTitle: nil,
                primaryAction: nil,
                secondaryTitle: String(localized: "approval.cancel", defaultValue: "Cancel"),
                secondaryAction: onCancelSend
            )
        case .retrying:
            statusStrip(
                icon: "clock.arrow.circlepath",
                text: String(localized: "composer.send.retrying", defaultValue: "Retry scheduled"),
                primaryTitle: String(localized: "approval.retryNow", defaultValue: "Retry now"),
                primaryAction: onRetrySend,
                secondaryTitle: String(localized: "approval.cancel", defaultValue: "Cancel"),
                secondaryAction: onCancelSend
            )
        case .needsReconsent:
            statusStrip(
                icon: "person.badge.key.fill",
                text: ApprovalRow.errorMessage(.needsReconsent),
                primaryTitle: String(localized: "approval.reauthorize", defaultValue: "Re-authorize"),
                primaryAction: onReauthorize,
                secondaryTitle: String(localized: "approval.cancel", defaultValue: "Cancel"),
                secondaryAction: onCancelSend
            )
        case .sent:
            statusStrip(
                icon: "checkmark.circle.fill",
                text: String(localized: "approval.sent", defaultValue: "Sent"),
                primaryTitle: nil,
                primaryAction: nil,
                secondaryTitle: nil,
                secondaryAction: nil
            )
        case .failed(let error):
            statusStrip(
                icon: "exclamationmark.triangle.fill",
                text: ApprovalRow.errorMessage(error),
                primaryTitle: String(localized: "approval.retry", defaultValue: "Retry"),
                primaryAction: onRetrySend,
                secondaryTitle: String(localized: "approval.cancel", defaultValue: "Cancel"),
                secondaryAction: onCancelSend
            )
        }
    }

    private func statusStrip(
        icon: String,
        text: String,
        primaryTitle: String?,
        primaryAction: (() -> Void)?,
        secondaryTitle: String?,
        secondaryAction: (() -> Void)?
    ) -> some View {
        HStack(spacing: RBSpace.s2) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.rbAccent)
            Text(text)
                .font(.rbGeist(12))
                .foregroundStyle(Color.rbFg2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: RBSpace.s2)
            if let primaryTitle, let primaryAction {
                Button(primaryTitle, action: primaryAction)
                    .buttonStyle(.rbPrimary)
                    .controlSize(.small)
            }
            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .buttonStyle(.rbGhost)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.rbBgElev1)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.rbStroke1)
                .frame(height: 1)
        }
    }
}
