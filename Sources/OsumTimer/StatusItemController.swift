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
    private let panel = PanelWindow()
    private var openSlot: UUID?
    /// Items currently drawn ringing, so each can be put back exactly once.
    private var pulsing: Set<UUID> = []

    init(store: TimerStore) {
        self.store = store

        observe()
        sync()

        // SwiftUI has no handle on the popover that hosts it; the panel asks to
        // be dismissed through this instead of reaching into AppKit itself.
        NotificationCenter.default.addObserver(
            forName: .osumClosePanel, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.closePanel() }
        }

        // The item for a brand new slot is created by the observer that watches
        // the store, which runs a beat later — sync first so there is something
        // to hang the panel off.
        NotificationCenter.default.addObserver(
            forName: .osumOpenPanel, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let id = note.object as? UUID else { return }
                self.sync()
                self.openPanel(for: id)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .osumOpenSettings, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.closePanel()  // the popover is transient; it would close anyway
                SettingsWindow.show()
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
            _ = store.ringing                           // starts and ends the pulse
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
        // Set on the panel rather than on NSApp: forcing the whole app into an
        // appearance would drag the status items with it, and those have to keep
        // following the menu bar or their text stops matching everything beside it.
        let appearance = Preferences.shared.appearance.appearance
        if panel.appearance != appearance { panel.appearance = appearance }

        let slots = store.slots
        let live = Set(slots.map(\.id))

        for (id, item) in items where !live.contains(id) {
            if let button = item.button {
                slotsByButton.removeValue(forKey: ObjectIdentifier(button))
                RingLook.remove(from: button)  // forgets it, so a reused identity starts clean
            }
            NSStatusBar.system.removeStatusItem(item)
            items.removeValue(forKey: id)
            titles.removeValue(forKey: id)
        }

        for slot in slots { update(slot) }
        syncPulse()
        // Only the height ever changes, and only when the slot changes state;
        // where the panel sits was decided when it opened and is left alone.
        panel.fit()
    }

    // MARK: - Pulse

    /// While a timer's alarm is sounding, its item turns into a dark pill with
    /// white text. Fixed colours, not the
    /// system's click highlight: that highlight is a faint tint on recent macOS,
    /// easy to miss against a busy wallpaper, while white on near-black reads
    /// the same in either appearance and over anything behind the bar.
    private func syncPulse() {
        let ringing = store.ringing
        for id in pulsing.subtracting(ringing) {
            if let button = items[id]?.button { RingLook.remove(from: button) }
        }
        pulsing = ringing
        for id in ringing {
            if let button = items[id]?.button { RingLook.apply(to: button) }
        }
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
        let percent = timer.display == .percent ? timer.percentElapsed(at: store.tick) : nil
        let title = Self.title(for: timer, at: store.tick)

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
        //
        // In percent mode the bar rides the same way, next to the digits: "73%"
        // says how far along, the bar shows it, and together they are still
        // narrower than "1:00:00" was.
        let label = Preferences.shared.showLabelsInMenuBar ? timer.tag : nil
        if label != nil || percent != nil {
            let key = "\(label ?? "")|\(percent.map(String.init) ?? "")"
            if labels[slot.id] != key {
                labels[slot.id] = key
                button.image = labelCache.image(label: label, percent: percent, paused: timer.isPaused)
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

    /// What the item reads for a timer. Percent alone does not say how long
    /// that is, so the clock rides along in brackets: "98% (15:11)", or
    /// "98% (15:11 / 25:00)". Without percent, the clock alone: "15:11", or
    /// "15:11 / 25:00".
    ///
    /// A repeating chain adds which round it is on: "15:11 ↻5". Which step
    /// of the round is not worth the menu bar width.
    static func title(for timer: TimerItem, at now: Date) -> String {
        let clock = timer.display == .percent
            ? padded(
                "\(timer.percentElapsed(at: now))% (\(timer.clock(timer.clockValue(at: now))))",
                to: "100% (\(timer.clock(timer.duration)))"
            )
            : padded(timer.clock(timer.clockValue(at: now)), to: timer.clock(timer.duration))
        guard timer.repeats, !timer.stopped else { return clock }
        return "\(clock) ↻\(timer.round)"
    }

    /// Pads a countdown out to the width of the longest string this timer will
    /// ever show, so the item never changes width as the digits fall away.
    ///
    /// The item sizes itself to its title, so "1:00:00" → "59:59" and again
    /// "10:00" → "9:59" shrink it, sliding it and everything left of it along
    /// the bar — and dragging an open panel with it, since the panel is anchored
    /// to the item. Monospaced digits do not cover it: the character count is
    /// what changes.
    ///
    /// Padding the string rather than fixing `item.length`: an explicit length
    /// is laid out with 16pt of dead space added beside the button, so the
    /// digits sit off-centre in the item and the panel's arrow no longer lines
    /// up with them.
    ///
    /// The two spaces are exact stand-ins in a monospaced-digit font — FIGURE
    /// SPACE carries a digit's advance, PUNCTUATION SPACE a colon's — so a
    /// padded string measures identically to the one it is matched against.
    /// Split across both ends to keep the digits centred.
    static func padded(_ title: String, to widest: String) -> String {
        let digits = widest.filter(\.isNumber).count - title.filter(\.isNumber).count
        let colons = widest.filter { $0 == ":" }.count - title.filter { $0 == ":" }.count
        guard digits > 0 || colons > 0 else { return title }

        let pad = Array(String(repeating: "\u{2007}", count: max(0, digits))
            + String(repeating: "\u{2008}", count: max(0, colons)))
        let split = pad.count / 2
        return String(pad[..<split]) + title + String(pad[split...])
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
    /// Nothing takes a colour any more. Any fixed colour here is chosen against
    /// the app's appearance rather than the menu bar's, and the bar is
    /// translucent over whatever is behind it: paused in `secondaryLabelColor`
    /// came out near-black on a dark bar, and the accent blue on `0:00` was just
    /// as hard to read — for a state that `0:00` and the alarm already announce.
    /// Both are shown by other means, and the digits stay system-tinted, which
    /// also lets them invert when the item is clicked and drawn highlighted.
    private func tint(done: Bool, paused: Bool) -> NSColor? {
        nil
    }

    // MARK: - Panel

    @objc private func buttonClicked(_ sender: NSStatusBarButton) {
        guard let id = slotsByButton[ObjectIdentifier(sender)] else { return }
        // Reaching for the menu bar at all means the alarm has done its job.
        store.silenceAlarm()

        // Clicking the item whose panel is open closes it.
        if panel.isShown, openSlot == id {
            closePanel()
            return
        }

        show(id, from: sender)
    }

    func closePanel() {
        panel.close(notify: false)
        openSlot = nil
    }

    /// Opens a slot's panel without a click — used by the demo hook to make the
    /// panel inspectable in a screenshot.
    func openPanel(for id: UUID, retries: Int = 6) {
        guard let button = items[id]?.button else { return }
        // A status item created a moment ago has not been placed in the bar yet,
        // and a panel anchored to that lands in the bottom-left corner. Give the
        // bar a few moments, then show regardless: an item the menu bar has
        // hidden — a full bar collapses the ones that do not fit — never gets a
        // frame at all, and the panel still has to appear.
        if (button.window?.frame.height ?? 0) == 0, retries > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.openPanel(for: id, retries: retries - 1)
            }
            return
        }
        show(id, from: button)
    }

    private func show(_ id: UUID, from sender: NSStatusBarButton) {
        openSlot = id
        panel.show(
            under: sender,
            appearance: Preferences.shared.appearance.appearance,
            content: SlotView(slotID: id).environment(store)
        ) { [weak self] in
            self?.openSlot = nil
        }
    }
}

/// The ringing look on a status item button: white on near-black. The dark
/// fades in when the alarm starts and out when it stops, rather than snapping.
@MainActor
private enum RingLook {
    private static let dark = NSColor(white: 0.08, alpha: 0.92).cgColor
    private static let clear = NSColor(white: 0.08, alpha: 0).cgColor
    private static let fadeIn: CFTimeInterval = 0.5
    private static let fadeOut: CFTimeInterval = 0.7

    /// Buttons dark now, not counting ones fading out.
    private static var active: Set<ObjectIdentifier> = []
    /// Bumped on every start and stop, so a fade-out that finishes after the
    /// alarm has started again does not undo the new one.
    private static var generation: [ObjectIdentifier: Int] = [:]

    /// Called on every tick while ringing; only the first call does anything.
    static func apply(to button: NSStatusBarButton) {
        let key = ObjectIdentifier(button)
        guard !active.contains(key) else { return }
        button.wantsLayer = true
        guard let layer = button.layer else { return }
        active.insert(key)
        generation[key, default: 0] += 1
        // A dark appearance turns the plain title and the template bar white,
        // with no hardcoded colour to forget to undo.
        button.appearance = NSAppearance(named: .darkAqua)
        layer.cornerRadius = 6
        // The layer's own background draws beneath the title; a sublayer would
        // cover it.
        fade(layer, to: dark, over: fadeIn)
    }

    static func remove(from button: NSStatusBarButton) {
        let key = ObjectIdentifier(button)
        guard active.remove(key) != nil, let layer = button.layer else { return }
        generation[key, default: 0] += 1
        let mine = generation[key]

        fade(layer, to: clear, over: fadeOut)
        // The text goes back to the bar's own colour halfway, once the dark
        // behind it is mostly gone — white on a light bar would vanish.
        DispatchQueue.main.asyncAfter(deadline: .now() + fadeOut / 2) {
            guard generation[key] == mine else { return }
            button.appearance = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + fadeOut) {
            guard generation[key] == mine else { return }
            layer.backgroundColor = nil
            layer.cornerRadius = 0
        }
    }

    /// Animates from wherever the background is on screen now — partway
    /// through an opposite fade included — to `color`, and leaves it there.
    private static func fade(_ layer: CALayer, to color: CGColor, over duration: CFTimeInterval) {
        let animation = CABasicAnimation(keyPath: "backgroundColor")
        animation.fromValue = layer.presentation()?.backgroundColor ?? layer.backgroundColor ?? clear
        animation.toValue = color
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.backgroundColor = color
        CATransaction.commit()
        layer.add(animation, forKey: "osum.fade")
    }
}

/// Draws what sits beside the digits — a tag chip, a percent bar, or both —
/// cached per rendering.
///
/// An image, not styled text: the chip's colours are fixed by design, and an
/// attributed title would take the countdown's colour out of the system's hands
/// along with it.
@MainActor
private final class LabelCache {
    private var cache: [String: NSImage] = [:]

    /// The bar's footprint, sized to sit on the text's baseline like a glyph.
    private static let barSize = NSSize(width: 22, height: 5)

    func image(label: String?, percent: Int?, paused: Bool) -> NSImage? {
        // A bare bar is a template: AppKit tints it like the digits and inverts
        // it with them when the item is highlighted. A chip fixes its own
        // colours, so beside one the bar takes a fixed colour too.
        guard let label else {
            return percent.map { bar(elapsed: $0, paused: paused) }
        }
        guard let percent else { return chip(for: label) }

        let key = "\(label)|\(percent)|\(paused)"
        if let cached = cache[key] { return cached }
        guard let chip = chip(for: label) else { return nil }
        let gap: CGFloat = 4
        let barSize = Self.barSize
        let size = NSSize(width: chip.size.width + gap + barSize.width, height: max(chip.size.height, barSize.height))
        let image = NSImage(size: size, flipped: false) { rect in
            chip.draw(in: NSRect(origin: .zero, size: chip.size))
            let frame = NSRect(x: chip.size.width + gap, y: (rect.height - barSize.height) / 2,
                               width: barSize.width, height: barSize.height)
            Self.drawBar(in: frame, elapsed: percent, paused: paused, color: .labelColor)
            return true
        }
        cache[key] = image
        return image
    }

    /// The bar on its own, drawn in black and marked as a template so the menu
    /// bar picks the actual colour.
    private func bar(elapsed percent: Int, paused: Bool) -> NSImage {
        let key = "bar|\(percent)|\(paused)"
        if let cached = cache[key] { return cached }

        let image = NSImage(size: Self.barSize, flipped: false) { rect in
            Self.drawBar(in: rect, elapsed: percent, paused: paused, color: .black)
            return true
        }
        image.isTemplate = true
        cache[key] = image
        return image
    }

    /// A track with the elapsed fraction filled, growing from the left toward
    /// the digits. Two alphas of one colour: the track is faint, the fill solid
    /// — or dimmed, when the timer is paused.
    private static func drawBar(in rect: NSRect, elapsed percent: Int, paused: Bool, color: NSColor) {
        let radius = rect.height / 2
        color.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()

        let width = rect.width * CGFloat(max(0, min(100, percent))) / 100
        guard width > 0 else { return }
        let filled = NSRect(x: rect.minX, y: rect.minY, width: max(rect.height, width), height: rect.height)
        color.withAlphaComponent(paused ? 0.45 : 1).setFill()
        NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
    }

    private func chip(for tag: String) -> NSImage? {
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
    /// Posted with a slot's `UUID` when that slot's panel should be shown —
    /// "Add timer" hands the new item straight back as an open duration field.
    static let osumOpenPanel = Notification.Name("OsumTimer.openPanel")
    /// Posted by a panel's gear; any of them opens the one settings window.
    static let osumOpenSettings = Notification.Name("OsumTimer.openSettings")
}
