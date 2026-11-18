import HelmUI
import SwiftUI

/// The Tweaks page: one kit card per tweak in `TweakRegistry.all`, each with the tweak's own switch in its header
/// and the tweak's settings below while it is live. The cards sit in the module page's column, as a module's sections do.
///
/// The header is the same whether the tweak has settings or not: a tweak with no `rows` shows its header alone,
/// and the page has no empty state of its own, because the registry is never empty in a shipped build.
struct TweaksPage: View {
    @ObservedObject var host: TweakHost

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HelmSpace.s7) {
                ForEach(host.descriptors, id: \.idRaw) { tweak in
                    HelmSettingsSection {
                        header(tweak)
                        if let rows = host.live[tweak.idRaw]?.rows() {
                            ForEach(rows.indices, id: \.self) { rows[$0] }
                        }
                    }
                }
            }
            .padding(.horizontal, HelmLayout.formInset)
            .padding(.vertical, HelmSpace.s6)
            .helmSettingsColumn()
        }
    }

    private func header(_ tweak: any TweakDescriptor) -> some View {
        HStack(alignment: .center, spacing: HelmSpace.s5) {
            ShellGlyphView(tweak.tweakGlyph, filled: false, size: 22)
                .foregroundStyle(HelmText.quiet)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: HelmSpace.s1) {
                Text(tweak.tweakName).font(HelmText.rowTitle)
                Text(tweak.tweakSummary)
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmText.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: HelmSpace.s5)
            Toggle(tweak.tweakName, isOn: Binding(
                get: { host.isEnabled(tweak) },
                set: { host.setEnabled(tweak, $0) }))
                .labelsHidden()
        }
    }
}
