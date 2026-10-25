// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 CloudCoder Limited
// Draws the TurboFan Pro app icon (TurboFan icon plus an amber PRO badge) (CloudCoder cloud with a fan and turbo hub) and writes AppIcon.icns.
// Usage: swift assets/make-icon-pro.swift assets/AppIconPro.icns
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

// CloudCoder palette
let bgTop = color(0x1d2733), bgBottom = color(0x0c1117)
let cloudLight = color(0x4fb8ff), cloudDeep = color(0x2b5fc8)
let amber = color(0xf0a34a)

func drawIcon(size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(size)
    ctx.scaleBy(x: s / 1024, y: s / 1024) // draw in a 1024 grid

    // Background: macOS-style rounded square with a soft vertical gradient.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.45))
    ctx.addPath(tilePath); ctx.setFillColor(bgBottom); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(tilePath); ctx.clip()
    let bg = CGGradient(colorsSpace: nil, colors: [bgTop, bgBottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()

    // Cloud: circles on a rounded base, filled with the CloudCoder blue gradient.
    let cloud = CGMutablePath()
    cloud.addRoundedRect(in: CGRect(x: 214, y: 300, width: 596, height: 250), cornerWidth: 125, cornerHeight: 125)
    cloud.addEllipse(in: CGRect(x: 300, y: 380, width: 260, height: 260))
    cloud.addEllipse(in: CGRect(x: 430, y: 420, width: 330, height: 330))
    ctx.saveGState()
    ctx.addPath(cloud); ctx.clip()
    let blue = CGGradient(colorsSpace: nil, colors: [cloudLight, cloudDeep] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(blue, start: CGPoint(x: 512, y: 750), end: CGPoint(x: 512, y: 300), options: [])
    ctx.restoreGState()

    // Fan: three curved white blades around a hub, centred low in the cloud.
    let hub = CGPoint(x: 512, y: 470)
    ctx.setFillColor(color(0xffffff, 0.96))
    for i in 0..<3 {
        ctx.saveGState()
        ctx.translateBy(x: hub.x, y: hub.y)
        ctx.rotate(by: CGFloat(i) * 2 * .pi / 3 + 0.35)
        let blade = CGMutablePath()
        blade.move(to: CGPoint(x: 0, y: 18))
        blade.addCurve(to: CGPoint(x: 18, y: 150), control1: CGPoint(x: -70, y: 60), control2: CGPoint(x: -60, y: 150))
        blade.addCurve(to: CGPoint(x: 22, y: 18), control1: CGPoint(x: 80, y: 150), control2: CGPoint(x: 60, y: 60))
        blade.closeSubpath()
        ctx.addPath(blade); ctx.fillPath()
        ctx.restoreGState()
    }

    // Turbo hub: amber disc with a small dark bolt.
    ctx.setFillColor(amber)
    ctx.fillEllipse(in: CGRect(x: hub.x - 46, y: hub.y - 46, width: 92, height: 92))
    let bolt = CGMutablePath()
    bolt.move(to: CGPoint(x: hub.x + 8, y: hub.y + 34))
    bolt.addLine(to: CGPoint(x: hub.x - 20, y: hub.y - 4))
    bolt.addLine(to: CGPoint(x: hub.x - 1, y: hub.y - 4))
    bolt.addLine(to: CGPoint(x: hub.x - 9, y: hub.y - 34))
    bolt.addLine(to: CGPoint(x: hub.x + 20, y: hub.y + 6))
    bolt.addLine(to: CGPoint(x: hub.x + 1, y: hub.y + 6))
    bolt.closeSubpath()
    ctx.addPath(bolt); ctx.setFillColor(bgBottom); ctx.fillPath()

    // PRO badge: amber pill, bottom right.
    let pill = CGRect(x: 560, y: 150, width: 300, height: 120)
    ctx.addPath(CGPath(roundedRect: pill, cornerWidth: 60, cornerHeight: 60, transform: nil))
    ctx.setFillColor(amber); ctx.fillPath()
    let text = NSAttributedString(string: "PRO", attributes: [
        .font: NSFont.systemFont(ofSize: 84, weight: .black),
        .foregroundColor: NSColor(cgColor: bgBottom)!, .kern: 4])
    let ts = text.size()
    text.draw(at: CGPoint(x: pill.midX - ts.width / 2, y: pill.midY - ts.height / 2 + 2))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// Write an .iconset and convert it with iconutil.
let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let png = drawIcon(size: base * scale).representation(using: .png, properties: [:])!
        try png.write(to: iconset.appendingPathComponent(name))
    }
}
try drawIcon(size: 1024).representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: (out as NSString).deletingPathExtension + ".png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out]
try p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "wrote \(out)" : "iconutil failed")
