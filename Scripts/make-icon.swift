#!/usr/bin/env swift
// Renders the BrainDump app icon (brain SF Symbol on indigo background)
// into an iconset directory suitable for `iconutil`.
//
// Usage: swift Scripts/make-icon.swift <output-iconset-dir>

import AppKit
import Foundation

let outputDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "/tmp/BrainDump.iconset"

try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

func renderFrame(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    // Background: deep indigo rounded rect
    let radius = size * 0.225
    let bgColor = NSColor(red: 0.16, green: 0.11, blue: 0.36, alpha: 1.0)
    bgColor.setFill()
    NSBezierPath(
        roundedRect: NSRect(x: 0, y: 0, width: size, height: size),
        xRadius: radius, yRadius: radius
    ).fill()

    // Brain SF Symbol, white, centered with padding
    let pad = size * 0.17
    let symbolRect = NSRect(x: pad, y: pad, width: size - pad * 2, height: size - pad * 2)

    let symbolNames = ["brain.head.profile", "brain", "brain.filled.head.profile"]
    var symbol: NSImage?
    for name in symbolNames {
        if let img = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
            symbol = img
            break
        }
    }

    if let sym = symbol {
        let config = NSImage.SymbolConfiguration(paletteColors: [.white])
        let white = sym.withSymbolConfiguration(config) ?? sym
        white.draw(
            in: symbolRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )
    }

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to path: String) throws {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        print("ERROR: could not encode PNG for \(path)")
        return
    }
    try png.write(to: URL(fileURLWithPath: path))
}

// iconutil size table: (canvas px, filename)
let sizes: [(Int, String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for (px, filename) in sizes {
    let img = renderFrame(size: CGFloat(px))
    let dest = (outputDir as NSString).appendingPathComponent(filename)
    do {
        try writePNG(img, to: dest)
        print("  \(filename) (\(px)px)")
    } catch {
        print("ERROR writing \(filename): \(error)")
    }
}

print("Iconset written to \(outputDir)")
