import AppKit
import SwiftUI

/// Offline artwork downloaded from each agent's official project site or GitHub repository.
/// SF Symbols remain the fallback for integrations that do not ship an asset yet.
struct AgentArtwork: View {
    let kind: CLIKind
    var size: CGFloat = 34

    var body: some View {
        Group {
            if let resource = kind.artworkResourceName,
               let image = Self.image(named: resource) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            } else {
                Image(systemName: kind.systemImage)
                    .font(.system(size: max(14, size * 0.47)))
                    .foregroundStyle(BrandPalette.BriefTheme.signal)
            }
        }
        .frame(width: size, height: size)
        .background(
            BrandPalette.BriefTheme.signal.opacity(0.1),
            in: RoundedRectangle(cornerRadius: max(7, size * 0.24))
        )
        .accessibilityHidden(true)
    }

    private static func image(named resource: String) -> NSImage? {
        for fileExtension in ["svg", "png"] {
            guard let imageURL = resourceBundle.url(
                forResource: resource,
                withExtension: fileExtension
            ), let image = NSImage(contentsOf: imageURL), image.isValid else {
                continue
            }
            return image
        }
        return nil
    }

    /// SwiftPM executables look beside the binary while building, but a proper macOS app
    /// stores resources in Contents/Resources. Prefer the packaged location so installed
    /// builds never depend on the source checkout embedded in Bundle.module's fallback path.
    private static let resourceBundle: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("CapsStack_CapsStack.bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return .module
    }()
}
