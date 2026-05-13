import Foundation
import MailProviders
import MailDomain
import Persistence
import GRDB

public actor MailSyncEngine {
    public let accountId: String
    private let api: any GmailAPI
    private let db: AppDatabase
    private var currentState: SyncState = .idle
    private let eventContinuation: AsyncStream<SyncEvent>.Continuation
    public nonisolated let events: AsyncStream<SyncEvent>
    private var retryTask: Task<Void, Never>?

    public init(accountId: String, api: any GmailAPI, db: AppDatabase) {
        self.accountId = accountId
        self.api = api
        self.db = db
        let (stream, continuation) = AsyncStream<SyncEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(64)
        )
        self.events = stream
        self.eventContinuation = continuation
    }

    deinit {
        eventContinuation.finish()
    }

    public func bootstrap() async {
        transition(to: .bootstrapping)
        let continuation = self.eventContinuation
        do {
            try await Bootstrap.run(
                accountId: accountId,
                api: api,
                db: db,
                onProgress: { progress in
                    continuation.yield(.progress(progress))
                },
                onThreadUpserted: { threadId in
                    continuation.yield(.threadUpserted(threadId))
                }
            )
            transition(to: .live)
        } catch let error as GmailAPIError {
            if case .rateLimited(let retryAfter) = error {
                handleRateLimited(retryAfter: retryAfter ?? 60) { engine in
                    await engine.bootstrap()
                }
            } else {
                continuation.yield(.error(.bootstrapFailed(error)))
                transition(to: .degraded)
            }
        } catch {
            continuation.yield(.error(.bootstrapFailed(error)))
            transition(to: .degraded)
        }
    }

    public func refresh() async {
        guard currentState == .live || currentState == .idle else { return }
        let continuation = self.eventContinuation
        do {
            try await IncrementalSync.run(
                accountId: accountId,
                api: api,
                db: db,
                onThreadUpserted: { threadId in
                    continuation.yield(.threadUpserted(threadId))
                }
            )
        } catch let error as GmailAPIError {
            if case .rateLimited(let retryAfter) = error {
                handleRateLimited(retryAfter: retryAfter ?? 60) { engine in
                    await engine.refresh()
                }
            } else {
                continuation.yield(.error(.incrementalFailed(error)))
            }
        } catch {
            continuation.yield(.error(.incrementalFailed(error)))
        }
    }

    public func stop() {
        retryTask?.cancel()
        retryTask = nil
        eventContinuation.finish()
    }

    public var state: SyncState { currentState }

    private func transition(to newState: SyncState) {
        currentState = newState
        eventContinuation.yield(.state(newState))
    }

    private func handleRateLimited(retryAfter: TimeInterval, resumeWith operation: @Sendable @escaping (isolated MailSyncEngine) async -> Void) {
        let capped = min(retryAfter, 300)
        eventContinuation.yield(.error(.rateLimited(retryAfter: capped)))
        transition(to: .paused)
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(capped))
            guard !Task.isCancelled, let self else { return }
            await operation(self)
        }
    }
}
