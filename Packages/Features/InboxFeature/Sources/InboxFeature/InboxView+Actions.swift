import ActionsFeature
import SwiftUI

extension InboxView {
    @ViewBuilder
    var actionOutboxStrip: some View {
        if let actionStore {
            TrustActionOutboxStrip(items: actionStore.outboxItems) { opId in
                Task { await actionStore.retry(opId: opId) }
            }
        }
    }

    func requestAction(_ action: TrustMVPAction, for thread: ThreadRow) async {
        guard let actionStore else { return }
        await actionStore.requestAction(TrustActionRequest(
            action: action,
            target: TrustActionTarget(
                accountId: thread.accountId,
                threadId: thread.id,
                subject: thread.subject
            )
        ))
    }
}
