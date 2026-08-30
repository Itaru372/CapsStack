import SwiftUI

/// Offline artwork downloaded from each agent's official project site or GitHub repository.
/// SF Symbols remain the fallback for established integrations that do not ship an asset yet.
struct AgentArtwork: View {
    let kind: CLIKind
    var size: CGFloat = 34

    var body: some View {
        Group {
            if let resource = kind.artworkResourceName,
               Bundle.module.url(forResource: resource, withExtension: "png") != nil {
                Image(resource, bundle: .module)
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
}
