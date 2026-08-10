public enum ExternalDisplaySupport {
    /// External display present = any online display that is not built-in.
    ///
    /// **`[false]` is ambiguous and is deliberately read as «yes».** It is what
    /// a desktop Mac reports — it has no built-in display, so the rule is
    /// unconditionally true there and «keep awake with an external display»
    /// amounts to «never sleep». It is *also* what a laptop reports with the
    /// lid shut: the built-in goes offline and only the dock's monitor is left.
    /// That second case is the whole reason this rule exists, so the reading
    /// that serves it wins.
    ///
    /// A review proposed requiring a built-in among them, which fixes the
    /// desktop and breaks the laptop. Telling the two apart needs a fact
    /// `CGGetOnlineDisplayList` does not carry — whether this Mac has a
    /// built-in panel at all, not whether one is awake — so the honest fix is
    /// a hardware reading, not a change of rule here.
    public static func hasExternal(builtInFlags: [Bool]) -> Bool { builtInFlags.contains(false) }
}
