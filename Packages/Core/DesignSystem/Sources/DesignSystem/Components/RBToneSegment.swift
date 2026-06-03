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
    public let isEnabled: Bool
    @Binding public var selection: ID

    public init(segments: [Segment], selection: Binding<ID>) {
        self.init(segments: segments, selection: selection, isEnabled: true)
    }

    public init(segments: [Segment], selection: Binding<ID>, isEnabled: Bool = true) {
        self.segments = segments
        self.isEnabled = isEnabled
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(segments) { segment in
                let isSelected = segment.id == selection
                Button {
                    selection = segment.id
                } label: {
                    let shape = RoundedRectangle(cornerRadius: RBRadius.xs)

                    HStack(spacing: 4) {
                        Text(segment.label)
                            .font(.rbGeist(12, weight: isSelected ? .medium : .regular))
                            .foregroundStyle(labelColor(isSelected: isSelected))
                        Text(segment.detail)
                            .font(.rbMono(10))
                            .foregroundStyle(isEnabled ? Color.rbFg3 : Color.rbFg4)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .frame(minHeight: RBControlMetrics.compactHitTarget)
                    .background(
                        isSelected
                            ? AnyShapeStyle(Color.rbAccentSoft)
                            : AnyShapeStyle(Color.clear)
                    )
                    .clipShape(shape)
                    .shadow(
                        color: isEnabled && isSelected ? .black.opacity(0.12) : .clear,
                        radius: 2,
                        y: 1
                    )
                    .contentShape(shape)
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
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

    private func labelColor(isSelected: Bool) -> Color {
        if !isEnabled { return .rbFg4 }
        return isSelected ? .rbFg1 : .rbFg3
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
