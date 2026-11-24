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
        VStack(alignment: .leading, spacing: HelmSpace.s4) {
            header
            if vm.connections.isEmpty {
                Text(VPNStr.noVPNs())
                    // The panel's scale, not the settings window's.
                    .font(HelmText.smallPrint)
                    .foregroundStyle(HelmText.quiet)
            } else {
                VStack(spacing: HelmSpace.s4) {
                    ForEach(vm.connections) { connectionRow($0) }
                }
            }
        }
        .helmPanelCard()
        // The panel's hosting view is built once and ordered in and out, so
        // `.task` runs only at the first open, and the panel does not activate
        // the app, so `helmOnAppActive` never fires. Becoming key is the one
        // event it raises (`HelmPanel.toggle` calls `makeKey()` on every open).
        // The engine's network observer is the real answer; this costs one
        // `scutil --nc list` per window activation.
        .onReceive(NotificationCenter.default.publisher(
            for: NSWindow.didBecomeKeyNotification)) { _ in vm.refresh() }
    }

    private var header: some View {
        // The token, not `.indigo`, as on Keep Awake's tile.
        HelmWidgetHeader(symbol: "lock.shield", tint: VPNDescriptor.tint.colour, name: VPNDescriptor.metadata.name,
                         active: anyConnected) {
            HelmStatusDot(active: anyConnected)
        }
    }

    /// **`isConnected`, not `isUp`**: `isUp` includes `.connecting`, and a
    /// green dot three seconds into a handshake says this Mac is protected
    /// while it is not, on the surface glanced at before sending something
    /// that should not go in clear.
    var anyConnected: Bool {
        vm.connections.contains(where: \.status.isConnected)
    }

    /// The row's dot, by the same word as `anyConnected`.
    static func lit(_ c: VPNConnection) -> Bool { c.status.isConnected }

    private func connectionRow(_ c: VPNConnection) -> some View {
        // Whether traffic is on the tunnel is `isConnected` (the dot); whether
        // the switch may be touched is `VPNCardAction`, which says yes while a
        // handshake runs, exactly when somebody wants out; where it stands is
        // the `Toggle` below.
        let action = VPNCardAction.of(c.status)
        return HStack(spacing: HelmSpace.s4) {
            HelmStatusDot(active: Self.lit(c))
            Text(c.name).lineLimit(1)
            Spacer(minLength: HelmSpace.s4)
            if c.status.isTransitioning { ProgressView().controlSize(.small) }
            // **`isUp`, not the card's verb.** A switch's position is what was
            // last asked for: a tunnel on its way *down* would otherwise throw
            // the switch back on the moment it was turned off.
            Toggle("", isOn: Binding(
                get: { c.status.isUp },
                set: { on in on ? vm.connect(c.name) : vm.disconnect(c.name) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
                .disabled(!action.enabled)
                .accessibilityLabel(c.name)
        }
    }

}
