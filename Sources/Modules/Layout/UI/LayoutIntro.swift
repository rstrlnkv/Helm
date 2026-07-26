import SwiftUI
import HelmRuntime
import HelmUI

/// What this module is, said once, before it starts changing what you type.
///
/// Shown the first time the page is opened rather than at install: a module
/// that rewrites words in other applications should explain itself to the
/// person who went looking for it, at the moment they did — not in a queue of
/// notices on first launch that nobody reads.
struct LayoutIntro: View {
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                HelmIconPlate(symbol: "keyboard", tint: .pink, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(LyStr.introTitle).font(.title3.weight(.semibold))
                    Text(LyStr.introSubtitle).font(.callout).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                point("textformat.abc", LyStr.introWhat)
                point("checkmark.shield", LyStr.introWhen)
                point("hand.raised", LyStr.introWhere)
                point("arrow.uturn.backward", LyStr.introUndo)
            }

            HStack {
                Spacer()
                Button(LyStr.introStart, action: onDone)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 18)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
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
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
