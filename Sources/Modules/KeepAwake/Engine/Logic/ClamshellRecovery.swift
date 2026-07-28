public enum ClamshellRecovery {
    /// Parse `pmset -g` output for the "SleepDisabled 1" state.
    public static func sleepDisabled(inPmsetOutput out: String) -> Bool {
        out.split(separator: "\n").contains { line in
            let l = line.lowercased()
            return l.contains("sleepdisabled") && l.contains("1")
        }
    }
}
