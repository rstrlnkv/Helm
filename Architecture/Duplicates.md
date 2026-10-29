# Duplicates

`Sources/Modules/Duplicates/` decides which of several identical files is the extra
one, and that decision is a belief rather than a fact the disk holds. The two
beliefs, `byPlace` (the default) and `byDate`, are `KeepPolicy.swift`; one ladder
answers both what stays and why (its doc comment, read by `SurvivingCopy.swift`).

A group's size is what `CloneShare.reclaimable` (`Sources/HelmRuntime/CloneShare.swift`)
says removing it returns, not the sum of its files.

Acting on a finding re-reads the pair: `DuplicateVerification` is its own phase
beside the removal. `DuplicateVerification.Batch` memoises the survivor's reading
only, for the life of one press; the copy about to stop existing is read from disk
in full every time.

The unattended walk is narrower than the watched one: it asks
`ScanRoot.refusesDescentInHome` of every directory it meets, so the `~/Library`
subtrees macOS guards with TCC stay out of the 0600 journal
(`DuplicateScanner`'s `unattended`).

## How Duplicates' model reaches its engine

`DuplicatesViewModel` is built with the engine by the descriptor's `makeModule` and held
by the host. It calls `find`, `cancel`, `trash`, `stopRemoval` and `backgroundScan`
through its `DuplicatesWork` port, which the engine conforms to, and each is answered by
return: a search that was stopped answers nil, a removal that was stopped answers
`cancelled`. The progress of a search and of a removal goes to a sink the model hands
over with that call, an `AsyncStream` that keeps the newest tick and that the model
drains while it awaits the answer, so there is no stream on the engine and two calls in
flight need no name to be told apart. The gates stay in the engine: `trash` partitions
through `KeptCopies` and `UserFileScope`, re-reads each pair through
`DuplicateVerification`, and only then hands the path to `HelmTrash.remove`;
`DuplicatesRemovalGateTests.testAPathTheGateRefusesIsRefusedByTheEngineAndNotAttempted`
holds that a refused path is reported and never handed to the `trashing:` port, which
production sets to `HelmTrash.moveToTrash` and no test leaves to a default.

The model asks the keychain for the stored keep policy in `appear()`, which the page
calls from its `.task`, not in `init`: `makeModule` runs when the module starts. On the
person's switch and on quit the host calls the descriptor's `stop(_:)`, after which the
model reaches no work, shows no search answer still in flight and asks the keychain
nothing more except by saving a chosen folder or policy, which `stop` does not refuse;
a removal already handed to the engine still lands, and what moved before the stop is
reported. The model keeps no state for a reply that never
arrives: an answer is always a return.

A background scan and a search the person started share the engine's one finder slot, so
one begins by cancelling the other.

