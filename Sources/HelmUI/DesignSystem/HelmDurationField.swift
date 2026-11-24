import SwiftUI

/// A length of time, entered the way Clock enters one.
///
/// The shape is macOS's own timer: a column per unit, its abbreviation in small
/// quiet type above the figure, the figures large and light, separated by a
/// colon, so nobody who wants two hours has to type `120`.
///
/// **Hours and minutes, not seconds**: the session is
/// `startSession(minutes:)` down to the stored deadline, so a seconds column
/// would take a number and round it away.
///
/// The unit labels are the caller's (`"h"` / `"m"`), with the same values as
/// Clock's own `hour_abbr` and `min_abbr`.
struct HelmDurationField: View {
    /// Splitting a duration and putting it back together, with the ceiling
    /// applied once.
    ///
    /// The part that can be wrong in a way nobody sees: a person types `90`
    /// into the minutes column and means an hour and a half, and every path
    /// that carries their number has to agree about that.
    enum Parts {
        /// Whole hours and the remainder, from a total that is clamped first —
        /// so a number that arrived from a plist cannot draw a 700-hour field.
        static func split(_ minutes: Int, ceiling: Int) -> (hours: Int, minutes: Int) {
            let total = max(0, min(minutes, ceiling))
            return (total / 60, total % 60)
        }

        /// …and back. **The minutes column is not capped at 59**: `90` means an
        /// hour and a half, and the sum carries into the hours on the next
        /// redraw. What is enforced is the module's own ceiling, once, at the
        /// end, the one `startSession` clamps to, so the engine never quietly
        /// shortens a session this field accepted.
        static func total(hours: Int, minutes: Int, ceiling: Int) -> Int {
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

    init(minutes: Binding<Int>, ceiling: Int,
                hourLabel: String, minuteLabel: String) {
        _minutes = minutes
        self.ceiling = ceiling
        self.hourLabel = hourLabel
        self.minuteLabel = minuteLabel
        let parts = Parts.split(minutes.wrappedValue, ceiling: ceiling)
        _hourText = State(initialValue: String(format: "%02d", parts.hours))
        _minuteText = State(initialValue: String(format: "%02d", parts.minutes))
    }

    var body: some View {
        HStack(spacing: 6) {
            column(hourLabel, text: $hourText, field: .hours)
            // The colon carries a hidden label of its own, so it sits in the
            // digits row rather than level with the unit captions above.
            VStack(spacing: 2) {
                Text(hourLabel).font(.system(size: 11, weight: .semibold)).hidden()
                Text(":")
                    .font(Self.digitFont)
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
                .font(Self.digitFont)
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

    /// One font for the same three. `HelmText.heroFont` one step down, with
    /// tabular digits: this is the number the countdown is about to become,
    /// and it should not arrive in another voice. 34 is off the scale, which
    /// goes 22 · 40, because 22 halves the field.
    private static let digitFont = Font.system(size: 34, weight: .light).monospacedDigit()

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
