import Foundation

public struct DraftID: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    public static func generate() -> DraftID {
        DraftID(rawValue: UUID().uuidString.lowercased())
    }

    public var description: String {
        rawValue
    }
}

public struct SendQueueItemID: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    public static func generate() -> SendQueueItemID {
        SendQueueItemID(rawValue: UUID().uuidString.lowercased())
    }

    public var description: String {
        rawValue
    }
}

public struct SendIdempotencyKey: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    public static func generate() -> SendIdempotencyKey {
        SendIdempotencyKey(rawValue: UUID().uuidString.lowercased())
    }

    public var description: String {
        rawValue
    }
}

public enum DraftBodyStorage: String, Codable, Sendable, CaseIterable {
    case sqlite
    case localFile = "local_file"
}

public struct DraftIdentity: Codable, Hashable, Sendable {
    public let provider: MailProviderIdentifier
    public let accountID: String
    public let id: DraftID

    public init(provider: MailProviderIdentifier, accountID: String, id: DraftID) {
        self.provider = provider
        self.accountID = accountID
        self.id = id
    }
}

public struct DraftMessage: Codable, Equatable, Identifiable, Sendable {
    public let id: DraftID
    public let provider: MailProviderIdentifier
    public let accountID: String
    public let from: Address
    public let to: [Address]
    public let cc: [Address]
    public let bcc: [Address]
    public let subject: String
    public let bodyText: String?
    public let bodyHTML: String?
    public let bodyStorage: DraftBodyStorage
    public let threadID: String?
    public let replyToProviderMessageID: String?
    public let rfcMessageID: String?
    public let rfcInReplyTo: String?
    public let rfcReferences: [String]
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: DraftID,
        provider: MailProviderIdentifier,
        accountID: String,
        from: Address,
        to: [Address],
        cc: [Address] = [],
        bcc: [Address] = [],
        subject: String,
        bodyText: String? = nil,
        bodyHTML: String? = nil,
        bodyStorage: DraftBodyStorage = .sqlite,
        threadID: String? = nil,
        replyToProviderMessageID: String? = nil,
        rfcMessageID: String? = nil,
        rfcInReplyTo: String? = nil,
        rfcReferences: [String] = [],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.provider = provider
        self.accountID = accountID
        self.from = from
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.bodyText = bodyText
        self.bodyHTML = bodyHTML
        self.bodyStorage = bodyStorage
        self.threadID = threadID
        self.replyToProviderMessageID = replyToProviderMessageID
        self.rfcMessageID = rfcMessageID
        self.rfcInReplyTo = rfcInReplyTo
        self.rfcReferences = rfcReferences
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum SendQueueStatus: String, Codable, Sendable, CaseIterable {
    case pending
    case sending
    case retryScheduled
    case needsConsent
    case failed
    case sent
    case canceled
    case duplicateSuppressed
}

public struct SendRetryPolicy: Codable, Equatable, Sendable {
    public let backoffSeconds: [Int]
    public let maxProviderAttempts: Int

    public init(backoffSeconds: [Int], maxProviderAttempts: Int) {
        self.backoffSeconds = backoffSeconds
        self.maxProviderAttempts = maxProviderAttempts
    }

    public static let trustMVPDefault = SendRetryPolicy(
        backoffSeconds: [60, 300, 900, 3_600, 14_400],
        maxProviderAttempts: 5
    )

    public func canRetry(afterAttempts attempts: Int) -> Bool {
        attempts < maxProviderAttempts
    }

    public func delaySeconds(forNextAttemptAfter attemptsCompleted: Int) -> Int? {
        guard canRetry(afterAttempts: attemptsCompleted) else {
            return nil
        }
        let index = max(0, attemptsCompleted - 1)
        guard index < backoffSeconds.count else {
            return nil
        }
        return backoffSeconds[index]
    }
}

public enum SendFailureCategory: String, Codable, Sendable, CaseIterable {
    case missingCredential
    case insufficientScope
    case authExpired
    case rateLimited
    case offline
    case timeout
    case providerUnavailable
    case validation
    case notFound
    case invalidResponse
    case unsupportedOperation
    case conflict
    case ambiguousCompletion
    case unknown
}

public struct SanitizedSendFailure: Codable, Equatable, Sendable {
    public let category: SendFailureCategory
    public let providerErrorCode: String?
    public let userVisibleMessage: String?
    public let retryAfterSeconds: Int?
    public let occurredAt: Date

    public init(
        category: SendFailureCategory,
        providerErrorCode: String? = nil,
        userVisibleMessage: String? = nil,
        retryAfterSeconds: Int? = nil,
        occurredAt: Date
    ) {
        self.category = category
        self.providerErrorCode = providerErrorCode
        self.userVisibleMessage = userVisibleMessage
        self.retryAfterSeconds = retryAfterSeconds
        self.occurredAt = occurredAt
    }
}

public struct ProviderSendResult: Codable, Equatable, Sendable {
    public let provider: MailProviderIdentifier
    public let providerMessageID: String?
    public let providerThreadID: String?
    public let rfcMessageID: String?
    public let providerRequestID: String?
    public let sentAt: Date

    public init(
        provider: MailProviderIdentifier,
        providerMessageID: String? = nil,
        providerThreadID: String? = nil,
        rfcMessageID: String? = nil,
        providerRequestID: String? = nil,
        sentAt: Date
    ) {
        self.provider = provider
        self.providerMessageID = providerMessageID
        self.providerThreadID = providerThreadID
        self.rfcMessageID = rfcMessageID
        self.providerRequestID = providerRequestID
        self.sentAt = sentAt
    }
}

public struct ProviderSendRequest: Codable, Equatable, Sendable {
    public let provider: MailProviderIdentifier
    public let accountID: String
    public let idempotencyKey: SendIdempotencyKey
    public let from: Address
    public let to: [Address]
    public let cc: [Address]
    public let bcc: [Address]
    public let subject: String
    public let bodyText: String?
    public let bodyHTML: String?
    public let threadID: String?
    public let replyToProviderMessageID: String?
    public let rfcMessageID: String?
    public let rfcInReplyTo: String?
    public let rfcReferences: [String]

    public init(
        provider: MailProviderIdentifier,
        accountID: String,
        idempotencyKey: SendIdempotencyKey,
        from: Address,
        to: [Address],
        cc: [Address] = [],
        bcc: [Address] = [],
        subject: String,
        bodyText: String? = nil,
        bodyHTML: String? = nil,
        threadID: String? = nil,
        replyToProviderMessageID: String? = nil,
        rfcMessageID: String? = nil,
        rfcInReplyTo: String? = nil,
        rfcReferences: [String] = []
    ) {
        self.provider = provider
        self.accountID = accountID
        self.idempotencyKey = idempotencyKey
        self.from = from
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.bodyText = bodyText
        self.bodyHTML = bodyHTML
        self.threadID = threadID
        self.replyToProviderMessageID = replyToProviderMessageID
        self.rfcMessageID = rfcMessageID
        self.rfcInReplyTo = rfcInReplyTo
        self.rfcReferences = rfcReferences
    }

    public init(queuedMessage: QueuedOutgoingMessage) {
        self.init(
            provider: queuedMessage.provider,
            accountID: queuedMessage.accountID,
            idempotencyKey: queuedMessage.idempotencyKey,
            from: queuedMessage.from,
            to: queuedMessage.to,
            cc: queuedMessage.cc,
            bcc: queuedMessage.bcc,
            subject: queuedMessage.subject,
            bodyText: queuedMessage.bodyText,
            bodyHTML: queuedMessage.bodyHTML,
            threadID: queuedMessage.threadID,
            replyToProviderMessageID: queuedMessage.replyToProviderMessageID,
            rfcMessageID: queuedMessage.rfcMessageID,
            rfcInReplyTo: queuedMessage.rfcInReplyTo,
            rfcReferences: queuedMessage.rfcReferences
        )
    }

    public var bodyForPlainTextProvider: String {
        bodyText ?? bodyHTML ?? ""
    }
}

public struct ProviderSendError: Error, Equatable, Sendable {
    public let failure: SanitizedSendFailure

    public init(failure: SanitizedSendFailure) {
        self.failure = failure
    }
}

public protocol MailSendProvider: Sendable {
    var provider: MailProviderIdentifier { get }
    func send(_ request: ProviderSendRequest) async throws -> ProviderSendResult
}

public struct QueuedOutgoingMessage: Codable, Equatable, Identifiable, Sendable {
    public let id: SendQueueItemID
    public let draftID: DraftID?
    public let provider: MailProviderIdentifier
    public let accountID: String
    public let idempotencyKey: SendIdempotencyKey
    public let status: SendQueueStatus
    public let from: Address
    public let to: [Address]
    public let cc: [Address]
    public let bcc: [Address]
    public let subject: String
    public let bodyText: String?
    public let bodyHTML: String?
    public let bodyStorage: DraftBodyStorage
    public let threadID: String?
    public let replyToProviderMessageID: String?
    public let providerMessageID: String?
    public let providerThreadID: String?
    public let rfcMessageID: String?
    public let rfcInReplyTo: String?
    public let rfcReferences: [String]
    public let attempts: Int
    public let retryPolicy: SendRetryPolicy
    public let nextAttemptAt: Date?
    public let lastAttemptAt: Date?
    public let createdAt: Date
    public let updatedAt: Date
    public let sentAt: Date?
    public let sanitizedFailure: SanitizedSendFailure?

    public init(
        id: SendQueueItemID,
        draftID: DraftID? = nil,
        provider: MailProviderIdentifier,
        accountID: String,
        idempotencyKey: SendIdempotencyKey,
        status: SendQueueStatus,
        from: Address,
        to: [Address],
        cc: [Address] = [],
        bcc: [Address] = [],
        subject: String,
        bodyText: String? = nil,
        bodyHTML: String? = nil,
        bodyStorage: DraftBodyStorage = .sqlite,
        threadID: String? = nil,
        replyToProviderMessageID: String? = nil,
        providerMessageID: String? = nil,
        providerThreadID: String? = nil,
        rfcMessageID: String? = nil,
        rfcInReplyTo: String? = nil,
        rfcReferences: [String] = [],
        attempts: Int = 0,
        retryPolicy: SendRetryPolicy = .trustMVPDefault,
        nextAttemptAt: Date? = nil,
        lastAttemptAt: Date? = nil,
        createdAt: Date,
        updatedAt: Date,
        sentAt: Date? = nil,
        sanitizedFailure: SanitizedSendFailure? = nil
    ) {
        self.id = id
        self.draftID = draftID
        self.provider = provider
        self.accountID = accountID
        self.idempotencyKey = idempotencyKey
        self.status = status
        self.from = from
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.bodyText = bodyText
        self.bodyHTML = bodyHTML
        self.bodyStorage = bodyStorage
        self.threadID = threadID
        self.replyToProviderMessageID = replyToProviderMessageID
        self.providerMessageID = providerMessageID
        self.providerThreadID = providerThreadID
        self.rfcMessageID = rfcMessageID
        self.rfcInReplyTo = rfcInReplyTo
        self.rfcReferences = rfcReferences
        self.attempts = attempts
        self.retryPolicy = retryPolicy
        self.nextAttemptAt = nextAttemptAt
        self.lastAttemptAt = lastAttemptAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sentAt = sentAt
        self.sanitizedFailure = sanitizedFailure
    }
}

public protocol DraftStore: Sendable {
    func save(_ draft: DraftMessage) async throws -> DraftMessage
    func fetchDraft(id: DraftID, accountID: String) async throws -> DraftMessage?
    func deleteDraft(id: DraftID, accountID: String) async throws
}

public protocol SendQueue: Sendable {
    func enqueue(_ message: QueuedOutgoingMessage) async throws -> QueuedOutgoingMessage
    func fetchQueuedMessage(id: SendQueueItemID) async throws -> QueuedOutgoingMessage?
    func fetchQueuedMessage(
        provider: MailProviderIdentifier,
        accountID: String,
        idempotencyKey: SendIdempotencyKey
    ) async throws -> QueuedOutgoingMessage?
}
