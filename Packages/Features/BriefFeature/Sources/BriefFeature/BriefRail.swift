import DesignSystem
import SwiftUI

/// The AI Brief rail that sits to the right of the thread column (340 px wide).
/// Shows a structured brief when available, or an empty state for informational threads.
public struct BriefRail: View {
    @Bindable var store: BriefStore

    public init(store: BriefStore) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            if store.isLoading {
                loadingState
            } else if store.error != nil {
                errorState
            } else if let brief = store.brief {
                briefContent(brief)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .background(railBackground)
    }

    // MARK: - Brief Content

    @ViewBuilder
    private func briefContent(_ brief: ThreadBriefViewData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Head: eyebrow + confidence
            HStack {
                Text(String(localized: "brief.eyebrow", defaultValue: "\u{25C6} RE:BOX BRIEF \u{00B7} LOCAL"))
                    .font(.rbMono(10.5))
                    .tracking(1.47)
                    .foregroundStyle(Color.rbCitron500)

                Spacer()

                Text("confidence \(Int(brief.confidence * 100))%")
                    .font(.rbMono(10.5))
                    .foregroundStyle(Color.rbFg3)
            }
            .padding(.bottom, 10)

            // Summary
            Text(brief.summary)
                .font(.rbGeist(15, weight: .medium))
                .foregroundStyle(Color.rbFg1)
                .lineSpacing(3)
                .padding(.bottom, 12)

            // Fields grid
            fieldsGrid(brief)
                .padding(.vertical, 10)

            // Evidence
            if !brief.evidence.isEmpty {
                Text("Evidence: \(brief.evidence.joined(separator: " \u{00B7} "))")
                    .font(.rbMono(10.5))
                    .foregroundStyle(Color.rbFg3)
                    .padding(.bottom, 12)
            }

            // CTAs
            ctaRow
        }
    }

    @ViewBuilder
    private func fieldsGrid(_ brief: ThreadBriefViewData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().overlay(Color.rbStroke1)

            if let request = brief.request {
                fieldRow(key: String(localized: "brief.field.request", defaultValue: "REQUEST"), value: request)
            }
            if let deadline = brief.deadline {
                fieldRow(key: String(localized: "brief.field.deadline", defaultValue: "DEADLINE"), value: deadline, valueColor: .rbSignalDeadline)
            }
            if let risk = brief.risk {
                fieldRow(key: String(localized: "brief.field.risk", defaultValue: "RISK"), value: risk)
            }
            if let nextStep = brief.nextStep {
                fieldRow(key: String(localized: "brief.field.nextStep", defaultValue: "NEXT STEP"), value: nextStep)
            }

            Divider().overlay(Color.rbStroke1)
        }
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private func fieldRow(key: String, value: String, valueColor: Color = .rbFg1) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(key)
                .font(.rbMono(10, weight: .medium))
                .tracking(0.14 * 10)
                .foregroundStyle(Color.rbFg3)
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(.rbGeist(12.5))
                .foregroundStyle(valueColor)
        }
    }

    private var ctaRow: some View {
        GeometryReader { geo in
            let narrow = geo.size.width < 360
            let layout = narrow
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout(spacing: 6))
            layout {
                Button {
                } label: {
                    Label(String(localized: "brief.cta.draftReply", defaultValue: "Draft reply"), systemImage: "sparkles")
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .buttonStyle(.rbPrimary)
                .fixedSize(horizontal: false, vertical: true)

                Button {
                } label: {
                    Label(String(localized: "brief.cta.snooze", defaultValue: "Snooze to Fri AM"), systemImage: "clock")
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .buttonStyle(.rbSecondary)
                .fixedSize(horizontal: false, vertical: true)

                Button {
                } label: {
                    Text(String(localized: "brief.cta.logCRM", defaultValue: "Log to CRM"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .buttonStyle(.rbGhost)
                .fixedSize(horizontal: false, vertical: true)

                if !narrow { Spacer() }
            }
        }
        .frame(minHeight: 34, idealHeight: 80)
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "brief.loading.eyebrow", defaultValue: "\u{25C6} THINKING LOCALLY"))
                    .font(.rbMono(10.5))
                    .tracking(1.47)
                    .foregroundStyle(Color.rbSignalLocalAi)
                Spacer()
            }
            .padding(.bottom, 4)

            ProgressView()
                .controlSize(.small)
                .tint(Color.rbCitron500)
        }
        .padding(16)
        .background(Color.rbBgElev1)
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.lg))
    }

    // MARK: - Error State

    private var errorState: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                EyebrowLabel(String(localized: "brief.error.eyebrow", defaultValue: "Re:Box brief"))
                Spacer()
            }

            Text(String(localized: "brief.error.message", defaultValue: "Brief generation failed"))
                .font(.rbGeist(15, weight: .medium))
                .foregroundStyle(Color.rbFg3)
                .lineSpacing(3)

            Button {
                store.retry()
            } label: {
                Text(String(localized: "brief.error.retry", defaultValue: "Retry"))
            }
            .buttonStyle(.rbGhost)
        }
        .padding(16)
        .background(Color.rbBgElev1)
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.lg))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                EyebrowLabel(String(localized: "brief.empty.eyebrow", defaultValue: "Re:Box brief"))
                Spacer()
                Text(String(localized: "brief.empty.status", defaultValue: "no action found"))
                    .font(.rbMono(10.5))
                    .foregroundStyle(Color.rbFg3)
            }

            Text(String(localized: "brief.empty.message", defaultValue: "Nothing to summarize here \u{2014} informational thread."))
                .font(.rbGeist(15, weight: .medium))
                .foregroundStyle(Color.rbFg3)
                .lineSpacing(3)
        }
        .padding(16)
        .background(Color.rbBgElev1)
        .clipShape(RoundedRectangle(cornerRadius: RBRadius.lg))
    }

    // MARK: - Rail Background

    @Environment(\.colorScheme) private var colorScheme

    private var railBackground: some View {
        // CSS: color-mix(in oklch, citron-500 4%/10%, bg-canvas) → bg-canvas
        // Approximate by layering a citron gradient over the canvas
        ZStack {
            Color.rbBgCanvas
            LinearGradient(
                colors: [
                    Color.rbCitron500.opacity(colorScheme == .dark ? 0.04 : 0.10),
                    Color.rbCitron500.opacity(0)
                ],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: colorScheme == .dark ? 0.4 : 0.5)
            )
        }
    }
}

#if DEBUG
#Preview("Brief Rail — with data") {
    let store = BriefStore()
    return BriefRail(store: store)
        .frame(width: RBLayout.briefRailWidth, height: 600)
        .onAppear {
            store.brief = ThreadBriefViewData(
                summary: "Client approved pricing and asks for the contract draft by Friday.",
                request: "Send contract draft",
                deadline: "Fri \u{00B7} May 15",
                risk: "Tight turnaround",
                nextStep: "Draft reply with contract attached",
                confidence: 0.88,
                evidence: ["msg_1", "msg_3", "contract.pdf p.2"]
            )
        }
        .preferredColorScheme(.dark)
}

#Preview("Brief Rail — empty") {
    let store = BriefStore()
    return BriefRail(store: store)
        .frame(width: RBLayout.briefRailWidth, height: 600)
        .preferredColorScheme(.dark)
}
#endif
