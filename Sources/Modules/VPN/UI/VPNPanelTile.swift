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
                    // The panel's scale, not the settings window's.
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

    /// **`isConnected`, not `isUp`** — the same distinction the settings page
    /// draws its dot by and argues for at its own call site: `isUp` includes
    /// `.connecting`, and a green dot on a tunnel three seconds into a handshake
    /// is the panel saying this Mac is protected while it is not. This is the
    /// surface somebody glances at before sending something they would not send
    /// in clear.
    private var anyConnected: Bool {
        vm.connections.contains(where: \.status.isConnected)
    }

    private func connectionRow(_ c: VPNConnection) -> some View {
        // Three questions, and the dot and the switch used to share one answer.
        // Whether traffic is on the tunnel is `isConnected` (above); what can be
        // *asked for* while it is coming up is `VPNCardAction`, which is the
        // engine's to answer and says «stop» — so the switch stays thrown while a
        // handshake runs and can be turned off, which is exactly when somebody
        // wants out.
        let action = VPNCardAction.of(c.status)
        return HStack(spacing: 8) {
            HelmStatusDot(active: c.status.isConnected)
            Text(c.name).lineLimit(1)
            Spacer(minLength: 8)
            if c.status.isTransitioning { ProgressView().controlSize(.small) }
            Toggle("", isOn: Binding(
                get: { action.verb == .disconnect },
                set: { on in on ? vm.connect(c.name) : vm.disconnect(c.name) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
                .disabled(!action.enabled)
                .accessibilityLabel(c.name)
        }
    }

}
