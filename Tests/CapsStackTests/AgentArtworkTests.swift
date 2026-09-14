import AppKit
import SwiftUI
import XCTest
@testable import CapsStack

@MainActor
final class AgentArtworkTests: XCTestCase {
    private let requestedArtwork: [(kind: CLIKind, name: String)] = [
        (.codex, "AgentCodex"),
        (.claudeCode, "AgentClaudeCode"),
        (.opencode, "AgentOpenCode"),
        (.pi, "AgentPi"),
        (.githubCopilot, "AgentGitHubCopilot")
    ]

    func testRequestedAgentArtworkIsBundledAndDecodable() throws {
        XCTAssertEqual(Set(requestedArtwork.map(\.name)).count, requestedArtwork.count)

        for artwork in requestedArtwork {
            XCTAssertEqual(artwork.kind.artworkResourceName, artwork.name)
            let url = try XCTUnwrap(
                BrandAssets.resourceBundle.url(forResource: artwork.name, withExtension: "svg"),
                "Missing SVG artwork for \(artwork.kind.rawValue)"
            )
            let image = try XCTUnwrap(NSImage(contentsOf: url))
            XCTAssertTrue(image.isValid, artwork.name)
            XCTAssertGreaterThan(image.size.width, 0, artwork.name)
            XCTAssertGreaterThan(image.size.height, 0, artwork.name)
            XCTAssertNotNil(BrandAssets.nsImage(named: artwork.name), artwork.name)
        }
    }

    func testRequestedAgentArtworkStaysInsideItsFrameInBothAppearances() throws {
        _ = NSApplication.shared
        let iconSizes: [CGFloat] = [28, 34, 48]

        for scheme in [ColorScheme.light, .dark] {
            let suffix = scheme == .light ? "light" : "dark"
            for iconSize in iconSizes {
                for artwork in requestedArtwork {
                    let probeSize = CGSize(width: iconSize + 20, height: iconSize + 20)
                    let snapshot = try render(
                        ZStack {
                            Color.white
                            AgentArtwork(kind: artwork.kind, size: iconSize)
                        }
                        .environment(\.colorScheme, scheme)
                        .frame(width: probeSize.width, height: probeSize.height),
                        size: probeSize,
                        appearance: scheme
                    )

                    XCTAssertEqual(snapshot.size, probeSize, "\(artwork.name)-\(suffix)-\(iconSize)")
                    try assertOuterMarginIsWhite(
                        snapshot,
                        margin: 8,
                        message: "\(artwork.name)-\(suffix)-\(iconSize) protrudes outside its frame"
                    )

                    let source = try XCTUnwrap(BrandAssets.nsImage(named: artwork.name))
                    let availableSize = iconSize - 8
                    let scale = min(
                        availableSize / source.size.width,
                        availableSize / source.size.height
                    )
                    XCTAssertLessThanOrEqual(
                        source.size.width * scale,
                        availableSize + 0.01,
                        "\(artwork.name) exceeds the padded width"
                    )
                    XCTAssertLessThanOrEqual(
                        source.size.height * scale,
                        availableSize + 0.01,
                        "\(artwork.name) exceeds the padded height"
                    )
                }
            }

            if let outputPath = ProcessInfo.processInfo.environment["CAPSSTACK_QA_OUTPUT"] {
                let outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)
                try FileManager.default.createDirectory(
                    at: outputDirectory,
                    withIntermediateDirectories: true
                )
                let gridSize = CGSize(width: 5 * 104 + 32, height: 112)
                let grid = HStack(spacing: 12) {
                    ForEach(requestedArtwork, id: \.name) { artwork in
                        VStack(spacing: 6) {
                            AgentArtwork(kind: artwork.kind, size: 48)
                            Text(artwork.kind.collectionDisplayName)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(width: 92, height: 28)
                        }
                        .frame(width: 104)
                    }
                }
                .padding(16)
                .background(Color.white)
                .environment(\.colorScheme, scheme)
                let snapshot = try render(
                    grid.frame(width: gridSize.width, height: gridSize.height),
                    size: gridSize,
                    appearance: scheme
                )
                try writePNG(
                    snapshot,
                    to: outputDirectory.appendingPathComponent("agent-artwork-\(suffix).png")
                )
            }
        }
    }

    private func render<Content: View>(
        _ content: Content,
        size: CGSize,
        appearance: ColorScheme? = nil
    ) throws -> NSImage {
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = CGRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        if let appearance {
            let nsAppearance = NSAppearance(
                named: appearance == .dark ? .darkAqua : .aqua
            )
            window.appearance = nsAppearance
            hostingView.appearance = nsAppearance
        }
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        let representation = try XCTUnwrap(
            hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        )
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)

        let image = NSImage(size: size)
        image.addRepresentation(representation)
        return image
    }

    private func assertOuterMarginIsWhite(
        _ image: NSImage,
        margin: CGFloat,
        message: String
    ) throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        let pixelsPerPoint = CGFloat(bitmap.pixelsWide) / image.size.width
        let marginPixels = max(1, Int(ceil(margin * pixelsPerPoint)))
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh

        for x in 0..<width {
            let isMarginColumn = x < marginPixels || x >= width - marginPixels
            for y in 0..<height {
                let isMarginRow = y < marginPixels || y >= height - marginPixels
                guard isMarginColumn || isMarginRow else { continue }
                let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                let distanceFromWhite =
                    abs(color.redComponent - 1)
                    + abs(color.greenComponent - 1)
                    + abs(color.blueComponent - 1)
                XCTAssertLessThan(distanceFromWhite, 0.04, message)
            }
        }
    }

    private func writePNG(_ image: NSImage, to url: URL) throws {
        let tiffData = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiffData))
        let pngData = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try pngData.write(to: url, options: .atomic)
    }
}
