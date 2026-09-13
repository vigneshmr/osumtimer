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
        // Reading it is what registers the login item on a first run; nothing
        // else is guaranteed to touch preferences before you open Settings.
        _ = Preferences.shared.launchAtLogin

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
            return
        }

        installReopenHandler()
        presentDraftPanel()
    }

    /// Opening the app while it is already running arrives as a reopen Apple
    /// event. Taken straight off the event manager rather than through
    /// `applicationShouldHandleReopen`, which SwiftUI's scene machinery swallows
    /// for an app whose only scene is `Settings`.
    private func installReopenHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleReopen(_:with:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEReopenApplication)
        )
    }

    @objc private func handleReopen(_ event: NSAppleEventDescriptor, with reply: NSAppleEventDescriptor) {
        presentDraftPanel()
    }

    private func presentDraftPanel() {
        guard let store else { return }
        let id = store.slots.first(where: \.isDraft)?.id ?? store.addSlot()
        // The status item for a new slot is created by the observer that watches
        // the store; the notification syncs the bar first, so there is something
        // to hang the panel off either way.
        NotificationCenter.default.post(name: .osumOpenPanel, object: id)
    }
}
