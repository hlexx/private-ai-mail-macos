import SwiftUI

/// Pill containing a magnifying-glass SF Symbol, a TextField with placeholder, and a trailing keyboard hint.
public struct SearchField: View {
    @Binding public var text: String
    public let onCommit: () -> Void
    var isFocused: FocusState<Bool>.Binding

    public init(text: Binding<String>, isFocused: FocusState<Bool>.Binding, onCommit: @escaping () -> Void = {}) {
        self._text = text
        self.isFocused = isFocused
        self.onCommit = onCommit
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(Color.rbFg3)

            TextField(
                String(localized: "search.placeholder", defaultValue: "Search or ask Re:Box (last week, contracts, due Friday\u{2026})"),
                text: $text
            )
            .textFieldStyle(.plain)
            .font(.rbGeist(13))
            .foregroundStyle(Color.rbFg1)
            .focused(isFocused)
            .onSubmit(onCommit)
            .onKeyPress(.escape) {
                if !text.isEmpty {
                    text = ""
                    return .handled
                }
                isFocused.wrappedValue = false
                return .handled
            }

            Text("\u{2318}L")
                .font(.rbMono(10))
                .foregroundStyle(Color.rbFg3)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.rbStroke1, lineWidth: 1)
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.rbBgElev1)
        .overlay(
            Capsule()
                .strokeBorder(Color.rbStroke1, lineWidth: 1)
        )
        .clipShape(Capsule())
    }
}

#if DEBUG
struct SearchFieldPreview: View {
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        SearchField(text: $text, isFocused: $focused)
            .frame(maxWidth: 480)
            .padding()
            .background(Color.rbBgCanvas)
    }
}

#Preview("Search Field") {
    SearchFieldPreview()
        .preferredColorScheme(.dark)
}
#endif
