import SwiftUI
import HelmUI
import Module_Screenshots_Engine

/// The thickness and opacity pop-over: two sliders and the number of each, on glass like the palette it stands under (or above, when there is no room under).
///
/// **Thickness** snaps to the three steps of the chosen tool and says the step's points (`AnnotationThickness.points(for:)`);
/// **Opacity** runs 0.1…1 and says a whole percent. Both edit `EditorBarModel.picked`, the next object's style, through
/// the editor's one door, so a pick is remembered for the chosen tool alone like any other.
///
/// **It appears by a clipped, measured height**, the reveal of `HelmAccordion.swift` written out here and **not** its
/// `helmAccordion`: that modifier measures the height itself and keeps it in the view's own state, and this card's height is
/// needed by the AppKit host before the view exists (to size the panel's window), so the host measures it and passes it in
/// as `height`. The card is laid out whole, and the frame grows between 0 and that number inside
/// `HelmMotion.disclosure`, which is instant under Reduce Motion. The glass is applied outside the clip, so it is
/// the revealed height that is glass. Inside it the ink is `ink`, a literal primary colour with an opacity,
/// because a hierarchical style resolves differently while the clip's layer exists.
struct EditorPopover: View {
    @ObservedObject var model: EditorBarModel
    /// The card's measured height, which the frame grows to; nil lays the card out whole, which is how it is measured.
    let height: CGFloat?
    /// What is drawn, against what the model says: written only in a transaction of its own, so the first open plays
    /// the reveal and a later one does too.
    @State private var shown = false

    static let width: CGFloat = 232

    /// The number's ink, a literal primary colour with an opacity, for the reason the card gives. Measured by designer, by
    /// window capture of a test window, at opacity 0.70: 4.44:1 and 4.49:1 on light glass over a dark backdrop (the
    /// darkest ones), 4.88:1 on the r9 glass, 6.6:1 on dark glass; 4.5:1 is what a 13 pt figure answers to. 0.76 is
    /// **predicted, not re-measured**: taking the 4.44:1 fill as a neutral grey and the ink as black at that opacity, it
    /// gives about 4.9:1 on the darkest backdrop; dark glass, which only rises with the ink, is not re-measured either.
    private static let ink = Color.primary.opacity(0.76)

    /// The tool whose steps are shown. The pop-over opens only with a tool chosen; the pen is the answer for the
    /// instant after that tool was put down, while the card is still on its way out.
    private var tool: AnnotationTool { model.tool ?? .pen }

    var body: some View {
        card
            .fixedSize(horizontal: false, vertical: true)
            .frame(height: height.map { shown ? $0 : 0 }, alignment: .top)
            .clipped()
            .glassEffect(.regular, in: .rect(cornerRadius: HelmRadius.frame))
            .allowsHitTesting(shown)
            .accessibilityHidden(!shown)
            .frame(maxHeight: height == nil ? nil : .infinity, alignment: .top)
            .onAppear { withAnimation(HelmMotion.disclosure) { shown = model.popoverOpen } }
            .onChange(of: model.popoverOpen) { _, open in withAnimation(HelmMotion.disclosure) { shown = open } }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s6) {
            row(ScStr.thicknessLabel, number: Self.thicknessText(model.picked.thickness, for: tool)) {
                Slider(value: thickness, in: 0...Double(AnnotationThickness.allCases.count - 1), step: 1) { Text(ScStr.thicknessLabel) }
            }
            row(ScStr.opacityLabel, number: Self.opacityText(model.picked.opacity)) {
                Slider(value: opacity, in: 0.1...1) { Text(ScStr.opacityLabel) }
            }
        }
        .padding(.horizontal, HelmSpace.s5 + HelmSpace.s1)
        .padding(.top, HelmSpace.s5)
        .padding(.bottom, HelmSpace.s6 + HelmSpace.s3)
        .frame(width: Self.width)
    }

    private func row(_ name: String, number: String, @ViewBuilder slider: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: HelmSpace.s4) {
            HStack {
                Text(name)
                Spacer(minLength: HelmSpace.s4)
                Text(number).font(HelmText.rowTitle.weight(.medium)).foregroundStyle(Self.ink).monospacedDigit()
            }
            .font(HelmText.rowTitle)
            slider()
                .labelsHidden()
                .accessibilityLabel(name)
                .accessibilityValue(number)
        }
    }

    /// A step is a whole number on the slider; a value that does not change the step sends nothing.
    private var thickness: Binding<Double> {
        Binding {
            Double(model.picked.thickness.rawValue)
        } set: { value in
            guard let step = AnnotationThickness(rawValue: Int(value.rounded())), step != model.picked.thickness else { return }
            model.perform(.thickness(step))
        }
    }

    /// Whole percents: the number beside the slider is whole, so the value it sets is.
    private var opacity: Binding<Double> {
        Binding {
            model.picked.opacity
        } set: { value in
            let whole = (value * 100).rounded() / 100
            if whole != model.picked.opacity { model.perform(.opacity(whole)) }
        }
    }

    // MARK: The numbers

    /// The language Helm speaks, not the Mac's region: the decimal mark follows the first, like the words beside it. A
    /// format style is a value and holds no cache, so a language changed between two captures is read at once.
    private static var locale: Locale { Locale(identifier: AppLanguage.current.rawValue) }

    /// «1.5 pt»: the step's points in the language's own decimal mark and the unit macOS writes for points in that language
    /// (Ruler's `pt`: «пт» in Russian, «点» in Chinese, `pt` in the rest), an unbreakable space before it where the language
    /// puts one — Chinese puts none.
    static func thicknessText(_ step: AnnotationThickness, for tool: AnnotationTool) -> String {
        let points = Double(step.points(for: tool)).formatted(.number.precision(.fractionLength(0...1)).locale(locale))
        return L("\(points)\u{00A0}pt", [.ru: "\(points)\u{00A0}пт", .es: "\(points)\u{00A0}pt", .fr: "\(points)\u{00A0}pt", .de: "\(points)\u{00A0}pt",
                                         .ja: "\(points)\u{00A0}pt", .zh: "\(points)点", .pt: "\(points)\u{00A0}pt"])
    }

    /// «100 %»: a whole percent, with the space or none that the language puts before the sign.
    static func opacityText(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }
}
