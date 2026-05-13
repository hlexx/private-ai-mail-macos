import SwiftUI

/// Mono uppercase tracking-eyebrow label, used for section headers like
/// "Re:Box brief · local", "Drafted locally · tone:", etc.
public struct EyebrowLabel: View {
    public let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text.uppercased())
            .rbTextStyle(.eyebrow)
            .foregroundStyle(Color.rbFg3)
    }
}

#if DEBUG
#Preview("Eyebrow Labels") {
    VStack(alignment: .leading, spacing: 12) {
        EyebrowLabel("Re:Box brief · local")
        EyebrowLabel("Drafted locally · tone:")
        EyebrowLabel("What should I do with this thread?")
    }
    .padding()
    .background(Color.rbBgCanvas)
    .preferredColorScheme(.dark)
}
#endif
