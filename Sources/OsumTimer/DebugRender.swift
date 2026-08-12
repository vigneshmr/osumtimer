import SwiftUI
import AppKit

/// Renders the panel to a PNG and exits: `OSUMTIMER_RENDER=/path/out.png`.
///
/// A popover over a live desktop is a poor thing to screenshot — this draws the
/// same views offscreen, so layout can be checked deterministically.
@MainActor
enum DebugRender {
    static func runIfRequested() -> Bool {
        guard let path = ProcessInfo.processInfo.environment["OSUMTIMER_RENDER"] else { return false }

        // A scratch store, so a render never touches real saved timers.
        let store = TimerStore(store: Persistence(filename: "render-preview.json"))
        let running = store.slots[0].id
        store.start(running, with: .init(duration: 1500, tag: "deepwork", echo: "25 min"))
        let draft = store.addSlot()

        render(SlotView(slotID: running).environment(store), to: path)
        render(SlotView(slotID: draft).environment(store), to: (path as NSString).deletingPathExtension + "-draft.png")

        exit(0)
    }

    private static func render(_ view: some View, to path: String) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
