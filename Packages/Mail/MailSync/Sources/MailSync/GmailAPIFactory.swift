import MailProviders

public typealias GmailAPIFactory = @Sendable (String) throws -> any GmailAPI
