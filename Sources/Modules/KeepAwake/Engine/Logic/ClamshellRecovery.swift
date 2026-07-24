public enum ClamshellRecovery {
    /// On launch, restore sleep if we recorded disabling it and pmset still shows it disabled.
    public static func shouldRestoreSleep(guardFlagSet: Bool, pmsetShowsDisabled: Bool) -> Bool {
        guardFlagSet && pmsetShowsDisabled
    }
    /// Parse `pmset -g` output for the "SleepDisabled 1" state.
    public static func sleepDisabled(inPmsetOutput out: String) -> Bool {
        out.split(separator: "\n").contains { line in
            let l = line.lowercased()
            return l.contains("sleepdisabled") && l.contains("1")
        }
    }
}
