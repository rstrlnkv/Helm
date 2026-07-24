public enum TimerPolicy {
    public enum Action: Equatable, Sendable { case deactivate, continueAsAuto }
    /// On timer expiry: if an auto condition still holds and not suppressed, keep going as auto.
    public static func onExpiry(hasAutoCondition: Bool, suppressed: Bool) -> Action {
        (hasAutoCondition && !suppressed) ? .continueAsAuto : .deactivate
    }
}
