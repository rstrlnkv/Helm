import SwiftUI
import HelmUI

/// Homebrew's real UI lives in Settings. The panel tile is a compact entry point.
struct HomebrewPanelTile: View {
    var body: some View {
        HStack(spacing: 10) {
            HelmIconBadge(symbol: "shippingbox", color: .pink, active: false)
            VStack(alignment: .leading, spacing: 1) {
                Text(HbStr.moduleName).font(.headline)
                Text(HbStr.panelHint).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(HbStr.openInSettings) {
                NotificationCenter.default.post(name: .helmOpenSettings, object: nil)
            }
            .controlSize(.small)
        }
        .helmPanelCard()
    }
}
