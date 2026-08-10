import Foundation

/// The options a pop-up offers, with the stored value always among them.
///
/// A stepper accepts every number in its range; a pop-up offers a handful. Swap
/// one for the other and any stored value that is not on the list has no row to
/// be selected in — SwiftUI draws the button empty, and the first thing the
/// person does about that is pick something, which silently overwrites a
/// setting they never meant to change. Values reach settings from outside the
/// pop-up: an older build's stepper, a hand-edited plist, a default that moved.
///
/// So the list is «the offered ones, plus whatever is actually stored», in
/// order. The odd value is visible, keeps working, and disappears from the menu
/// once something else is chosen.
public enum HelmChoices {
    public static func including(_ value: Int, in offered: [Int]) -> [Int] {
        offered.contains(value) ? offered : (offered + [value]).sorted()
    }
}
