import SwiftUI

/// CapsStack-specific actions that benefit from a more literal symbol than the
/// nearest SF Symbol. Generated artwork is monochrome and rendered as a template,
/// so it follows the foreground style in both appearances.
enum ProductSymbol: String, CaseIterable {
    case returnBrief = "SymbolReturnBrief"
    case awayMemo = "SymbolAwayMemo"
    case stepAway = "SymbolStepAway"
    case collectionSources = "SymbolCollectionSources"
    case noSessions = "SymbolNoSessions"
    case highlights = "SymbolHighlights"
    case summarizer = "SymbolSummarizer"

    var fallbackSystemName: String {
        switch self {
        case .returnBrief: "text.page"
        case .awayMemo: "square.and.pencil"
        case .stepAway: "cup.and.saucer.fill"
        case .collectionSources: "tray.and.arrow.down"
        case .noSessions: "tray"
        case .highlights: "scope"
        case .summarizer: "text.quote"
        }
    }
}

struct ProductSymbolImage: View {
    let symbol: ProductSymbol
    var size: CGFloat = 16

    var body: some View {
        Group {
            if let image = BrandAssets.nsImage(named: symbol.rawValue) {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: symbol.fallbackSystemName)
                    .resizable()
            }
        }
        .scaledToFit()
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
