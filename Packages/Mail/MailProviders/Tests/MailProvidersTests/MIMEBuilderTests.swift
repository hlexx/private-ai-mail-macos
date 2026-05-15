import Testing
import Foundation
@testable import MailProviders
import MailDomain

@Suite("MIMEBuilder")
struct MIMEBuilderTests {

    // MARK: - Plain ASCII subject + body

    @Test func plainASCIIMessage() throws {
        let msg = OutgoingMessage(
            from: Address(name: "Alice", email: "alice@example.com"),
            to: [Address(name: "Bob", email: "bob@example.com")],
            subject: "Hello Bob",
            body: "Hi Bob, how are you?",
            messageIDSeed: "test-id-001"
        )

        let raw = MIMEBuilder.buildRFC5322(msg)

        #expect(raw.contains("From: Alice <alice@example.com>\r\n"))
        #expect(raw.contains("To: Bob <bob@example.com>\r\n"))
        #expect(raw.contains("Subject: Hello Bob\r\n"))
        #expect(raw.contains("Message-ID: <test-id-001@hlexx.privateaimail>\r\n"))
        #expect(raw.contains("Content-Type: text/plain; charset=utf-8\r\n"))
        #expect(raw.contains("Content-Transfer-Encoding: quoted-printable\r\n"))
        #expect(raw.contains("Hi Bob, how are you?"))
        // Verify CRLF line endings throughout
        #expect(!raw.contains("\r\n\n"))
        let lines = raw.components(separatedBy: "\r\n")
        #expect(lines.count > 5)
    }

    // MARK: - UTF-8 subject RFC 2047

    @Test func utf8SubjectEncodedAsRFC2047() throws {
        let msg = OutgoingMessage(
            from: Address(email: "sender@example.com"),
            to: [Address(email: "recipient@example.com")],
            subject: "Контракт — Acme",
            body: "Details inside.",
            messageIDSeed: "test-id-002"
        )

        let raw = MIMEBuilder.buildRFC5322(msg)

        // Subject must be RFC 2047 B-encoded
        #expect(raw.contains("Subject: =?utf-8?B?"))
        // Verify the encoded value decodes back
        let subjectLine = raw.components(separatedBy: "\r\n").first(where: { $0.hasPrefix("Subject:") })!
        let encoded = subjectLine.replacingOccurrences(of: "Subject: =?utf-8?B?", with: "")
            .replacingOccurrences(of: "?=", with: "")
        let decoded = Data(base64Encoded: encoded).flatMap { String(data: $0, encoding: .utf8) }
        #expect(decoded == "Контракт — Acme")
    }

    // MARK: - Multi-recipient To and Cc

    @Test func multiRecipientToAndCc() throws {
        let msg = OutgoingMessage(
            from: Address(email: "sender@example.com"),
            to: [
                Address(name: "Bob", email: "bob@example.com"),
                Address(email: "carol@example.com"),
            ],
            cc: [
                Address(name: "Dave", email: "dave@example.com"),
                Address(email: "eve@example.com"),
            ],
            subject: "Group message",
            body: "Hello all",
            messageIDSeed: "test-id-003"
        )

        let raw = MIMEBuilder.buildRFC5322(msg)

        #expect(raw.contains("To: Bob <bob@example.com>, carol@example.com\r\n"))
        #expect(raw.contains("Cc: Dave <dave@example.com>, eve@example.com\r\n"))
    }

    // MARK: - In-Reply-To and References

    @Test func inReplyToPopulatesHeaders() throws {
        let msg = OutgoingMessage(
            from: Address(email: "sender@example.com"),
            to: [Address(email: "recipient@example.com")],
            subject: "Re: Original",
            body: "Reply body",
            inReplyTo: "<original@mail.example.com>",
            references: ["<root@mail.example.com>"],
            messageIDSeed: "test-id-004"
        )

        let raw = MIMEBuilder.buildRFC5322(msg)

        #expect(raw.contains("In-Reply-To: <original@mail.example.com>\r\n"))
        #expect(raw.contains("References: <root@mail.example.com> <original@mail.example.com>\r\n"))
    }

    // MARK: - Base64URL output validity

    @Test func outputIsValidBase64URL() throws {
        let msg = OutgoingMessage(
            from: Address(email: "sender@example.com"),
            to: [Address(email: "recipient@example.com")],
            subject: "Test",
            body: "Hello world with special chars: +/= and more",
            messageIDSeed: "test-id-005"
        )

        let encoded = try MIMEBuilder.encode(msg)

        // Must not contain standard base64 chars that base64url replaces
        #expect(!encoded.contains("+"))
        #expect(!encoded.contains("/"))
        #expect(!encoded.contains("="))
        #expect(!encoded.contains(" "))
        #expect(!encoded.contains("\n"))
        #expect(!encoded.contains("\r"))
        // Must be non-empty
        #expect(!encoded.isEmpty)
        // Must decode back
        let decoded = MIMEBuilder.base64URLDecode(encoded)
        #expect(decoded != nil)
    }

    // MARK: - Round-trip decode and verify fields

    @Test func roundTripDecodeVerifiesFields() throws {
        let msg = OutgoingMessage(
            from: Address(name: "Alice Sender", email: "alice@example.com"),
            to: [Address(name: "Bob Receiver", email: "bob@example.com")],
            cc: [Address(email: "cc@example.com")],
            subject: "Test Round Trip",
            body: "This is the body text.",
            inReplyTo: "<orig@mail.example.com>",
            references: ["<root@mail.example.com>"],
            messageIDSeed: "roundtrip-seed"
        )

        let encoded = try MIMEBuilder.encode(msg)
        let decoded = MIMEBuilder.base64URLDecode(encoded)
        #expect(decoded != nil)

        let raw = String(data: decoded!, encoding: .utf8)!

        #expect(raw.contains("From: Alice Sender <alice@example.com>"))
        #expect(raw.contains("To: Bob Receiver <bob@example.com>"))
        #expect(raw.contains("Cc: cc@example.com"))
        #expect(raw.contains("Subject: Test Round Trip"))
        #expect(raw.contains("In-Reply-To: <orig@mail.example.com>"))
        #expect(raw.contains("References: <root@mail.example.com> <orig@mail.example.com>"))
        #expect(raw.contains("Message-ID: <roundtrip-seed@hlexx.privateaimail>"))
        #expect(raw.contains("This is the body text."))
    }

    // MARK: - UTF-8 display name encoding

    @Test func utf8DisplayNameEncoded() throws {
        let msg = OutgoingMessage(
            from: Address(name: "Алексей", email: "alex@example.com"),
            to: [Address(email: "bob@example.com")],
            subject: "Hello",
            body: "Hi",
            messageIDSeed: "test-id-006"
        )

        let raw = MIMEBuilder.buildRFC5322(msg)

        // Display name should be RFC 2047 encoded
        #expect(raw.contains("From: =?utf-8?B?"))
        #expect(raw.contains("<alex@example.com>"))
    }

    // MARK: - Bcc header present in MIME

    @Test func bccHeaderPresent() throws {
        let msg = OutgoingMessage(
            from: Address(email: "sender@example.com"),
            to: [Address(email: "to@example.com")],
            bcc: [Address(email: "secret@example.com")],
            subject: "BCC test",
            body: "Hidden copy",
            messageIDSeed: "test-id-007"
        )

        let raw = MIMEBuilder.buildRFC5322(msg)
        #expect(raw.contains("Bcc: secret@example.com\r\n"))
    }

    // MARK: - Quoted-printable encodes non-ASCII body

    @Test func quotedPrintableEncodesNonASCII() throws {
        let msg = OutgoingMessage(
            from: Address(email: "sender@example.com"),
            to: [Address(email: "to@example.com")],
            subject: "Test",
            body: "Привет мир",
            messageIDSeed: "test-id-008"
        )

        let raw = MIMEBuilder.buildRFC5322(msg)

        // Body should be QP-encoded (non-ASCII bytes as =XX)
        let bodyStart = raw.range(of: "\r\n\r\n")!.upperBound
        let bodyPart = String(raw[bodyStart...])
        #expect(bodyPart.contains("="))
        #expect(!bodyPart.contains("Привет"))
    }
}
