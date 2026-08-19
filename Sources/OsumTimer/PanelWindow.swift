import AppKit
import SwiftUI

/// The bubble hanging off a menu bar item.
///
/// Not an `NSPopover`: a popover insists on centring itself under its item and
/// re-aims itself whenever that item moves or changes width, which is exactly
/// what a countdown does every second. The panel would twitch under the cursor
/// mid-sentence. This one is placed once, when it opens, and never again — the
/// item can shuffle along the bar underneath it and the words stay put.
///
/// It also lets the pointer sit near a corner rather than dead centre, which a
/// popover only ever does by accident at the edge of a screen.
/// The bubble's shape, in numbers. Kept out of the window class so the shape
/// that draws it can read them without hopping to the main actor.
enum PanelMetrics {
    /// How far the pointer's tip sits from the bubble's trailing edge.
    static let pointerInset: CGFloat = 26
    static let pointerWidth: CGFloat = 15
    static let pointerHeight: CGFloat = 7
    static let radius: CGFloat = 10
}

@MainActor
final class PanelWindow {

    private var window: KeyPanel?
    private var hosting: NSHostingView<AnyView>?
    /// Where the pointer points, in the bubble's own coordinates. Fixed for as
    /// long as the bubble is open.
    private var pointerX: CGFloat = 0
    private var onClose: (() -> Void)?

    var isShown: Bool { window?.isVisible ?? false }
    var appearance: NSAppearance? {
        get { window?.appearance }
        set { window?.appearance = newValue }
    }

    /// Opens `content` under `button`, or moves an already open bubble to it.
    func show<Content: View>(
        under button: NSStatusBarButton,
        appearance: NSAppearance?,
        content: Content,
        onClose: @escaping () -> Void
    ) {
        self.onClose = onClose
        close(notify: false)

        let panel = KeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: Design.popoverWidth, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.appearance = appearance
        panel.onResignKey = { [weak self] in self?.close(notify: true) }

        // Placed against the item as it stands right now, and left there.
        let anchor = anchorPoint(for: button)
        let frame = frame(for: NSSize(width: Design.popoverWidth, height: 1), anchoredAt: anchor)
        pointerX = min(
            max(anchor.x - frame.minX, PanelMetrics.radius + PanelMetrics.pointerWidth),
            Design.popoverWidth - PanelMetrics.radius - PanelMetrics.pointerWidth / 2
        )

        let root = AnyView(
            PanelChrome(pointerX: pointerX) { content }
                .frame(width: Design.popoverWidth)
        )
        let view = NSHostingView(rootView: root)
        view.frame = NSRect(origin: .zero, size: view.fittingSize)
        panel.contentView = view
        hosting = view
        window = panel

        resize(to: view.fittingSize, keepingTopAt: frame.maxY, x: frame.minX)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
    }

    /// The panel grows and shrinks as its slot changes state. Only its height
    /// ever gives: the top edge and the left edge are where they were put.
    func fit() {
        guard let window, let hosting else { return }
        let size = hosting.fittingSize
        guard abs(size.height - window.frame.height) > 0.5 else { return }
        resize(to: size, keepingTopAt: window.frame.maxY, x: window.frame.minX)
    }

    func close(notify: Bool = true) {
        window?.onResignKey = nil
        window?.orderOut(nil)
        window = nil
        hosting = nil
        if notify { onClose?() }
    }

    // MARK: - Geometry

    private func resize(to size: NSSize, keepingTopAt top: CGFloat, x: CGFloat) {
        guard let window else { return }
        window.setFrame(
            NSRect(x: x, y: top - size.height, width: size.width, height: size.height),
            display: true
        )
        window.invalidateShadow()
    }

    /// The point on the underside of the menu bar the pointer aims at.
    private func anchorPoint(for button: NSStatusBarButton) -> CGPoint {
        guard let itemWindow = button.window else { return .zero }
        let rect = itemWindow.frame
        return CGPoint(x: rect.midX, y: rect.minY)
    }

    /// Hangs the bubble from `anchor` with the pointer near its trailing corner,
    /// nudged back onto the screen if that would push it off.
    private func frame(for size: NSSize, anchoredAt anchor: CGPoint) -> NSRect {
        var x = anchor.x - (size.width - PanelMetrics.pointerInset)
        let top = anchor.y - 2
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: anchor.x, y: anchor.y - 1)) })
            ?? NSScreen.main {
            let margin: CGFloat = 8
            x = min(x, screen.frame.maxX - size.width - margin)
            x = max(x, screen.frame.minX + margin)
        }
        return NSRect(x: x, y: top - size.height, width: size.width, height: size.height)
    }
}

/// Borderless windows refuse key by default, and the duration field is the whole
/// point of the panel.
private final class KeyPanel: NSPanel {
    var onResignKey: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        // Clicking away dismisses it, the way a menu behaves.
        DispatchQueue.main.async { [weak self] in self?.onResignKey?() }
    }

    /// Escape closes the panel; borderless windows have no other way to.
    override func cancelOperation(_ sender: Any?) {
        NotificationCenter.default.post(name: .osumClosePanel, object: nil)
    }
}

/// The bubble itself: the panel's content, with a pointer poking out of the top
/// near one corner.
private struct PanelChrome<Content: View>: View {
    let pointerX: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.top, PanelMetrics.pointerHeight)
            .background(
                BubbleShape(pointerX: pointerX)
                    .fill(Design.surface)
            )
            .overlay(
                BubbleShape(pointerX: pointerX)
                    .stroke(Design.hairline, lineWidth: 1)
            )
            .clipShape(BubbleShape(pointerX: pointerX))
    }
}

private struct BubbleShape: Shape {
    let pointerX: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = PanelMetrics.radius
        let height = PanelMetrics.pointerHeight
        let half = PanelMetrics.pointerWidth / 2
        let body = CGRect(
            x: rect.minX, y: rect.minY + height,
            width: rect.width, height: rect.height - height
        )

        var path = Path(roundedRect: body, cornerRadius: radius, style: .continuous)
        var tip = Path()
        tip.move(to: CGPoint(x: pointerX - half, y: body.minY))
        tip.addLine(to: CGPoint(x: pointerX, y: rect.minY))
        tip.addLine(to: CGPoint(x: pointerX + half, y: body.minY))
        tip.closeSubpath()
        path.addPath(tip)
        return path
    }
}
