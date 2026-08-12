import AppKit
import SwiftUI
import Observation

/// Owns the menu bar: one permanent "home" item that opens the input popover,
/// plus one status item per running timer, side by side.
///
/// `MenuBarExtra` is a static scene, so it cannot express "N items, created and
/// destroyed as timers come and go" — that requires driving `NSStatusItem`
/// directly. This class is the only AppKit surface in the app.
@MainActor
final class StatusItemController {
    private let store: TimerStore
    private let home: NSStatusItem
    private var items: [UUID: NSStatusItem] = [:]
    /// Last string rendered per item, so an unchanged "1:23" never repaints.
    private var titles: [UUID: String] = [:]
    private let popover = NSPopover()
    private let ringCache = RingCache()

    init(store: TimerStore) {
        self.store = store
        self.home = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        home.button?.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Timers")
        home.button?.imagePosition = .imageOnly
        home.button?.target = self
        home.button?.action = #selector(togglePopover)

        popover.behavior = .transient
        popover.contentSize = NSSize(width: Design.popoverWidth, height: 1)
        popover.contentViewController = NSHostingController(
            rootView: PopoverView().environment(store)
        )

        observe()
        sync()
    }

    // MARK: - Observation

    /// Re-arms after every change; `store.tick` fires once a second, which is
    /// also what advances every countdown label.
    private func observe() {
        withObservationTracking {
            _ = store.tick
            _ = store.timers
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.sync()
                self?.observe()
            }
        }
    }

    // MARK: - Sync

    private func sync() {
        let timers = store.sorted
        let live = Set(timers.map(\.id))

        // Retire items for timers that are gone.
        for (id, item) in items where !live.contains(id) {
            NSStatusBar.system.removeStatusItem(item)
            items.removeValue(forKey: id)
            titles.removeValue(forKey: id)
        }

        for timer in timers { update(timer) }
    }

    private func update(_ timer: TimerItem) {
        let item = items[timer.id] ?? make(for: timer.id)
        guard let button = item.button else { return }

        let remaining = timer.remaining(at: store.tick)
        let done = timer.hasFired(at: store.tick)
        var title = Parser.clock(for: remaining)
        if let tag = timer.tag { title = "#\(tag) " + title }

        // Only touch the button when the rendered text actually changes.
        if titles[timer.id] != title {
            titles[timer.id] = title
            button.attributedTitle = NSAttributedString(string: title, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .medium),
                .foregroundColor: color(done: done, paused: timer.isPaused),
            ])
        }

        button.image = ringCache.image(progress: timer.progress(at: store.tick), paused: timer.isPaused)
        button.imagePosition = .imageLeading
        FileHandle.standardError.write("DBG title=\(button.attributedTitle.string) len=\(item.length) w=\(button.frame.width) img=\(button.image != nil)\n".data(using: .utf8)!)
        item.menu = menu(for: timer, done: done)
    }

    private func make(for id: UUID) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        items[id] = item
        return item
    }

    private func color(done: Bool, paused: Bool) -> NSColor {
        if done { return NSColor(Design.accent) }
        // Otherwise defer to the system's menu bar tint, which adapts on its own.
        return paused ? .secondaryLabelColor : .labelColor
    }

    // MARK: - Per-timer menu

    private func menu(for timer: TimerItem, done: Bool) -> NSMenu {
        let menu = NSMenu()

        if done {
            menu.addItem(action("Restart", id: timer.id) { $0.restart($1) })
        } else {
            let label = timer.isPaused ? "Resume" : "Pause"
            menu.addItem(action(label, id: timer.id) { $0.togglePause($1) })
            menu.addItem(action("Restart", id: timer.id) { $0.restart($1) })
        }

        menu.addItem(.separator())
        menu.addItem(action("Remove", id: timer.id) { $0.remove($1) })
        menu.addItem(.separator())
        menu.addItem(withTitle: "New Timer…", action: #selector(showPopover), keyEquivalent: "n").target = self
        return menu
    }

    /// Wraps a store command as a menu item, so the selector plumbing lives once.
    private func action(_ title: String, id: UUID, perform: @escaping (TimerStore, UUID) -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(runAction(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = Command(id: id, perform: perform)
        return item
    }

    private final class Command {
        let id: UUID
        let perform: (TimerStore, UUID) -> Void
        init(id: UUID, perform: @escaping (TimerStore, UUID) -> Void) {
            self.id = id
            self.perform = perform
        }
    }

    @objc private func runAction(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? Command else { return }
        command.perform(store, command.id)
        sync()
    }

    // MARK: - Popover

    @objc private func togglePopover() {
        popover.isShown ? popover.performClose(nil) : showPopover()
    }

    @objc private func showPopover() {
        guard let button = home.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // Without this the text field never takes first responder and typing is lost.
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }
}

/// Renders the SwiftUI progress ring to an image, cached per visible step.
/// A 1/60 quantisation means at most 120 renders for the ring's whole lifetime.
@MainActor
private final class RingCache {
    private var cache: [Int: NSImage] = [:]

    func image(progress: Double, paused: Bool) -> NSImage? {
        let step = Int((progress * 60).rounded()) * (paused ? -1 : 1)
        if let cached = cache[step] { return cached }

        let renderer = ImageRenderer(content:
            ProgressRing(progress: progress, paused: paused, size: 12).padding(1)
        )
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let cgImage = renderer.cgImage else { return nil }

        let image = NSImage(cgImage: cgImage, size: NSSize(width: 14, height: 14))
        cache[step] = image
        return image
    }
}
