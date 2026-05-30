import Foundation
import MailDomain
import Testing
@testable import MailProviders

@Suite("ProviderContracts")
struct ProviderContractsTests {
    @Test func gmailCapabilitiesExposeLabelCentricContract() {
        let capabilities = MailProviderCapabilities.gmail

        #expect(capabilities.supportsLabels)
        #expect(!capabilities.supportsFolders)
        #expect(!capabilities.supportsCategories)
        #expect(capabilities.supportsSend)
        #expect(capabilities.supportsAttachmentDownload)
        #expect(capabilities.supportsDeltaSync)
        #expect(capabilities.supportsServerSearch)
        #expect(capabilities.supportsAliases)
    }

    @Test func outlookCapabilitiesExposeFolderCentricContract() {
        let capabilities = MailProviderCapabilities.outlook

        #expect(!capabilities.supportsLabels)
        #expect(capabilities.supportsFolders)
        #expect(capabilities.supportsCategories)
        #expect(capabilities.supportsSend)
        #expect(capabilities.supportsAttachmentDownload)
        #expect(capabilities.supportsDeltaSync)
        #expect(capabilities.supportsServerSearch)
        #expect(capabilities.supportsAliases)
    }

    @Test(arguments: [
        (GmailAPIError.unauthorized, MailProviderErrorCategory.authExpired),
        (GmailAPIError.rateLimited(retryAfter: 30), MailProviderErrorCategory.rateLimited),
        (GmailAPIError.serverError(statusCode: 404), MailProviderErrorCategory.notFound),
        (GmailAPIError.serverError(statusCode: 409), MailProviderErrorCategory.conflict),
        (GmailAPIError.serverError(statusCode: 501), MailProviderErrorCategory.unsupportedOperation),
        (GmailAPIError.serverError(statusCode: 503), MailProviderErrorCategory.providerUnavailable),
        (GmailAPIError.networkError(URLError(.notConnectedToInternet)), MailProviderErrorCategory.offline),
        (GmailAPIError.decodingError(URLError(.cannotDecodeRawData)), MailProviderErrorCategory.invalidResponse),
        (GmailAPIError.insufficientScope, MailProviderErrorCategory.insufficientScope),
        (GmailAPIError.exhaustedRetries, MailProviderErrorCategory.providerUnavailable),
        (GmailAPIError.invalidResponse, MailProviderErrorCategory.invalidResponse),
    ])
    func gmailErrorsMapToSharedCategory(input: GmailAPIError, expected: MailProviderErrorCategory) {
        #expect(input.sharedCategory == expected)
    }

    @Test func gmailErrorsMapToSendQueueFailureCategories() {
        #expect(GmailAPIError.unauthorized.sendFailureCategory == .authExpired)
        #expect(GmailAPIError.insufficientScope.sendFailureCategory == .insufficientScope)
        #expect(GmailAPIError.rateLimited(retryAfter: 30).sendFailureCategory == .rateLimited)
        #expect(GmailAPIError.networkError(URLError(.timedOut)).sendFailureCategory == .timeout)
        #expect(GmailAPIError.networkError(URLError(.notConnectedToInternet)).sendFailureCategory == .offline)
        #expect(GmailAPIError.serverError(statusCode: 400).sendFailureCategory == .validation)
        #expect(GmailAPIError.serverError(statusCode: 404).sendFailureCategory == .notFound)
        #expect(GmailAPIError.serverError(statusCode: 409).sendFailureCategory == .conflict)
        #expect(GmailAPIError.serverError(statusCode: 503).sendFailureCategory == .providerUnavailable)

        let failure = GmailAPIError.rateLimited(retryAfter: 30).sanitizedSendFailure(
            occurredAt: Date(timeIntervalSince1970: 10)
        )
        #expect(failure.category == .rateLimited)
        #expect(failure.providerErrorCode == "429")
        #expect(failure.retryAfterSeconds == 30)
    }

    @Test func graphErrorsMapToSendQueueFailureCategories() {
        #expect(GraphAPIError.unauthorized.sendFailureCategory == .authExpired)
        #expect(GraphAPIError.insufficientScope.sendFailureCategory == .insufficientScope)
        #expect(GraphAPIError.rateLimited(retryAfter: 45).sendFailureCategory == .rateLimited)
        #expect(GraphAPIError.networkError("timed out").sendFailureCategory == .timeout)
        #expect(GraphAPIError.networkError("offline").sendFailureCategory == .offline)
        #expect(GraphAPIError.serverError(statusCode: 400, code: "ErrorInvalidRecipients").sendFailureCategory == .validation)
        #expect(GraphAPIError.serverError(statusCode: 404, code: "ErrorItemNotFound").sendFailureCategory == .notFound)
        #expect(GraphAPIError.serverError(statusCode: 409, code: "Conflict").sendFailureCategory == .conflict)
        #expect(GraphAPIError.serverError(statusCode: 503, code: "ServiceUnavailable").sendFailureCategory == .providerUnavailable)

        let failure = GraphAPIError.serverError(statusCode: 503, code: "ServiceUnavailable").sanitizedSendFailure(
            occurredAt: Date(timeIntervalSince1970: 10)
        )
        #expect(failure.category == .providerUnavailable)
        #expect(failure.providerErrorCode == "ServiceUnavailable")
    }
}
