import SwiftUI

/// The shared "connected / not" indicator dot.
///
/// It lived beside the app picker because the first screen that needed one was
/// there. It is a design-system mark used by three call sites, and it was
/// filling `Color.green` — 2.22:1 against the window in light appearance, on a
/// dot 8 pt across whose colour *is* its entire message.
public struct HelmStatusDot: View {
    let active: Bool
    public init(active: Bool) { self.active = active }
    public var body: some View {
        Circle()
            .fill(active ? HelmSignal.success : Color.secondary.opacity(0.4))
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }
}
