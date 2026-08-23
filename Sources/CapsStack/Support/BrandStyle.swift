import AppKit
import SwiftUI

enum BrandPalette {
    static let inkAubergine = adaptive(
        light: rgb(0x35, 0x2A, 0x38),
        dark: rgb(0xEA, 0xE1, 0xEC)
    )
    static let agedBrass = adaptive(
        light: rgb(0xB8, 0x9B, 0x48),
        dark: rgb(0xD2, 0xB7, 0x5B)
    )
    static let agedBrassNS = adaptiveNS(
        light: rgb(0xB8, 0x9B, 0x48),
        dark: rgb(0xD2, 0xB7, 0x5B)
    )
    static let petrolSlate = adaptive(
        light: rgb(0x4F, 0x71, 0x74),
        dark: rgb(0x78, 0xA2, 0xA5)
    )
    static let petrolSlateNS = adaptiveNS(
        light: rgb(0x4F, 0x71, 0x74),
        dark: rgb(0x78, 0xA2, 0xA5)
    )
    static let ricePaper = adaptive(
        light: rgb(0xEF, 0xE7, 0xD8),
        dark: rgb(0x25, 0x21, 0x28)
    )
    static let bone = adaptive(
        light: rgb(0xF7, 0xF3, 0xEA),
        dark: rgb(0x2D, 0x28, 0x30)
    )

    /// The approved return-brief design is intentionally dark-only. These fixed surfaces
    /// keep cards readable when the system appearance changes around the app window.
    enum BriefTheme {
        static let canvas = rgbColor(0x10, 0x10, 0x13)
        static let panel = rgbColor(0x18, 0x18, 0x1C)
        static let card = rgbColor(0x21, 0x21, 0x26)
        static let border = Color.white.opacity(0.08)
        static let signal = rgbColor(0xC6, 0xF2, 0x4E)
    }

    private static func rgb(_ red: Int, _ green: Int, _ blue: Int) -> NSColor {
        NSColor(
            srgbRed: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: 1
        )
    }

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: adaptiveNS(light: light, dark: dark))
    }

    private static func rgbColor(_ red: Int, _ green: Int, _ blue: Int) -> Color {
        Color(red: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255)
    }

    private static func adaptiveNS(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }
}

enum BrandAssets {
    static let resourceBundle: Bundle = {
        let bundleName = "CapsStack_CapsStack.bundle"
        if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent(bundleName),
           let bundledResources = Bundle(url: resourceURL) {
            return bundledResources
        }
        return .module
    }()

    static func image(named name: String) -> Image {
        if let image = nsImage(named: name) {
            return Image(nsImage: image)
        }
        return Image(systemName: "questionmark.square.dashed")
    }

    static func nsImage(named name: String) -> NSImage? {
        guard let url = resourceBundle.url(forResource: name, withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    static func menuBarImage(indicatorColor: NSColor, displaySize: CGFloat = 18) -> NSImage? {
        guard let source = nsImage(named: "CapsStackMenuBar") else {
            return nil
        }

        let imageSize = source.size
        let image = NSImage(size: imageSize)
        image.lockFocus()
        source.draw(
            in: NSRect(origin: .zero, size: imageSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )

        let indicatorDiameter = imageSize.width * 0.125
        let indicatorRect = NSRect(
            x: imageSize.width * 0.6375,
            y: imageSize.height * 0.50,
            width: indicatorDiameter,
            height: indicatorDiameter
        )
        indicatorColor.setFill()
        NSBezierPath(ovalIn: indicatorRect).fill()
        image.unlockFocus()

        image.size = NSSize(width: displaySize, height: displaySize)
        image.isTemplate = false
        return image
    }
}

struct BrandAppIcon: View {
    var size: CGFloat = 44

    var body: some View {
        BrandAssets.image(named: "CapsStackAppIcon")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct BrandMenuBarIcon: View {
    let indicatorColor: NSColor
    var size: CGFloat = 26

    var body: some View {
        Group {
            if let image = BrandAssets.menuBarImage(
                indicatorColor: indicatorColor,
                displaySize: size
            ) {
                Image(nsImage: image)
                .resizable()
                .interpolation(.high)
            } else {
                Image(systemName: "square.dashed")
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension AppPhase {
    var brandColor: Color {
        switch self {
        case .idle: .secondary
        case .away: Color(nsColor: .systemGreen)
        case .summarizing: BrandPalette.petrolSlate
        case .failed: .red
        case .disabled: .gray
        }
    }

    var menuBarIndicatorColor: NSColor {
        switch self {
        case .idle: BrandPalette.agedBrassNS
        case .away: .systemGreen
        case .summarizing: BrandPalette.petrolSlateNS
        case .failed: .systemRed
        case .disabled: .systemGray
        }
    }
}
