import SwiftUI
import UsageKit
import UsageViews

struct AccountsView: View {
    static let windowID = "accounts"

    let model: UsageModel
    @FocusState private var addClaudeFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Accounts")
                .font(.system(size: 18))
                .foregroundStyle(Palette.content.color)

            if let keychainProblem = model.keychainProblem {
                problem(keychainProblem)
            }

            if model.accounts.isEmpty {
                note("Sign in with the account you use in Claude Code or Codex.")
            }
            ForEach(model.accounts) { row($0) }

            if let provider = model.signingIn {
                HStack(spacing: 12) {
                    note("Finish signing in to \(provider.title) in your browser.")
                    Spacer()
                    Button("Cancel", action: model.cancelSignIn).buttonStyle(LinkButtonStyle())
                }
            } else {
                HStack(spacing: 8) {
                    Button("Add Claude Code") { model.signIn(.claude) }
                        .focused($addClaudeFocused)
                    Button("Add Codex") { model.signIn(.codex) }
                }
                .buttonStyle(PillButtonStyle())
            }
            if let accountProblem = model.accountProblem {
                problem(accountProblem)
            }

            Toggle("Open at login", isOn: Binding(
                get: { model.opensAtLogin }, set: { model.setOpensAtLogin($0) }))
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .foregroundStyle(Palette.neutral.color)
        }
        .padding(24)
        .defaultFocus($addClaudeFocused, true)
        .frame(width: 420)
        .background(Palette.base100.color)
        .environment(\.colorScheme, .dark)
        .task { await model.refresh(ifOlderThan: 60) }
    }

    private func row(_ account: StoredAccount) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.content.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(account.id.provider.title) \(account.plan)\(account.grant == nil ? " · sign-in expired" : "")")
                    .font(.system(size: 11))
                    .foregroundStyle((account.grant == nil ? Palette.error : Palette.neutral).color)
            }
            Spacer()
            if account.grant == nil {
                Button("Sign in") { model.signIn(account.id.provider) }
                    .buttonStyle(PillButtonStyle())
                    .disabled(model.signingIn != nil)
            }
            Button("Remove") { Task { await model.remove(account.id) } }
                .buttonStyle(LinkButtonStyle())
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Palette.neutral.color)
    }

    private func problem(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Palette.error.color)
            .fixedSize(horizontal: false, vertical: true)
    }
}
