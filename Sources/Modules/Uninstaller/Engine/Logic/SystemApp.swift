import Foundation

/// Whether an app belongs to macOS rather than to the person using it.
///
/// Safari was listed with a checkbox and a size of zero. Ticking it bought a
/// leftovers scan, a click and a failure report to learn what its identifier
/// already said — macOS will refuse the move, and refusing after the click is
/// the right explanation at the wrong moment.
///
/// The rule is `LeftoverActions.available`'s, which decides the same question
/// for the leftovers list: a `com.apple.` identifier means the row offers
/// looking and nothing else. It is spelled again rather than shared because the
/// two engines do not depend on one another and neither may reach into the
/// other; if a third module needs it, it belongs in `HelmRuntime` and all three
/// should read it from there.
///
/// The separator carries the rule. `com.applesauce.jam` starts with the letters
/// of `com.apple` and is somebody's own app — the same mistake, one dot away,
/// once sent a user to switch off a different vendor's system extension.
public enum SystemApp {
    public static func isSystem(bundleID: String) -> Bool {
        bundleID.hasPrefix("com.apple.")
    }
}
