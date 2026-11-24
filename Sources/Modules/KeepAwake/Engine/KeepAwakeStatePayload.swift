import Foundation

/// The state every Keep Awake surface draws, and the one declaration of it.
///
/// An extension, so the payload keeps the name `KeepAwakeEngine.StatePayload`
/// while living outside the session logic.
extension KeepAwakeEngine {
    /// Public because the model reads it from `stream()`. Declared a second
    /// time over there, a field added to one and not the other would compile and
    /// leave the screen on its defaults.
    public struct StatePayload: Sendable, Equatable {
        public let isActive: Bool
        public let conditions: Set<ActiveCondition>
        public let clamshellActive: Bool
        public let endDate: Date?
        public let startDate: Date?
        /// A rule that applies and is being ignored. Every other field here
        /// describes a Mac being held awake; this one is the only account of a
        /// Mac that is not, while everything on screen says it should be.
        public let suppressed: Bool
        /// Defaulted: empty means «no rule's trigger holds», which is the reading
        /// that shows no caption and no «Paused» note — a screen that says
        /// nothing beats a screen that says the wrong thing.
        public var triggeredConditions: Set<ActiveCondition> = []
        public var holdingApps: [String] = []
        public var batteryStopped: Bool = false
        /// macOS refused to turn sleep off. The default is the reading that says
        /// nothing is wrong.
        public var lidRefused: Bool = false
        /// The lid option is off and the rule it needed is still on disk.
        public var lidGrantRemains: Bool = false
        /// IOKit refused the sleep assertion, so the Mac sleeps on schedule while
        /// the session runs. The default says nothing is wrong.
        public var assertionRefused: Bool = false
    }
}
