import AppKit
import SwiftUI

/// **The one way a page asks for a search control.**
///
/// The control is the window's, not the page's: `.searchable` declares it here
/// and `SettingsSplitViewController`'s `sceneBridgingOptions` carries it out of
/// the pane into the window's toolbar, where macOS 26 and later draw it as
/// Liquid Glass. Measured on macOS 27 (2026-09-20): the bridged item arrives as
/// `com.apple.SwiftUI.search` / `AppKitSearchToolbarItem`, an
/// `NSSearchToolbarItem` carrying a real `NSSearchField`, and **the prompt is
/// carried whole** — `placeholderString` reads back exactly what was handed in.
/// That is worth saying because the neighbouring bridge is not so kind: the one
/// that carries a pane's toolbar into the window carries its subtitle and drops
/// its title, which is why `SettingsWindow` sets the window's title by hand.
///
/// **The collapsed magnifier cannot be asked for on macOS, and arrives anyway.**
/// `SearchToolbarBehavior.minimize` is `@available(macOS, unavailable)` — only
/// `.automatic` exists here — so nothing in this file decides the control's
/// shape. AppKit decides it from the width the toolbar has left over: room, and
/// the field is drawn open; no room, and it is a magnifier that opens on a
/// click. Neither a `SearchToolbarBehavior` nor a hand-rolled button of our own
/// can move that, so neither is here.
///
/// **What the bridge does not carry is a name.** `accessibilityLabel()` on the
/// mounted field is nil in every state — empty, typed into, collapsed — and a
/// SwiftUI `.accessibilityLabel` on the searchable view does not reach it: the
/// field is AppKit's, built by the bridge, and never in this view's tree at all.
/// So the name is restored from AppKit, where the field actually is:
/// `ToolbarSearchName` in the app layer names every bridged field the window's
/// toolbar takes, and `ASearchFieldSaysWhatItIsTests` reads it back off the
/// mounted control.
///
/// **And what it does not carry either is a history**, which would be a leak
/// rather than a gap. An `NSSearchField` handed a `recentsAutosaveName` persists
/// the words searched for into the user defaults domain under that key, where
/// any process running as this user can read them — and the two bars this app
/// has are typed with the names of somebody's applications and the packages they
/// went looking for. Nothing here can ask for one: `.searchable` exposes no such
/// API and the control is the framework's. Measured on macOS 27 (2026-09-21) on
/// the mounted field: `recentsAutosaveName` nil and `recentSearches` empty at
/// mount, after typing and after a Return that fired the submit.
/// `ASearchKeepsNoHistoryOfWhatWasTypedTests` reads both back off the control
/// and carries the canary that shows what a name on this very field would cost,
/// because an SDK is free to change this under us without a word.
///
/// `prompt` is a `String` rather than a `Text` for the reason every visible
/// string in this target is one: the English text is the key.
public extension View {

    /// Search for what this view is showing, in the window's toolbar.
    ///
    /// - Parameter onSubmit: run on Return and on Return only. Measured on the
    ///   bridged field (2026-09-20): four keystrokes moved the binding four
    ///   times and this closure ran zero times; one Return ran it once. That
    ///   distinction is the whole reason the parameter exists — Homebrew's
    ///   search is two `brew search` runs over the network, and a page that ran
    ///   them per keystroke would put four of them out to spell «wget».
    func helmSearchable(text: Binding<String>, prompt: String,
                        onSubmit: (() -> Void)? = nil) -> some View {
        searchable(text: text, placement: .toolbar, prompt: Text(prompt))
            .onSubmit(of: .search) { onSubmit?() }
    }
}
