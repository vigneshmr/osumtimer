import SwiftUI

/// The panel behind a single menu bar item.
///
/// An item starts empty: this shows a field, you type, and that same item becomes
/// the countdown. Once running, the panel shows the timer's own controls. Every
/// state carries "+ Add timer", which spawns another empty item beside it.
struct SlotView: View {
    let slotID: UUID
    @Environment(TimerStore.self) private var store

    /// What the user has typed at a running timer. Non-empty means they are
    /// rewriting its duration, so the panel turns back into the draft editor —
    /// typing at a timer drafts a new one rather than nudging the live one.
    @State private var typed = ""

    private var slot: Slot? { store.slot(slotID) }

    var body: some View {
        VStack(spacing: 0) {
            // The running panel keeps its own field while you type, rather than
            // swapping in the draft one: handing first responder between two
            // fields mid-keystroke drops everything after the first character.
            if let timer = slot?.timer {
                RunningPanel(slotID: slotID, timer: timer, now: store.tick, typed: $typed)
            } else {
                DraftPanel(slotID: slotID, seed: $typed)
            }
            Divider().overlay(Design.hairline)
            footer
        }
        .frame(width: Design.popoverWidth)
        .background(Design.surface)
    }

    private var footer: some View {
        HStack(spacing: 0) {
            Button {
                let id = store.addSlot()
                // Adding a timer is asking to set one: the new item's panel opens
                // on its own duration field, so you type instead of hunting for it
                // in the bar.
                NotificationCenter.default.post(name: .osumOpenPanel, object: id)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                    Text("Add timer")
                }
                .font(Design.caption)
                .foregroundStyle(Design.accent)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Spacer()

            // Every panel carries it, and they all open the same window — the
            // settings are the app's, not this timer's.
            Button {
                NotificationCenter.default.post(name: .osumOpenSettings, object: nil)
            } label: {
                Image(systemName: "gearshape")
                    .font(Design.caption)
                    .foregroundStyle(Design.textFaint)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Settings")
            .accessibilityLabel("Settings")
            .padding(.trailing, 12)

            if canQuit {
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(Design.caption)
                    .foregroundStyle(Design.textFaint)
            } else {
                Button {
                    store.remove(slotID)
                    // This item is gone; the panel that belonged to it goes too.
                    NotificationCenter.default.post(name: .osumClosePanel, object: nil)
                } label: {
                    Image(systemName: "trash")
                        .font(Design.caption)
                        .foregroundStyle(Design.textFaint)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Remove this timer")
                .accessibilityLabel("Remove this timer")
            }
        }
        .padding(.horizontal, Design.gutter)
        .padding(.vertical, 8)
    }

    /// Quitting is only offered when this is the last item and it holds nothing:
    /// with siblings in the bar, or a timer set here, the useful action is to
    /// remove just this one — quitting would take the others down with it.
    private var canQuit: Bool {
        store.slots.count == 1 && slot?.timer == nil
    }
}

/// An empty item: type a duration and it becomes this item's countdown.
private struct DraftPanel: View {
    let slotID: UUID
    /// Characters typed at a running timer, which opened this editor. Cleared
    /// when the edit is committed or abandoned.
    @Binding var seed: String
    @Environment(TimerStore.self) private var store
    @FocusState private var focused: Bool

    /// The field's text lives in the store, so closing the panel mid-edit and
    /// reopening it finds the words still there.
    private var text: Binding<String> {
        Binding(
            get: { store.slot(slotID)?.draft ?? "" },
            set: { store.setDraft(slotID, $0) }
        )
    }

    private var parsed: Result<ParsedTimer, ParseError>? {
        text.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty
            ? nil
            : Parser.parse(text.wrappedValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            TextField("45m", text: text)
                .textFieldStyle(.plain)
                .font(Design.input)
                .foregroundStyle(Design.textPrimary)
                .focused($focused)
                .onSubmit(submit)

            hint
        }
        .padding(.horizontal, Design.gutter)
        .padding(.top, 13)
        .padding(.bottom, 11)
        .onAppear {
            // Characters typed at a running timer arrive here; anything already
            // in the slot is an edit in progress and wins.
            if text.wrappedValue.isEmpty, !seed.isEmpty { text.wrappedValue = seed }
            focused = true
        }
        // Deleting back to nothing abandons the edit: a timer that was running
        // is still running, so show it again rather than stranding a blank field.
        .onChange(of: text.wrappedValue) { _, new in
            if new.isEmpty { seed = "" }
        }
    }

    /// Live feedback: you see how the input was read before committing to it.
    @ViewBuilder
    private var hint: some View {
        switch parsed {
        case .success(let value):
            HStack(spacing: 5) {
                Text(value.echo)
                if let tag = value.tag {
                    Text("#\(tag)").foregroundStyle(Design.accent)
                }
            }
            .font(Design.caption)
            .foregroundStyle(Design.textSecondary)
        case .failure(let error) where error != .empty:
            Text(draftMessage(for: error))
                .font(Design.caption)
                .foregroundStyle(Design.textFaint)
        default:
            recents
        }
    }

    @ViewBuilder
    private var recents: some View {
        if store.recents.isEmpty {
            Text("try 25, 1.5h, 1:30, @5pm")
                .font(Design.caption)
                .foregroundStyle(Design.textFaint)
        } else {
            // As many chips as the panel can hold at their natural size. A fixed
            // count cannot work: four short ones fit where three "1:00:00" do
            // not, and squeezing them truncates every chip to "23:…".
            ViewThatFits(in: .horizontal) {
                chips(4)
                chips(3)
                chips(2)
                chips(1)
            }
        }
    }

    private func chips(_ count: Int) -> some View {
        HStack(spacing: 5) {
            // Labelled and started from what was typed, whatever that was: a
            // length replays as itself, a time of day resolves against the clock
            // as it stands now rather than replaying a stale gap.
            ForEach(store.recents.prefix(count), id: \.self) { expression in
                Button(expression) {
                    store.start(slotID, recent: expression)
                }
                .buttonStyle(.plain)
                .font(Design.caption.monospacedDigit())
                .foregroundStyle(Design.textSecondary)
                .fixedSize()
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Design.surfaceRaised)
                )
            }
        }
    }

    private func submit() {
        guard case .success(let value)? = parsed else { return }
        store.start(slotID, with: value)
        text.wrappedValue = ""
        seed = ""
    }
}

/// Both panels parse the same input, so they say the same thing when it is wrong.
private func draftMessage(for error: ParseError) -> String {
    switch error {
    case .unrecognized: "not a duration"
    case .notPositive: "must be more than zero"
    case .tooLong: "longer than a week"
    case .empty: ""
    }
}

/// A live item: its countdown and its own controls. Nothing here refers to any
/// other timer — this panel belongs to one menu bar item.
private struct RunningPanel: View {
    let slotID: UUID
    let timer: TimerItem
    let now: Date
    /// What has been typed over the countdown. Empty means the timer is just
    /// being watched; anything else means a new duration is being written.
    @Binding var typed: String
    @Environment(TimerStore.self) private var store
    @FocusState private var capturing: Bool

    private var done: Bool { timer.hasFired(at: now) }
    private var percent: Bool { timer.display == .percent }
    private var editing: Bool { !typed.isEmpty }

    private var parsed: Result<ParsedTimer, ParseError>? {
        typed.trimmingCharacters(in: .whitespaces).isEmpty ? nil : Parser.parse(typed)
    }

    var body: some View {
        VStack(spacing: 10) {
            // The field is always here, holding first responder whether or not
            // anything has been typed — it is simply invisible under the
            // countdown until it has content. Typing therefore never changes
            // which view owns the keyboard.
            ZStack(alignment: .leading) {
                TextField("", text: $typed)
                    .textFieldStyle(.plain)
                    .font(Design.input)
                    .foregroundStyle(Design.textPrimary)
                    .focused($capturing)
                    .onSubmit(submit)
                    .opacity(editing ? 1 : 0)

                if !editing { countdown }
            }
            .frame(maxWidth: .infinity)

            if editing {
                hint
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                controls
            }
        }
        .padding(.horizontal, Design.gutter)
        .padding(.top, 12)
        .padding(.bottom, 11)
        .onAppear { capturing = true }
    }

    /// The ring, the clock and its status line — what you see when not typing.
    private var countdown: some View {
        HStack(spacing: 9) {
            ProgressRing(progress: timer.progress(at: now), paused: timer.isPaused, size: 20)

            VStack(alignment: .leading, spacing: 1) {
                // Sized to the full duration — the longest string this timer
                // will ever show — so nothing shifts when 10:00 becomes 9:59.
                // Monospaced digits alone do not cover it: the character
                // count changes too.
                Text(percent ? "\(timer.percentElapsed(at: now))%" : Parser.clock(for: timer.remaining(at: now)))
                    .font(.system(size: 25, weight: .light).monospacedDigit())
                    .foregroundStyle(done ? Design.accent : Design.textPrimary)
                    .frame(minWidth: clockWidth, alignment: .leading)

                // The bar answers the question the percentage asks — how far
                // along — the ring is too small to show a difference of a few
                // points.
                if percent {
                    ProgressBar(progress: timer.progress(at: now), paused: timer.isPaused)
                        .frame(width: clockWidth, height: 4)
                        .padding(.vertical, 2)
                }

                // Duration, state and tag share one line. Given a tag its own
                // column, the panel has to be wide enough for a tag that is
                // usually absent — and then sits mostly empty.
                status
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Live feedback on what is being typed, in place of the controls.
    @ViewBuilder
    private var hint: some View {
        switch parsed {
        case .success(let value):
            HStack(spacing: 5) {
                Text(value.echo)
                if let tag = value.tag {
                    Text("#\(tag)").foregroundStyle(Design.accent)
                }
            }
            .font(Design.caption)
            .foregroundStyle(Design.textSecondary)
        case .failure(let error) where error != .empty:
            Text(draftMessage(for: error))
                .font(Design.caption)
                .foregroundStyle(Design.textFaint)
        default:
            Text("replaces this timer")
                .font(Design.caption)
                .foregroundStyle(Design.textFaint)
        }
    }

    /// Return commits what is typed; with nothing typed it presses the control
    /// this panel leads with — pause or resume a timer still counting, reset one
    /// that has rung.
    private func submit() {
        guard editing else { return defaultAction() }
        guard case .success(let value)? = parsed else { return }
        store.start(slotID, with: value)
        typed = ""
    }

    /// The control Return presses, and the one drawn as default. While the
    /// timer still has time on it the useful move is to stop or restart the
    /// count; once it has rung, the only thing left to do is reset it.
    private var pausesOnReturn: Bool { !done }

    private func defaultAction() {
        if pausesOnReturn {
            store.togglePause(slotID)
        } else {
            reset()
        }
    }

    /// The store decides what reset means: a plain duration rewinds in place,
    /// while a timer written as a time of day goes back to being a draft holding
    /// its own words.
    private func reset() {
        typed = ""
        store.restart(slotID)
    }

    private var controls: some View {
        HStack(spacing: 7) {
                if done {
                    GlyphButton(symbol: "arrow.clockwise", help: "Reset", size: 28,
                                prominent: true, isDefault: true) {
                        reset()
                    }
                } else {
                    GlyphButton(symbol: timer.isPaused ? "play.fill" : "pause.fill",
                                help: timer.isPaused ? "Resume" : "Pause", size: 28,
                                isDefault: pausesOnReturn) {
                        store.togglePause(slotID)
                    }
                    GlyphButton(symbol: "arrow.clockwise", help: "Reset", size: 28,
                                isDefault: !pausesOnReturn) { reset() }
                }
                // Clock or percent: how this one timer reads, in the bar and
                // here. Offered in every state, since a finished timer still
                // shows a number.
                GlyphButton(symbol: percent ? "clock" : "percent",
                            help: percent ? "Show as time" : "Show as percent", size: 28) {
                    store.toggleDisplay(slotID)
                }
                // Clear keeps the item and its place in the bar. Removing it
                // outright is the footer's trash, in every panel state.
                GlyphButton(symbol: "xmark", help: "Clear — keeps this menu bar item", size: 28) {
                    store.clear(slotID)
                }
            }
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var status: some View {
        HStack(spacing: 4) {
            Text(word)
                .foregroundStyle(done ? Design.accent : Design.textSecondary)
            if let tag = timer.tag {
                Text("#\(tag)")
                    .foregroundStyle(Design.textFaint)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .font(Design.caption)
    }

    /// Width of the full-duration clock string — or "100%" — measured in the
    /// same font.
    private var clockWidth: CGFloat {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 25, weight: .light)
        let widest = (percent ? "100%" : Parser.clock(for: timer.duration)) as NSString
        return ceil(widest.size(withAttributes: [.font: font]).width)
    }

    /// What the timer is, under its countdown. A timer set to a time of day says
    /// that time — the length it worked out to when it was set means nothing an
    /// hour later, while "until 4:00 PM" is what was actually asked for.
    private var word: String {
        if done { return "done" }
        // A percentage on its own does not say how long that is; the clock
        // moves down here so it is still one glance away.
        let what = percent
            ? Parser.clock(for: timer.remaining(at: now))
            : timer.target.map { "until \($0.label())" } ?? Parser.echo(for: timer.duration)
        if timer.isReady { return "ready · \(what)" }
        if timer.isPaused { return "paused · \(what)" }
        return what
    }

}
