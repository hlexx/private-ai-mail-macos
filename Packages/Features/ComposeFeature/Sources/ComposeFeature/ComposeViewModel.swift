import Foundation
import MailDomain
import Observation

// MARK: - Send State

public enum ComposeSendState: Sendable {
    case idle
    case awaitingApproval(deadline: Date)
    case sending
    case sent
    case failed(ComposeError)

    public var key: String {
        switch self {
        case .idle: return "idle"
        case .awaitingApproval: return "awaiting"
        case .sending: return "sending"
        case .sent: return "sent"
        case .failed: return "failed"
        }
    }
}

// MARK: - ComposeViewModel

@Observable
@MainActor
public final class ComposeViewModel {

    public var toField: String = ""
    public var ccField: String = ""
    public var subjectField: String = ""
    public var bodyText: String = ""
    public var sendState: ComposeSendState = .idle

    public var selectedAccountID: String?
    public var selectedAccountEmail: String?
    public var accounts: [AccountInfo] = []

    public var replyContext: ReplyContext?

    public var recipientCount: Int {
        parseAddresses(toField).count + parseAddresses(ccField).count
    }

    private var countdownTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private let composeServiceFactory: @Sendable (String) -> any ComposeService
    private let reauthorizeHandler: @Sendable (String) async throws -> Void

    public init(
        composeServiceFactory: @escaping @Sendable (String) -> any ComposeService,
        reauthorizeHandler: @escaping @Sendable (String) async throws -> Void = { _ in }
    ) {
        self.composeServiceFactory = composeServiceFactory
        self.reauthorizeHandler = reauthorizeHandler
    }

    // MARK: - Reset

    public func reset() {
        cancelSend()
        toField = ""
        ccField = ""
        subjectField = ""
        bodyText = ""
        replyContext = nil
    }

    // MARK: - Reply Pre-fill

    public func prefillReply(
        fromAddr: String,
        subject: String,
        threadID: String,
        lastMessageID: String,
        referencesChain: [String] = []
    ) {
        toField = fromAddr
        subjectField = Self.deduplicateRePrefix(subject)
        replyContext = ReplyContext(
            threadID: threadID,
            inReplyToMessageID: lastMessageID,
            referencesChain: referencesChain
        )
    }

    // MARK: - Send Flow

    public func requestSend() {
        guard case .idle = sendState else { return }
        let deadline = Date().addingTimeInterval(5)
        sendState = .awaitingApproval(deadline: deadline)
        countdownTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.executeSend()
        }
    }

    public func cancelSend() {
        countdownTask?.cancel()
        countdownTask = nil
        sendTask?.cancel()
        sendTask = nil
        sendState = .idle
    }

    public func confirmSendNow() {
        guard case .awaitingApproval = sendState else { return }
        countdownTask?.cancel()
        countdownTask = nil
        executeSend()
    }

    public func retrySend() {
        countdownTask?.cancel()
        countdownTask = nil
        sendTask?.cancel()
        sendTask = nil
        sendState = .idle
        requestSend()
    }

    public func reauthorizeAndRetry() {
        guard case .failed(.needsReconsent) = sendState else { return }
        guard let accountID = selectedAccountID else { return }
        sendState = .sending
        sendTask?.cancel()
        sendTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.reauthorizeHandler(accountID)
                guard !Task.isCancelled else { return }
                self.sendState = .idle
                self.requestSend()
            } catch {
                guard !Task.isCancelled else { return }
                self.sendState = .failed(.send(underlying: error))
            }
        }
    }

    // MARK: - Private

    private func executeSend() {
        guard let accountID = selectedAccountID,
              let accountEmail = selectedAccountEmail else {
            sendState = .failed(.noAccount)
            return
        }

        sendState = .sending

        sendTask = Task { [weak self] in
            guard let self else { return }

            let toAddrs = self.parseAddresses(self.toField)
            let ccAddrs = self.parseAddresses(self.ccField)

            let draft = ComposeDraft(
                accountID: accountID,
                from: Address(name: nil, email: accountEmail),
                to: toAddrs,
                cc: ccAddrs,
                subject: self.subjectField,
                body: self.bodyText,
                replyContext: self.replyContext
            )

            let service = self.composeServiceFactory(accountID)

            do {
                _ = try await service.send(draft)
                guard !Task.isCancelled else { return }
                self.sendState = .sent
            } catch let error as ComposeError {
                guard !Task.isCancelled else { return }
                self.sendState = .failed(error)
            } catch {
                guard !Task.isCancelled else { return }
                self.sendState = .failed(.send(underlying: error))
            }
        }
    }

    private func parseAddresses(_ raw: String) -> [Address] {
        splitAddresses(raw)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { chunk -> Address in
                if let open = chunk.firstIndex(of: "<"),
                   let close = chunk.firstIndex(of: ">") {
                    let email = String(chunk[chunk.index(after: open)..<close])
                    let name = chunk[chunk.startIndex..<open].trimmingCharacters(in: .whitespacesAndNewlines)
                    let cleanName = name.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    return Address(name: cleanName.isEmpty ? nil : cleanName, email: email)
                }
                return Address(name: nil, email: chunk)
            }
    }

    /// Split on commas, respecting quoted strings and angle brackets.
    private func splitAddresses(_ raw: String) -> [String] {
        var results: [String] = []
        var current = ""
        var inQuotes = false
        var inAngle = false

        for ch in raw {
            if ch == "\"" && !inAngle {
                inQuotes.toggle()
                current.append(ch)
            } else if ch == "<" && !inQuotes {
                inAngle = true
                current.append(ch)
            } else if ch == ">" && !inQuotes {
                inAngle = false
                current.append(ch)
            } else if ch == "," && !inQuotes && !inAngle {
                results.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty {
            results.append(current)
        }
        return results
    }

    public nonisolated static func deduplicateRePrefix(_ subject: String) -> String {
        let trimmed = subject.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().hasPrefix("re: ") {
            return trimmed
        }
        return "Re: \(trimmed)"
    }
}

// MARK: - Account Info

public struct AccountInfo: Identifiable, Sendable {
    public let id: String
    public let email: String
    public let displayName: String?

    public init(id: String, email: String, displayName: String? = nil) {
        self.id = id
        self.email = email
        self.displayName = displayName
    }
}
