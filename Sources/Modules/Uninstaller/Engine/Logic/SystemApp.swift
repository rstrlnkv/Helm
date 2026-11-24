import Foundation

/// Whether an app belongs to macOS rather than to the person using it.
///
/// macOS refuses to move its own apps, so the identifier answers before the
/// click rather than a failure report after it.
///
/// The rule is `LeftoverActions.available`'s: a `com.apple.` identifier offers
/// looking and nothing else. Spelled again because the two engines may not
/// import each other; a third user would move it to `HelmRuntime`.
///
/// The separator carries the rule: `com.applesauce.jam` is somebody's own app.
public enum SystemApp {
    public static func isSystem(bundleID: String) -> Bool {
        bundleID.hasPrefix("com.apple.")
    }
}
