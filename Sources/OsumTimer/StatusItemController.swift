import AppKit
import SwiftUI
import Observation

/// Owns the menu bar: exactly one status item per slot, in creation order.
///
/// There is no dispatcher item. An item starts empty, you type into its panel,
/// and that same item becomes the countdown — so x timers is always x items.
/// `MenuBarExtra` is a static scene and cannot express that, which is why this
/// drives `NSStatusItem` directly. It is the only AppKit surface in the app.
@MainActor
final class StatusItemController {
    private let store: TimerStore
    private var items: [UUID: NSStatusItem] = [:]
    /// Last string rendered per item, so an unchanged "1:23" never repaints.
    private var titles: [UUID: String] = [:]
    /// Maps a clicked button back to the slot it belongs to.
    private var slotsByButton: [ObjectIdentifier: UUID] = [:]
    private let popover = NSPopover()
    private var openSlot: UUID?

    init(store: TimerStore) {
        self.store = store
        popover.behavior = .transient
        popover.contentSize = NSSize(width: Design.popoverWidth, height: 1)

        observe()
        sync()
    }

    // MARK: - Observation

    /// Re-arms after every change; `store.tick` fires once a second, which is
    /// also what advances every countdown label.
    private func observe() {
        withObservationTracking {
            _ = store.tick
            _ = store.slots
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.sync()
                self?.observe()
            }
        }
    }

    // MARK: - Sync

    private func sync() {
        let slots = store.slots
        let live = Set(slots.map(\.id))

        for (id, item) in items where !live.contains(id) {
            if let button = item.button { slotsByButton.removeValue(forKey: ObjectIdentifier(button)) }
            NSStatusBar.system.removeStatusItem(item)
            items.removeValue(forKey: id)
            titles.removeValue(forKey: id)
        }

        for slot in slots { update(slot) }
    }

    private func update(_ slot: Slot) {
        let isNew = items[slot.id] == nil
        let item = items[slot.id] ?? make(for: slot.id)
        guard let button = item.button else { return }

        guard let timer = slot.timer else {
            // Draft: a bare glyph, as narrow as the item can be. Menu bar width is
            // the scarcest resource here — macOS hides items that do not fit.
            if titles[slot.id] != nil || isNew {
                titles[slot.id] = nil
                button.attributedTitle = NSAttributedString(string: "")
                button.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "New timer")
                button.imagePosition = .imageOnly
            }
            return
        }

        let done = timer.hasFired(at: store.tick)
        let title = Parser.clock(for: timer.remaining(at: store.tick))

        // Only touch the button when the rendered text actually changes.
        if titles[slot.id] != title {
            titles[slot.id] = title
            button.attributedTitle = NSAttributedString(string: title, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: Design.menuBarSize, weight: .medium),
                .foregroundColor: color(done: done, paused: timer.isPaused),
            ])
        }

        // Text only. The ring costs ~18pt per item, and menu bar width is the
        // scarcest resource in the app — macOS hides items that do not fit, so a
        // decorated item is one you may never see. The ring lives in the panel.
        if button.image != nil {
            button.image = nil
            button.imagePosition = .noImage
        }
    }

    private func make(for id: UUID) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        items[id] = item
        if let button = item.button {
            slotsByButton[ObjectIdentifier(button)] = id
            button.target = self
            button.action = #selector(buttonClicked(_:))
        }
        return item
    }

    private func color(done: Bool, paused: Bool) -> NSColor {
        if done { return NSColor(Design.accent) }
        // Otherwise defer to the system's menu bar tint, which adapts on its own.
        return paused ? .secondaryLabelColor : .labelColor
    }

    // MARK: - Panel

    @objc private func buttonClicked(_ sender: NSStatusBarButton) {
        guard let id = slotsByButton[ObjectIdentifier(sender)] else { return }

        // Clicking the item whose panel is open closes it.
        if popover.isShown, openSlot == id {
            popover.performClose(nil)
            openSlot = nil
            return
        }

        show(id, from: sender)
    }

    /// Opens a slot's panel without a click — used by the demo hook to make the
    /// panel inspectable in a screenshot.
    func openPanel(for id: UUID) {
        guard let button = items[id]?.button else { return }
        show(id, from: button)
    }

    private func show(_ id: UUID, from sender: NSStatusBarButton) {

        popover.performClose(nil)
        popover.contentViewController = NSHostingController(
            rootView: SlotView(slotID: id).environment(store)
        )
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        openSlot = id

        // Without this the text field never takes first responder and typing is lost.
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }
}
