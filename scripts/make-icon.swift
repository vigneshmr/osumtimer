// Draws the app icon and writes an .icns, with no design tools involved.
//
// The mark is a disc with a quarter cut out of it — a timer part-way through.
//
// One shape, two straight edges, no ornament: no stem, no hand, no tick marks.
// Deliberately not the app's thin open ring either, which at icon size is the
// power-button silhouette a dozen other apps already use. The cut quadrant says
// "elapsed" on its own, and holds its meaning down to 16pt where any added
// detail would only turn to mush.
//
// Usage: swift scripts/make-icon.swift <output.icns>

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let accent = (r: 0.094, g: 0.467, b: 0.949)

func drawIcon(size: Int) -> CGImage? {
    let scale = CGFloat(size)
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    // macOS icons sit in a rounded square inset from the canvas edge.
    let inset = scale * 0.08
    let rect = CGRect(x: inset, y: inset, width: scale - inset * 2, height: scale - inset * 2)
    let radius = rect.width * 0.2237  // the squircle radius Apple uses

    context.setFillColor(CGColor(red: accent.r, green: accent.g, blue: accent.b, alpha: 1))
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.fillPath()

    // Optically centred, not geometrically: removing the upper-right quadrant
    // moves the mark's visual weight down and left, so the disc is nudged back
    // toward the gap by a fraction of its radius.
    let dialRadius = scale * 0.28
    let centre = CGPoint(x: scale / 2 + dialRadius * 0.05, y: scale / 2 + dialRadius * 0.05)
    let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)

    // The dial: a solid disc, so the wedge can be cut out of it in blue.
    context.setFillColor(white)
    context.addArc(center: centre, radius: dialRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    context.fillPath()

    // The wedge, swept clockwise from twelve — a quarter of the way round.
    context.setFillColor(CGColor(red: accent.r, green: accent.g, blue: accent.b, alpha: 1))
    context.move(to: centre)
    context.addArc(
        center: centre,
        radius: dialRadius,
        startAngle: .pi / 2,
        endAngle: 0,
        clockwise: true
    )
    context.closePath()
    context.fillPath()

    return context.makeImage()
}

func write(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else {
        throw NSError(domain: "icon", code: 1)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "icon", code: 2) }
}

// MARK: - Main

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write("usage: make-icon.swift <output.icns>\n".data(using: .utf8)!)
    exit(2)
}

let output = URL(fileURLWithPath: arguments[1])
let iconset = FileManager.default.temporaryDirectory
    .appendingPathComponent("OsumTimer-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// The set iconutil expects: each size at 1x and 2x.
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        guard let image = drawIcon(size: base * scale) else { exit(1) }
        let suffix = scale == 1 ? "" : "@2x"
        try write(image, to: iconset.appendingPathComponent("icon_\(base)x\(base)\(suffix).png"))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
exit(iconutil.terminationStatus)
