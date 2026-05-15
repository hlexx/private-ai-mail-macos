import AuthenticationServices
import Foundation

public final class GmailOAuthClient: OAuthClient, Sendable {
    private let config: GmailOAuthConfig
    private let urlSession: URLSession

    public init(
        config: GmailOAuthConfig = .default,
        urlSession: URLSession? = nil
    ) {
        self.config = config
        if let urlSession {
            self.urlSession = urlSession
        } else {
            let sessionConfig = URLSessionConfiguration.ephemeral
            sessionConfig.httpCookieStorage = nil
            sessionConfig.urlCache = nil
            self.urlSession = URLSession(configuration: sessionConfig)
        }
    }

    @MainActor
    public func authorize() async throws -> TokenCredential {
        let pkce = PKCE.generate()
        let authURL = buildAuthorizationURL(pkce: pkce)
        let callbackURL = try await startWebAuthSession(url: authURL)
        let code = try extractCode(from: callbackURL)
        return try await exchangeCode(code, pkce: pkce)
    }

    @MainActor
    public func reauthorize(additionalScopes: [String]) async throws -> TokenCredential {
        let merged = Array(Set(config.scopes + additionalScopes))
        let overrideConfig = GmailOAuthConfig(
            clientID: config.clientID,
            redirectURI: config.redirectURI,
            scopes: merged
        )
        let pkce = PKCE.generate()
        let authURL = buildAuthorizationURL(config: overrideConfig, pkce: pkce, forceConsent: true)
        let callbackURL = try await startWebAuthSession(url: authURL)
        let code = try extractCode(from: callbackURL)
        return try await exchangeCode(code, pkce: pkce)
    }

    public func refresh(_ refreshToken: String) async throws -> TokenCredential {
        var request = URLRequest(url: GmailOAuthConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )

        let body: [String: String] = [
            "client_id": config.clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ]
        request.httpBody = body.urlEncodedData

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw AuthError.invalidResponse
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        return TokenCredential(
            accessToken: tokenResponse.accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(
                TimeInterval(tokenResponse.expiresIn)
            )
        )
    }

    // MARK: - Private

    private func buildAuthorizationURL(pkce: PKCE.Challenge) -> URL {
        buildAuthorizationURL(config: config, pkce: pkce, forceConsent: true)
    }

    private func buildAuthorizationURL(config: GmailOAuthConfig, pkce: PKCE.Challenge, forceConsent: Bool) -> URL {
        var components = URLComponents(
            url: GmailOAuthConfig.authorizationEndpoint,
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(
                name: "scope",
                value: config.scopes.joined(separator: " ")
            ),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: pkce.method),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: forceConsent ? "consent" : "consent"),
        ]
        return components.url!
    }

    @MainActor
    private func startWebAuthSession(url: URL) async throws -> URL {
        // Retain the session outside the continuation closure so ARC does not
        // deallocate it before the callback fires.
        var retainedSession: ASWebAuthenticationSession?

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "com.hlexx.privateaimail"
            ) { callbackURL, error in
                // The completion is invoked on the XPC reply queue, but this
                // closure captures `retainedSession` from a `@MainActor` scope.
                // Hop to MainActor explicitly to satisfy Swift 6 isolation
                // checking — without this, `_swift_task_checkIsolatedSwift`
                // trips and the process crashes with SIGTRAP.
                Task { @MainActor in
                    // Break the intentional retain cycle now that the callback fired.
                    retainedSession = nil

                    if let error {
                        if (error as NSError).code
                            == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                            continuation.resume(throwing: AuthError.cancelled)
                        } else {
                            continuation.resume(throwing: AuthError.network(error))
                        }
                        return
                    }
                    guard let callbackURL else {
                        continuation.resume(throwing: AuthError.invalidResponse)
                        return
                    }
                    continuation.resume(returning: callbackURL)
                }
            }
            retainedSession = session
            session.presentationContextProvider = WebAuthContextProvider.shared
            session.prefersEphemeralWebBrowserSession = false
            if !session.start() {
                retainedSession = nil
                continuation.resume(throwing: AuthError.network(
                    NSError(domain: "AuthKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to start web auth session"])
                ))
            }
        }
    }

    private func extractCode(from url: URL) throws -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value
        else {
            if let error = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "error" })?.value,
                error == "access_denied" {
                throw AuthError.denied
            }
            throw AuthError.invalidResponse
        }
        return code
    }

    private func exchangeCode(
        _ code: String,
        pkce: PKCE.Challenge
    ) async throws -> TokenCredential {
        var request = URLRequest(url: GmailOAuthConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )

        let body: [String: String] = [
            "client_id": config.clientID,
            "code": code,
            "code_verifier": pkce.verifier,
            "grant_type": "authorization_code",
            "redirect_uri": config.redirectURI,
        ]
        request.httpBody = body.urlEncodedData

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw AuthError.invalidResponse
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard let refreshToken = tokenResponse.refreshToken else {
            throw AuthError.missingRefreshToken
        }

        return TokenCredential(
            accessToken: tokenResponse.accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(
                TimeInterval(tokenResponse.expiresIn)
            )
        )
    }
}

#if canImport(AppKit)
import AppKit

private final class WebAuthContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebAuthContextProvider()
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }
}
#endif

private struct TokenResponse: Decodable {
    let accessToken: String
    let expiresIn: Int
    let refreshToken: String?
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
    }
}

extension Dictionary where Key == String, Value == String {
    private static var formURLEncodedAllowed: CharacterSet {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return allowed
    }

    var urlEncodedData: Data {
        let str = map { key, value in
            let k = key.addingPercentEncoding(
                withAllowedCharacters: Self.formURLEncodedAllowed
            ) ?? key
            let v = value.addingPercentEncoding(
                withAllowedCharacters: Self.formURLEncodedAllowed
            ) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
        return Data(str.utf8)
    }
}
