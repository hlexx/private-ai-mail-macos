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

            HStack {
                addButton
                Spacer()
            }

            statusView
        }
        .padding()
        .task {
            store.startObserving()
        }
        .onDisappear {
            store.stopObserving()
        }
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
    private var addButton: some View {
        Button {
            store.addGmailAccount()
        } label: {
            Label(
                String(localized: "accounts.add.gmail", defaultValue: "Add Gmail account"),
                systemImage: "plus"
            )
        }
        .disabled(isAddInProgress)
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
