/// Which rows of the automation card can carry a mark, and which do.
///
/// The mark column is one width for every row of the card — the two rules that
/// can be ticked and the three that never will — so the answer to «can a mark
/// appear here at all» has to be one value, and the settings alone cannot give it.
///
/// **A row this Mac does not draw cannot be counted.** The display rule is
/// hidden on a Mac with no lid while its switch may still be in the file, and
/// counting it indents every row for a mark nothing can put there
/// (`Architecture/KeepAwake.md § Rules read from the machine`).
///
/// **And the lid is the second source.** Its row carries a mark of its own once
/// sleep is off, so `isEmpty` cannot be read off the rules alone; a second
/// reader for it would let the column disagree with the marks it makes room for.
public struct MarkableRules: Equatable, Sendable {
    /// The rules that are switched on **and drawn on this Mac**.
    public let rules: Set<ActiveCondition>
    /// Sleep is off for the whole Mac right now, because the lid is shut and
    /// somebody asked for that. Not a rule: the lid is a switch that changes the
    /// machine rather than a condition that fires.
    public let lidHolding: Bool

    /// - Parameters:
    ///   - hasLid: whether the display rule's row and the lid row are drawn at
    ///     all; both go by the lid, a Mac with none has neither.
    static func of(autoExternalDisplay: Bool, autoPower: Bool, lidHolding: Bool,
                          hasLid: Bool) -> MarkableRules {
        var rules = Set<ActiveCondition>()
        if autoExternalDisplay, hasLid { rules.insert(.externalDisplay) }
        if autoPower { rules.insert(.power) }
        return MarkableRules(rules: rules, lidHolding: lidHolding && hasLid)
    }

    /// The same question with the hardware already answered, so no call site
    /// spells `MacHardware` itself.
    public static func onThisMac(autoExternalDisplay: Bool, autoPower: Bool,
                                 lidHolding: Bool) -> MarkableRules {
        of(autoExternalDisplay: autoExternalDisplay, autoPower: autoPower,
           lidHolding: lidHolding, hasLid: MacHardware.hasLid)
    }

    /// Whether a given rule is drawn as switched on.
    public func contains(_ condition: ActiveCondition) -> Bool { rules.contains(condition) }

    /// Nothing in this card can carry a mark, so no row is indented for one.
    public var isEmpty: Bool { rules.isEmpty && !lidHolding }
}
