import Foundation

public struct GmailOAuthConfig: Sendable {
    public let clientID: String
    public let redirectURI: String
    public let scopes: [String]

    public static let `default` = GmailOAuthConfig(
        clientID: "YOUR_CLIENT_ID.apps.googleusercontent.com",
        redirectURI: "com.hlexx.privateaimail:/oauth2callback",
        scopes: [
            "https://www.googleapis.com/auth/gmail.readonly",
            "https://www.googleapis.com/auth/gmail.metadata",
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
