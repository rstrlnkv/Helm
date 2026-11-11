import Foundation

/// Section headings more than one page needs.
///
/// The same argument as `HelmBasket`, one class of string over: three pages draw
/// a group of «how it acts» switches, and all three declared «Behaviour» in
/// their own strings file. One word with three declarations is a word that gets
/// split by somebody who cannot see the other two — and a heading that means one
/// thing has to keep meaning it.
///
/// A heading that belongs to one page stays in that page's own strings.
public enum HelmSectionName {
    /// The group of switches that say how a module behaves — Helm's own general
    /// settings, Keep Awake's, and the Keyboard's.
    public static var behaviour: String { L(.behaviour) }
}
