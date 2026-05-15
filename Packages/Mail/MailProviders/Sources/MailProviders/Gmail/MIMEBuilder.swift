import Foundation
import MailDomain

public enum MIMEBuilder {

    public static func encode(_ message: OutgoingMessage) throws -> String {
        let raw = buildRFC5322(message)
        guard let data = raw.data(using: .utf8) else {
            throw MIMEBuilderError.encodingFailed
        }
        return base64URLEncode(data)
    }

    // MARK: - RFC 5322 assembly

    static func buildRFC5322(_ message: OutgoingMessage) -> String {
        var lines: [String] = []

        lines.append("Date: \(rfc5322Date())")
        lines.append("Message-ID: <\(messageID(seed: message.messageIDSeed))>")
        lines.append("From: \(formatAddress(message.from))")

        if !message.to.isEmpty {
            lines.append("To: \(message.to.map(formatAddress).joined(separator: ", "))")
        }
        if !message.cc.isEmpty {
            lines.append("Cc: \(message.cc.map(formatAddress).joined(separator: ", "))")
        }
        if !message.bcc.isEmpty {
            lines.append("Bcc: \(message.bcc.map(formatAddress).joined(separator: ", "))")
        }

        lines.append("Subject: \(encodeHeaderValue(message.subject))")

        if let inReplyTo = message.inReplyTo {
            lines.append("In-Reply-To: \(inReplyTo)")
            var refs = message.references
            if !refs.contains(inReplyTo) {
                refs.append(inReplyTo)
            }
            if !refs.isEmpty {
                lines.append("References: \(refs.joined(separator: " "))")
            }
        } else if !message.references.isEmpty {
            lines.append("References: \(message.references.joined(separator: " "))")
        }

        lines.append("MIME-Version: 1.0")
        lines.append("Content-Type: text/plain; charset=utf-8")
        lines.append("Content-Transfer-Encoding: quoted-printable")
        lines.append("")
        lines.append(quotedPrintableEncode(message.body))

        return lines.joined(separator: "\r\n")
    }

    // MARK: - Address formatting

    private static let rfc5322Specials = CharacterSet(charactersIn: "()<>[]:;@\\,\"")

    static func formatAddress(_ addr: Address) -> String {
        guard let name = addr.name, !name.isEmpty else {
            return addr.email
        }
        if !name.allSatisfy({ $0.isASCII && $0 != "\r" && $0 != "\n" }) {
            let encoded = encodeHeaderValue(name)
            return "\(encoded) <\(addr.email)>"
        }
        if name.unicodeScalars.contains(where: { rfc5322Specials.contains($0) }) {
            let quoted = name.replacingOccurrences(of: "\\", with: "\\\\")
                             .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(quoted)\" <\(addr.email)>"
        }
        return "\(name) <\(addr.email)>"
    }

    // MARK: - RFC 2047 encoding

    static func encodeHeaderValue(_ value: String) -> String {
        if value.allSatisfy({ $0.isASCII && $0 != "\r" && $0 != "\n" }) {
            return value
        }
        guard let data = value.data(using: .utf8) else { return value }
        let b64 = data.base64EncodedString()
        return "=?utf-8?B?\(b64)?="
    }

    // MARK: - Quoted-Printable encoding

    static func quotedPrintableEncode(_ text: String) -> String {
        var result: [String] = []
        let lines = text.components(separatedBy: "\n")

        for line in lines {
            let encoded = quotedPrintableEncodeLine(line)
            result.append(contentsOf: wrapQuotedPrintable(encoded))
        }

        return result.joined(separator: "\r\n")
    }

    private static func quotedPrintableEncodeLine(_ line: String) -> String {
        var out = ""
        for byte in line.utf8 {
            if byte == 0x09 || (byte >= 0x20 && byte <= 0x7E && byte != 0x3D) {
                out.append(Character(UnicodeScalar(byte)))
            } else {
                out.append(String(format: "=%02X", byte))
            }
        }
        return out
    }

    private static func wrapQuotedPrintable(_ line: String, maxLen: Int = 76) -> [String] {
        if line.count <= maxLen {
            return [line]
        }
        var lines: [String] = []
        var current = ""
        var i = line.startIndex

        while i < line.endIndex {
            if line[i] == "=" && line.distance(from: i, to: line.endIndex) >= 3 {
                let chunk = String(line[i...line.index(i, offsetBy: 2)])
                if current.count + chunk.count > maxLen - 1 {
                    lines.append(current + "=")
                    current = ""
                }
                current += chunk
                i = line.index(i, offsetBy: 3)
            } else {
                if current.count + 1 > maxLen - 1 {
                    lines.append(current + "=")
                    current = ""
                }
                current.append(line[i])
                i = line.index(after: i)
            }
        }
        if !current.isEmpty {
            lines.append(current)
        }
        return lines
    }

    // MARK: - Message-ID

    static func messageID(seed: String?) -> String {
        let id = seed ?? UUID().uuidString.lowercased()
        return "\(id)@hlexx.privateaimail"
    }

    // MARK: - RFC 5322 Date

    static func rfc5322Date(_ date: Date = Date()) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        fmt.timeZone = TimeZone.current
        return fmt.string(from: date)
    }

    // MARK: - Base64URL

    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func base64URLDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}

public enum MIMEBuilderError: Error {
    case encodingFailed
}
