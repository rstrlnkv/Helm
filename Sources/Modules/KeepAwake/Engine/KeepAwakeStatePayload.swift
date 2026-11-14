import Foundation

/// The state every Keep Awake surface draws, and the one declaration of it.
///
/// Out of `KeepAwakeEngine` and still `KeepAwakeEngine.StatePayload`: an
/// extension keeps the name every reader already spells while taking the payload
/// out of the middle of the session logic. The name is the point — the same type,
/// not a copy — because the defect its own comment records is what happens when a
/// payload is declared twice.
extension KeepAwakeEngine {
    /// Public because the model reads it from `stream()`. Declared a second
    /// time over there it would be two declarations of one fact, and a field
    /// added to one and not the other would compile and leave the screen on its
    /// defaults.
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

        init(isActive: Bool, conditions: Set<ActiveCondition>, clamshellActive: Bool,
                    endDate: Date?, startDate: Date?, suppressed: Bool,
                    triggeredConditions: Set<ActiveCondition> = [], holdingApps: [String] = [],
                    batteryStopped: Bool = false, lidRefused: Bool = false,
                    lidGrantRemains: Bool = false, assertionRefused: Bool = false) {
            self.isActive = isActive
            self.conditions = conditions
            self.clamshellActive = clamshellActive
            self.endDate = endDate
            self.startDate = startDate
            self.suppressed = suppressed
            self.triggeredConditions = triggeredConditions
            self.holdingApps = holdingApps
            self.batteryStopped = batteryStopped
            self.lidRefused = lidRefused
            self.lidGrantRemains = lidGrantRemains
            self.assertionRefused = assertionRefused
        }
    }
}
