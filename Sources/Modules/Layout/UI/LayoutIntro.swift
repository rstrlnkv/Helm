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

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s6) {
            HStack(spacing: 12) {
                HelmIconPlate(symbol: "keyboard", tint: .pink, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(LyStr.introTitle).font(.system(size: 16, weight: .semibold))
                    Text(LyStr.introSubtitle).font(HelmText.rowTitle).foregroundStyle(HelmText.quiet)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                point("textformat.abc", LyStr.introWhat)
                point("checkmark.shield", LyStr.introWhen)
                point("hand.raised", LyStr.introWhere)
                point("arrow.uturn.backward", LyStr.introUndo(gesture: gesture))
            }

            HStack {
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
        VStack(alignment: .leading, spacing: 6) {
            TextField(LyStr.tryItPlaceholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))
            Text(LyStr.tryItHint)
                .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
