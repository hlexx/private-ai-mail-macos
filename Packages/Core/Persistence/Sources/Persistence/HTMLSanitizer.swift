import Foundation

/// Utilities for cleaning HTML before plaintext extraction or AI input.
public enum HTMLSanitizer {
    /// Strip `<style>…</style>` and `<script>…</script>` blocks from HTML.
    /// Prevents CSS rule text from leaking into plaintext extraction and AI input.
    public static func stripStyleAndScript(_ html: String) -> String {
        html
            .replacingOccurrences(
                of: "<style[^>]*>[\\s\\S]*?</style>",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(
                of: "<script[^>]*>[\\s\\S]*?</script>",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
    }
}
