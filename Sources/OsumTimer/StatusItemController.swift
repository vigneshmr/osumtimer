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
    /// Label currently drawn per item; absent means the item carries none.
    private var labels: [UUID: String] = [:]
    private let labelCache = LabelCache()
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

        // SwiftUI has no handle on the popover that hosts it; the panel asks to
        // be dismissed through this instead of reaching into AppKit itself.
        NotificationCenter.default.addObserver(
            forName: .osumClosePanel, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.closePanel() }
        }

        NotificationCenter.default.addObserver(
            forName: .osumOpenSettings, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.closePanel()  // the popover is transient; it would close anyway
                SettingsWindow.shared.show()
            }
        }
    }

    // MARK: - Observation

    /// Re-arms after every change; `store.tick` fires once a second, which is
    /// also what advances every countdown label.
    private func observe() {
        withObservationTracking {
            _ = store.tick
            _ = store.slots
            _ = Preferences.shared.showLabelsInMenuBar  // toggling it redraws the bar
            _ = Preferences.shared.appearance           // and so does restyling it
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.sync()
                self?.observe()
            }
        }
    }

    // MARK: - Sync

    private func sync() {
        // Set on the popover rather than on NSApp: forcing the whole app into an
        // appearance would drag the status items with it, and those have to keep
        // following the menu bar or their text stops matching everything beside it.
        let appearance = Preferences.shared.appearance.appearance
        if popover.appearance != appearance { popover.appearance = appearance }

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
                labels[slot.id] = nil
                button.attributedTitle = NSAttributedString(string: "")
                button.title = ""
                button.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "New timer")
                button.imagePosition = .imageOnly
            }
            return
        }

        let done = timer.hasFired(at: store.tick)
        let title = Parser.clock(for: timer.remaining(at: store.tick))

        // Only touch the button when what it renders actually changes; the state
        // is part of that, since it decides how the title is coloured.
        let rendered = "\(title)|\(done)|\(timer.isPaused)"
        if titles[slot.id] != rendered {
            titles[slot.id] = rendered
            button.font = NSFont.monospacedDigitSystemFont(ofSize: Design.menuBarSize, weight: .medium)

            if let tint = tint(done: done, paused: timer.isPaused) {
                button.attributedTitle = NSAttributedString(
                    string: title, attributes: [.font: button.font!, .foregroundColor: tint]
                )
            } else {
                // No attributed string in the ordinary case: a hardcoded colour
                // cannot invert when the item is clicked and drawn highlighted,
                // which leaves the countdown unreadable against the highlight.
                // A plain title lets AppKit colour it, including that inversion.
                button.attributedTitle = NSAttributedString(string: "")
                button.title = title
            }
        }

        // The label rides as an image, not as part of the title: its light-on-dark
        // chip needs fixed colours, and an attributed title would freeze the
        // countdown's colour too, which is what made paused timers unreadable.
        // Otherwise text only — menu bar width is the scarcest resource in the
        // app, and macOS hides items that do not fit.
        let label = Preferences.shared.showLabelsInMenuBar ? timer.tag : nil
        if let label {
            if labels[slot.id] != label {
                labels[slot.id] = label
                button.image = labelCache.image(for: label)
                button.imagePosition = .imageLeading
            }
        } else if button.image != nil {
            // Keyed off the button, not the label cache: an item that was a
            // draft still carries the draft's timer glyph, and the cache agrees
            // that "no label" has not changed — leaving the glyph sitting behind
            // the digits.
            labels[slot.id] = nil
            button.image = nil
            button.imagePosition = .noImage
        }
    }

    private func make(for id: UUID) -> NSStatusItem {
        // An item with no remembered position is placed left of everything already
        // in the bar, and on a notched display that lands behind the notch: the
        // item reports itself visible, has a real 32pt frame, and is simply never
        // drawn. Seeding a spot in the right-hand cluster on first run avoids it.
        // AppKit rewrites the same key when the item is Cmd-dragged, so this only
        // ever decides where an item the user has never moved starts out.
        let name = "slot-\(items.count)"
        let key = "NSStatusItem Preferred Position \(name)"
        if UserDefaults.standard.object(forKey: key) == nil {
            // Points from the right edge of the screen, stepped so several timers
            // do not all ask for the same spot.
            UserDefaults.standard.set(160 + 40 * items.count, forKey: key)
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = name
        items[id] = item
        if let button = item.button {
            slotsByButton[ObjectIdentifier(button)] = id
            button.target = self
            button.action = #selector(buttonClicked(_:))
        }
        return item
    }

    /// The colour a state needs, or nil to let the system tint it — which is the
    /// right answer whenever the text carries no state of its own.
    ///
    /// Paused deliberately gets no colour. `secondaryLabelColor` resolves against
    /// the app's appearance rather than the menu bar's, so on a dark bar it came
    /// out near-black and the countdown all but disappeared. Pause is shown with
    /// a template glyph instead, which AppKit tints the same way it tints its own.
    private func tint(done: Bool, paused: Bool) -> NSColor? {
        done ? NSColor(Design.accent) : nil
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

    func closePanel() {
        popover.performClose(nil)
        openSlot = nil
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

/// Draws a tag as a light-on-dark chip, cached per tag.
///
/// An image, not styled text: the chip's colours are fixed by design, and an
/// attributed title would take the countdown's colour out of the system's hands
/// along with it.
@MainActor
private final class LabelCache {
    private var cache: [String: NSImage] = [:]

    func image(for tag: String) -> NSImage? {
        if let cached = cache[tag] { return cached }

        let renderer = ImageRenderer(content: LabelChip(tag: tag))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let cgImage = renderer.cgImage else { return nil }

        let size = NSSize(
            width: CGFloat(cgImage.width) / renderer.scale,
            height: CGFloat(cgImage.height) / renderer.scale
        )
        let image = NSImage(cgImage: cgImage, size: size)
        cache[tag] = image
        return image
    }
}

private struct LabelChip: View {
    let tag: String

    var body: some View {
        Text(tag.prefix(1).uppercased() + tag.dropFirst())
            .font(.system(size: Design.menuBarSize - 2, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.black.opacity(0.55))
            )
            .padding(1)
    }
}

extension Notification.Name {
    /// Posted by the panel when it wants the popover dismissed.
    static let osumClosePanel = Notification.Name("OsumTimer.closePanel")
    /// Posted by a panel's gear; any of them opens the one settings window.
    static let osumOpenSettings = Notification.Name("OsumTimer.openSettings")
}
