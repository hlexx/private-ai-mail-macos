import AuthKit
import DesignSystem
import Persistence
import SwiftUI

public struct PrivacyTab: View {
    @Bindable var store: AccountsTabStore

    public init(store: AccountsTabStore) {
        self.store = store
    }

    public var body: some View {
        let state = PrivacySettingsState.make(
            accounts: store.accounts,
            reauthorizationPhases: store.reauthorizationPhases
        )

        Form {
            ForEach(state.sections) { section in
                Section {
                    ForEach(section.rows) { row in
                        rowView(row)
                    }
                } header: {
                    Text(section.title.defaultValue)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.rbBgCanvas)
        .padding()
        .task {
            store.startObserving()
        }
        .onDisappear {
            store.stopObserving()
        }
    }

    private func rowView(_ row: PrivacySettingsRow) -> some View {
        HStack(alignment: .top, spacing: RBSpace.s4) {
            privacyCopyView(row)
                .frame(
                    minWidth: PrivacySettingsLayout.copyColumnMinWidth,
                    maxWidth: PrivacySettingsLayout.detailMaxWidth,
                    alignment: .leading
                )

            Spacer(minLength: RBSpace.s3)

            if row.accessory != nil {
                accessoryView(row.accessory)
                    .frame(
                        width: PrivacySettingsLayout.accessoryColumnWidth,
                        alignment: .trailing
                    )
                    .padding(.top, PrivacySettingsLayout.accessoryTopPadding)
            }
        }
        .padding(.vertical, RBSpace.s2)
    }

    private func privacyCopyView(_ row: PrivacySettingsRow) -> some View {
        VStack(alignment: .leading, spacing: RBSpace.s1) {
            Text(row.title.defaultValue)
                .font(.body)

            if let detail = row.detail {
                Text(detail.defaultValue)
                    .font(.caption)
                    .foregroundStyle(Color.rbFg3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func accessoryView(_ accessory: PrivacySettingsAccessory?) -> some View {
        switch accessory {
        case .none:
            EmptyView()
        case .status(let text):
            Text(text.defaultValue)
                .font(.caption)
                .foregroundStyle(Color.rbFg3)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: PrivacySettingsLayout.accessoryMaxWidth, alignment: .trailing)
                .fixedSize(horizontal: false, vertical: true)
        case .progress(let text):
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(text.defaultValue)
                    .font(.caption)
                    .foregroundStyle(Color.rbFg3)
            }
            .frame(maxWidth: PrivacySettingsLayout.accessoryMaxWidth, alignment: .trailing)
            .fixedSize(horizontal: false, vertical: true)
        case .button(let text, let action, let isEnabled):
            Button(text.defaultValue) {
                perform(action)
            }
            .controlSize(.small)
            .disabled(!isEnabled)
        case .destructiveButton(let text, let action, let isEnabled):
            Button(role: .destructive) {
                perform(action)
            } label: {
                Text(text.defaultValue)
            }
            .controlSize(.small)
            .disabled(!isEnabled)
        }
    }

    private func perform(_ action: PrivacySettingsAction) {
        switch action {
        case .reauthorize(let accountId):
            store.reauthorizeAccount(accountId)
        case .removeAccount(let accountId):
            store.removeAccount(accountId)
        }
    }
}

enum PrivacySettingsLayout {
    static let detailMaxWidth: CGFloat = 520
    static let accessoryMaxWidth: CGFloat = 180
    static let copyColumnMinWidth: CGFloat = 360
    static let accessoryColumnWidth: CGFloat = 190
    static let accessoryTopPadding: CGFloat = 1
}
