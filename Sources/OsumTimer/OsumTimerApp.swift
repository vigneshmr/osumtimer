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
        if DebugRender.runIfRequested() { return }
        notifier.requestAuthorization()

        let store = TimerStore(notifier: notifier)
        self.store = store
        self.statusItems = StatusItemController(store: store)

        // Seeds two running timers so the menu bar can be inspected in a screenshot.
        if ProcessInfo.processInfo.environment["OSUMTIMER_DEMO"] != nil {
            store.start(store.slots[0].id, with: .init(duration: 1500, tag: "focus", echo: "25 min"))
            store.start(store.addSlot(), with: .init(duration: 600, tag: nil, echo: "10 min"))
            let first = store.slots[0].id
            if ProcessInfo.processInfo.environment["OSUMTIMER_DEMO"] == "paused" {
                store.togglePause(first)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.statusItems?.openPanel(for: first)
            }
        }
    }
}
