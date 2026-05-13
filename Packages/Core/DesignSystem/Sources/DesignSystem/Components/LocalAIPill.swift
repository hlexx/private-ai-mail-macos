import SwiftUI

/// Pill with a 6 px citron dot + "Local AI · M-series" text.
public struct LocalAIPill: View {
    public init() {}

    public var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.rbCitron500)
                .frame(width: 6, height: 6)
                .shadow(color: Color.rbCitron500.opacity(0.3), radius: 3, x: 0, y: 0)
            Text(String(localized: "pill.localAI", defaultValue: "LOCAL AI · M-SERIES"))
                .font(.rbMono(10.5, weight: .semibold))
                .tracking(0.06 * 10.5)
        }
        .foregroundStyle(Color.rbSignalLocalAi)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.rbSignalLocalAiBg)
        .clipShape(Capsule())
    }
}

#if DEBUG
#Preview("LocalAIPill") {
    LocalAIPill()
        .padding()
        .background(Color.rbBgCanvas)
        .preferredColorScheme(.dark)
}
#endif
