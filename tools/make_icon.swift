import AppKit
import CoreGraphics

// 构建期图标生成器：纯代码绘制 AppIcon.iconset（CI 上无设计资源可用）。
// 用法: make_icon <输出目录>
// 画面：深灰圆角底 + 三条推子轨（琥珀色推子帽）+ X32 字标。

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    let full = CGRect(x: 0, y: 0, width: s, height: s)
    let radius = s * 0.2237
    let bg = NSBezierPath(roundedRect: full, xRadius: radius, yRadius: radius)
    NSColor.clear.setFill()
    bg.fill()

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.18, green: 0.18, blue: 0.21, alpha: 1),
        NSColor(calibratedRed: 0.07, green: 0.07, blue: 0.09, alpha: 1)
    ])!
    gradient.draw(in: bg, angle: -90)

    // 内描边
    NSColor(calibratedWhite: 1.0, alpha: 0.10).setStroke()
    bg.lineWidth = max(s * 0.006, 0.5)
    bg.stroke()

    // 三条推子轨
    let trackW = s * 0.072
    let trackH = s * 0.44
    let trackY = s * 0.20
    let amber = NSColor(calibratedRed: 1.0, green: 0.70, blue: 0.22, alpha: 1)
    let caps: [CGFloat] = [0.66, 0.24, 0.86]
    let xs: [CGFloat] = [0.245, 0.5, 0.755]
    for i in 0..<3 {
        let x = s * xs[i]
        let track = NSBezierPath(roundedRect: NSRect(x: x - trackW / 2, y: trackY, width: trackW, height: trackH),
                                 xRadius: trackW / 2, yRadius: trackW / 2)
        NSColor(calibratedWhite: 0.04, alpha: 1).setFill()
        track.fill()
        // 推子帽
        let capH = s * 0.075
        let capY = trackY + trackH * caps[i] - capH / 2
        let cap = NSBezierPath(roundedRect: NSRect(x: x - trackW * 0.85, y: capY, width: trackW * 1.7, height: capH),
                               xRadius: capH * 0.32, yRadius: capH * 0.32)
        amber.setFill()
        cap.fill()
        NSColor(calibratedWhite: 0.0, alpha: 0.35).setStroke()
        cap.lineWidth = max(s * 0.004, 0.4)
        cap.stroke()
    }

    // 刻度线
    NSColor(calibratedWhite: 1.0, alpha: 0.14).setStroke()
    let ticks = NSBezierPath()
    ticks.lineWidth = max(s * 0.004, 0.4)
    for k in 0...5 {
        let ty = trackY + trackH * CGFloat(k) / 5.0
        ticks.move(to: NSPoint(x: s * 0.13, y: ty))
        ticks.line(to: NSPoint(x: s * 0.87, y: ty))
    }
    ticks.stroke()

    // X32 字标
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.boldSystemFont(ofSize: s * 0.19),
        .foregroundColor: NSColor(calibratedRed: 1.0, green: 0.86, blue: 0.63, alpha: 1),
        .paragraphStyle: para
    ]
    let text = "X32" as NSString
    text.draw(in: NSRect(x: 0, y: s * 0.035, width: s, height: s * 0.22), withAttributes: attrs)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let entries: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]
for (px, name) in entries {
    let data = render(size: px)
    try! data.write(to: URL(fileURLWithPath: outDir + "/" + name))
}
print("iconset 已生成: \(outDir) (\(entries.count) 个 PNG)")
