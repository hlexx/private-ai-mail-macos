import SwiftUI
import Testing

@testable import PrivateAIMail

@Suite("KeyboardShortcutCatalog")
struct KeyboardShortcutCatalogTests {

    @Test("Every ActionKey case appears in ShortcutSpec.all")
    func allActionKeysCovered() {
        let catalogActionKeys = Set(ShortcutSpec.all.map(\.actionKey))
        for actionKey in ActionKey.allCases {
            #expect(
                catalogActionKeys.contains(actionKey),
                "ActionKey.\(actionKey.rawValue) is missing from ShortcutSpec.all"
            )
        }
    }

    @Test("No duplicate key+modifiers+scope triple")
    func noDuplicateBindings() {
        var seen = Set<String>()
        for spec in ShortcutSpec.all {
            let keyChar = String(spec.key.character)
            let triple = "\(keyChar)|\(spec.modifiers.rawValue)|\(spec.scope.rawValue)"
            #expect(
                !seen.contains(triple),
                "Duplicate binding for \(spec.id): \(triple)"
            )
            seen.insert(triple)
        }
    }

    @Test("All specs have non-empty id and label")
    func specsHaveMetadata() {
        for spec in ShortcutSpec.all {
            #expect(!spec.id.isEmpty)
            #expect(!spec.label.isEmpty)
        }
    }

    @Test("Catalog has expected minimum count")
    func catalogSize() {
        #expect(ShortcutSpec.all.count >= 22)
    }
}
