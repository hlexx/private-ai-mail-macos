import Testing
import SwiftUI
@testable import DesignSystem

@Suite("Tokens Cheatsheet")
struct TokensCheatsheetTests {
    @MainActor
    @Test func cheatsheetBuildsInDark() {
        let view = TokensCheatsheet()
            .preferredColorScheme(.dark)
            .frame(width: 600, height: 800)
        _ = NSHostingView(rootView: view)
    }

    @MainActor
    @Test func cheatsheetBuildsInLight() {
        let view = TokensCheatsheet()
            .preferredColorScheme(.light)
            .frame(width: 600, height: 800)
        _ = NSHostingView(rootView: view)
    }
}
