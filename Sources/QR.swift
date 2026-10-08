import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import UniformTypeIdentifiers

// MARK: - Options

enum CorrectionLevel: String, CaseIterable, Identifiable {
    case low = "L", medium = "M", quartile = "Q", high = "H"
    var id: String { rawValue }
    /// ISO/IEC 18004 recovery capacity for each level.
    var recovery: Int {
        switch self {
        case .low: return 7
        case .medium: return 15
        case .quartile: return 25
        case .high: return 30
        }
    }
    var label: String { "Level \(rawValue) — \(recovery)%" }
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case png = "PNG", pdf = "PDF", svg = "SVG"
    var id: String { rawValue }
    var ext: String { rawValue.lowercased() }
    var isVector: Bool { self != .png }
    var contentType: UTType {
        switch self {
        case .png: return .png
        case .pdf: return .pdf
        case .svg: return .svg
        }
    }
}

// MARK: - Module grid

/// A QR symbol as a boolean grid, row-major with a top-left origin.
/// This is the symbol *only* — the quiet zone is added at render time.
struct QRGrid {
    let size: Int
    let dark: [Bool]

    func isDark(_ x: Int, _ y: Int) -> Bool { dark[y * size + x] }

    /// Symbol version 1…40. Every version is 17 + 4v modules square.
    var version: Int? {
        guard size >= 21, size <= 177, (size - 17) % 4 == 0 else { return nil }
        return (size - 17) / 4
    }

    var darkCount: Int { dark.lazy.filter { $0 }.count }
}

/// Resolved output dimensions for a raster or vector render.
struct QRGeometry {
    let modules: Int      // symbol side, in modules
    let quiet: Int        // quiet zone per edge, in modules
    let side: Int         // modules + quiet * 2
    let scale: Int        // pixels (or points) per module
    let pixels: Int       // side * scale
}

// MARK: - Rendering

enum QR {
    /// ISO/IEC 18004 specifies a 4-module quiet zone as the minimum.
    static let defaultQuietZone = 4
    static let quietZoneRange = 0...16

    private static let ciContext = CIContext()

    static func grid(_ text: String, level: CorrectionLevel) -> QRGrid? {
        guard !text.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = level.rawValue
        guard let output = filter.outputImage,
              let cg = ciContext.createCGImage(output, from: output.extent)
        else { return nil }
        return readModules(cg)
    }

    /// Reads a 1-pixel-per-module bitmap, cropped to the symbol's bounding box.
    /// CoreImage emits its own 1-module border; dropping it makes the quiet
    /// zone entirely ours to choose, including none at all.
    private static func readModules(_ image: CGImage) -> QRGrid? {
        let n = image.width
        guard n > 0 else { return nil }
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: n * n)
        defer { buffer.deallocate() }
        buffer.initialize(repeating: 255, count: n * n)
        guard let ctx = CGContext(
            data: buffer, width: n, height: n,
            bitsPerComponent: 8, bytesPerRow: n,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: n, height: n))

        // Finder patterns sit in three corners, so the dark bounding box is
        // exactly the symbol.
        var minX = n, minY = n, maxX = -1, maxY = -1
        for y in 0..<n {
            for x in 0..<n where buffer[y * n + x] < 128 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }

        let side = max(maxX - minX + 1, maxY - minY + 1)
        var dark = [Bool](repeating: false, count: side * side)
        for y in 0..<side {
            let sy = minY + y
            guard sy <= maxY else { break }
            for x in 0..<side {
                let sx = minX + x
                guard sx <= maxX else { break }
                dark[y * side + x] = buffer[sy * n + sx] < 128
            }
        }
        return QRGrid(size: side, dark: dark)
    }

    static func geometry(_ grid: QRGrid, quiet: Int, targetPixels: Int) -> QRGeometry {
        let quiet = clampQuiet(quiet)
        let side = grid.size + quiet * 2
        let scale = max(1, targetPixels / side)
        return QRGeometry(modules: grid.size, quiet: quiet, side: side,
                          scale: scale, pixels: side * scale)
    }

    static func geometry(_ text: String, level: CorrectionLevel,
                         quiet: Int, targetPixels: Int) -> QRGeometry? {
        guard let grid = grid(text, level: level) else { return nil }
        return geometry(grid, quiet: quiet, targetPixels: targetPixels)
    }

    static func clampQuiet(_ q: Int) -> Int {
        min(max(q, quietZoneRange.lowerBound), quietZoneRange.upperBound)
    }

    /// How many more characters fit before the symbol steps up a version.
    /// Probed rather than looked up, so it needs no capacity tables and stays
    /// correct whatever encoding mode CoreImage picks.
    static func headroom(_ text: String, level: CorrectionLevel, limit: Int = 1024) -> Int? {
        guard let base = grid(text, level: level), let version = base.version,
              let filler = text.last else { return nil }

        func sameVersion(_ extra: Int) -> Bool {
            grid(text + String(repeating: filler, count: extra), level: level)?.version == version
        }

        var fits = 0, over = 1
        while over <= limit, sameVersion(over) { fits = over; over *= 2 }
        if over > limit { return fits }
        while fits + 1 < over {
            let mid = (fits + over) / 2
            if sameVersion(mid) { fits = mid } else { over = mid }
        }
        return fits
    }

    /// Dark modules as one path in a top-left-origin space, merging horizontal
    /// runs so adjacent squares fill as a single shape (no hairline seams).
    private static func path(_ grid: QRGrid, module: CGFloat, quiet: Int) -> CGPath {
        let path = CGMutablePath()
        let q = CGFloat(quiet)
        for y in 0..<grid.size {
            var x = 0
            while x < grid.size {
                guard grid.isDark(x, y) else { x += 1; continue }
                var run = 1
                while x + run < grid.size, grid.isDark(x + run, y) { run += 1 }
                path.addRect(CGRect(x: (CGFloat(x) + q) * module,
                                    y: (CGFloat(y) + q) * module,
                                    width: CGFloat(run) * module,
                                    height: module))
                x += run
            }
        }
        return path
    }

    private static func fill(_ ctx: CGContext, _ grid: QRGrid,
                             side: CGFloat, module: CGFloat, quiet: Int) {
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        ctx.translateBy(x: 0, y: side)      // flip to a top-left origin
        ctx.scaleBy(x: 1, y: -1)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.addPath(path(grid, module: module, quiet: quiet))
        ctx.fillPath()
    }

    // MARK: Raster

    /// Whole-module raster: the largest crisp image that fits `targetPixels`.
    static func cgImage(_ text: String, level: CorrectionLevel,
                        quiet: Int = defaultQuietZone, targetPixels: Int) -> CGImage? {
        guard let grid = grid(text, level: level) else { return nil }
        let geo = geometry(grid, quiet: quiet, targetPixels: targetPixels)
        guard let ctx = CGContext(
            data: nil, width: geo.pixels, height: geo.pixels,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        fill(ctx, grid, side: CGFloat(geo.pixels),
             module: CGFloat(geo.scale), quiet: geo.quiet)
        return ctx.makeImage()
    }

    static func pngData(_ text: String, level: CorrectionLevel,
                        quiet: Int = defaultQuietZone, targetPixels: Int) -> Data? {
        guard let cg = cgImage(text, level: level, quiet: quiet, targetPixels: targetPixels)
        else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        rep.size = NSSize(width: cg.width, height: cg.height)
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: Vector

    static func pdfData(_ text: String, level: CorrectionLevel,
                        quiet: Int = defaultQuietZone, points: CGFloat) -> Data? {
        guard let grid = grid(text, level: level) else { return nil }
        let quiet = clampQuiet(quiet)
        let modules = CGFloat(grid.size + quiet * 2)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        var box = CGRect(x: 0, y: 0, width: points, height: points)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        ctx.beginPDFPage(nil)
        fill(ctx, grid, side: points, module: points / modules, quiet: quiet)
        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }

    static func svgData(_ text: String, level: CorrectionLevel,
                        quiet: Int = defaultQuietZone) -> Data? {
        guard let grid = grid(text, level: level) else { return nil }
        let quiet = clampQuiet(quiet)
        let side = grid.size + quiet * 2
        var d = ""
        for y in 0..<grid.size {
            var x = 0
            while x < grid.size {
                guard grid.isDark(x, y) else { x += 1; continue }
                var run = 1
                while x + run < grid.size, grid.isDark(x + run, y) { run += 1 }
                d += "M\(x + quiet) \(y + quiet)h\(run)v1h-\(run)z"
                x += run
            }
        }
        let svg = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(side) \(side)" \
        width="\(side * 8)" height="\(side * 8)" shape-rendering="crispEdges">
        <rect width="\(side)" height="\(side)" fill="#ffffff"/>
        <path fill="#000000" d="\(d)"/>
        </svg>
        """
        return svg.data(using: .utf8)
    }

    /// Export in the chosen format. `size` is pixels for PNG, points for PDF,
    /// and ignored for SVG.
    static func data(_ text: String, level: CorrectionLevel, quiet: Int,
                     format: ExportFormat, size: Int) -> Data? {
        switch format {
        case .png: return pngData(text, level: level, quiet: quiet, targetPixels: size)
        case .pdf: return pdfData(text, level: level, quiet: quiet, points: CGFloat(size))
        case .svg: return svgData(text, level: level, quiet: quiet)
        }
    }
}
