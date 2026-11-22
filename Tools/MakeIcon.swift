import AppKit
import CoreGraphics

/// Draws the app icon on a 1024pt design grid and emits an .icns.
/// Run via `./build.sh --icon`; the result is checked in at Resources/AppIcon.icns.
@main
struct MakeIcon {

    // macOS icon grid: an 824pt rounded square centred on a 1024pt canvas.
    static let canvas: CGFloat = 1024
    static let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    static let plateRadius: CGFloat = 184

    /// 9×9 module grid. E = finder eye (drawn separately), # = data module.
    static let pattern = [
        "EEE.#.EEE",
        "EEE##.EEE",
        "EEE.#.EEE",
        ".#.##.#.#",
        "#.#..##.#",
        ".##.#..#.",
        "EEE#.##.#",
        "EEE.##..#",
        "EEE#.#.##",
    ]

    static func main() throws {
        let out = CommandLine.arguments.count > 1
            ? CommandLine.arguments[1] : "Resources/AppIcon.icns"
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString)")
        let iconset = work.appendingPathComponent("AppIcon.iconset")
        try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

        let variants: [(Int, String)] = [
            (16, "icon_16x16.png"),   (32, "icon_16x16@2x.png"),
            (32, "icon_32x32.png"),   (64, "icon_32x32@2x.png"),
            (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
            (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
            (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
        ]
        for (px, name) in variants {
            try render(px).write(to: iconset.appendingPathComponent(name))
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        proc.arguments = ["-c", "icns", iconset.path, "-o", out]
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            FileHandle.standardError.write(Data("iconutil failed\n".utf8))
            exit(1)
        }
        try? fm.removeItem(at: work)
        print("wrote \(out)")

        // Contact sheet for eyeballing the small sizes.
        if CommandLine.arguments.count > 2 {
            try contactSheet().write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
        }
    }

    // MARK: - Drawing

    static func render(_ px: Int) throws -> Data {
        guard let ctx = CGContext(
            data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw Err.context }
        ctx.setAllowsAntialiasing(true)
        ctx.scaleBy(x: CGFloat(px) / canvas, y: CGFloat(px) / canvas)
        draw(ctx)
        guard let image = ctx.makeImage() else { throw Err.context }
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: px, height: px)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw Err.context }
        return data
    }

    static func draw(_ ctx: CGContext) {
        let shape = CGPath(roundedRect: plate, cornerWidth: plateRadius,
                           cornerHeight: plateRadius, transform: nil)

        // Contact shadow under the plate.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 32,
                      color: CGColor(gray: 0, alpha: 0.30))
        ctx.addPath(shape)
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        ctx.fillPath()
        ctx.restoreGState()

        // Indigo gradient, top-left to bottom-right.
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        let space = CGColorSpaceCreateDeviceRGB()
        let gradient = CGGradient(colorsSpace: space, colors: [
            CGColor(red: 0.42, green: 0.58, blue: 1.00, alpha: 1),   // #6B94FF
            CGColor(red: 0.29, green: 0.29, blue: 0.90, alpha: 1),   // #4A4AE6
            CGColor(red: 0.19, green: 0.16, blue: 0.66, alpha: 1),   // #3029A8
        ] as CFArray, locations: [0, 0.55, 1])!
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: plate.minX, y: plate.maxY),
                               end: CGPoint(x: plate.maxX, y: plate.minY),
                               options: [])

        // Soft sheen across the top third.
        let sheen = CGGradient(colorsSpace: space, colors: [
            CGColor(gray: 1, alpha: 0.20), CGColor(gray: 1, alpha: 0),
        ] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(sheen,
                               start: CGPoint(x: 0, y: plate.maxY),
                               end: CGPoint(x: 0, y: plate.maxY - plate.height * 0.45),
                               options: [])
        ctx.restoreGState()

        // Hairline rim for definition on light backgrounds.
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.16))
        ctx.setLineWidth(3)
        ctx.strokePath()
        ctx.restoreGState()

        // Glyph, drawn top-left-origin like the rest of the codebase.
        ctx.saveGState()
        ctx.translateBy(x: 0, y: canvas)
        ctx.scaleBy(x: 1, y: -1)
        drawGlyph(ctx)
        ctx.restoreGState()
    }

    static func drawGlyph(_ ctx: CGContext) {
        let box: CGFloat = 512
        let origin = (canvas - box) / 2
        let m = box / 9
        let white = CGColor(gray: 1, alpha: 1)
        ctx.setFillColor(white)
        ctx.setStrokeColor(white)

        func at(_ gx: Int, _ gy: Int) -> CGPoint {
            CGPoint(x: origin + CGFloat(gx) * m, y: origin + CGFloat(gy) * m)
        }

        // Finder eyes: rounded ring plus a centre dot.
        for (gx, gy) in [(0, 0), (6, 0), (0, 6)] {
            let p = at(gx, gy)
            let frame = CGRect(x: p.x, y: p.y, width: m * 3, height: m * 3)
            let lw = m * 0.62
            ctx.setLineWidth(lw)
            let ring = frame.insetBy(dx: lw / 2, dy: lw / 2)
            ctx.addPath(CGPath(roundedRect: ring, cornerWidth: m * 0.78,
                               cornerHeight: m * 0.78, transform: nil))
            ctx.strokePath()

            let d = m * 1.22
            let dot = CGRect(x: frame.midX - d / 2, y: frame.midY - d / 2, width: d, height: d)
            ctx.addPath(CGPath(roundedRect: dot, cornerWidth: d * 0.30,
                               cornerHeight: d * 0.30, transform: nil))
            ctx.fillPath()
        }

        // Data modules.
        let d = m * 0.78
        for (gy, row) in pattern.enumerated() {
            for (gx, ch) in row.enumerated() where ch == "#" {
                let p = at(gx, gy)
                let r = CGRect(x: p.x + (m - d) / 2, y: p.y + (m - d) / 2, width: d, height: d)
                ctx.addPath(CGPath(roundedRect: r, cornerWidth: d * 0.30,
                                   cornerHeight: d * 0.30, transform: nil))
                ctx.fillPath()
            }
        }
    }

    /// 512 / 128 / 64 / 32 / 16 side by side on a neutral ground.
    static func contactSheet() throws -> Data {
        let sizes = [512, 128, 64, 32, 16]
        let w = 512 + 128 + 64 + 32 + 16 + 6 * 18, h = 560
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw Err.context }
        ctx.setFillColor(CGColor(gray: 0.90, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        var x: CGFloat = 20
        for size in sizes {
            let data = try render(size)
            let image = NSBitmapImageRep(data: data)!.cgImage!
            ctx.draw(image, in: CGRect(x: x, y: CGFloat(h - 20 - size),
                                       width: CGFloat(size), height: CGFloat(size)))
            x += CGFloat(size) + 18
        }
        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        return rep.representation(using: .png, properties: [:])!
    }

    enum Err: Error { case context }
}
