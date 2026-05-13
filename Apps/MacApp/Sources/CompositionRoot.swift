import Foundation
import Persistence
import MailSync
import InboxFeature
import ThreadFeature

@MainActor
final class CompositionRoot {
    let db: AppDatabase
    let inboxStore: InboxStore
    let threadStore: ThreadStore
    var syncSupervisor: SyncSupervisor?

    init() {
        let path = Self.defaultDBPath()
        // swiftlint:disable:next force_try
        self.db = try! AppDatabase.openSync(at: path)
        self.inboxStore = InboxStore(db: db)
        self.threadStore = ThreadStore(db: db)
    }

    private static func defaultDBPath() -> String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("PrivateAIMail")
            .appendingPathComponent("db.sqlite")
            .path
    }

    func refreshAccount(_ accountId: String) {
        guard let supervisor = syncSupervisor else { return }
        Task {
            await supervisor.refresh(accountId: accountId)
        }
    }
}
