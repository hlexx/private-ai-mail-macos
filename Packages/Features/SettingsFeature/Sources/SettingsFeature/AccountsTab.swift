import DesignSystem
import MailSync
import Persistence
import SwiftUI

public struct AccountsTab: View {
    @Bindable var store: AccountsTabStore

    public init(store: AccountsTabStore) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "accounts.title", defaultValue: "Connected Accounts"))
                .font(.headline)

            if store.accounts.isEmpty {
                ContentUnavailableView(
                    String(localized: "accounts.empty.title", defaultValue: "No accounts"),
                    systemImage: "person.crop.circle.badge.plus",
                    description: Text(String(
                        localized: "accounts.empty.description",
                        defaultValue: "Add a Gmail account to get started."
                    ))
                )
            } else {
                List {
                    ForEach(store.accounts, id: \.id) { account in
                        accountRow(account)
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            providerSelection

            statusView
        }
        .padding()
        .task {
            store.startObserving()
        }
        .onDisappear {
            store.stopObserving()
        }
        .background(Color.rbBgCanvas)
    }

    @ViewBuilder
    private func accountRow(_ account: AccountRecord) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.email)
                    .font(.body)
                Text(account.displayName ?? account.provider.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let syncState = store.syncStates[account.id], syncState == .bootstrapping {
                ProgressView()
                    .controlSize(.small)
            }

            Button(role: .destructive) {
                store.removeAccount(account.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(String(localized: "accounts.remove.help", defaultValue: "Remove account"))
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var providerSelection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "accounts.providers.title", defaultValue: "Add account"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(store.providerOptions) { option in
                providerOptionRow(option)
            }
        }
    }

    private func providerOptionRow(_ option: AccountProviderOption) -> some View {
        HStack(spacing: 12) {
            Image(systemName: option.systemImage)
                .frame(width: 20)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(option.title)
                        .font(.body)

                    if option.provider == .outlook {
                        Text(String(localized: "accounts.provider.outlook.beta", defaultValue: "Beta"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(option.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if case .disabled(let reason) = option.availability {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(option.actionTitle) {
                store.addAccount(provider: option.provider)
            }
            .disabled(isAddInProgress || !option.isEnabled)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusView: some View {
        switch store.addPhase {
        case .idle, .done:
            EmptyView()
        case .authorizing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(String(localized: "accounts.status.authorizing", defaultValue: "Waiting for authorization..."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .fetchingProfile:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(String(localized: "accounts.status.fetching_profile", defaultValue: "Fetching profile..."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .bootstrapping(let progress):
            HStack(spacing: 8) {
                ProgressView(value: progress)
                    .frame(width: 120)
                Text(String(localized: "accounts.status.syncing", defaultValue: "Syncing messages..."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .error(let message):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                Button(String(localized: "accounts.dismiss", defaultValue: "Dismiss")) {
                    store.dismissError()
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var isAddInProgress: Bool {
        switch store.addPhase {
        case .authorizing, .fetchingProfile, .bootstrapping:
            return true
        default:
            return false
        }
    }
}
