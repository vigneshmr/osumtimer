import AppKit
import SwiftUI

/// How to use the app, in the settings window's own space: one step per
/// action, each a picture of the real panel and a line on what to press.
struct GuideView: View {
    var back: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                // Escape goes back too, the way it leaves any sheet.
                Button(action: back) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Settings")
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                Spacer()
            }
            .overlay(Text("Guide").font(.headline))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            ScrollView(.vertical) {
                VStack(spacing: 28) {
                    ForEach(Array(GuideStep.all.enumerated()), id: \.offset) { index, step in
                        GuideStepView(number: index + 1, step: step,
                                      picture: GuidePictures.picture(index, scheme: scheme))
                    }
                }
                .padding(.vertical, 22)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct GuideStepView: View {
    let number: Int
    let step: GuideStep
    let picture: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("\(number)")
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Design.accent, in: Circle())
                Text(step.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Design.textPrimary)
            }

            if let picture {
                Image(nsImage: picture)
                    .clipShape(RoundedRectangle(cornerRadius: Design.radius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Design.radius, style: .continuous)
                            .strokeBorder(Design.hairline, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .accessibilityHidden(true)
            }

            step.how
                .font(Design.caption)
                .foregroundStyle(Design.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One thing to learn: what it is called, the panel as it looks, and what to
/// press. The symbols in `how` are the glyphs on the panel's own buttons.
private struct GuideStep {
    let title: String
    let how: Text
    /// The item this step shows the panel of.
    let slot: Slot
    /// The button this step is about, drawn as if the pointer were on it.
    var pointing: String? = nil

    private static func glyph(_ name: String) -> Text {
        Text(Image(systemName: name)).foregroundStyle(Design.textPrimary)
    }

    /// A timer 8:56 into 25 minutes — far enough along that the ring, the
    /// percentage and the bar all show something.
    private static func running(_ change: (inout TimerItem) -> Void) -> Slot {
        // Untagged: "paused · 25 min #deepwork" is wider than the panel.
        var timer = TimerItem(duration: 25 * 60, input: "25m", now: Date().addingTimeInterval(-536))
        change(&timer)
        return Slot(timer: timer)
    }

    /// Built fresh each time: the timers in it are set relative to now.
    static var all: [GuideStep] { [
        GuideStep(
            title: "Start a timer",
            how: Text("Click \(glyph("timer")) in the menu bar and type how long — ")
                + Text("25, 1.5h, 1:30").foregroundStyle(Design.textPrimary)
                + Text(", or ")
                + Text("@5pm").foregroundStyle(Design.textPrimary)
                + Text(" for a time of day. Add ")
                + Text("#tag").foregroundStyle(Design.accent)
                + Text(" to name it, then press Return."),
            slot: Slot(draft: "25m #deepwork")
        ),
        GuideStep(
            title: "Pause",
            how: Text("\(glyph("pause.fill")) stops the clock where it is — Return does the same. \(glyph("play.fill")) carries on from there."),
            slot: running { _ in },
            pointing: "pause.fill"
        ),
        GuideStep(
            title: "Reset",
            how: Text("\(glyph("arrow.clockwise")) rewinds to the full length and holds it there. Press \(glyph("play.fill")) to run it again."),
            slot: running { _ in },
            pointing: "arrow.clockwise"
        ),
        GuideStep(
            title: "Show percentage",
            how: Text("\(glyph("ellipsis")) → Progress bar reads the timer as how far along it is, with a bar, in the panel and the menu bar. The clock moves to the line below."),
            slot: running { $0.display = .percent }
        ),
        GuideStep(
            title: "Show total",
            how: Text("\(glyph("ellipsis")) → Show total adds what the clock is out of: “16:04 / 25:00”, or “16:04 to 3pm” for a time of day."),
            slot: running { $0.showTotal = true }
        ),
        GuideStep(
            title: "Intervals",
            how: Text("\(glyph("ellipsis")) → Intervals cuts the run into segments. Type a name, then Return or \(glyph("forward.end.fill")) starts the next at 0:00 — the timer carries on."),
            slot: running { $0.intervals = [.init(name: "Warm up", start: 0), .init(name: "Sets", start: 300), .init(name: "", start: 470)] },
            pointing: "forward.end.fill"
        ),
        GuideStep(
            title: "Stop and copy",
            how: Text("\(glyph("stop.fill")) ends the run and lists the intervals. Copy as Markdown puts them on the clipboard as a table."),
            slot: running {
                $0.intervals = [.init(name: "Warm up", start: 0), .init(name: "Sets", start: 300), .init(name: "Cool down", start: 470)]
                $0.pause()
                $0.stopped = true
            }
        ),
    ] }
}

/// Pictures of the real panel, drawn offscreen from a scratch store the way
/// `DebugRender` draws them — a mock would drift from the app it explains.
/// Made once per appearance: the timers in them are frozen at the moment of
/// drawing, so there is nothing to redraw.
@MainActor
enum GuidePictures {
    private static var cache: [ColorScheme: [NSImage?]] = [:]

    static func picture(_ index: Int, scheme: ColorScheme) -> NSImage? {
        if cache[scheme] == nil { cache[scheme] = render(scheme) }
        return cache[scheme]?[index]
    }

    static func render(_ scheme: ColorScheme) -> [NSImage?] {
        // Scratch everything, so a picture never touches real timers — nor,
        // through `rememberLastChoice`, the real defaults. The timers go in
        // through the file, the only way to hand the store one already partway
        // through. Drafts are added after: loading drops them when timers exist.
        let steps = GuideStep.all
        let file = Persistence(filename: "guide-preview.json")
        file.save(.init(slots: steps.map(\.slot).filter { !$0.isDraft }))
        let store = TimerStore(
            store: file,
            preferences: Preferences(defaults: UserDefaults(suiteName: "OsumTimerGuide")!)
        )
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)!

        return steps.map { step in
            var id = step.slot.id
            if step.slot.isDraft {
                id = store.addSlot()
                store.setDraft(id, step.slot.draft)
            }
            let view = GuideScene(slotID: id)
                .environment(\.pointedGlyph, step.pointing)
                .environment(\.isPicture, true)
                .environment(store)
                .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            var image: NSImage?
            // The palette resolves per appearance at draw time, not from the
            // SwiftUI environment.
            appearance.performAsCurrentDrawingAppearance { image = renderer.nsImage }
            return image
        }
    }
}

/// A strip of menu bar above the panel it opens, so each picture shows both
/// places a change lands.
private struct GuideScene: View {
    let slotID: UUID
    @Environment(TimerStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            menuBar
            Divider().overlay(Design.hairline)
            if let draft = store.slot(slotID).flatMap({ $0.isDraft ? $0.draft : nil }) {
                typing(draft)
            } else {
                SlotView(slotID: slotID)
            }
        }
        .background(Design.surface)
    }

    /// The draft panel with words in it. An offscreen render cannot draw a
    /// text field — it comes out as a placeholder sign — so the typing is drawn
    /// as text, with the panel's own spacing and its live reading underneath.
    private func typing(_ draft: String) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 1) {
                    Text(draft)
                    Rectangle().fill(Design.accent).frame(width: 1.5, height: 19)
                }
                .font(Design.input)
                .foregroundStyle(Design.textPrimary)

                if case .success(let value) = Parser.parse(draft) {
                    HStack(spacing: 5) {
                        Text(value.echo)
                        if let tag = value.tag {
                            Text("#\(tag)").foregroundStyle(Design.accent)
                        }
                    }
                    .font(Design.caption)
                    .foregroundStyle(Design.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Design.gutter)
            .padding(.top, 13)
            .padding(.bottom, 11)

            Divider().overlay(Design.hairline)

            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                    Text("Add timer")
                }
                .foregroundStyle(Design.accent)
                Spacer()
                Image(systemName: "gearshape")
                Text("Quit")
            }
            .font(Design.caption)
            .foregroundStyle(Design.textFaint)
            .padding(.horizontal, Design.gutter)
            .padding(.vertical, 8)
        }
        .frame(width: Design.popoverWidth)
    }

    private var menuBar: some View {
        HStack(spacing: 4) {
            if let timer = store.slot(slotID)?.timer {
                if timer.display == .percent {
                    ProgressBar(progress: timer.progress(at: store.tick), paused: timer.isPaused)
                        .frame(width: 22, height: 5)
                }
                Text(StatusItemController.title(for: timer, at: store.tick))
                    .font(Design.menuBar)
            } else {
                Image(systemName: "timer")
                    .font(.system(size: Design.menuBarSize))
            }
        }
        .foregroundStyle(Design.textPrimary)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(Design.hairline, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .background(Design.surfaceRaised)
    }
}
