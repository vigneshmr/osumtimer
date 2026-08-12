import SwiftUI

/// The one surface: a field at the top, timers beneath it.
///
/// The field is focused the moment the popover opens, so the fastest path to a
/// timer is hotkey → type → Return, with no pointer involved.
struct PopoverView: View {
    @Environment(TimerStore.self) private var store
    @State private var text = ""
    @FocusState private var focused: Bool

    private var parsed: Result<ParsedTimer, ParseError>? {
        text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : Parser.parse(text)
    }

    var body: some View {
        VStack(spacing: 0) {
            field
            if !store.timers.isEmpty {
                Divider().overlay(Design.hairline)
                list
            }
            footer
        }
        .frame(width: Design.popoverWidth)
        .background(Design.surface)
        .onAppear { focused = true }
    }

    // MARK: - Field

    private var field: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("45m", text: $text)
                .textFieldStyle(.plain)
                .font(Design.input)
                .foregroundStyle(Design.textPrimary)
                .focused($focused)
                .onSubmit(submit)

            hint
        }
        .padding(.horizontal, Design.gutter)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    /// Live feedback under the field. This is what makes natural-language input
    /// feel trustworthy rather than a guess — you see the reading before you commit.
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
            recentsRow
        }
    }

    private var recentsRow: some View {
        HStack(spacing: 5) {
            if store.recents.isEmpty {
                Text("try 25, 1.5h, 1:30, @5pm")
                    .font(Design.caption)
                    .foregroundStyle(Design.textFaint)
            } else {
                ForEach(store.recents, id: \.self) { duration in
                    Button(Parser.clock(for: duration)) {
                        store.add(.init(duration: duration, tag: nil, echo: Parser.echo(for: duration)))
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
        store.add(value)
        text = ""
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(store.sorted) { timer in
                    TimerRow(timer: timer, now: store.tick)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 232)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if store.timers.count > 1 {
                Button("Clear all", action: store.removeAll)
                    .buttonStyle(.plain)
                    .font(Design.caption)
                    .foregroundStyle(Design.textFaint)
            }
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(Design.caption)
                .foregroundStyle(Design.textFaint)
        }
        .padding(.horizontal, Design.gutter)
        .padding(.vertical, 9)
        .overlay(alignment: .top) { Divider().overlay(Design.hairline) }
    }
}

/// One countdown. Controls appear on hover, so the resting state is just a
/// ring, a time, and a tag.
struct TimerRow: View {
    let timer: TimerItem
    let now: Date

    @Environment(TimerStore.self) private var store
    @State private var hovering = false

    private var done: Bool { timer.hasFired(at: now) }

    var body: some View {
        HStack(spacing: 9) {
            ProgressRing(progress: timer.progress(at: now), paused: timer.isPaused)

            Text(Parser.clock(for: timer.remaining(at: now)))
                .font(Design.clock)
                .foregroundStyle(done ? Design.accent : (timer.isPaused ? Design.textSecondary : Design.textPrimary))

            if let tag = timer.tag {
                Text("#\(tag)")
                    .font(Design.label)
                    .foregroundStyle(Design.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if hovering {
                if done {
                    GlyphButton(symbol: "arrow.clockwise", help: "Restart") { store.restart(timer.id) }
                } else {
                    GlyphButton(symbol: timer.isPaused ? "play.fill" : "pause.fill",
                                help: timer.isPaused ? "Resume" : "Pause") { store.togglePause(timer.id) }
                }
                GlyphButton(symbol: "xmark", help: "Remove") { store.remove(timer.id) }
            }
        }
        .padding(.horizontal, Design.gutter)
        .padding(.vertical, 7)
        .background(hovering ? Design.surfaceRaised : .clear)
        .contentShape(.rect)
        .onHover { hovering = $0 }
    }
}
