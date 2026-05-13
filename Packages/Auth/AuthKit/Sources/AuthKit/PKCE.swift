import Foundation
import CryptoKit

public enum PKCE: Sendable {
    public struct Challenge: Sendable {
        public let verifier: String
        public let challenge: String
        public let method: String = "S256"
    }

    public static func generate() -> Challenge {
        let verifier = generateVerifier()
        let challenge = computeChallenge(from: verifier)
        return Challenge(verifier: verifier, challenge: challenge)
    }

    static func generateVerifier(length: Int = 43) -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "Failed to generate random bytes for PKCE verifier")
        return String(Data(bytes)
            .base64URLEncodedString()
            .prefix(length))
    }

    static func computeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64URLEncodedString()
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
