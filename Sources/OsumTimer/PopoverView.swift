import SwiftUI

/// The panel behind a single menu bar item.
///
/// An item starts empty: this shows a field, you type, and that same item becomes
/// the countdown. Once running, the panel shows the timer's own controls. Every
/// state carries "+ Add timer", which spawns another empty item beside it.
struct SlotView: View {
    let slotID: UUID
    @Environment(TimerStore.self) private var store

    private var slot: Slot? { store.slot(slotID) }

    var body: some View {
        VStack(spacing: 0) {
            if let timer = slot?.timer {
                RunningPanel(slotID: slotID, timer: timer, now: store.tick)
            } else {
                DraftPanel(slotID: slotID)
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
                store.addSlot()
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

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(Design.caption)
                .foregroundStyle(Design.textFaint)
        }
        .padding(.horizontal, Design.gutter)
        .padding(.vertical, 10)
    }
}

/// An empty item: type a duration and it becomes this item's countdown.
private struct DraftPanel: View {
    let slotID: UUID
    @Environment(TimerStore.self) private var store
    @State private var text = ""
    @FocusState private var focused: Bool

    private var parsed: Result<ParsedTimer, ParseError>? {
        text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : Parser.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            TextField("45m", text: $text)
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
        .onAppear { focused = true }
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
            Text(message(for: error))
                .font(Design.caption)
                .foregroundStyle(Design.textFaint)
        default:
            recents
        }
    }

    private var recents: some View {
        HStack(spacing: 5) {
            if store.recents.isEmpty {
                Text("try 25, 1.5h, 1:30, @5pm")
                    .font(Design.caption)
                    .foregroundStyle(Design.textFaint)
            } else {
                ForEach(store.recents, id: \.self) { duration in
                    Button(Parser.clock(for: duration)) {
                        store.start(slotID, with: .init(duration: duration, tag: nil, echo: Parser.echo(for: duration)))
                    }
                    .buttonStyle(.plain)
                    .font(Design.caption.monospacedDigit())
                    .foregroundStyle(Design.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Design.surfaceRaised)
                    )
                }
            }
        }
    }

    private func message(for error: ParseError) -> String {
        switch error {
        case .unrecognized: "not a duration"
        case .notPositive: "must be more than zero"
        case .tooLong: "longer than a week"
        case .empty: ""
        }
    }

    private func submit() {
        guard case .success(let value)? = parsed else { return }
        store.start(slotID, with: value)
        text = ""
    }
}

/// A live item: its countdown and its own controls. Nothing here refers to any
/// other timer — this panel belongs to one menu bar item.
private struct RunningPanel: View {
    let slotID: UUID
    let timer: TimerItem
    let now: Date
    @Environment(TimerStore.self) private var store

    private var done: Bool { timer.hasFired(at: now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                ProgressRing(progress: timer.progress(at: now), paused: timer.isPaused, size: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text(Parser.clock(for: timer.remaining(at: now)))
                        .font(.system(size: 26, weight: .light).monospacedDigit())
                        .foregroundStyle(done ? Design.accent : Design.textPrimary)

                    Text(status)
                        .font(Design.caption)
                        .foregroundStyle(done ? Design.accent : Design.textSecondary)
                }

                Spacer()

                if let tag = timer.tag {
                    Text("#\(tag)")
                        .font(Design.label)
                        .foregroundStyle(Design.textSecondary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 7) {
                if done {
                    GlyphButton(symbol: "arrow.clockwise", help: "Restart", size: 28, prominent: true) {
                        store.restart(slotID)
                    }
                } else {
                    GlyphButton(symbol: timer.isPaused ? "play.fill" : "pause.fill",
                                help: timer.isPaused ? "Resume" : "Pause", size: 28) {
                        store.togglePause(slotID)
                    }
                    GlyphButton(symbol: "arrow.clockwise", help: "Restart", size: 28) { store.restart(slotID) }
                }
                // Clear keeps the item and its place in the bar; Remove takes both.
                GlyphButton(symbol: "xmark", help: "Clear — keeps this menu bar item", size: 28) {
                    store.clear(slotID)
                }
                Spacer()
                GlyphButton(symbol: "trash", help: "Remove this menu bar item", size: 28) {
                    store.remove(slotID)
                }
            }
        }
        .padding(.horizontal, Design.gutter)
        .padding(.top, 13)
        .padding(.bottom, 12)
    }

    private var status: String {
        if done { return "done" }
        if timer.isPaused { return "paused · \(Parser.echo(for: timer.duration))" }
        return Parser.echo(for: timer.duration)
    }

}
