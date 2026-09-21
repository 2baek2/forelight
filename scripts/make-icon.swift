#!/usr/bin/env swift
import AppKit

// Renders the Forelight app icon master (1024x1024 PNG).
// Usage: swift scripts/make-icon.swift [output.png]

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : ".build/AppIcon-1024.png"

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else {
    FileHandle.standardError.write("no graphics context\n".data(using: .utf8)!)
    exit(1)
}

// Rounded-square background, macOS style.
let inset = size * 0.055
let backgroundRect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let radius = backgroundRect.width * 0.2237
let backgroundPath = NSBezierPath(roundedRect: backgroundRect, xRadius: radius, yRadius: radius)
let background = NSGradient(colors: [
    NSColor(srgbRed: 0.14, green: 0.14, blue: 0.20, alpha: 1),
    NSColor(srgbRed: 0.06, green: 0.06, blue: 0.09, alpha: 1)
])!
background.draw(in: backgroundPath, angle: -90)

// Soft accent glow behind the glyph.
context.saveGState()
backgroundPath.addClip()
let accent = NSColor(srgbRed: 0.04, green: 0.52, blue: 1.0, alpha: 1)
let glowColors = [
    accent.withAlphaComponent(0.50).cgColor,
    accent.withAlphaComponent(0.0).cgColor
] as CFArray
if let glowGradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: glowColors,
    locations: [0, 1]
) {
    let center = CGPoint(x: size / 2, y: size * 0.64)
    context.drawRadialGradient(
        glowGradient,
        startCenter: center,
        startRadius: 0,
        endCenter: center,
        endRadius: size * 0.58,
        options: []
    )
}
context.restoreGState()

// Viewfinder glyph.
func tinted(_ source: NSImage, _ color: NSColor) -> NSImage {
    let result = NSImage(size: source.size)
    result.lockFocus()
    source.draw(in: NSRect(origin: .zero, size: source.size))
    color.set()
    NSRect(origin: .zero, size: source.size).fill(using: .sourceIn)
    result.unlockFocus()
    return result
}

let symbolSize = size * 0.50
let configuration = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .medium)
if let symbol = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: nil)?
    .withSymbolConfiguration(configuration) {
    let glyph = tinted(symbol, .white)
    let glyphRect = NSRect(
        x: (size - glyph.size.width) / 2,
        y: (size - glyph.size.height) / 2,
        width: glyph.size.width,
        height: glyph.size.height
    )
    glyph.draw(in: glyphRect, from: .zero, operation: .sourceOver, fraction: 1)
}
image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("failed to encode png\n".data(using: .utf8)!)
    exit(1)
}

let url = URL(fileURLWithPath: outputPath)
try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
do {
    try png.write(to: url)
    print("wrote \(url.path)")
} catch {
    FileHandle.standardError.write("write failed: \(error)\n".data(using: .utf8)!)
    exit(1)
}
