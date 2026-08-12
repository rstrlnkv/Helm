// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// Which configurations Helm has no usable secret for, and what a connect should
/// do about it.
///
/// A rule fires as often as its app launches, and an automatic connect may not
/// open the System keychain (`VPNCredentialsPort`), so a Mac whose credential
/// cache is empty produced a `--nc start` that could not work at every launch —
/// three inside an hour in the report this was written for, each announcing a
/// connection nobody had. Nothing anywhere remembered «this configuration has no
/// usable secret», which is what this book is.
///
/// **It is a latch with two reverse channels, not a flag**, because the fact it
/// holds can stop being true without Helm doing anything (CLAUDE.md § Anything
/// that can stop being true on its own owns a channel to say so): a person
/// pressing Connect fills the cache, and the tunnel may come up regardless —
/// somebody raised it in System Settings, or `scutil` never needed Helm's secret
/// for it. `step` is the first channel and `reconcile` the second; without them
/// this would be a warning nobody could clear.
///
/// Internal, not public: the engine publishes `names` as `[String]`, so no other
/// target names this type (CLAUDE.md § `public` means "another target uses this").
struct VPNSecretBook: Sendable {
    private var locked: Set<String> = []

    init() {}

    /// Sorted, so a payload saying the same thing is the same bytes and the page
    /// draws in one order. The only way to ask what is in here — a `holds(_:)`
    /// beside it had no caller but a test.
    var names: [String] { locked.sorted() }

    /// What a connect does about the secret, and the book's own record of it in
    /// one step — the read and the decision are the same fact, and separating
    /// them left the caller holding «was this news» to combine by hand.
    enum Step: Equatable {
        /// Read: these go on the command line.
        case supply(VPNCredentials)
        /// Nothing to supply and nothing to say: this configuration keeps no
        /// secret Helm has to hand over.
        case nothingToSupply
        /// There is a secret and Helm did not get it. Worth one attempt — the tool
        /// may not need it, and a tunnel that comes up regardless clears this book
        /// on the very next refresh — but not worth announcing a connection over.
        case tryWithoutIt
        /// …and not worth a second. Only an automatic connect is ever refused: a
        /// person pressing Connect is the gesture the prompt exists for, and their
        /// press must reach the tool whatever this book remembers.
        case refuse
    }

    mutating func step(for read: VPNCredentialRead, name: String, automatic: Bool) -> Step {
        // Exhaustive, no `default:` — a fourth answer from the port has to be a
        // build error here rather than a silent «nothing to do».
        switch read {
        case .ready(let credentials):
            locked.remove(name)
            return .supply(credentials)
        case .notNeeded:
            locked.remove(name)
            return .nothingToSupply
        case .behindAPrompt:
            let news = locked.insert(name).inserted
            return news || !automatic ? .tryWithoutIt : .refuse
        }
    }

    /// What the connection list says, which Helm is never told directly.
    ///
    /// A tunnel that is **up** needed nothing from this book after all, and a
    /// configuration that is no longer on the machine is not something to draw a
    /// sentence about. `isConnected` rather than `isUp`: a handshake in flight is
    /// not proof the secret was accepted, and clearing on `.connecting` would take
    /// the notice away a moment before the connection failed.
    ///
    /// - Returns: whether the book changed.
    @discardableResult
    mutating func reconcile(against connections: [VPNConnection]) -> Bool {
        let keep = locked.filter { name in
            connections.contains { $0.name == name && !$0.status.isConnected }
        }
        guard keep != locked else { return false }
        locked = keep
        return true
    }
}
