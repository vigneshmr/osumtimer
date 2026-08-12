import SwiftUI

@main
struct OsumTimerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The menu bar is driven by StatusItemController, not by a scene — the
        // app needs one declared scene regardless, and Settings is the inert choice.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let notifier = Notifier()
    private var store: TimerStore?
    private var statusItems: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar only: no Dock icon, no main menu.
        NSApp.setActivationPolicy(.accessory)
        notifier.requestAuthorization()

        let store = TimerStore(notifier: notifier)
        self.store = store
        self.statusItems = StatusItemController(store: store)

        if ProcessInfo.processInfo.environment["OSUMTIMER_DEMO"] != nil {
            store.add(.init(duration: 1500, tag: "focus", echo: "25 min"))
            store.add(.init(duration: 600, tag: nil, echo: "10 min"))
        }
    }
}
