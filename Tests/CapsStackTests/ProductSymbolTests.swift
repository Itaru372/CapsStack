import AppKit
import SwiftUI
import XCTest
@testable import CapsStack

@MainActor
final class ProductSymbolTests: XCTestCase {
    func testGeneratedSymbolsAreCompactTransparentResources() throws {
        XCTAssertEqual(ProductSymbol.allCases.count, 7)

        for symbol in ProductSymbol.allCases {
            let url = try XCTUnwrap(
                BrandAssets.resourceBundle.url(forResource: symbol.rawValue, withExtension: "png"),
                "Missing generated resource: \(symbol.rawValue)"
            )
            let data = try Data(contentsOf: url)
            let representation = try XCTUnwrap(NSBitmapImageRep(data: data))

            XCTAssertEqual(representation.pixelsWide, 256, symbol.rawValue)
            XCTAssertEqual(representation.pixelsHigh, 256, symbol.rawValue)
            XCTAssertTrue(representation.hasAlpha, symbol.rawValue)
            XCTAssertLessThan(data.count, 256_000, symbol.rawValue)
            XCTAssertNotNil(BrandAssets.nsImage(named: symbol.rawValue), symbol.rawValue)
        }
    }

    func testProductSymbolViewDoesNotExpandPastRequestedSize() {
        for symbol in ProductSymbol.allCases {
            let requestedSize: CGFloat = 18
            let hostingView = NSHostingView(
                rootView: ProductSymbolImage(symbol: symbol, size: requestedSize)
            )
            let fittingSize = hostingView.fittingSize

            XCTAssertLessThanOrEqual(fittingSize.width, requestedSize, symbol.rawValue)
            XCTAssertLessThanOrEqual(fittingSize.height, requestedSize, symbol.rawValue)
        }
    }
}
