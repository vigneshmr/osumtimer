import SwiftUI

/// The whole visual language, in one file.
///
/// One neutral ramp, one accent, one radius scale, one type scale. Nothing is
/// decorative: every border is a hairline, every surface is flat, and the only
/// saturated colour in the app is the progress ring. Restraint is the look.
enum Design {
    // Neutrals — a single ramp, used by role rather than by name.
    static let surface = Color(light: .init(white: 1.0, alpha: 1), dark: .init(white: 0.075, alpha: 1))
    static let surfaceRaised = Color(light: .init(white: 0.965, alpha: 1), dark: .init(white: 0.125, alpha: 1))
    static let hairline = Color(light: .black.alpha(0.09), dark: .white.alpha(0.10))

    static let textPrimary = Color(light: .black.alpha(0.90), dark: .white.alpha(0.93))
    static let textSecondary = Color(light: .black.alpha(0.45), dark: .white.alpha(0.45))
    static let textFaint = Color(light: .black.alpha(0.28), dark: .white.alpha(0.28))

    static let accent = Color(red: 0.094, green: 0.467, blue: 0.949)   // #1877F2

    // Geometry — a 4pt grid, two radii, and that is the entire system.
    static let radius: CGFloat = 10
    static let radiusSmall: CGFloat = 7
    static let gutter: CGFloat = 14
    // Sized to the control row (4 × 28 + gaps) plus gutters — the panel is as
    // wide as its widest content needs and no wider.
    static let popoverWidth: CGFloat = 224

    // Type — one family, four sizes. Numerals are always monospaced so digits
    // never reflow while counting down.
    static let input = Font.system(size: 17, weight: .regular)
    static let clock = Font.system(size: 17, weight: .medium).monospacedDigit()
    static let label = Font.system(size: 14, weight: .medium)
    static let caption = Font.system(size: 13, weight: .regular)
    static let menuBar = Font.system(size: menuBarSize, weight: .medium).monospacedDigit()

    // The menu bar title is drawn with AppKit, so its size lives here as a
    // number that both the SwiftUI font above and StatusItemController can use.
    // Deliberately not scaled with the popover type: this text sits beside the
    // clock and other status items, so it takes the system's own menu bar size
    // and follows it if the user changes it.
    static let menuBarSize: CGFloat = NSFont.menuBarFont(ofSize: 0).pointSize
}

extension NSColor {
    func alpha(_ value: CGFloat) -> NSColor { withAlphaComponent(value) }
}

extension Color {
    /// Resolves per appearance so the palette is declared once, in one place.
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

/// The countdown ring. Sweeps clockwise from twelve, thins to a hairline track.
struct ProgressRing: View {
    var progress: Double
    var paused: Bool
    var size: CGFloat = 15

    var body: some View {
        ZStack {
            Circle()
                .stroke(Design.hairline, lineWidth: 1.5)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(
                    paused ? Design.textFaint : Design.accent,
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                // Deliberately not animated. Interpolating between two progress
                // values only looks right when they are one second apart; every
                // other change — pause, reset, a new duration, a timer replaced
                // in place — sends the head flying around the ring to catch up.
                // A once-a-second step at this size reads as motion anyway.
        }
        .frame(width: size, height: size)
    }
}

/// A borderless glyph button — the only button style in the app.
///
/// Icon-only: labels do not fit four abreast at the panel's width, and a clipped
/// word ("Re…", "Cl…") reads worse than no word. The name lives in the tooltip,
/// which is also what carries it to VoiceOver.
struct GlyphButton: View {
    var symbol: String
    var help: String
    var size: CGFloat = 20
    var prominent = false
    /// The button Return presses. Ringed so the key's effect is visible before
    /// it is pressed, the way a default button reads in a dialog.
    var isDefault = false
    var action: () -> Void

    @State private var hovering = false

    private var foreground: Color {
        if prominent { return Design.accent }
        return hovering ? Design.textPrimary : Design.textSecondary
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: Design.radiusSmall, style: .continuous)
                        .fill(hovering ? Design.hairline : Design.surfaceRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Design.radiusSmall, style: .continuous)
                        .strokeBorder(Design.accent.opacity(isDefault ? 0.7 : 0), lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}
