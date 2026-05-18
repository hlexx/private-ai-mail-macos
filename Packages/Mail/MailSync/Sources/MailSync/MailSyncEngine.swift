import Foundation
import GRDB
import MailDomain
import MailProviders
import Persistence

public actor MailSyncEngine {
    public let accountId: String
    private let api: any GmailAPI
    private let db: AppDatabase
    private var currentState: SyncState = .idle
    private var continuations: [UUID: AsyncStream<SyncEvent>.Continuation] = [:]
    private var retryTask: Task<Void, Never>?

    public init(accountId: String, api: any GmailAPI, db: AppDatabase) {
        self.accountId = accountId
        self.api = api
        self.db = db
    }

    deinit {
        retryTask?.cancel()
        for continuation in continuations.values {
            continuation.finish()
        }
    }

    /// Creates a new event stream for this engine. Each caller gets its own
    /// independent stream — multiple consumers can subscribe without splitting events.
    public func makeEventStream() -> AsyncStream<SyncEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<SyncEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(64)
        )
        continuation.onTermination = { [weak self] _ in
            Task { [weak self] in
                await self?.removeContinuation(id)
            }
        }
        continuations[id] = continuation
        return stream
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func broadcast(_ event: SyncEvent) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    public func bootstrap() async {
        transition(to: .bootstrapping)
        do {
            try await Bootstrap.run(
                accountId: accountId,
                api: api,
                db: db,
                onProgress: { [weak self] progress in
                    await self?.broadcast(.progress(progress))
                },
                onThreadUpserted: { [weak self] threadId in
                    await self?.broadcast(.threadUpserted(threadId))
                }
            )
            transition(to: .live)
        } catch let error as GmailAPIError {
            if case .rateLimited(let retryAfter) = error {
                handleRateLimited(retryAfter: retryAfter ?? 60) { engine in
                    await engine.bootstrap()
                }
            } else {
                broadcast(.error(.bootstrapFailed(error)))
                transition(to: .degraded)
            }
        } catch {
            broadcast(.error(.bootstrapFailed(error)))
            transition(to: .degraded)
        }
    }

    public func refresh() async {
        guard currentState == .live || currentState == .idle else { return }
        do {
            try await IncrementalSync.run(
                accountId: accountId,
                api: api,
                db: db,
                onThreadUpserted: { [weak self] threadId in
                    await self?.broadcast(.threadUpserted(threadId))
                }
            )
        } catch let syncError as SyncError {
            if case .historyExpired = syncError {
                await bootstrap()
            } else {
                broadcast(.error(syncError))
            }
        } catch let error as GmailAPIError {
            if case .rateLimited(let retryAfter) = error {
                handleRateLimited(retryAfter: retryAfter ?? 60) { engine in
                    await engine.refresh()
                }
            } else if case .serverError(statusCode: 404) = error {
                await bootstrap()
            } else {
                broadcast(.error(.incrementalFailed(error)))
            }
        } catch {
            broadcast(.error(.incrementalFailed(error)))
        }
    }

    public func stop() {
        retryTask?.cancel()
        retryTask = nil
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }

    public var state: SyncState { currentState }

    private func transition(to newState: SyncState) {
        currentState = newState
        broadcast(.state(newState))
    }

    private func handleRateLimited(retryAfter: TimeInterval, resumeWith operation: @Sendable @escaping (isolated MailSyncEngine) async -> Void) {
        let capped = min(retryAfter, 300)
        broadcast(.error(.rateLimited(retryAfter: capped)))
        transition(to: .paused)
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(capped))
            guard !Task.isCancelled, let self else { return }
            await operation(self)
        }
    }
}
