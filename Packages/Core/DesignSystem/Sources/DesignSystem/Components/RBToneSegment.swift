import SwiftUI

/// A 3-button segmented pill for tone selection (Concise / Warm / Direct).
/// Selected state has `rbAccentSoft` background with shadow; each segment shows
/// label + smaller word count.
public struct RBToneSegment<ID: Hashable>: View {
    public struct Segment: Identifiable {
        public var id: ID
        public let label: String
        public let detail: String

        public init(id: ID, label: String, detail: String) {
            self.id = id
            self.label = label
            self.detail = detail
        }
    }

    public let segments: [Segment]
    @Binding public var selection: ID

    public init(segments: [Segment], selection: Binding<ID>) {
        self.segments = segments
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(segments) { segment in
                let isSelected = segment.id == selection
                Button {
                    selection = segment.id
                } label: {
                    HStack(spacing: 4) {
                        Text(segment.label)
                            .font(.rbGeist(12, weight: isSelected ? .medium : .regular))
                            .foregroundStyle(isSelected ? Color.rbFg1 : Color.rbFg3)
                        Text(segment.detail)
                            .font(.rbMono(10))
                            .foregroundStyle(Color.rbFg3)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        isSelected
                            ? AnyShapeStyle(Color.rbAccentSoft)
                            : AnyShapeStyle(Color.clear)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: RBRadius.xs))
                    .shadow(color: isSelected ? .black.opacity(0.12) : .clear, radius: 2, y: 1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.rbBgCanvas)
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: RBRadius.sm)
                .strokeBorder(Color.rbStroke1, lineWidth: 1)
        )
    }
}

#if DEBUG
#Preview("Tone Segment") {
    struct Preview: View {
        @State var tone = "warm"
        var body: some View {
            RBToneSegment(
                segments: [
                    .init(id: "concise", label: "Concise", detail: "42w"),
                    .init(id: "warm", label: "Warm", detail: "61w"),
                    .init(id: "direct", label: "Direct", detail: "28w"),
                ],
                selection: $tone
            )
            .padding()
            .background(Color.rbBgCanvas)
        }
    }
    return Preview()
        .preferredColorScheme(.dark)
}
#endif
