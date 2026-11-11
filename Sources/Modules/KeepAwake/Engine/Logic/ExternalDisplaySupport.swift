enum ExternalDisplaySupport {
    /// External display present = any online display that is not built-in.
    ///
    /// **`[false]` is ambiguous and is deliberately read as «yes».** It is what
    /// a desktop Mac reports — it has no built-in display — and *also* what a
    /// laptop reports with the lid shut: the built-in goes offline and only the
    /// dock's monitor is left. That second case is the whole reason this rule
    /// exists, so the reading that serves it wins.
    ///
    /// Requiring a built-in among them would fix the desktop and break the
    /// laptop, so the two are not told apart here. The callers do it with a
    /// hardware fact this list does not carry: the engine asks
    /// `lidInfo.hasLid()` first (`externalDisplayCondition`, `holdingAppRules`),
    /// so on a Mac with no lid the rule is false whatever this answers.
    static func hasExternal(builtInFlags: [Bool]) -> Bool { builtInFlags.contains(false) }
}
