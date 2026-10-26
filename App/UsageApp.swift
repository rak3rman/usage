import SwiftUI
import UsageViews

@main
struct UsageApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: delegate.model)
        } label: {
            Image(nsImage: MenuBarMeter.image(percent: delegate.model.peakPercent))
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
