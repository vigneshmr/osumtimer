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

    static let accent = Color(red: 0.063, green: 0.639, blue: 0.498)   // #10A37F

    // Geometry — a 4pt grid, two radii, and that is the entire system.
    static let radius: CGFloat = 10
    static let radiusSmall: CGFloat = 7
    static let gutter: CGFloat = 14
    static let popoverWidth: CGFloat = 292

    // Type — one family, four sizes. Numerals are always monospaced so digits
    // never reflow while counting down.
    static let input = Font.system(size: 15, weight: .regular)
    static let clock = Font.system(size: 15, weight: .medium).monospacedDigit()
    static let label = Font.system(size: 12, weight: .medium)
    static let caption = Font.system(size: 11, weight: .regular)
    static let menuBar = Font.system(size: 12.5, weight: .medium).monospacedDigit()
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
                .animation(.linear(duration: 0.9), value: progress)
        }
        .frame(width: size, height: size)
    }
}

/// A borderless glyph button — the only button style in the app.
struct GlyphButton: View {
    var symbol: String
    var help: String
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(hovering ? Design.textPrimary : Design.textFaint)
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(hovering ? Design.hairline : .clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
