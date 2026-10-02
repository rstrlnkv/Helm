# The gates

Five types answer five different questions about where a path may be reached,
and four of them are about reading or removing. The fifth is about writing, and
it is the only one, which is why it reads differently from its neighbours: it
answers *may Helm write this path*, over one file the user owns and Helm did not
create. This is the list of who asks which:

```bash
command grep -rn --include='*.swift' \
  -oE '(RemovableScope|UserFileScope|WatchScope|ScanRoot|SSHFileScope)\.[a-zA-Z]+' Sources/
```

`RemovableScope` (`Sources/HelmRuntime/RemovableScope.swift`) asks what belongs to an
*application*, by position rather than by blocklist; the roots it allows are printed by

```bash
sed -n '/private static func roots/,/^    }/p' Sources/HelmRuntime/RemovableScope.swift
```

`UserFileScope` (`Sources/HelmRuntime/UserFileScope.swift`) asks what belongs to the
*user*; Disk and Duplicates read it. `WatchScope`
(`Sources/Modules/Autopilot/Engine/Logic/WatchScope.swift`) is Autopilot's own and asks
where an unattended folder rule may reach. `ScanRoot` (`Sources/HelmRuntime/ScanRoot.swift`)
asks where a read nobody is watching may begin and how far it may descend. The doc comments
of `WatchScope`, `ScanRoot` and `SSHFileScope` say what the others cannot answer.

`SSHFileScope` (`Sources/Modules/Hosts/Engine/Logic/SSHFileScope.swift`) asks whether Helm
may **write** a path, and it exists because Hosts & Keys is the one module that edits a
file the user wrote by hand; `mayWrite(_:home:under:)` is the whole gate.

Paths reach `RemovableScope` and `UserFileScope` through
`Sources/HelmRuntime/PathCanonical.swift`, which resolves symlinked ancestors and leaves
the leaf alone, so a stale alias is trashed rather than chased. `ScanRoot` and the
deciding check of `SSHFileScope` use its `resolvingWholePath`, which resolves the leaf
too, because they read or write what the path points at rather than remove the name
(`PathCanonical.swift` says why for reading, `SSHFileScope`'s doc comment for writing). `WatchScope` canonicalises on its own, resolving the
whole path, leaf included, as far as it exists. `PathCanonical.ancestryIdentity(of:)` returns the device-and-inode chain that
`Sources/HelmRuntime/HelmTrash.swift` re-reads immediately before each move.

`UserFileScope` compares a path against its protected prefixes in **both** spellings,
because `NSString.standardizingPath` rewrites `/private/var/…` to `/var/…` for a path
that exists on disk and leaves it alone for one that does not, resolves no symlinks and
folds no case; `PathCanonical.withoutPrivate` is the shared spelling of the same fact.
Which gate is asked decides what the symptom looks like. Pointing the duplicate finder at
`~/Downloads` under `RemovableScope` disabled every checkbox in its own result, which
reads as a permissions problem and is a question put to the wrong gate.

A walk asks a directory's *name* and never its contents: reading a directory to decide
whether to read it is itself the Photos consent prompt (`ScanRoot.refusesDescent`). The
gate is asked of every directory a walk meets and not of the root alone
(`Sources/Modules/Duplicates/Engine/DuplicateScanner.swift`). A walk's paths are compared
against a root with `/private` stripped from both sides, because the enumerator resolves
the root's own symlinks on the way out; a gate comparing raw strings matches nothing and
fails open, silently, so such a gate is tested with paths that exist on disk. A scan that
came back with nothing because its root was refused is a nil report and never an empty
one (ARCHITECTURE.md § Background scans, where the attempt is written before the work).

What happened between a reading and the act is asked of every stored reading, and who
re-asked: a flag is the wrong question, and a reading that was true when taken is not
evidence at the moment of the act.
