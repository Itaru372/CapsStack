import CapsStackLocalization
import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 18) {
            BrandAppIcon(size: 88)
            VStack(spacing: 6) {
                Text("CapsStack").font(.system(size: 28, weight: .bold))
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text(CapsStackText.resource(.brandPromise))
                .font(.title3.weight(.medium))
            Text(CapsStackText.resource(.setupDescription))
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Label(CapsStackText.resource(.localProcessing), systemImage: "lock.shield")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(32)
        .frame(width: 420)
        .background(BrandPalette.BriefTheme.canvas)
        .tint(BrandPalette.BriefTheme.signal)
    }
}
