#!/usr/bin/env swift
//
//  make-icon.swift
//  Renders the PicPress app icon (and an optional PNG preview) with CoreGraphics.
//  Run through scripts/make-icon.sh, which also produces the .icns via iconutil.
//

import AppKit
import Foundation

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    guard let context = NSGraphicsContext.current?.cgContext else { return image }

    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    context.clear(canvas)

    // macOS icons leave a little air around the squircle.
    let inset = size * 0.079
    let body = canvas.insetBy(dx: inset, dy: inset)
    let radius = body.width * 0.2237

    // Soft drop shadow.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -size * 0.012),
                      blur: size * 0.035,
                      color: NSColor.black.withAlphaComponent(0.30).cgColor)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius).fill()
    context.restoreGState()

    // Gradient body.
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
    bodyPath.addClip()
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.31, green: 0.66, blue: 1.00, alpha: 1),
        NSColor(srgbRed: 0.46, green: 0.34, blue: 0.96, alpha: 1)
    ])!
    gradient.draw(in: bodyPath, angle: -55)

    // Subtle top highlight.
    let highlight = NSBezierPath(roundedRect: body.insetBy(dx: body.width * 0.03, dy: body.height * 0.03),
                                 xRadius: radius * 0.92, yRadius: radius * 0.92)
    NSColor.white.withAlphaComponent(0.16).setStroke()
    highlight.lineWidth = max(1, size * 0.006)
    highlight.stroke()

    // Compress arrows.
    guard let symbol = NSImage(systemSymbolName: "arrow.down.right.and.arrow.up.left",
                               accessibilityDescription: nil) else { return image }
    let configuration = NSImage.SymbolConfiguration(pointSize: size * 0.46, weight: .bold)
    guard let configured = symbol.withSymbolConfiguration(configuration) else { return image }

    let symbolSize = configured.size
    let tinted = NSImage(size: symbolSize)
    tinted.lockFocus()
    configured.draw(in: NSRect(origin: .zero, size: symbolSize))
    NSColor.white.set()
    NSRect(origin: .zero, size: symbolSize).fill(using: .sourceAtop)
    tinted.unlockFocus()

    let target = NSRect(x: (size - symbolSize.width) / 2,
                        y: (size - symbolSize.height) / 2,
                        width: symbolSize.width,
                        height: symbolSize.height)
    tinted.draw(in: target)

    return image
}

func writePNG(_ image: NSImage, to url: URL, pixelSize: Int) {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: pixelSize,
                                     pixelsHigh: pixelSize,
                                     bitsPerSample: 8,
                                     samplesPerPixel: 4,
                                     hasAlpha: true,
                                     isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0,
                                     bitsPerPixel: 0) else { return }
    rep.size = NSSize(width: pixelSize, height: pixelSize)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
               from: NSRect(origin: .zero, size: image.size),
               operation: .sourceOver,
               fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: url)
    }
}

let arguments = CommandLine.arguments.dropFirst()
guard let outputDirectory = arguments.first else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output-dir>\n".utf8))
    exit(2)
}

let directory = URL(fileURLWithPath: outputDirectory)
try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

let master = drawIcon(size: 1024)
let pngURL = directory.appendingPathComponent("icon-1024.png")
writePNG(master, to: pngURL, pixelSize: 1024)
print("wrote \(pngURL.path)")
