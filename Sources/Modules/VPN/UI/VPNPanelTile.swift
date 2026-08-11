import AppKit
import SwiftUI
import HelmUI
import Module_VPN_Engine

/// Compact tile shown in the shared Helm panel: each configured VPN gets a
/// small connect/disconnect switch.
struct VPNPanelTile: View {
    @ObservedObject private var vm: VPNViewModel

    init(vm: VPNViewModel) {
        self.vm = vm
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if vm.connections.isEmpty {
                Text(VPNStr.noVPNs)
                    .font(.caption)
                    .foregroundStyle(HelmText.quiet)
            } else {
                VStack(spacing: 8) {
                    ForEach(vm.connections) { connectionRow($0) }
                }
            }
        }
        .helmPanelCard()
        // The panel's hosting view is built once and merely ordered in and out,
        // so `.task` here runs at the first open and never again — and the
        // panel deliberately does not activate the app, so `helmOnAppActive`
        // never fires for it either. Becoming key is the one event a
        // non-activating panel does raise, and `HelmPanel.toggle` calls
        // `makeKey()` on every open for its own reasons.
        //
        // The engine's network observer is the real answer; this is the route
        // that needs nothing to have fired. One `scutil --nc list` on the
        // engine's own queue, once per window activation.
        .onReceive(NotificationCenter.default.publisher(
            for: NSWindow.didBecomeKeyNotification)) { _ in vm.refresh() }
    }

    private var header: some View {
        // The token, not `.indigo` — see the same note on Keep Awake's tile.
        HelmWidgetHeader(symbol: "lock.shield", tint: VPNDescriptor.tint.colour, name: "VPN",
                         active: anyConnected) {
            HelmStatusDot(active: anyConnected)
        }
    }

    private var anyConnected: Bool {
        vm.connections.contains(where: \.status.isUp)
    }

    private func connectionRow(_ c: VPNConnection) -> some View {
        let active = c.status.isUp
        let transitioning = c.status.isTransitioning
        return HStack(spacing: 8) {
            HelmStatusDot(active: active)
            Text(c.name).lineLimit(1)
            Spacer(minLength: 8)
            if transitioning { ProgressView().controlSize(.small) }
            Toggle("", isOn: Binding(
                get: { active },
                set: { on in on ? vm.connect(c.name) : vm.disconnect(c.name) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
                .accessibilityLabel(c.name)
        }
    }

}
