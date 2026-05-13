import Testing
import SwiftUI
import AppKit
@testable import DesignSystem

@Suite("Atoms — all components build in both themes")
struct AtomsTests {

    // MARK: - SignalChip

    @MainActor
    @Test func signalChipAllVariantsDark() {
        let view = signalChipGrid()
            .preferredColorScheme(.dark)
            .frame(width: 500, height: 120)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 500, height: 120)
        host.layout()
    }

    @MainActor
    @Test func signalChipAllVariantsLight() {
        let view = signalChipGrid()
            .preferredColorScheme(.light)
            .frame(width: 500, height: 120)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 500, height: 120)
        host.layout()
    }

    private func signalChipGrid() -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                SignalChip(kind: .due(label: "Fri", urgent: false))
                SignalChip(kind: .due(label: "Overdue", urgent: true))
                SignalChip(kind: .reply(label: "Reply"))
                SignalChip(kind: .att(pages: 4))
            }
            HStack(spacing: 6) {
                SignalChip(kind: .ai(label: "AI"))
                SignalChip(kind: .logged(target: "CRM"))
                SignalChip(kind: .cc(label: "CC'd"))
                SignalChip(kind: .cal(label: "Tue"))
                SignalChip(kind: .paid(label: "Paid"))
            }
        }
        .padding()
        .background(Color.rbBgCanvas)
    }

    // MARK: - RBButtonStyle

    @MainActor
    @Test func buttonStylesDark() {
        let view = buttonStylesView()
            .preferredColorScheme(.dark)
            .frame(width: 300, height: 200)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 200)
        host.layout()
    }

    @MainActor
    @Test func buttonStylesLight() {
        let view = buttonStylesView()
            .preferredColorScheme(.light)
            .frame(width: 300, height: 200)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 200)
        host.layout()
    }

    private func buttonStylesView() -> some View {
        VStack(spacing: 12) {
            Button("Primary") {}
                .buttonStyle(.rbPrimary)
            Button("Secondary") {}
                .buttonStyle(.rbSecondary)
            Button("Ghost") {}
                .buttonStyle(.rbGhost)
        }
        .padding()
        .background(Color.rbBgCanvas)
    }

    // MARK: - RBIconButton

    @MainActor
    @Test func iconButtonDark() {
        let view = iconButtonRow()
            .preferredColorScheme(.dark)
            .frame(width: 200, height: 60)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 200, height: 60)
        host.layout()
    }

    @MainActor
    @Test func iconButtonLight() {
        let view = iconButtonRow()
            .preferredColorScheme(.light)
            .frame(width: 200, height: 60)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 200, height: 60)
        host.layout()
    }

    private func iconButtonRow() -> some View {
        HStack(spacing: 4) {
            RBIconButton(systemName: "line.3.horizontal.decrease", accessibilityLabel: "Filter") {}
            RBIconButton(systemName: "sun.max", accessibilityLabel: "Theme") {}
            RBIconButton(systemName: "gearshape", accessibilityLabel: "Settings") {}
        }
        .padding()
        .background(Color.rbBgCanvas)
    }

    // MARK: - LocalAIPill

    @MainActor
    @Test func localAIPillDark() {
        let view = LocalAIPill()
            .padding()
            .background(Color.rbBgCanvas)
            .preferredColorScheme(.dark)
            .frame(width: 250, height: 50)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 250, height: 50)
        host.layout()
    }

    @MainActor
    @Test func localAIPillLight() {
        let view = LocalAIPill()
            .padding()
            .background(Color.rbBgCanvas)
            .preferredColorScheme(.light)
            .frame(width: 250, height: 50)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 250, height: 50)
        host.layout()
    }

    // MARK: - AccountSwitcher

    @MainActor
    @Test func accountSwitcherDark() {
        let view = AccountSwitcher(dotColor: .rbCobalt500, label: "alex@studio.eu") {}
            .padding()
            .background(Color.rbBgCanvas)
            .preferredColorScheme(.dark)
            .frame(width: 250, height: 50)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 250, height: 50)
        host.layout()
    }

    @MainActor
    @Test func accountSwitcherLight() {
        let view = AccountSwitcher(dotColor: .rbCobalt500, label: "alex@studio.eu") {}
            .padding()
            .background(Color.rbBgCanvas)
            .preferredColorScheme(.light)
            .frame(width: 250, height: 50)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 250, height: 50)
        host.layout()
    }

    // MARK: - SearchField

    @MainActor
    @Test func searchFieldDark() {
        let view = SearchField(text: .constant(""))
            .frame(maxWidth: 480)
            .padding()
            .background(Color.rbBgCanvas)
            .preferredColorScheme(.dark)
            .frame(width: 500, height: 60)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 500, height: 60)
        host.layout()
    }

    @MainActor
    @Test func searchFieldLight() {
        let view = SearchField(text: .constant(""))
            .frame(maxWidth: 480)
            .padding()
            .background(Color.rbBgCanvas)
            .preferredColorScheme(.light)
            .frame(width: 500, height: 60)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 500, height: 60)
        host.layout()
    }

    // MARK: - EyebrowLabel

    @MainActor
    @Test func eyebrowLabelDark() {
        let view = VStack(alignment: .leading, spacing: 8) {
            EyebrowLabel("Re:Box brief · local")
            EyebrowLabel("Drafted locally · tone:")
        }
        .padding()
        .background(Color.rbBgCanvas)
        .preferredColorScheme(.dark)
        .frame(width: 300, height: 80)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 80)
        host.layout()
    }

    @MainActor
    @Test func eyebrowLabelLight() {
        let view = VStack(alignment: .leading, spacing: 8) {
            EyebrowLabel("Re:Box brief · local")
            EyebrowLabel("Drafted locally · tone:")
        }
        .padding()
        .background(Color.rbBgCanvas)
        .preferredColorScheme(.light)
        .frame(width: 300, height: 80)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 80)
        host.layout()
    }

    // MARK: - AvatarView

    @MainActor
    @Test func avatarViewDark() {
        let view = HStack(spacing: 8) {
            AvatarView(name: "John Doe", size: 32)
            AvatarView(name: "Sarah Chen", size: 28)
            AvatarView(name: "Alex", size: 40)
        }
        .padding()
        .background(Color.rbBgCanvas)
        .preferredColorScheme(.dark)
        .frame(width: 250, height: 70)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 250, height: 70)
        host.layout()
    }

    @MainActor
    @Test func avatarViewLight() {
        let view = HStack(spacing: 8) {
            AvatarView(name: "John Doe", size: 32)
            AvatarView(name: "Sarah Chen", size: 28)
            AvatarView(name: "Alex", size: 40)
        }
        .padding()
        .background(Color.rbBgCanvas)
        .preferredColorScheme(.light)
        .frame(width: 250, height: 70)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 250, height: 70)
        host.layout()
    }

    // MARK: - AvatarView initials extraction

    @Test func avatarInitialsExtraction() {
        #expect(AvatarView.extractInitials(from: "John Doe") == "JD")
        #expect(AvatarView.extractInitials(from: "Sarah") == "SA")
        #expect(AvatarView.extractInitials(from: "Maria Garcia Lopez") == "ML")
        #expect(AvatarView.extractInitials(from: "") == "?")
    }
}
