// 生成应用图标和安装器背景图。用法：swift scripts/make-assets.swift
// 输出：Resources/AppIcon.icns、Installer/Resources/background.png

import AppKit

func render(pixels: Int, points: CGFloat, _ draw: (CGFloat) -> Void) -> NSBitmapImageRep {
    render(pixelsWide: pixels, pixelsHigh: pixels, pointSize: NSSize(width: points, height: points)) { draw(points) }
}

func render(pixelsWide: Int, pixelsHigh: Int, pointSize: NSSize, _ draw: () -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = pointSize
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, to path: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(deviceRed: r, green: g, blue: b, alpha: a)
}

// 闪电：在 unit × unit 的方框内，原点为左下角。
func boltPath(in rect: NSRect) -> NSBezierPath {
    let points: [(CGFloat, CGFloat)] = [
        (0.58, 1.00), (0.12, 0.44), (0.44, 0.44), (0.36, 0.00), (0.88, 0.60), (0.54, 0.60),
    ]
    let path = NSBezierPath()
    for (index, point) in points.enumerated() {
        let p = NSPoint(x: rect.minX + point.0 * rect.width, y: rect.minY + point.1 * rect.height)
        index == 0 ? path.move(to: p) : path.line(to: p)
    }
    path.close()
    path.lineJoinStyle = .round
    return path
}

// 机身：一块圆角扁盒，Mac mini 的正面。
func slabPath(in rect: NSRect) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: rect.height * 0.27, yRadius: rect.height * 0.27)
}

func drawIcon(_ s: CGFloat) {
    let u = s / 1024
    let plate = NSRect(x: 100 * u, y: 100 * u, width: 824 * u, height: 824 * u)
    let platePath = NSBezierPath(roundedRect: plate, xRadius: 185 * u, yRadius: 185 * u)

    NSGraphicsContext.saveGraphicsState()
    let plateShadow = NSShadow()
    plateShadow.shadowColor = rgb(0, 0, 0, 0.35)
    plateShadow.shadowBlurRadius = 24 * u
    plateShadow.shadowOffset = NSSize(width: 0, height: -12 * u)
    plateShadow.set()
    rgb(0.07, 0.09, 0.17).setFill()
    platePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [rgb(0.05, 0.07, 0.15), rgb(0.13, 0.19, 0.38), rgb(0.24, 0.33, 0.62)])!
        .draw(in: platePath, angle: 90)

    // 顶部一抹高光，让底板不那么平。
    NSGraphicsContext.saveGraphicsState()
    platePath.addClip()
    NSGradient(colors: [rgb(1, 1, 1, 0), rgb(1, 1, 1, 0.14)])!
        .draw(in: NSRect(x: plate.minX, y: plate.midY, width: plate.width, height: plate.height / 2), angle: 90)
    NSGraphicsContext.restoreGraphicsState()

    // 闪电
    let bolt = boltPath(in: NSRect(x: 392 * u, y: 520 * u, width: 240 * u, height: 290 * u))
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = rgb(1.0, 0.80, 0.25, 0.55)
    glow.shadowBlurRadius = 40 * u
    glow.set()
    rgb(1.0, 0.82, 0.30).setFill()
    bolt.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [rgb(1.0, 0.70, 0.18), rgb(1.0, 0.90, 0.45)])!.draw(in: bolt, angle: 90)

    // 机身
    let slabRect = NSRect(x: 222 * u, y: 258 * u, width: 580 * u, height: 190 * u)
    let slab = slabPath(in: slabRect)
    NSGraphicsContext.saveGraphicsState()
    let slabShadow = NSShadow()
    slabShadow.shadowColor = rgb(0, 0, 0, 0.45)
    slabShadow.shadowBlurRadius = 30 * u
    slabShadow.shadowOffset = NSSize(width: 0, height: -16 * u)
    slabShadow.set()
    rgb(0.85, 0.86, 0.89).setFill()
    slab.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [rgb(0.74, 0.76, 0.80), rgb(0.90, 0.91, 0.93), rgb(0.98, 0.98, 0.99)])!
        .draw(in: slab, angle: 90)

    // 电源指示灯
    let led = NSRect(x: slabRect.maxX - 78 * u, y: slabRect.midY - 11 * u, width: 22 * u, height: 22 * u)
    NSGraphicsContext.saveGraphicsState()
    let ledGlow = NSShadow()
    ledGlow.shadowColor = rgb(0.25, 0.95, 0.55, 0.9)
    ledGlow.shadowBlurRadius = 14 * u
    ledGlow.set()
    rgb(0.30, 0.88, 0.52).setFill()
    NSBezierPath(ovalIn: led).fill()
    NSGraphicsContext.restoreGraphicsState()
}

// 安装器背景：左侧步骤列表下方放一个应用图标，其余透明。
func drawBackground() {
    let transform = NSAffineTransform()
    transform.translateX(by: 30, yBy: 26)
    transform.concat()
    drawIcon(120)
}

let fm = FileManager.default
let iconset = fm.temporaryDirectory.appendingPathComponent("AppIcon-\(ProcessInfo.processInfo.processIdentifier).iconset")
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let rep = render(pixels: points * scale, points: CGFloat(points), drawIcon)
        let suffix = scale == 2 ? "@2x" : ""
        write(rep, to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png").path)
    }
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! iconutil.run()
iconutil.waitUntilExit()
try? fm.removeItem(at: iconset)

let paneSize = NSSize(width: 620, height: 418)
write(render(pixelsWide: 1240, pixelsHigh: 836, pointSize: paneSize, drawBackground),
      to: "Installer/Resources/background.png")

// 预览用的大图，不入库。
if CommandLine.arguments.contains("--preview") {
    try? fm.createDirectory(atPath: "build", withIntermediateDirectories: true)
    write(render(pixels: 512, points: 512, drawIcon), to: "build/icon-preview.png")
}
print("assets written")
