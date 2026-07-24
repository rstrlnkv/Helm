import SwiftUI
import HelmUI

/// The uninstaller's real UI lives in Settings (list-heavy). The panel tile is a
/// compact entry point: icon + name + a button that opens Settings on this module.
struct UninstallerPanelTile: View {
    var body: some View {
        HStack(spacing: 10) {
            HelmIconBadge(symbol: "trash", color: .pink, active: false)
            VStack(alignment: .leading, spacing: 1) {
                Text(UnStr.moduleName).font(.headline)
                Text(UnStr.panelHint).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(UnStr.openInSettings) {
                NotificationCenter.default.post(name: .helmOpenSettings, object: nil)
            }
            .controlSize(.small)
        }
        .helmPanelCard()
    }
}
