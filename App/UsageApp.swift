import SwiftUI
import UsageViews

@main
struct UsageApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: delegate.model)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "circle.grid.3x3.fill")
                if let peak = delegate.model.peakPercent { Text(Format.percent(peak)) }
            }
            .accessibilityLabel("Usage")
        }
        .menuBarExtraStyle(.window)

        Window("Accounts", id: AccountsView.windowID) {
            AccountsView(model: delegate.model)
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = UsageModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await model.poll() }
    }
}
