import SwiftUI
import UsageKit
import UsageViews

struct PopoverView: View {
    let model: UsageModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Usage")
                .font(.system(size: 18))
                .foregroundStyle(Palette.content.color)

            if let keychainProblem = model.keychainProblem {
                Text(keychainProblem)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.error.color)
            } else if let snapshot = model.snapshot, !snapshot.accounts.isEmpty {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(snapshot.accounts) { AccountRow($0, now: context.date) }
                    }
                }
            } else {
                Text("No accounts yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.neutral.color)
                Button("Add an account…", action: openAccounts).buttonStyle(PillButtonStyle())
            }

            HStack(spacing: 16) {
                Button("Accounts…", action: openAccounts)
                Button("Refresh") { Task { await model.refresh() } }
                    .disabled(model.isRefreshing)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(LinkButtonStyle())
        }
        .padding(20)
        .frame(width: 360)
        .background(Palette.base100.color)
        .environment(\.colorScheme, .dark)
        .task { await model.refresh(ifOlderThan: 60) }
    }

    private func openAccounts() {
        openWindow(id: AccountsView.windowID)
        NSApp.activate(ignoringOtherApps: true)
    }
}
