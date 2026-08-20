import SwiftUI

/// A length of time, entered the way Clock enters one.
///
/// The shape is macOS's own timer: a column per unit, its abbreviation in small
/// quiet type above the figure, the figures large and light and separated by a
/// colon. It replaces a single «minutes» box, which asked somebody who wanted
/// two hours to type `120` — arithmetic the app can do and the person should
/// not have to, and a box that reads the same whether it holds 90 or 900.
///
/// **Hours and minutes, not hours-minutes-seconds.** Clock shows three because
/// Clock can count in seconds; this module's session is `startSession(minutes:)`
/// all the way down to the stored deadline, so a seconds column would take a
/// number and round it away. A field that accepts what it cannot keep is the
/// same defect as a label that names a control that does not exist.
///
/// The unit labels are the caller's, not this file's: they belong to whichever
/// module is drawing, and Helm already carries them (`"h"` / `"m"`) with the
/// same values macOS's own Clock uses — `hour_abbr` and `min_abbr` in
/// `Clock.app/Contents/Resources/Localizable.loctable` read `ч` / `мин` in
/// Russian and `Std.` / `Min.` in German, which is exactly what those two keys
/// already say.
public struct HelmDurationField: View {
    /// Splitting a duration and putting it back together, with the ceiling
    /// applied once.
    ///
    /// Out here as a nested type rather than inline in the body because it is
    /// the part that can be wrong in a way nobody sees: a person types `90`
    /// into the minutes column and means an hour and a half, and every path
    /// that carries their number has to agree about that.
    public enum Parts {
        /// Whole hours and the remainder, from a total that is clamped first —
        /// so a number that arrived from a plist cannot draw a 700-hour field.
        public static func split(_ minutes: Int, ceiling: Int) -> (hours: Int, minutes: Int) {
            let total = max(0, min(minutes, ceiling))
            return (total / 60, total % 60)
        }

        /// …and back. **The minutes column is not capped at 59.** Somebody who
        /// types `90` there has said an hour and a half, and refusing it would
        /// be the field correcting a person who was not wrong; the sum carries
        /// into the hours on the next redraw. What *is* enforced is the module's
        /// own ceiling, once, at the end — the same one `startSession` clamps
        /// to, so a number this field accepts cannot be a session the engine
        /// then quietly shortens.
        public static func total(hours: Int, minutes: Int, ceiling: Int) -> Int {
            guard hours >= 0, minutes >= 0 else { return 0 }
            // Multiplied inside the ceiling rather than after it: `hours * 60`
            // on an hours field somebody pasted `999999999` into overflows,
            // and an overflow is a trap, not a large number.
            let fromHours = min(hours, ceiling / 60 + 1) * 60
            return min(fromHours + min(minutes, ceiling), ceiling)
        }
    }

    @Binding private var minutes: Int
    private let ceiling: Int
    private let hourLabel: String
    private let minuteLabel: String

    /// What is being typed, as text, because a field mid-edit is not a number:
    /// an empty box and a box holding `0` are different states, and binding
    /// straight to an `Int` makes the first one impossible to be in — the
    /// digit you just deleted comes back as a `0` under the caret.
    @State private var hourText: String
    @State private var minuteText: String
    @FocusState private var focus: Field?

    private enum Field { case hours, minutes }

    public init(minutes: Binding<Int>, ceiling: Int,
                hourLabel: String, minuteLabel: String) {
        _minutes = minutes
        self.ceiling = ceiling
        self.hourLabel = hourLabel
        self.minuteLabel = minuteLabel
        let parts = Parts.split(minutes.wrappedValue, ceiling: ceiling)
        _hourText = State(initialValue: String(format: "%02d", parts.hours))
        _minuteText = State(initialValue: String(format: "%02d", parts.minutes))
    }

    public var body: some View {
        HStack(spacing: 6) {
            column(hourLabel, text: $hourText, field: .hours)
            // The colon carries a hidden label of its own, so it sits in the
            // *digits* row rather than being baseline-aligned with the unit
            // captions above them. Photographed without it: the colon floated
            // level with «ч» and «мин», a third of the way up the field.
            VStack(spacing: 2) {
                Text(hourLabel).font(.system(size: 11, weight: .semibold)).hidden()
                Text(":")
                    // 34 is on no step, and the step it means does not exist:
                    // the scale goes 22 · 40 and this is «the hero's figure,
                    // one down». 40 is the hero itself and 22 halves the
                    // field. Recorded by `TypeScaleRatchetTests` as an
                    // exception rather than swept into a screen redrawn.
                    .font(.system(size: 34, weight: .light).monospacedDigit())
                    .foregroundStyle(HelmText.faint)
                    .frame(height: fieldHeight)
            }
            // Furniture; VoiceOver reads the two fields by their own labels and
            // does not need a colon announced between them.
            .accessibilityHidden(true)
            column(minuteLabel, text: $minuteText, field: .minutes)
        }
        .onChange(of: hourText) { _, _ in publish() }
        .onChange(of: minuteText) { _, _ in publish() }
        // Leaving the field is when a half-typed number becomes a duration:
        // «7» in the minutes box is drawn back as «07», and an empty box as
        // «00», so what is on screen is what will be started.
        .onChange(of: focus) { _, now in if now == nil { normalize() } }
    }

    private func column(_ label: String, text: Binding<String>, field: Field) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(HelmText.faint)
                .textCase(.uppercase)
                .accessibilityHidden(true)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                // The hero's own figure, one step down: this is the same number
                // in the same module and it should not arrive in a different
                // voice from the countdown it is about to become.
                .font(.system(size: 34, weight: .light).monospacedDigit())
                .frame(width: 62, height: fieldHeight)
                .focused($focus, equals: field)
                .accessibilityLabel(label)
                .background(
                    RoundedRectangle(cornerRadius: HelmRadius.ctl, style: .continuous)
                        .fill(HelmText.quiet.opacity(focus == field ? 0.12 : 0.06))
                )
        }
    }

    /// One number for the boxes and for the colon beside them, so the three
    /// cannot drift apart when the type size is next touched.
    private var fieldHeight: CGFloat { 52 }

    private func digits(_ text: String) -> Int {
        Int(text.filter(\.isNumber).prefix(6)) ?? 0
    }

    private func publish() {
        minutes = Parts.total(hours: digits(hourText),
                              minutes: digits(minuteText),
                              ceiling: ceiling)
    }

    private func normalize() {
        let parts = Parts.split(minutes, ceiling: ceiling)
        hourText = String(format: "%02d", parts.hours)
        minuteText = String(format: "%02d", parts.minutes)
    }
}
