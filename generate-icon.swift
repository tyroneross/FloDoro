#!/usr/bin/env swift
// generate-icon.swift — Creates AppIcon.icns programmatically using AppKit
// No external assets needed. Renders a gradient circle with "F" lettermark.

import AppKit
import Foundation

let iconsetDir = "AppIcon.iconset"
let icnsOutput = "AppIcon.icns"

// Required sizes for macOS .iconset
let sizes: [(name: String, size: Int)] = [
    ("icon_16x16",       16),
    ("icon_16x16@2x",    32),
    ("icon_32x32",       32),
    ("icon_32x32@2x",    64),
    ("icon_128x128",     128),
    ("icon_128x128@2x",  256),
    ("icon_256x256",     256),
    ("icon_256x256@2x",  512),
    ("icon_512x512",     512),
    ("icon_512x512@2x",  1024),
]

func renderIcon(size: Int) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        img.unlockFocus()
        return img
    }

    let s = CGFloat(size)
    let rect = CGRect(x: 0, y: 0, width: s, height: s)

    // --- Background: rounded square with gradient ---
    let cornerRadius = s * 0.22
    let bgPath = NSBezierPath(roundedRect: rect.insetBy(dx: s * 0.02, dy: s * 0.02),
                               xRadius: cornerRadius, yRadius: cornerRadius)

    // Gradient: teal-blue (matches .timerAccent / .flowAccent from Theme.swift)
    let topColor = NSColor(red: 0.02, green: 0.588, blue: 0.412, alpha: 1.0)    // breakAccent green
    let bottomColor = NSColor(red: 0.145, green: 0.388, blue: 0.922, alpha: 1.0) // timerAccent blue

    if let gradient = NSGradient(starting: topColor, ending: bottomColor) {
        gradient.draw(in: bgPath, angle: -45)
    }

    // --- Subtle inner shadow for depth ---
    ctx.saveGState()
    let shadowColor = NSColor(white: 0, alpha: 0.15)
    let innerRect = rect.insetBy(dx: s * 0.04, dy: s * 0.04)
    let innerPath = NSBezierPath(roundedRect: innerRect, xRadius: cornerRadius * 0.9, yRadius: cornerRadius * 0.9)
    shadowColor.setStroke()
    innerPath.lineWidth = s * 0.01
    innerPath.stroke()
    ctx.restoreGState()

    // --- Timer ring arc (partial circle) ---
    let ringCenter = CGPoint(x: s * 0.5, y: s * 0.48)
    let ringRadius = s * 0.28
    let ringWidth = s * 0.04

    // Background ring (faint white)
    let bgRing = NSBezierPath()
    bgRing.appendArc(withCenter: ringCenter, radius: ringRadius,
                     startAngle: 0, endAngle: 360)
    NSColor(white: 1.0, alpha: 0.2).setStroke()
    bgRing.lineWidth = ringWidth
    bgRing.lineCapStyle = .round
    bgRing.stroke()

    // Progress arc (bright white, ~75% fill, starting from top)
    let progressRing = NSBezierPath()
    progressRing.appendArc(withCenter: ringCenter, radius: ringRadius,
                           startAngle: 90, endAngle: 90 - 270, clockwise: true)
    NSColor(white: 1.0, alpha: 0.9).setStroke()
    progressRing.lineWidth = ringWidth
    progressRing.lineCapStyle = .round
    progressRing.stroke()

    // --- "F" lettermark ---
    let fontSize = s * 0.3
    let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
    let letter = "F" as NSString
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
    ]
    let letterSize = letter.size(withAttributes: attrs)
    let letterOrigin = CGPoint(
        x: (s - letterSize.width) / 2 + s * 0.01,
        y: (s - letterSize.height) / 2 - s * 0.02
    )
    letter.draw(at: letterOrigin, withAttributes: attrs)

    img.unlockFocus()
    return img
}

// Create iconset directory
let fm = FileManager.default
try? fm.removeItem(atPath: iconsetDir)
try fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

// Render each required size
for (name, size) in sizes {
    let image = renderIcon(size: size)
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        fputs("Failed to render \(name)\n", stderr)
        exit(1)
    }
    let path = "\(iconsetDir)/\(name).png"
    try png.write(to: URL(fileURLWithPath: path))
}

// Convert to .icns using iconutil
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetDir, "-o", icnsOutput]
try iconutil.run()
iconutil.waitUntilExit()

if iconutil.terminationStatus != 0 {
    fputs("iconutil failed with status \(iconutil.terminationStatus)\n", stderr)
    exit(1)
}

// Clean up iconset directory
try? fm.removeItem(atPath: iconsetDir)

print("Generated \(icnsOutput)")
