// Draws the app icon and writes an .icns, with no design tools involved.
//
// The mark is the app's own progress ring: a thin white circle on the accent
// blue, open at the top with the head sitting in the gap — the same thing the
// menu bar draws, so the icon and the app agree.
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

    // The ring, centred, opened at twelve o'clock.
    let centre = CGPoint(x: scale / 2, y: scale / 2)
    let ringRadius = scale * 0.26
    let lineWidth = max(scale * 0.055, 1)

    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    context.setLineWidth(lineWidth)
    context.setLineCap(.round)
    context.addArc(
        center: centre,
        radius: ringRadius,
        startAngle: .pi / 2 + 0.42,
        endAngle: .pi / 2 - 0.42,
        clockwise: false
    )
    context.strokePath()

    // The head, filling the gap it left.
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.addArc(
        center: CGPoint(x: centre.x, y: centre.y + ringRadius),
        radius: lineWidth * 0.75,
        startAngle: 0,
        endAngle: .pi * 2,
        clockwise: false
    )
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
