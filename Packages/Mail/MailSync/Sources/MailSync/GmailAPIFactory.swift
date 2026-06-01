import MailProviders

// TODO(trust-mvp-01): Replace this Gmail-specific factory with a provider-neutral
// adapter factory once shared provider contracts are introduced.
public typealias GmailAPIFactory = @Sendable (String) throws -> any GmailAPI
