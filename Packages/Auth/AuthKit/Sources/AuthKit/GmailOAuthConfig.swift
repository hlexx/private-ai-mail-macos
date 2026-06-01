import Foundation

public struct GmailOAuthConfig: Sendable {
    public let clientID: String
    public let redirectURI: String
    public let scopes: [String]

    /// Reversed-client-ID URL scheme registered for our iOS OAuth client.
    /// Google auto-binds this scheme to the client; we must also list it
    /// in `Info.plist` under `CFBundleURLTypes` so macOS routes the
    /// authorization callback back to the app, and use it as
    /// `ASWebAuthenticationSession.callbackURLScheme` in `GmailOAuthClient`.
    public static let reversedClientIDScheme =
        "com.googleusercontent.apps.398444518659-8e9pmd46dbm71a2t0ejuui2b6tvcgtkp"

    public static let `default` = GmailOAuthConfig(
        // iOS OAuth client (Google Cloud project mediaplatform-210614).
        // For iOS clients Google's documented redirect URI pattern is the
        // *reversed* client ID followed by `:/oauth2callback`. The scheme
        // is auto-registered for the client when you create it; the app
        // must register the same scheme in CFBundleURLTypes so macOS
        // forwards the callback.
        clientID: "398444518659-8e9pmd46dbm71a2t0ejuui2b6tvcgtkp.apps.googleusercontent.com",
        redirectURI: "\(reversedClientIDScheme):/oauth2callback",
        scopes: [
            // NOTE — do NOT request gmail.metadata alongside gmail.readonly.
            // Google treats `gmail.metadata` as a stricter, mutually
            // exclusive variant: combining the two yields a token with
            // metadata-only access, so any messages.get / message body
            // read fails with 403 insufficient_scope and Bootstrap aborts.
            // `gmail.readonly` already grants metadata + full message
            // reads, which is what the on-device pipeline needs.
            "https://www.googleapis.com/auth/gmail.readonly",
            // Trust MVP mailbox actions and provider draft creation require
            // Gmail write access. `gmail.modify` covers label mutations,
            // trash, drafts, compose, and send without permanent deletion.
            "https://www.googleapis.com/auth/gmail.modify",
            "https://www.googleapis.com/auth/gmail.send",
            "https://www.googleapis.com/auth/userinfo.email"
        ]
    )

    static let authorizationEndpoint = URL(
        string: "https://accounts.google.com/o/oauth2/v2/auth"
    )!
    static let tokenEndpoint = URL(
        string: "https://oauth2.googleapis.com/token"
    )!

    public init(clientID: String, redirectURI: String, scopes: [String]) {
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.scopes = scopes
    }
}
