import Testing
@testable import AIEmbeddings

@Suite("AIEmbeddings")
struct AIEmbeddingsTests {
    @Test func moduleNameIsExported() {
        #expect(AIEmbeddings.moduleName == "AIEmbeddings")
    }
}
