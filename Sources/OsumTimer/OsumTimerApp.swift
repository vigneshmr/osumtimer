import AppKit

/// Plain AppKit, not a SwiftUI `App`: the menu bar is driven by
/// StatusItemController, and a SwiftUI app with no window scene opens its
/// `Settings` scene on launch. See `SettingsWindow`.
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let notifier = Notifier()
    private var store: TimerStore?
    private var statusItems: StatusItemController?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.mainMenu = mainMenu()
        app.run()
    }

    /// Never shown — the app has no menu bar of its own — but its key
    /// equivalents are what make ⌘, ⌘W ⌘Q and copy/paste in the panel's text
    /// field work while the app is active.
    private static func mainMenu() -> NSMenu {
        func item(_ title: String, _ action: Selector?, _ key: String, _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            return item
        }
        func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            parent.submenu = menu
            return parent
        }

        let settings = item("Settings…", #selector(openSettings(_:)), ",")
        let main = NSMenu()
        main.addItem(submenu("OsumTimer", [
            settings,
            .separator(),
            item("Quit OsumTimer", #selector(NSApplication.terminate(_:)), "q"),
        ]))
        main.addItem(submenu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
        ]))
        main.addItem(submenu("Window", [
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
        ]))
        return main
    }

    @objc private func openSettings(_ sender: Any?) {
        SettingsWindow.show()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar only: no Dock icon, no main menu.
        NSApp.setActivationPolicy(.accessory)
        // The system tooltip delay (~1s+) is too slow for icon-only buttons.
        // Registered, not set, so a `defaults write` override still wins.
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 150])
        if DebugRender.runIfRequested() { return }
        if handOffToRunningInstance() { return }
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

    /// Launch Services only routes a launch to the running copy when it is the
    /// same bundle on disk. Opening another copy — the build directory, the
    /// mounted disk image — starts a second process: a second menu bar item,
    /// and two stores writing over each other's file. So a launch that finds
    /// OsumTimer already running reopens that one, the way opening it again
    /// normally would, and quits before it has touched anything.
    ///
    /// Reopened through `openApplication`, not a notification of our own: it
    /// lands on the existing reopen handler, so it works on an older copy too.
    private func handOffToRunningInstance() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != me && !$0.isTerminated }
        guard let running = others.min(by: { ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast) }),
              let url = running.bundleURL else { return false }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        return true
    }

    /// Opening the app while it is already running arrives as a reopen Apple
    /// event, taken straight off the event manager.
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
