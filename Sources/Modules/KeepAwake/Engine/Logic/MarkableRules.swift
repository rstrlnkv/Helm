import HelmRuntime

/// Which rows of the automation card can carry a mark, and which do.
///
/// The mark column is one width for every row of the card — the two rules that
/// can be ticked and the three that never will — so the answer to «can a mark
/// appear here at all» has to be one value. Asked of the settings alone it was
/// wrong twice over.
///
/// **A row this Mac does not draw cannot be counted.** The display rule is
/// hidden on a machine with no display of its own, and the switch is still in
/// the file: a Studio whose plist was written while it was a laptop indented all
/// five visible rows for a mark column that nothing could put a mark in. The
/// hardware is asked here rather than in the page, so the rule is a function
/// with a test — this Mac has a built-in display, so there is nothing to
/// photograph.
///
/// **And the lid is the second source.** Its row carries a mark of its own once
/// sleep is off, so `isEmpty` cannot be read off the rules alone; a second
/// reader for it would be a second clock, and the column would disagree with the
/// marks it makes room for.
public struct MarkableRules: Equatable, Sendable {
    /// The rules that are switched on **and drawn on this Mac**.
    public let rules: Set<ActiveCondition>
    /// Sleep is off for the whole Mac right now, because the lid is shut and
    /// somebody asked for that. Not a rule: the lid is a switch that changes the
    /// machine rather than a condition that fires.
    public let lidHolding: Bool

    /// - Parameters:
    ///   - hasBuiltInDisplay: whether the display rule's row is drawn at all.
    ///   - hasLid: whether the lid row is.
    public static func of(autoExternalDisplay: Bool, autoPower: Bool, lidHolding: Bool,
                          hasBuiltInDisplay: Bool, hasLid: Bool) -> MarkableRules {
        var rules = Set<ActiveCondition>()
        if autoExternalDisplay, hasBuiltInDisplay { rules.insert(.externalDisplay) }
        if autoPower { rules.insert(.power) }
        return MarkableRules(rules: rules, lidHolding: lidHolding && hasLid)
    }

    /// The same question with the hardware already answered.
    ///
    /// The page asks it twice — once to seed the drawn value and once live — and
    /// spelling `MacHardware` at both is the shape this whole type is about: a
    /// question that belongs to the machine, asked per call site.
    public static func onThisMac(autoExternalDisplay: Bool, autoPower: Bool,
                                 lidHolding: Bool) -> MarkableRules {
        of(autoExternalDisplay: autoExternalDisplay, autoPower: autoPower,
           lidHolding: lidHolding, hasBuiltInDisplay: MacHardware.hasBuiltInDisplay,
           hasLid: MacHardware.hasLid)
    }

    /// Whether a given rule is drawn as switched on.
    public func contains(_ condition: ActiveCondition) -> Bool { rules.contains(condition) }

    /// Nothing in this card can carry a mark, so no row is indented for one.
    public var isEmpty: Bool { rules.isEmpty && !lidHolding }
}
