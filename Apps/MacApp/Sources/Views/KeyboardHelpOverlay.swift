import DesignSystem
import SwiftUI

struct KeyboardHelpOverlay: View {

    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.headline)
                    .foregroundStyle(Color.rbFg1)
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.rbFg3)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()
                .background(Color.rbStroke2)

            ScrollView {
                KeyboardCatalogList()
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
            }
        }
        .frame(width: 480, height: 520)
        .background(Color.rbBgElev1)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.rbStroke2, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
    }
}

// MARK: - Display Key Combo

extension ShortcutSpec {
    var displayKeyCombo: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("\u{2303}") }
        if modifiers.contains(.option) { parts.append("\u{2325}") }
        if modifiers.contains(.shift) { parts.append("\u{21E7}") }
        if modifiers.contains(.command) { parts.append("\u{2318}") }

        let keyStr = displayKeyName
        parts.append(keyStr)
        return parts.joined()
    }

    private var displayKeyName: String {
        let char = key.character
        switch char {
        case "\r", "\n": return "\u{21A9}" // Return
        case " ": return "Space"
        case "\u{7F}", "\u{08}": return "\u{232B}" // Delete
        default: break
        }

        // F-keys: NSF5FunctionKey etc. are in the Unicode private use area
        let scalar = char.unicodeScalars.first?.value ?? 0
        if scalar == UInt32(NSF5FunctionKey) { return "F5" }

        // Regular character — uppercase for display
        return String(char).uppercased()
    }
}
