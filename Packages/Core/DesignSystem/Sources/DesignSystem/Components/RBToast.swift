import SwiftUI

public struct RBToast: View {
    let message: String
    let systemImage: String

    public init(_ message: String, systemImage: String = "checkmark.circle.fill") {
        self.message = message
        self.systemImage = systemImage
    }

    public var body: some View {
        HStack(spacing: RBSpace.s2) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.rbSignalSuccess)
            Text(message)
                .rbTextStyle(.bodySM)
                .foregroundStyle(Color.rbFg1)
        }
        .padding(.horizontal, RBSpace.s4)
        .padding(.vertical, RBSpace.s2)
        .background(Color.rbBgElev2)
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.md))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
    }
}
