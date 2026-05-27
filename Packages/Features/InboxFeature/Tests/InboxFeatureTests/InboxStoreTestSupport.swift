import Foundation
@testable import InboxFeature

private let pollIntervalMilliseconds = 25

@discardableResult
@MainActor
func waitForThreadIDs(
    in store: InboxStore,
    timeoutMilliseconds: Int = 3_000,
    until predicate: (Set<String>) -> Bool
) async throws -> Set<String> {
    let attempts = max(1, timeoutMilliseconds / pollIntervalMilliseconds)
    for _ in 0..<attempts {
        let ids = Set(store.threads.map(\.id))
        if predicate(ids) {
            return ids
        }
        try await Task.sleep(for: .milliseconds(pollIntervalMilliseconds))
    }
    return Set(store.threads.map(\.id))
}

@discardableResult
@MainActor
func waitForFolderCounts(
    in store: InboxStore,
    timeoutMilliseconds: Int = 3_000,
    until predicate: ([FolderID: Int]) -> Bool
) async throws -> [FolderID: Int] {
    let attempts = max(1, timeoutMilliseconds / pollIntervalMilliseconds)
    for _ in 0..<attempts {
        let counts = store.folderCounts
        if predicate(counts) {
            return counts
        }
        try await Task.sleep(for: .milliseconds(pollIntervalMilliseconds))
    }
    return store.folderCounts
}
