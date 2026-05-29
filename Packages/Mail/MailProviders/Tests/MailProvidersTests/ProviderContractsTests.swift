import Foundation
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
}
