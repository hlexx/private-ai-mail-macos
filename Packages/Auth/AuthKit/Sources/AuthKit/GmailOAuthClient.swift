import AuthenticationServices
import Foundation

public final class GmailOAuthClient: OAuthClient, @unchecked Sendable {
    private let config: GmailOAuthConfig
    private let urlSession: URLSession

    public init(
        config: GmailOAuthConfig = .default,
        urlSession: URLSession = .shared
    ) {
        self.config = config
        self.urlSession = urlSession
    }

    @MainActor
    public func authorize() async throws -> TokenCredential {
        let pkce = PKCE.generate()
        let authURL = buildAuthorizationURL(pkce: pkce)
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
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        return components.url!
    }

    @MainActor
    private func startWebAuthSession(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "com.hlexx.privateaimail"
            ) { callbackURL, error in
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
            session.presentationContextProvider = WebAuthContextProvider.shared
            session.prefersEphemeralWebBrowserSession = false
            if !session.start() {
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
