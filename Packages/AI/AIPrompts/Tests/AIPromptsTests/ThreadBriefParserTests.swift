import Foundation
import Testing
@testable import AIPrompts

@Suite("ThreadBriefParser")
struct ThreadBriefParserTests {

    // MARK: - Fixture parsing

    @Test("parses contract approval fixture")
    func parseContractApproval() throws {
        let brief = try parseFixture("contract_approval")
        #expect(brief.summary != nil)
        #expect(brief.request == "Send the contract draft by Friday EOD.")
        #expect(brief.deadline == "Friday EOD")
        #expect(brief.risk != nil)
        #expect(brief.evidence.count == 3)
        #expect(brief.confidence >= 0 && brief.confidence <= 1)
    }

    @Test("parses informational digest fixture with null fields")
    func parseInformationalDigest() throws {
        let brief = try parseFixture("informational_digest")
        #expect(brief.summary != nil)
        #expect(brief.request == nil)
        #expect(brief.deadline == nil)
        #expect(brief.risk == nil)
        #expect(brief.nextStep == nil)
        #expect(brief.confidence == 0.65)
    }

    @Test("parses invoice receipt fixture")
    func parseInvoiceReceipt() throws {
        let brief = try parseFixture("invoice_receipt")
        #expect(brief.summary?.contains("€1,840") == true)
        #expect(brief.request == nil)
        #expect(brief.evidence.count == 1)
    }

    @Test("parses seat count renewal fixture")
    func parseSeatCountRenewal() throws {
        let brief = try parseFixture("seat_count_renewal")
        #expect(brief.request == "Confirm the seat count by Wednesday.")
        #expect(brief.deadline == "Wednesday")
        #expect(brief.nextStep != nil)
    }

    // MARK: - Malformed JSON

    @Test("rejects empty string")
    func rejectEmpty() {
        #expect(throws: ThreadBriefParser.ParseError.self) {
            try ThreadBriefParser.parse("")
        }
    }

    @Test("rejects non-JSON text")
    func rejectPlainText() {
        #expect(throws: ThreadBriefParser.ParseError.self) {
            try ThreadBriefParser.parse("This is not JSON at all.")
        }
    }

    @Test("rejects truncated JSON")
    func rejectTruncated() {
        let truncated = """
            {"summary": "test", "evidence": ["a"]
            """
        #expect(throws: ThreadBriefParser.ParseError.self) {
            try ThreadBriefParser.parse(truncated)
        }
    }

    // MARK: - Schema violations

    @Test("accepts missing evidence field with default empty evidence")
    func acceptsMissingEvidence() throws {
        let json = """
            {"summary": "test", "confidence": 0.5}
            """
        let brief = try ThreadBriefParser.parse(json)
        #expect(brief.summary == "test")
        #expect(brief.evidence.isEmpty)
    }

    @Test("accepts missing confidence field with default confidence")
    func acceptsMissingConfidence() throws {
        let json = """
            {"summary": "test", "evidence": ["a"]}
            """
        let brief = try ThreadBriefParser.parse(json)
        #expect(brief.summary == "test")
        #expect(brief.confidence == 0.7)
    }

    @Test("rejects confidence out of range (above 1)")
    func rejectConfidenceAbove1() {
        let json = """
            {"summary": "test", "evidence": ["a"], "confidence": 1.5}
            """
        #expect {
            try ThreadBriefParser.parse(json)
        } throws: { error in
            guard let parseError = error as? ThreadBriefParser.ParseError,
                  case .schemaViolation(let msg) = parseError else { return false }
            return msg.contains("confidence")
        }
    }

    @Test("rejects confidence below 0")
    func rejectConfidenceBelow0() {
        let json = """
            {"summary": "test", "evidence": ["a"], "confidence": -0.1}
            """
        #expect {
            try ThreadBriefParser.parse(json)
        } throws: { error in
            guard let parseError = error as? ThreadBriefParser.ParseError,
                  case .schemaViolation(let msg) = parseError else { return false }
            return msg.contains("confidence")
        }
    }

    @Test("ignores extra fields from local model output")
    func ignoresExtraFields() throws {
        let json = """
            {"summary": "test", "evidence": ["a"], "confidence": 0.5, "foo": "bar"}
            """
        let brief = try ThreadBriefParser.parse(json)
        #expect(brief.summary == "test")
        #expect(brief.confidence == 0.5)
    }

    @Test("accepts string evidence from local model output")
    func acceptsStringEvidence() throws {
        let json = """
            {"summary": "test", "evidence": "not an array", "confidence": 0.5}
            """
        let brief = try ThreadBriefParser.parse(json)
        #expect(brief.evidence == ["not an array"])
    }

    @Test("accepts common aliases")
    func acceptsCommonAliases() throws {
        let json = """
            {"summary": "test", "next_step": "Reply later", "evidence": [], "confidence_score": "0.6"}
            """
        let brief = try ThreadBriefParser.parse(json)
        #expect(brief.nextStep == "Reply later")
        #expect(brief.confidence == 0.6)
    }

    @Test("accepts seeded duplicate opening brace")
    func acceptsSeededDuplicateOpeningBrace() throws {
        let json = """
            {{"summary": "Payment update needed", "evidence": ["Payment failed"], "confidence": 0.8}}
            """
        let brief = try ThreadBriefParser.parse(json)
        #expect(brief.summary == "Payment update needed")
        #expect(brief.confidence == 0.8)
    }

    @Test("accepts nested brief object")
    func acceptsNestedBriefObject() throws {
        let json = """
            {"brief": {"summary": "Payment update needed", "evidence": ["Payment failed"], "confidence": "0.75"}}
            """
        let brief = try ThreadBriefParser.parse(json)
        #expect(brief.summary == "Payment update needed")
        #expect(brief.evidence == ["Payment failed"])
        #expect(brief.confidence == 0.75)
    }

    @Test("rejects empty object")
    func rejectsEmptyObject() {
        #expect(throws: ThreadBriefParser.ParseError.self) {
            try ThreadBriefParser.parse("{}")
        }
    }

    // MARK: - Markdown fence handling

    @Test("strips markdown json fence")
    func stripMarkdownFence() throws {
        let fenced = """
            ```json
            {"summary": "test", "evidence": ["a"], "confidence": 0.8}
            ```
            """
        let brief = try ThreadBriefParser.parse(fenced)
        #expect(brief.summary == "test")
        #expect(brief.confidence == 0.8)
    }

    @Test("strips generic markdown fence")
    func stripGenericFence() throws {
        let fenced = """
            ```
            {"summary": "test", "evidence": [], "confidence": 0.5}
            ```
            """
        let brief = try ThreadBriefParser.parse(fenced)
        #expect(brief.summary == "test")
    }

    @Test("extracts JSON from surrounding text")
    func extractFromSurroundingText() throws {
        let messy = """
            Here is the analysis:
            {"summary": "test brief", "evidence": ["e1"], "confidence": 0.7}
            Hope this helps!
            """
        let brief = try ThreadBriefParser.parse(messy)
        #expect(brief.summary == "test brief")
        #expect(brief.confidence == 0.7)
    }

    // MARK: - Null mapping

    @Test("maps JSON null to Swift nil correctly")
    func nullMapping() throws {
        let json = """
            {
              "summary": "informational",
              "request": null,
              "deadline": null,
              "risk": null,
              "nextStep": null,
              "evidence": [],
              "confidence": 0.6
            }
            """
        let brief = try ThreadBriefParser.parse(json)
        #expect(brief.summary == "informational")
        #expect(brief.request == nil)
        #expect(brief.deadline == nil)
        #expect(brief.risk == nil)
        #expect(brief.nextStep == nil)
        #expect(brief.evidence.isEmpty)
    }

    // MARK: - Helpers

    private func parseFixture(_ name: String) throws -> ParsedThreadBrief {
        let fixtureURL = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? fixtureURLFromTestDir(name)
        let data = try Data(contentsOf: fixtureURL)
        let json = String(data: data, encoding: .utf8)!
        return try ThreadBriefParser.parse(json)
    }

    private func fixtureURLFromTestDir(_ name: String) -> URL {
        let thisFile = URL(fileURLWithPath: #filePath)
        return thisFile
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("\(name).json")
    }
}
