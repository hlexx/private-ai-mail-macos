import Testing

// NOTE: Snapshot tests for ModelSetupScene (in-progress, error, idle-before-start)
// in dark and light themes are deferred per NOTES.md — MacAppTests target cannot
// `@testable import MacApp` because MacApp is a .app product, not a framework.
// These stubs confirm the test file compiles. Real snapshot coverage will land
// once RBSidebar/RBToolbar extraction unblocks the MacAppTests target.

@Suite("ModelSetupScene")
struct ModelSetupSceneTests {

    @Test func inProgressState_placeholder() {
        // TODO: snapshot test for in-progress state (dark + light)
        #expect(Bool(true))
    }

    @Test func errorState_placeholder() {
        // TODO: snapshot test for error state (dark + light)
        #expect(Bool(true))
    }

    @Test func idleBeforeStart_placeholder() {
        // TODO: snapshot test for idle-before-start state (dark + light)
        #expect(Bool(true))
    }
}
