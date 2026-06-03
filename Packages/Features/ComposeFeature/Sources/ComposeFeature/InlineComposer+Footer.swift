import DesignSystem
import SwiftUI

extension InlineComposer {
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

    func statusStrip(
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

    var footerRow: some View {
        HStack {
            citationsLine
            Spacer()
            ctaButtons
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.rbBgCanvas)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.rbStroke1)
                .frame(height: 1)
        }
    }

    var citationsLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11))
            if let reply = replyStore.reply, !reply.evidenceMessageIDs.isEmpty {
                Text("\(reply.evidenceMessageIDs.count) citations \u{00B7} \(reply.evidenceMessageIDs.joined(separator: " \u{00B7} "))")
            } else {
                Text("On-device AI")
            }
        }
        .font(.rbMono(10.5))
        .foregroundStyle(Color.rbFg3)
    }

    var ctaButtons: some View {
        GeometryReader { geo in
            let narrow = geo.size.width < 400
            HStack(spacing: RBSpace.s2) {
                Spacer(minLength: 0)

                if draftGenerationRequested || replyStore.reply != nil || replyStore.isLoading {
                    Button {
                        requestDraftGeneration(force: true)
                    } label: {
                        Label(String(localized: "composer.cta.regenerate", defaultValue: "Regenerate"), systemImage: "sparkle")
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .buttonStyle(.rbGhost)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if narrow {
                    Button {
                        onEditInFull(draftText)
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.rbSecondary)
                    .help(String(localized: "composer.cta.editInFull", defaultValue: "Edit in full"))
                    .disabled(!canSubmitDraft)
                } else {
                    Button {
                        onEditInFull(draftText)
                    } label: {
                        Text(String(localized: "composer.cta.editInFull", defaultValue: "Edit in full"))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .buttonStyle(.rbSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .disabled(!canSubmitDraft)
                }

                Button {
                    onSend(draftText)
                } label: {
                    Label(String(localized: "composer.cta.send", defaultValue: "Send"), systemImage: "paperplane.fill")
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .buttonStyle(.rbPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .disabled(!canSubmitDraft || !sendState.allowsNewSendRequest)
                .keyboardShortcut(.return, modifiers: [.command])
                .help("Send (⌘⏎)")
            }
        }
        .frame(height: 32)
    }

    var canSubmitDraft: Bool {
        !replyStore.isLoading
            && replyStore.error == nil
            && ReplyStore.isDisplayableDraft(draftText)
    }
}
