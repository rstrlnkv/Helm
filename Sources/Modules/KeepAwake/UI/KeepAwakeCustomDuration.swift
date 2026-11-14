import SwiftUI
import HelmUI
import Module_KeepAwake_Engine

/// The free-form duration prompt of both surfaces: the page's «Other…» starts
/// a session, the panel's only remembers the length. One range, the longest
/// session `startSession` accepts; the caller says its verb and what it does.
struct KeepAwakeCustomDuration: View {
    /// The editor's highest entry; a test holds it to the engine's longest session.
    static let ceiling = TimerPolicy.longestSessionMinutes

    @Binding var minutes: Int
    let verb: String
    let apply: () -> Void

    /// The prompt as built; a test reads the ceiling it was given.
    var prompt: HelmDurationPrompt {
        HelmDurationPrompt(KAStr.customTimeTitle, minutes: $minutes,
                           ceiling: Self.ceiling,
                           hourLabel: KAStr.hoursUnitShort,
                           minuteLabel: KAStr.minutesUnitShort,
                           verb: verb, apply: apply)
    }

    var body: some View { prompt }
}
