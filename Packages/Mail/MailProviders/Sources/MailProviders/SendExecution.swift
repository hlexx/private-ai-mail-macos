import Foundation
import MailDomain

public final class GmailSendExecutor: MailSendProvider {
    public let provider = MailProviderIdentifier.gmail

    private let api: any GmailAPI
    private let now: @Sendable () -> Date

    public init(api: any GmailAPI, now: @escaping @Sendable () -> Date = Date.init) {
        self.api = api
        self.now = now
    }

    public func send(_ request: ProviderSendRequest) async throws -> ProviderSendResult {
        try validate(request, expectedProvider: provider, now: now())

        let rfcMessageID = Self.rfcMessageID(for: request)
        let outgoing = OutgoingMessage(
            from: request.from,
            to: request.to,
            cc: request.cc,
            bcc: request.bcc,
            subject: request.subject,
            body: request.bodyForPlainTextProvider,
            inReplyTo: request.rfcInReplyTo,
            references: request.rfcReferences,
            messageIDSeed: request.idempotencyKey.rawValue,
            messageIDHeader: rfcMessageID
        )

        let raw: String
        do {
            raw = try MIMEBuilder.encode(outgoing)
        } catch {
            throw ProviderSendError(
                failure: SanitizedSendFailure(
                    category: .validation,
                    providerErrorCode: "mime_build_failed",
                    occurredAt: now()
                )
            )
        }

        do {
            let sent = try await api.sendMessage(raw: raw, threadId: request.threadID)
            return ProviderSendResult(
                provider: provider,
                providerMessageID: sent.id,
                providerThreadID: sent.threadId,
                rfcMessageID: rfcMessageID,
                sentAt: now()
            )
        } catch let error as ProviderSendError {
            throw error
        } catch let error as GmailAPIError {
            throw ProviderSendError(failure: error.sanitizedSendFailure(occurredAt: now()))
        } catch {
            throw ProviderSendError(
                failure: SanitizedSendFailure(
                    category: .unknown,
                    providerErrorCode: "gmail_unknown",
                    occurredAt: now()
                )
            )
        }
    }

    private static func rfcMessageID(for request: ProviderSendRequest) -> String {
        guard let rfcMessageID = request.rfcMessageID else {
            return "<\(MIMEBuilder.messageID(seed: request.idempotencyKey.rawValue))>"
        }
        let trimmed = rfcMessageID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("<"), trimmed.hasSuffix(">") {
            return trimmed
        }
        return "<\(trimmed)>"
    }
}

public final class GraphSendExecutor: MailSendProvider {
    public let provider = MailProviderIdentifier.outlook

    private let api: any GraphAPI
    private let now: @Sendable () -> Date

    public init(api: any GraphAPI, now: @escaping @Sendable () -> Date = Date.init) {
        self.api = api
        self.now = now
    }

    public func send(_ request: ProviderSendRequest) async throws -> ProviderSendResult {
        try validate(request, expectedProvider: provider, now: now())

        let body = GraphDTO.ItemBody(
            contentType: request.bodyHTML == nil ? .text : .html,
            content: request.bodyHTML ?? request.bodyText ?? ""
        )
        let graphMessage = GraphDTO.Message(
            subject: request.subject,
            body: body,
            toRecipients: request.to.map(Self.graphRecipient),
            ccRecipients: request.cc.isEmpty ? nil : request.cc.map(Self.graphRecipient),
            bccRecipients: request.bcc.isEmpty ? nil : request.bcc.map(Self.graphRecipient)
        )
        let sendRequest = GraphDTO.SendMailRequest(message: graphMessage, saveToSentItems: true)

        do {
            let result = try await api.sendMail(sendRequest)
            guard result.accepted else {
                throw ProviderSendError(
                    failure: SanitizedSendFailure(
                        category: .providerUnavailable,
                        providerErrorCode: "\(result.statusCode)",
                        occurredAt: now()
                    )
                )
            }
            return ProviderSendResult(
                provider: provider,
                providerMessageID: nil,
                providerThreadID: nil,
                rfcMessageID: nil,
                providerRequestID: result.requestId,
                sentAt: now()
            )
        } catch let error as ProviderSendError {
            throw error
        } catch let error as GraphAPIError {
            throw ProviderSendError(failure: error.sanitizedSendFailure(occurredAt: now()))
        } catch {
            throw ProviderSendError(
                failure: SanitizedSendFailure(
                    category: .unknown,
                    providerErrorCode: "graph_unknown",
                    occurredAt: now()
                )
            )
        }
    }

    private static func graphRecipient(_ address: Address) -> GraphDTO.Recipient {
        GraphDTO.Recipient(
            emailAddress: GraphDTO.EmailAddress(name: address.name, address: address.email)
        )
    }
}

private func validate(
    _ request: ProviderSendRequest,
    expectedProvider: MailProviderIdentifier,
    now: Date
) throws {
    guard request.provider == expectedProvider else {
        throw ProviderSendError(
            failure: SanitizedSendFailure(
                category: .unsupportedOperation,
                providerErrorCode: "provider_mismatch",
                occurredAt: now
            )
        )
    }

    guard !request.to.isEmpty else {
        throw ProviderSendError(
            failure: SanitizedSendFailure(
                category: .validation,
                providerErrorCode: "missing_recipients",
                occurredAt: now
            )
        )
    }
}
