import DesignSystem
import SwiftUI

public struct TrustActionOutboxStrip: View {
    private let items: [TrustActionOutboxItem]
    private let onRetry: (String) -> Void

    public init(
        items: [TrustActionOutboxItem],
        onRetry: @escaping (String) -> Void
    ) {
        self.items = items
        self.onRetry = onRetry
    }

    public var body: some View {
        if !items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items.prefix(5)) { item in
                        TrustActionStatusChip(item: item, onRetry: onRetry)
                    }
                }
                .padding(.horizontal, RBSpace.s4)
                .padding(.vertical, 8)
            }
            .background(Color.rbBgElev1)
            .overlay(alignment: .bottom) {
                Color.rbStroke1.frame(height: 1)
            }
        }
    }
}

public extension View {
    func trustActionApprovalAlert(_ actionStore: TrustActionUIStore?) -> some View {
        alert(
            actionStore?.pendingApproval?.title ?? "",
            isPresented: Binding(
                get: { actionStore?.pendingApproval != nil },
                set: { isPresented in
                    if !isPresented {
                        actionStore?.cancelPendingAction()
                    }
                }
            )
        ) {
            Button(String(localized: "action.confirm.cancel", defaultValue: "Cancel"), role: .cancel) {
                actionStore?.cancelPendingAction()
            }
            Button(String(localized: "action.confirm.continue", defaultValue: "Continue")) {
                Task { await actionStore?.confirmPendingAction() }
            }
        } message: {
            Text(actionStore?.pendingApproval?.message ?? "")
        }
    }
}

private struct TrustActionStatusChip: View {
    let item: TrustActionOutboxItem
    let onRetry: (String) -> Void

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: item.action.systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text("\(item.action.title) · \(item.status.label)")
                .font(.rbGeist(11.5, weight: .medium))
                .lineLimit(1)
            if item.canRetry {
                Button(String(localized: "action.retry", defaultValue: "Retry")) {
                    onRetry(item.id)
                }
                .font(.rbGeist(11, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(Color.rbAccent)
            }
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .help(item.message)
    }

    private var foreground: Color {
        switch item.status {
        case .completed:
            Color.rbSignalSuccess
        case .failedRetryable, .failedNonRetryable:
            Color.rbSignalDeadline
        case .pending, .running:
            Color.rbFg2
        }
    }

    private var background: Color {
        switch item.status {
        case .completed:
            Color.rbSignalSuccess.opacity(0.10)
        case .failedRetryable, .failedNonRetryable:
            Color.rbSignalDeadline.opacity(0.10)
        case .pending, .running:
            Color.rbBgElev2
        }
    }
}
