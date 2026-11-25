import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func drawAppIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let s = size / 1024.0
    ctx.saveGState()

    // 1. macOS Rounded Squircle Mask (824x824 centered in 1024x1024)
    let squircleRect = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let cornerRadius = 185 * s
    let squirclePath = CGPath(roundedRect: squircleRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // Drop shadow behind squircle
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -20 * s), blur: 40 * s, color: NSColor(calibratedWhite: 0.0, alpha: 0.45).cgColor)
    ctx.setFillColor(NSColor(calibratedRed: 0.06, green: 0.08, blue: 0.14, alpha: 1.0).cgColor)
    ctx.addPath(squirclePath)
    ctx.fillPath()
    ctx.restoreGState()

    // Clip to Squircle
    ctx.addPath(squirclePath)
    ctx.clip()

    // 2. Deep Midnight Obsidian to Liquid Indigo Background Gradient
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        NSColor(calibratedRed: 0.13, green: 0.17, blue: 0.28, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.06, green: 0.08, blue: 0.15, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.03, green: 0.04, blue: 0.08, alpha: 1.0).cgColor
    ] as CFArray
    let bgLocations: [CGFloat] = [0.0, 0.55, 1.0]
    if let bgGrad = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: bgLocations) {
        ctx.drawLinearGradient(
            bgGrad,
            start: CGPoint(x: 512 * s, y: 924 * s),
            end: CGPoint(x: 512 * s, y: 100 * s),
            options: []
        )
    }

    // 3. Ambient Aurora Glow Orbs inside Squircle
    ctx.saveGState()
    let cyanGlowColors = [
        NSColor(calibratedRed: 0.15, green: 0.72, blue: 1.0, alpha: 0.38).cgColor,
        NSColor(calibratedRed: 0.15, green: 0.72, blue: 1.0, alpha: 0.0).cgColor
    ] as CFArray
    if let cyanGrad = CGGradient(colorsSpace: colorSpace, colors: cyanGlowColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(
            cyanGrad,
            startCenter: CGPoint(x: 310 * s, y: 720 * s), startRadius: 0,
            endCenter: CGPoint(x: 310 * s, y: 720 * s), endRadius: 420 * s,
            options: [.drawsBeforeStartLocation]
        )
    }

    let warmGlowColors = [
        NSColor(calibratedRed: 0.58, green: 0.32, blue: 0.96, alpha: 0.30).cgColor,
        NSColor(calibratedRed: 0.58, green: 0.32, blue: 0.96, alpha: 0.0).cgColor
    ] as CFArray
    if let warmGrad = CGGradient(colorsSpace: colorSpace, colors: warmGlowColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(
            warmGrad,
            startCenter: CGPoint(x: 720 * s, y: 310 * s), startRadius: 0,
            endCenter: CGPoint(x: 720 * s, y: 310 * s), endRadius: 400 * s,
            options: [.drawsBeforeStartLocation]
        )
    }
    ctx.restoreGState()

    // 4. MateView GT Metallic Stand & SoundBar Base
    let neckRect = CGRect(x: 484 * s, y: 248 * s, width: 56 * s, height: 110 * s)
    let neckPath = CGPath(roundedRect: neckRect, cornerWidth: 10 * s, cornerHeight: 10 * s, transform: nil)
    let metalColors = [
        NSColor(calibratedRed: 0.72, green: 0.78, blue: 0.88, alpha: 0.9).cgColor,
        NSColor(calibratedRed: 0.35, green: 0.40, blue: 0.52, alpha: 0.9).cgColor
    ] as CFArray
    ctx.saveGState()
    ctx.addPath(neckPath)
    ctx.clip()
    if let metalGrad = CGGradient(colorsSpace: colorSpace, colors: metalColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(metalGrad, start: CGPoint(x: 484 * s, y: 358 * s), end: CGPoint(x: 540 * s, y: 248 * s), options: [])
    }
    ctx.restoreGState()

    let baseRect = CGRect(x: 342 * s, y: 214 * s, width: 340 * s, height: 42 * s)
    let basePath = CGPath(roundedRect: baseRect, cornerWidth: 21 * s, cornerHeight: 21 * s, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8 * s), blur: 18 * s, color: NSColor(calibratedWhite: 0, alpha: 0.5).cgColor)
    ctx.addPath(basePath)
    ctx.clip()
    let baseColors = [
        NSColor(calibratedRed: 0.25, green: 0.30, blue: 0.42, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.14, green: 0.17, blue: 0.25, alpha: 1.0).cgColor
    ] as CFArray
    if let baseGrad = CGGradient(colorsSpace: colorSpace, colors: baseColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(baseGrad, start: CGPoint(x: 512 * s, y: 256 * s), end: CGPoint(x: 512 * s, y: 214 * s), options: [])
    }
    ctx.restoreGState()

    let ledRect = CGRect(x: 422 * s, y: 231 * s, width: 180 * s, height: 8 * s)
    let ledPath = CGPath(roundedRect: ledRect, cornerWidth: 4 * s, cornerHeight: 4 * s, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 12 * s, color: NSColor(calibratedRed: 0.2, green: 0.85, blue: 1.0, alpha: 0.95).cgColor)
    ctx.setFillColor(NSColor(calibratedRed: 0.45, green: 0.95, blue: 1.0, alpha: 1.0).cgColor)
    ctx.addPath(ledPath)
    ctx.fillPath()
    ctx.restoreGState()

    // 5. MateView GT Ultra-Thin Bezel Display Frame
    let monitorOuterRect = CGRect(x: 172 * s, y: 340 * s, width: 680 * s, height: 446 * s)
    let monitorOuterPath = CGPath(roundedRect: monitorOuterRect, cornerWidth: 38 * s, cornerHeight: 38 * s, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -16 * s), blur: 32 * s, color: NSColor(calibratedWhite: 0, alpha: 0.55).cgColor)
    ctx.setFillColor(NSColor(calibratedRed: 0.12, green: 0.15, blue: 0.23, alpha: 0.95).cgColor)
    ctx.addPath(monitorOuterPath)
    ctx.fillPath()
    ctx.restoreGState()

    let screenRect = CGRect(x: 190 * s, y: 358 * s, width: 644 * s, height: 410 * s)
    let screenPath = CGPath(roundedRect: screenRect, cornerWidth: 26 * s, cornerHeight: 26 * s, transform: nil)
    ctx.saveGState()
    ctx.addPath(screenPath)
    ctx.clip()

    let screenColors = [
        NSColor(calibratedRed: 0.08, green: 0.22, blue: 0.45, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.16, green: 0.12, blue: 0.35, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.05, green: 0.08, blue: 0.18, alpha: 1.0).cgColor
    ] as CFArray
    if let scrGrad = CGGradient(colorsSpace: colorSpace, colors: screenColors, locations: [0.0, 0.5, 1.0]) {
        ctx.drawLinearGradient(scrGrad, start: CGPoint(x: 190 * s, y: 768 * s), end: CGPoint(x: 834 * s, y: 358 * s), options: [])
    }

    let waveColors = [
        NSColor(calibratedRed: 0.20, green: 0.80, blue: 1.0, alpha: 0.45).cgColor,
        NSColor(calibratedRed: 0.98, green: 0.55, blue: 0.25, alpha: 0.28).cgColor,
        NSColor(calibratedRed: 0.10, green: 0.15, blue: 0.30, alpha: 0.0).cgColor
    ] as CFArray
    if let waveGrad = CGGradient(colorsSpace: colorSpace, colors: waveColors, locations: [0.0, 0.55, 1.0]) {
        ctx.drawRadialGradient(
            waveGrad,
            startCenter: CGPoint(x: 380 * s, y: 620 * s), startRadius: 0,
            endCenter: CGPoint(x: 512 * s, y: 560 * s), endRadius: 360 * s,
            options: [.drawsBeforeStartLocation]
        )
    }

    // 6. Control Center Sliders Floating Inside the Monitor Screen
    let pill1Back = CGRect(x: 254 * s, y: 590 * s, width: 516 * s, height: 84 * s)
    let pill1BackPath = CGPath(roundedRect: pill1Back, cornerWidth: 42 * s, cornerHeight: 42 * s, transform: nil)
    ctx.setFillColor(NSColor(calibratedWhite: 0.0, alpha: 0.36).cgColor)
    ctx.addPath(pill1BackPath)
    ctx.fillPath()

    let pill1Fill = CGRect(x: 254 * s, y: 590 * s, width: 400 * s, height: 84 * s)
    let pill1FillPath = CGPath(roundedRect: pill1Fill, cornerWidth: 42 * s, cornerHeight: 42 * s, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -4 * s), blur: 14 * s, color: NSColor(calibratedRed: 0.3, green: 0.85, blue: 1.0, alpha: 0.45).cgColor)
    ctx.setFillColor(NSColor(calibratedWhite: 1.0, alpha: 0.95).cgColor)
    ctx.addPath(pill1FillPath)
    ctx.fillPath()
    ctx.restoreGState()

    let sunCenter = CGPoint(x: 300 * s, y: 632 * s)
    ctx.setFillColor(NSColor(calibratedRed: 0.10, green: 0.14, blue: 0.22, alpha: 0.88).cgColor)
    ctx.fillEllipse(in: CGRect(x: sunCenter.x - 13 * s, y: sunCenter.y - 13 * s, width: 26 * s, height: 26 * s))
    ctx.setStrokeColor(NSColor(calibratedRed: 0.10, green: 0.14, blue: 0.22, alpha: 0.88).cgColor)
    ctx.setLineWidth(4.5 * s)
    ctx.setLineCap(.round)
    for ray in 0..<8 {
        let angle = CGFloat(ray) * (.pi / 4.0)
        let r1 = 19 * s
        let r2 = 25 * s
        ctx.move(to: CGPoint(x: sunCenter.x + cos(angle) * r1, y: sunCenter.y + sin(angle) * r1))
        ctx.addLine(to: CGPoint(x: sunCenter.x + cos(angle) * r2, y: sunCenter.y + sin(angle) * r2))
    }
    ctx.strokePath()

    let pill2Back = CGRect(x: 254 * s, y: 462 * s, width: 516 * s, height: 84 * s)
    let pill2BackPath = CGPath(roundedRect: pill2Back, cornerWidth: 42 * s, cornerHeight: 42 * s, transform: nil)
    ctx.setFillColor(NSColor(calibratedWhite: 0.0, alpha: 0.36).cgColor)
    ctx.addPath(pill2BackPath)
    ctx.fillPath()

    let pill2Fill = CGRect(x: 254 * s, y: 462 * s, width: 300 * s, height: 84 * s)
    let pill2FillPath = CGPath(roundedRect: pill2Fill, cornerWidth: 42 * s, cornerHeight: 42 * s, transform: nil)
    ctx.saveGState()
    ctx.addPath(pill2FillPath)
    ctx.clip()
    let pill2Colors = [
        NSColor(calibratedRed: 0.18, green: 0.65, blue: 1.0, alpha: 0.96).cgColor,
        NSColor(calibratedRed: 0.38, green: 0.86, blue: 1.0, alpha: 0.96).cgColor
    ] as CFArray
    if let p2Grad = CGGradient(colorsSpace: colorSpace, colors: pill2Colors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(p2Grad, start: CGPoint(x: 254 * s, y: 504 * s), end: CGPoint(x: 554 * s, y: 504 * s), options: [])
    }
    ctx.restoreGState()

    let spkCenter = CGPoint(x: 296 * s, y: 504 * s)
    ctx.setFillColor(NSColor.white.cgColor)
    let spkBody = CGMutablePath()
    spkBody.move(to: CGPoint(x: spkCenter.x - 16 * s, y: spkCenter.y - 7 * s))
    spkBody.addLine(to: CGPoint(x: spkCenter.x - 7 * s, y: spkCenter.y - 7 * s))
    spkBody.addLine(to: CGPoint(x: spkCenter.x + 4 * s, y: spkCenter.y - 17 * s))
    spkBody.addLine(to: CGPoint(x: spkCenter.x + 4 * s, y: spkCenter.y + 17 * s))
    spkBody.addLine(to: CGPoint(x: spkCenter.x - 7 * s, y: spkCenter.y + 7 * s))
    spkBody.addLine(to: CGPoint(x: spkCenter.x - 16 * s, y: spkCenter.y + 7 * s))
    spkBody.closeSubpath()
    ctx.addPath(spkBody)
    ctx.fillPath()

    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineWidth(4.5 * s)
    ctx.addArc(center: CGPoint(x: spkCenter.x + 4 * s, y: spkCenter.y), radius: 11 * s, startAngle: -.pi / 3, endAngle: .pi / 3, clockwise: false)
    ctx.strokePath()
    ctx.addArc(center: CGPoint(x: spkCenter.x + 4 * s, y: spkCenter.y), radius: 19 * s, startAngle: -.pi / 3, endAngle: .pi / 3, clockwise: false)
    ctx.strokePath()

    let glossPath = CGMutablePath()
    glossPath.move(to: CGPoint(x: 190 * s, y: 768 * s))
    glossPath.addLine(to: CGPoint(x: 560 * s, y: 768 * s))
    glossPath.addLine(to: CGPoint(x: 340 * s, y: 358 * s))
    glossPath.addLine(to: CGPoint(x: 190 * s, y: 358 * s))
    glossPath.closeSubpath()
    ctx.saveGState()
    ctx.addPath(glossPath)
    ctx.clip()
    let glossColors = [
        NSColor(calibratedWhite: 1.0, alpha: 0.14).cgColor,
        NSColor(calibratedWhite: 1.0, alpha: 0.01).cgColor
    ] as CFArray
    if let glossGrad = CGGradient(colorsSpace: colorSpace, colors: glossColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(glossGrad, start: CGPoint(x: 190 * s, y: 768 * s), end: CGPoint(x: 480 * s, y: 358 * s), options: [])
    }
    ctx.restoreGState()

    ctx.restoreGState()

    ctx.setStrokeColor(NSColor(calibratedWhite: 1.0, alpha: 0.35).cgColor)
    ctx.setLineWidth(2.5 * s)
    ctx.addPath(monitorOuterPath)
    ctx.strokePath()

    ctx.setStrokeColor(NSColor(calibratedWhite: 1.0, alpha: 0.24).cgColor)
    ctx.setLineWidth(3.0 * s)
    ctx.addPath(squirclePath)
    ctx.strokePath()

    ctx.restoreGState()
    image.unlockFocus()
    return image
}

func drawMenuBarTemplateIcon() -> NSImage {
    let size = NSSize(width: 18, height: 18)
    let image = NSImage(size: size)
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    ctx.setStrokeColor(NSColor.black.cgColor)
    ctx.setFillColor(NSColor.black.cgColor)

    let screenRect = CGRect(x: 1.75, y: 5.25, width: 14.5, height: 10.25)
    let screenPath = CGPath(roundedRect: screenRect, cornerWidth: 2.2, cornerHeight: 2.2, transform: nil)
    ctx.setLineWidth(1.4)
    ctx.addPath(screenPath)
    ctx.strokePath()

    let slider1 = CGPath(roundedRect: CGRect(x: 4.0, y: 11.2, width: 10.0, height: 1.5), cornerWidth: 0.75, cornerHeight: 0.75, transform: nil)
    ctx.addPath(slider1)
    ctx.fillPath()
    ctx.fillEllipse(in: CGRect(x: 9.8, y: 10.35, width: 3.2, height: 3.2))

    let slider2 = CGPath(roundedRect: CGRect(x: 4.0, y: 7.7, width: 10.0, height: 1.5), cornerWidth: 0.75, cornerHeight: 0.75, transform: nil)
    ctx.addPath(slider2)
    ctx.fillPath()
    ctx.fillEllipse(in: CGRect(x: 6.2, y: 6.85, width: 3.2, height: 3.2))

    ctx.fill(CGRect(x: 8.15, y: 3.1, width: 1.7, height: 2.1))
    let basePill = CGPath(roundedRect: CGRect(x: 4.8, y: 1.7, width: 8.4, height: 1.55), cornerWidth: 0.75, cornerHeight: 0.75, transform: nil)
    ctx.addPath(basePill)
    ctx.fillPath()

    image.unlockFocus()
    image.isTemplate = true
    return image
}

func savePNG(_ image: NSImage, to url: URL, pointSize: Int, pixelSize: Int) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return }

    rep.size = NSSize(width: pointSize, height: pointSize)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pointSize, height: pointSize), from: .zero, operation: .copy, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()

    if let data = rep.representation(using: .png, properties: [:]) {
        try data.write(to: url, options: .atomic)
    }
}

func writeAppleICNS(master: NSImage, to url: URL) throws {
    let chunks: [(String, Int)] = [
        ("icp4", 16),
        ("icp5", 32),
        ("icp6", 64),
        ("ic07", 128),
        ("ic08", 256),
        ("ic09", 512),
        ("ic10", 1024)
    ]
    var body = Data()
    for (ostype, px) in chunks {
        let tmpURL = URL(fileURLWithPath: "/tmp/icns_chunk_\(px).png")
        try savePNG(master, to: tmpURL, pointSize: px, pixelSize: px)
        let pngData = try Data(contentsOf: tmpURL)
        try? FileManager.default.removeItem(at: tmpURL)

        guard let typeBytes = ostype.data(using: .ascii), typeBytes.count == 4 else { continue }
        var chunkLen = UInt32(8 + pngData.count).bigEndian
        body.append(typeBytes)
        body.append(Data(bytes: &chunkLen, count: 4))
        body.append(pngData)
    }

    var fileData = Data()
    fileData.append("icns".data(using: .ascii)!)
    var totalLen = UInt32(8 + body.count).bigEndian
    fileData.append(Data(bytes: &totalLen, count: 4))
    fileData.append(body)
    try fileData.write(to: url, options: .atomic)
}

let targetResDirPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : (FileManager.default.currentDirectoryPath + "/dist/MateView GT Control.app/Contents/Resources")

let resDir = URL(fileURLWithPath: targetResDirPath, isDirectory: true)
try FileManager.default.createDirectory(at: resDir, withIntermediateDirectories: true)

let masterIcon = drawAppIcon(size: 1024)
let menuBarIcon = drawMenuBarTemplateIcon()

try savePNG(menuBarIcon, to: resDir.appendingPathComponent("MenuBarIcon.png"), pointSize: 18, pixelSize: 36)
let icnsURL = resDir.appendingPathComponent("AppIcon.icns")
try writeAppleICNS(master: masterIcon, to: icnsURL)
try savePNG(masterIcon, to: resDir.appendingPathComponent("AppIcon.png"), pointSize: 512, pixelSize: 512)

// Also save repo preview logo in Resources/logo.png if Resources folder exists
let repoLogoDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/Resources", isDirectory: true)
try? FileManager.default.createDirectory(at: repoLogoDir, withIntermediateDirectories: true)
try? savePNG(masterIcon, to: repoLogoDir.appendingPathComponent("logo.png"), pointSize: 512, pixelSize: 512)

print("Generated AppIcon.icns (\(try Data(contentsOf: icnsURL).count) bytes) and MenuBarIcon.png in \(resDir.path)")
