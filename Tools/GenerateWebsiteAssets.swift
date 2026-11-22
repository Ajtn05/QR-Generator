import SwiftUI
import AppKit

@main
struct GenerateWebsiteAssets {
    static func render(
        view: some View, appearance: NSAppearance.Name, size: CGSize,
        omitSidebar: Bool = false, path: String
    ) throws {
        guard let drawingAppearance = NSAppearance(named: appearance) else {
            fatalError("Appearance unavailable: \(appearance)")
        }
        NSApplication.shared.appearance = drawingAppearance
        let scheme: ColorScheme = appearance == .darkAqua ? .dark : .light
        let hostingView = NSHostingView(rootView: view.environment(\.colorScheme, scheme))
        hostingView.appearance = drawingAppearance
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()
        
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.appearance = drawingAppearance
        window.contentView = hostingView
        window.layoutIfNeeded()
        
        guard let rep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            fatalError("Failed to cache display")
        }
        drawingAppearance.performAsCurrentDrawingAppearance {
            hostingView.cacheDisplay(in: hostingView.bounds, to: rep)
        }
        let imageRep: NSBitmapImageRep
        if omitSidebar, let image = rep.cgImage {
            // AppKit's offscreen cache draws the sidebar selection without its normal window colors.
            let sidebarWidth = 192 * CGFloat(image.width) / size.width
            let bounds = CGRect(
                x: sidebarWidth, y: 0,
                width: CGFloat(image.width) - sidebarWidth, height: CGFloat(image.height)
            )
            guard let cropped = image.cropping(to: bounds) else {
                fatalError("Failed to crop the screenshot")
            }
            imageRep = NSBitmapImageRep(cgImage: cropped)
        } else {
            imageRep = rep
        }
        guard let data = imageRep.representation(using: .png, properties: [:]) else {
            fatalError("Failed to get PNG")
        }
        try data.write(to: URL(fileURLWithPath: path))
        print("Generated \(path)")
    }

    static func main() async throws {
        NSApplication.shared.finishLaunching()
        let fileManager = FileManager.default
        try? fileManager.createDirectory(atPath: "assets", withIntermediateDirectories: true)

        // 1. Link screen (Dark)
        UserDefaults.standard.set(PayloadKind.link.rawValue, forKey: "payloadKind")
        var p1 = Payload()
        p1.text = "https://example.com/menu"
        try render(
            view: ContentView(initial: p1).frame(width: 940, height: 760),
            appearance: .darkAqua,
            size: CGSize(width: 940, height: 760),
            omitSidebar: true,
            path: "assets/app-screenshot-dark.png"
        )

        // 2. Link screen (Light)
        try render(
            view: ContentView(initial: p1).frame(width: 940, height: 760),
            appearance: .aqua,
            size: CGSize(width: 940, height: 760),
            omitSidebar: true,
            path: "assets/app-screenshot-light.png"
        )

        // 3. Wi-Fi screen
        UserDefaults.standard.set(PayloadKind.wifi.rawValue, forKey: "payloadKind")
        var p2 = Payload()
        p2.ssid = "Guest Wi-Fi"
        p2.password = "example-password"
        p2.security = .wpa
        try render(
            view: ContentView(initial: p2).frame(width: 940, height: 760),
            appearance: .darkAqua,
            size: CGSize(width: 940, height: 760),
            omitSidebar: true,
            path: "assets/app-screenshot-wifi.png"
        )

        // 4. Contact vCard screen
        UserDefaults.standard.set(PayloadKind.contact.rawValue, forKey: "payloadKind")
        var p3 = Payload()
        p3.firstName = "Alex"
        p3.lastName = "Morgan"
        p3.contactPhone = "+1 415 555 0112"
        p3.contactEmail = "alex@example.com"
        p3.contactURL = "https://example.com"
        try render(
            view: ContentView(initial: p3).frame(width: 940, height: 760),
            appearance: .darkAqua,
            size: CGSize(width: 940, height: 760),
            omitSidebar: true,
            path: "assets/app-screenshot-contact.png"
        )

        // 5. Batch Export Sheet
        let batchView = BatchView(level: .medium, quiet: 4, format: .svg, size: 1024)
            .frame(width: 500, height: 380)
        try render(
            view: batchView,
            appearance: .darkAqua,
            size: CGSize(width: 500, height: 380),
            path: "assets/app-screenshot-batch.png"
        )

        // Reset payloadKind to link
        UserDefaults.standard.set(PayloadKind.link.rawValue, forKey: "payloadKind")
    }
}
