public enum ExternalDisplaySupport {
    /// External display present = any online display that is not built-in.
    public static func hasExternal(builtInFlags: [Bool]) -> Bool { builtInFlags.contains(false) }
}
