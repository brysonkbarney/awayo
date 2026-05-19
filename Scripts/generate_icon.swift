#!/usr/bin/env swift

import AppKit
import Foundation

let arguments = CommandLine.arguments

guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: generate_icon.swift /path/to/AppIcon.icns\n".utf8))
    exit(64)
}

let outputURL = URL(fileURLWithPath: arguments[1])
let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("Awayo-\(UUID().uuidString).iconset", isDirectory: true)

try FileManager.default.createDirectory(
    at: temporaryDirectory,
    withIntermediateDirectories: true
)

defer {
    try? FileManager.default.removeItem(at: temporaryDirectory)
}

let iconSizes = [16, 32, 128, 256, 512]

for size in iconSizes {
    try writeIcon(size: size, scale: 1, to: temporaryDirectory.appendingPathComponent("icon_\(size)x\(size).png"))
    try writeIcon(size: size, scale: 2, to: temporaryDirectory.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = [
    "-c",
    "icns",
    temporaryDirectory.path,
    "-o",
    outputURL.path
]

try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    exit(process.terminationStatus)
}

func writeIcon(size: Int, scale: Int, to url: URL) throws {
    let pixels = size * scale
    let pointSize = CGFloat(size)

    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw CocoaError(.featureUnsupported)
    }

    representation.size = NSSize(width: pointSize, height: pointSize)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: pointSize, height: pointSize).fill()

    let inset = pointSize * 0.075
    let radius = pointSize * 0.22
    let rect = NSRect(
        x: inset,
        y: inset,
        width: pointSize - inset * 2,
        height: pointSize - inset * 2
    )
    let rounded = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    let background = NSGradient(colors: [
        NSColor(calibratedRed: 0.02, green: 0.04, blue: 0.08, alpha: 1),
        NSColor(calibratedRed: 0.03, green: 0.42, blue: 0.42, alpha: 1)
    ])
    background?.draw(in: rounded, angle: -32)

    let glow = NSBezierPath(ovalIn: NSRect(
        x: pointSize * 0.56,
        y: pointSize * 0.56,
        width: pointSize * 0.24,
        height: pointSize * 0.24
    ))
    NSColor(calibratedRed: 0.95, green: 0.88, blue: 0.46, alpha: 0.92).setFill()
    glow.fill()

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
    shadow.shadowOffset = NSSize(width: 0, height: -pointSize * 0.012)
    shadow.shadowBlurRadius = pointSize * 0.035
    shadow.set()

    let letter = "A"
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: pointSize * 0.56, weight: .heavy),
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraph
    ]
    let letterRect = NSRect(
        x: 0,
        y: pointSize * 0.19,
        width: pointSize,
        height: pointSize * 0.58
    )
    letter.draw(in: letterRect, withAttributes: attributes)

    NSGraphicsContext.restoreGraphicsState()

    guard let data = representation.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }

    try data.write(to: url)
}
