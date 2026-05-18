import Testing
@testable import Persistence

@Suite("HTMLSanitizer")
struct HTMLSanitizerTests {

    @Test func stripsStyleBlocks() {
        let html = """
        <html><head><style type="text/css">
        body, table, td { font-family: Arial, Helvetica, sans-serif !important; }
        .mso-line-height-rule { mso-line-height-rule: exactly; }
        </style></head><body><h1>Summer Sale</h1></body></html>
        """
        let result = HTMLSanitizer.stripStyleAndScript(html)
        #expect(!result.contains("font-family"))
        #expect(!result.contains("mso-line-height-rule"))
        #expect(result.contains("<h1>Summer Sale</h1>"))
    }

    @Test func stripsMultipleStyleBlocks() {
        let html = """
        <style>a { color: red; }</style>
        <p>Hello</p>
        <STYLE type="text/css">b { font-weight: bold; }</STYLE>
        <p>World</p>
        """
        let result = HTMLSanitizer.stripStyleAndScript(html)
        #expect(!result.contains("color: red"))
        #expect(!result.contains("font-weight"))
        #expect(result.contains("<p>Hello</p>"))
        #expect(result.contains("<p>World</p>"))
    }

    @Test func stripsScriptBlocks() {
        let html = """
        <script>var x = 1;</script>
        <p>Content</p>
        <script type="text/javascript">console.log("track");</script>
        """
        let result = HTMLSanitizer.stripStyleAndScript(html)
        #expect(!result.contains("var x"))
        #expect(!result.contains("console.log"))
        #expect(result.contains("<p>Content</p>"))
    }

    @Test func caseInsensitive() {
        let html = "<STYLE>body{color:red}</STYLE><Script>alert(1)</Script><p>OK</p>"
        let result = HTMLSanitizer.stripStyleAndScript(html)
        #expect(!result.contains("color:red"))
        #expect(!result.contains("alert"))
        #expect(result.contains("<p>OK</p>"))
    }

    @Test func preservesHtmlWithoutStyleOrScript() {
        let html = "<h1>Hello</h1><p>World</p>"
        let result = HTMLSanitizer.stripStyleAndScript(html)
        #expect(result == html)
    }

    @Test func messageRecordHtmlToPlainTextStripsCSS() {
        let html = """
        <html><head><style>body { font-family: Arial !important; }</style></head>
        <body><p>Summer Sale 20% off</p></body></html>
        """
        let plain = MessageRecord.htmlToPlainText(html)
        #expect(plain != nil)
        #expect(plain!.contains("Summer Sale"))
        #expect(!plain!.contains("font-family"))
        #expect(!plain!.contains("Arial"))
    }
}
