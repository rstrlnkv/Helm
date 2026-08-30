import SwiftUI
import HelmUI

/// What this module is, said once, before it starts changing what you type.
///
/// Shown the first time the page is opened rather than at install: a module
/// that rewrites words in other applications should explain itself to the
/// person who went looking for it, at the moment they did — not in a queue of
/// notices on first launch that nobody reads.
struct LayoutIntro: View {
    /// The undo gesture as bound right now — a key name or a chord label,
    /// nil when neither exists. An automatic conversion is a change the person
    /// pressed no key for, so «tap the same key again» named nothing; the
    /// intro names the actual key or stops promising an undo it cannot offer.
    let gesture: String?
    let onDone: () -> Void

    init(gesture: String?, onDone: @escaping () -> Void) {
        self.gesture = gesture
        self.onDone = onDone
    }

    /// Open only when somebody asks. The four points are 306 pt in Russian —
    /// measured inside a real grouped `Form` at 744 pt, against 274 in English
    /// — so the module's own figure and every one of its settings started below
    /// the fold on the one visit where a person is deciding whether to trust it
    /// at all. The preamble and the verb stay; the explanation is a press away.
    @State private var open = false
    @State private var pointsHeight: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s5) {
            // **The block said the page's own name back to it, in a second
            // colour.**
            //
            // This opened with a 44 pt plate carrying the `keyboard` glyph in a
            // raw `.pink`, and the word `L("Keyboard")` beside it — 140 pt under
            // a page header drawing the same glyph in the module's magenta over
            // the same word. Two plates, two colours, one symbol, one screen,
            // and an introduction whose first line told you which page you were
            // already on.
            //
            // **Both halves of the repeat go, not just the colour.** Tinting the
            // plate correctly would have left two plates with one glyph on one
            // screen, which is the picture the finding is about; and the
            // sentence under it cannot be promoted into the vacancy, because in
            // seven of the eight languages it is a subordinate clause —
            // «Before it starts changing what you type.» — that reads as a
            // subtitle and not as a heading. Only the Russian was ever written
            // as a whole sentence, and one language is not a reason to set the
            // other seven as titles. So it stays a preamble, and the block
            // opens on it.
            Text(LyStr.introSubtitle)
                .font(HelmText.rowTitle).foregroundStyle(HelmText.quiet)
                .fixedSize(horizontal: false, vertical: true)

            // A reveal grows, never fades: `helmAccordion` measures the block
            // and animates the frame to it (ARCHITECTURE.md § Motion).
            VStack(alignment: .leading, spacing: HelmSpace.s5) {
                point("textformat.abc", LyStr.introWhat)
                point("checkmark.shield", LyStr.introWhen)
                point("hand.raised", LyStr.introWhere)
                point("arrow.uturn.backward", LyStr.introUndo(gesture: gesture))
                    .padding(.bottom, HelmSpace.s3)
            }
            .helmAccordion(open: open, height: $pointsHeight)

            HStack(spacing: HelmSpace.s5) {
                Button(open ? LyStr.introLess : LyStr.introMore) {
                    withAnimation(HelmMotion.disclosure) { open.toggle() }
                }
                Spacer()
                Button(LyStr.introStart, action: onDone)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        // No fixed width and no padding of its own: this is drawn as the first
        // section of the page now rather than in a sheet, and the form row it
        // sits in owns the margins. As a sheet it was five extra `NSWindow`s per
        // offscreen render and nothing of the first screen a new user sees
        // inside the page's own layers.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: HelmSpace.s5) {
            Image(systemName: symbol)
                .frame(width: 18)
                .foregroundStyle(HelmText.quiet)
                .accessibilityHidden(true)
            Text(text)
                .font(HelmText.rowTitle)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A place to try it without risking anything you were writing.
///
/// The module works in Helm's own window like anywhere else, so this is a real
/// test rather than a simulation — which is the point: a demonstration that
/// cheats teaches the wrong thing about when it fires.
struct LayoutTestField: View {
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s3) {
            TextField("", text: $text, prompt: Text(LyStr.tryItPlaceholder))
                .accessibilityLabel(LyStr.tryItPlaceholder)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            Text(LyStr.tryItHint)
                .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
