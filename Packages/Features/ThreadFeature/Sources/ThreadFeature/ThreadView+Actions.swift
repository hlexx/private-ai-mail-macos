import ActionsFeature
import SwiftUI

extension ThreadView {
    @ViewBuilder
    var actionOutboxStrip: some View {
        if let actionStore {
            TrustActionOutboxStrip(items: actionStore.outboxItems) { opId in
                Task { await actionStore.retry(opId: opId) }
            }
        }
    }

    var actionTarget: TrustActionTarget? {
        guard let accountId = store.observedAccountId,
              let threadId = store.observedThreadId else {
            return nil
        }
        return TrustActionTarget(accountId: accountId, threadId: threadId, subject: store.subject)
    }

    func requestActionOrFallback(_ action: TrustMVPAction, fallback: (() -> Void)?) {
        guard let actionStore, let actionTarget else {
            fallback?()
            return
        }
        Task {
            await actionStore.requestAction(TrustActionRequest(action: action, target: actionTarget))
        }
    }
}
