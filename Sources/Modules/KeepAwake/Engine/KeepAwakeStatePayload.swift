import Foundation

/// The state every Keep Awake surface draws, and the one declaration of it.
///
/// Out of `KeepAwakeEngine` and still `KeepAwakeEngine.StatePayload`: an
/// extension keeps the name every reader already spells while taking a wire type
/// with a hand-written decoder out of the middle of the session logic. The name
/// is the point — the same type, not a copy — because the defect its own comment
/// records is what happens when a payload is declared twice.
extension KeepAwakeEngine {
    /// Public because the page decodes it. It was typed out again over there,
    /// matched to this one by field names across a JSON hop with no compiler
    /// in between — and a field that stops matching does not fail, it silently
    /// decodes to nothing and the screen keeps its defaults forever. That is
    /// the bug `ModuleViewModel`'s own doc comment records, shipped once and
    /// then re-created inside the modules.
    public struct StatePayload: Codable {
        public let isActive: Bool
        public let conditions: [String]
        public let clamshellActive: Bool
        public let endDate: Date?
        public let startDate: Date?
        /// A rule that applies and is being ignored. Every other field here
        /// describes a Mac being held awake; this one is the only account of a
        /// Mac that is not, while everything on screen says it should be.
        public let suppressed: Bool
        /// Defaulted, because this field arrived after the wire did and an
        /// older payload still has to decode. Absent means «no rule's trigger
        /// holds», which is the reading that shows no caption and no «Paused»
        /// note — a screen that says nothing beats a screen that says the
        /// wrong thing.
        public var triggeredConditions: [String] = []
        /// Defaulted for the same reason as the field above: it arrived after
        /// the wire did, and an older payload has to decode.
        public var holdingApps: [String] = []
        /// Defaulted like the two above: it arrived after the wire did.
        public var batteryStopped: Bool = false
        /// macOS refused to turn sleep off. Defaulted like the three above, and
        /// the default is the reading that says nothing is wrong — which is what
        /// an older payload means, since a build that did not publish this could
        /// not have asked either.
        public var lidRefused: Bool = false
        /// The lid option is off and the rule it needed is still on disk.
        public var lidGrantRemains: Bool = false

        /// **Hand-written, because the five defaults above did not do what their
        /// own comments said.**
        ///
        /// A synthesised `Decodable` ignores a stored property's initial value and
        /// requires the key regardless — and the throw is not local: `JSONDecoder`
        /// gives up on the whole document, so a payload missing one late-arriving
        /// field decodes to *nothing at all* and every screen keeps its defaults
        /// for ever. Written down as «defaulted, so an older payload still has to
        /// decode» three times, at three fields, and true of none of them; the
        /// test that says so is `testAnOlderPayloadWithoutTheFieldsStillDecodes`.
        /// `PanelLayout.Tab.init(from:)` is the same repair for the same reason,
        /// one target over.
        ///
        /// **The list of «original» fields is five, and `suppressed` is not one
        /// of them.** `git show v0.9.0` has the released declaration —
        /// `isActive`, `conditions`, `clamshellActive`, `endDate`, `startDate`
        /// — and this comment said six while `suppressed`, which arrived three
        /// weeks after that tag, was decoded with `try decode`: the very
        /// document this decoder was written to accept was the one it threw on.
        /// The three non-optional ones stay required, because a payload without
        /// `isActive` is not an older payload, it is not this payload; the two
        /// dates are `nil` in every version of it.
        /// `APayloadFromTheLastReleaseDecodesTests` fails on the next field that
        /// arrives without a default, so the list is checked rather than read.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            isActive = try c.decode(Bool.self, forKey: .isActive)
            conditions = try c.decode([String].self, forKey: .conditions)
            clamshellActive = try c.decode(Bool.self, forKey: .clamshellActive)
            endDate = try c.decodeIfPresent(Date.self, forKey: .endDate)
            startDate = try c.decodeIfPresent(Date.self, forKey: .startDate)
            suppressed = try c.decodeIfPresent(Bool.self, forKey: .suppressed) ?? false
            triggeredConditions = try c.decodeIfPresent([String].self,
                                                        forKey: .triggeredConditions) ?? []
            holdingApps = try c.decodeIfPresent([String].self, forKey: .holdingApps) ?? []
            batteryStopped = try c.decodeIfPresent(Bool.self, forKey: .batteryStopped) ?? false
            lidRefused = try c.decodeIfPresent(Bool.self, forKey: .lidRefused) ?? false
            lidGrantRemains = try c.decodeIfPresent(Bool.self,
                                                    forKey: .lidGrantRemains) ?? false
        }

        public init(isActive: Bool, conditions: [String], clamshellActive: Bool,
                    endDate: Date?, startDate: Date?, suppressed: Bool,
                    triggeredConditions: [String] = [], holdingApps: [String] = [],
                    batteryStopped: Bool = false, lidRefused: Bool = false,
                    lidGrantRemains: Bool = false) {
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
        }
    }
}
