import SwiftUI

/// The content of a popover that asks «for how long»: a title,
/// `HelmDurationField` and one verb.
///
/// Zero is never a duration here: the verb is disabled at 0, and what 0 would
/// mean (Indefinite, or nothing) is the caller's to say — its `apply` is not
/// reached with it.
public struct HelmDurationPrompt: View {
    private let title: String
    @Binding private var minutes: Int
    private let ceiling: Int
    private let hourLabel: String
    private let minuteLabel: String
    private let verb: String
    private let apply: () -> Void

    public init(_ title: String, minutes: Binding<Int>, ceiling: Int,
                hourLabel: String, minuteLabel: String, verb: String,
                apply: @escaping () -> Void) {
        self.title = title
        self._minutes = minutes
        self.ceiling = ceiling
        self.hourLabel = hourLabel
        self.minuteLabel = minuteLabel
        self.verb = verb
        self.apply = apply
    }

    public var body: some View {
        VStack(spacing: HelmSpace.s5) {
            Text(title).font(HelmText.sectionHeading)
            HelmDurationField(minutes: $minutes, ceiling: ceiling,
                              hourLabel: hourLabel, minuteLabel: minuteLabel)
            Button(verb, action: apply)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(minutes == 0)
        }
        .padding(HelmSpace.s6)
        // The field's two columns and their unit labels; the width is not
        // measured per language.
        .frame(width: 230)
    }
}
