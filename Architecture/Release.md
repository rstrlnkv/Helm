# Release

The number is `MAJOR.MINOR.PATCH`. It lives in one place,
`Resources/HelmApp/Info.plist` under `CFBundleShortVersionString`, and
`/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/HelmApp/Info.plist`
is what the tree currently says it is. `CFBundleVersion` in that file is a placeholder:
`Scripts/package-app.sh:222` computes the build number as `git rev-list --count HEAD`
(`--no-replace-objects` and `-c core.commitGraph=false` alongside it, so neither a
replacement ref nor a forged or stale commit-graph cache can shorten the history it
walks), after refusing a checkout whose history cannot be trusted — none at all; a
shallow clone, which exits 0 having counted only the commits it fetched; a tree that is
not git's own top level, one whose own `.git` an ancestor's `core.worktree` can stand in
for, or one steered by a `GIT_DIR`/`GIT_WORK_TREE` from the environment; or a history a
graft or a replacement ref has given a shorter parent chain — rather than substituting a
number. The gate announces what it computed (`==> Build number: N`) right after, before
the compile it guards, and `Scripts/package-app.sh:298` writes the same number into the
plist *of the assembled bundle*, so the tree's copy and a shipped bundle's copy disagree
by design.

A release tag is `vMAJOR.MINOR.PATCH`; a prerelease tag is `vMAJOR.MINOR.PATCH-dev.N`.
`git tag --list 'v*' --sort=v:refname` is the list and `git tag --list 'v*' | wc -l` the
count. `-dev` is the only suffix the scheme has: `UpdateVersion.prereleaseOrdinal`
reads the trailing number of the suffix and nothing else, so `-dev.2` and `-beta.2` are
indistinguishable to it.

MAJOR marks a milestone — a new architecture, a breaking redesign. MINOR is a new
capability or a reworking of an existing one. PATCH is a fix, and it is also the step of
a **numbered line**: one MINOR's worth of work cut into releases that ship one at a time.
A MINOR bump resets PATCH to zero, a MAJOR bump resets both. What makes a line a line
rather than a licence to call any feature a patch is that the whole series — which
releases, in what order, where it ends — is written down before the first of them ships.
`CHANGELOG.md` names the line in one italic line under the first section heading it
ships; that italic line is the only prose a section there gets, and
`command grep -c '^\*[^*]' CHANGELOG.md` counts them against
`command grep -c '^## ' CHANGELOG.md` version headings.

While the number is `0.x`, MINOR is the lane the work runs in. `1.0.0` is reserved for a
Developer ID and notarization — the build opening without `xattr` — plus a settled module
set: "1.0" is the claim that the program is ready for other people.

## Channels and publishing

Two releases carrying one version are invisible to the updater: `UpdateVersion.isNewer`
requires a strictly greater version, so a release without a bump reaches nobody, and
nothing published can pull a user back to an earlier build — there is no rollback, and
that is the shape of the comparison rather than a missing feature.

There are two channels, `beta` and `dev`, and `UpdateCheck.Channel` is where they and
the reason for the name `beta` live. In the app the switch is About → Update channel,
and switching re-checks at once.

Everything reaches the dev channel first, as a `vX.Y.Z-dev.N` prerelease, and the same
code goes out as the beta `vX.Y.Z` release once the count of known problems is zero. A dev
build writes its log itself and a beta build does not (ARCHITECTURE.md § Diagnostics log),
so the dev round is the only round with evidence in it to triage against `helm.log`. A
`-dev.N` prerelease leaves the beta numbering alone: the eventual `vX.Y.Z` supersedes
every `-dev.N` before it. Two consequences of that arrangement look like faults and are
not. A release published with `--prerelease` is invisible to the Beta channel, because
`releases/latest` skips every prerelease — so the flag, or its absence, is what decides
reachability rather than presentation. And in the window between a beta shipping and the
next `-dev` build being cut, the newest entry in the whole releases list *is* the beta, so
the Dev channel answers "up to date" and is right.

One release is one `CHANGELOG.md` section, one git tag, and both a `.dmg` and a `.zip`
attached with a `sha256` line for each in the notes, which `Scripts/make-zip.sh` and
`Scripts/make-dmg.sh` each print. The zip is what the in-app updater downloads for a
silent install; the dmg is the manual drag-install path.

`Scripts/package-app.sh:258` builds `swift build -c release --product HelmApp`, assembles
and signs in `$TMPDIR/helm-package`, and leaves a copy in `build/` for inspection. Only the signed copy under `$TMPDIR` is
installed: it is the bundle the script signed and verified, while `.build/` holds an
unsigned one with no usable identity at all. `Scripts/make-dmg.sh` and
`Scripts/make-zip.sh` package that signed bundle and refuse one that does not verify.
`Scripts/package-dev.sh` builds through `Scripts/package-app.sh` and installs **Helm Dev**
beside the real app; its header says why a separate bundle. The release scripts are
`Scripts/package-app.sh`, `Scripts/make-dmg.sh`, `Scripts/make-zip.sh` and
`Scripts/package-dev.sh`; `Scripts/flags` and `Scripts/design` produce nothing
that ships on their own, and neither does `Scripts/test.sh`.

The push comes before the release is created, never after: the release is tagged against
the remote HEAD, so an unpushed commit puts the tag on the wrong one. A bad dev build is
undone by publishing the next dev number with the reverted code and its digest lines,
never by deleting or re-tagging a release people may have downloaded. A prerelease user
who switches to Beta sees "up to date", because Beta reads the last non-prerelease tag,
which is lower than what they are running, so the switch appears to do nothing until the
next beta passes them.

Before a release the tree is built from a fresh `git clone`: the manifest is refused whole
when a declared test path does not exist, so an untracked test directory makes `swift
test` work in one checkout and on nobody else's, and the working copy is not evidence.

## Signing and grants

The checkout stays out from under a file provider (iCloud Drive, Dropbox and the like) and
is signed from the staged path `Scripts/package-app.sh` prints, never in place: a provider
stamps `com.apple.FinderInfo` onto the directories it manages faster than `xattr -c`
clears it, and `codesign` refuses a bundle carrying it. An unsigned bundle has no cdhash
for TCC to hang Full Disk Access on, so the permission comes loose on every rebuild. A
passing strict signature verification says the bundle is valid and not that it is the
same program TCC granted.

`Scripts/package-app.sh:327` signs ad-hoc (`--sign -`) unless the Mac building it
names an identity of its own (`Scripts/signing-identity.sh`), and a release is always
ad-hoc — `Scripts/make-zip.sh` and `Scripts/make-dmg.sh` refuse anything else. An ad-hoc
bundle carries no Team ID and macOS ties a granted permission to the exact binary. A
cdhash is a hash of contents, so every rebuild is a different program to TCC while the
checkbox in System Settings stays ticked. A grant therefore survives relaunch and
reboot — the installed binary's cdhash changes only when it is replaced — and every
reinstall costs both toggles again. `AppBuild` (`Sources/HelmRuntime/AppBuild.swift`)
is where the app asks what copy of itself it is; its doc comments say why a version
string cannot answer what the cdhash answers.

A stable signing identity is the only real fix, and the same purchase is what
`NEVPNManager`, an `SMAppService` helper and notarization each need.

## The updater

`Sources/HelmApp/UpdateService.swift` carries the networking and the published state;
`UpdateCheck.evaluate` is pure and tested; `Installer.installZip` does the install, and
`UpdateSwap` and `UpdateHandoff` (`Sources/HelmApp/UpdateSwap.swift`) are the detached
swap and the note a failure is reported by at the next launch. Their doc comments hold
the reasons: why the app downloads the zip itself, why the old bundle is moved aside
before the copy, and why the note is written before the app quits.

Nothing installs without a published digest. The updater strips quarantine on purpose and
the app is ad-hoc signed, so `codesign --verify` proves nothing — any ad-hoc signature
passes, and TLS protects the transport rather than the contents. No digest for this exact
asset name opens the release page with the reason stated, and a digest that disagrees
refuses the install outright (`ReleaseDigest`, `Sources/HelmRuntime/ReleaseDigest.swift`),
and the unpacked bundle's own version is re-read as well, so a mislabelled asset cannot
be swapped in either.

## What shipped

`CHANGELOG.md` at the root of the tree is the canonical English record and is not
bundled — nothing in `Scripts/package-app.sh` or `Package.swift` names it.
`Sources/HelmApp/ChangelogData.swift` is the same list inside the app. A version heading in
the file is `## X.Y.Z — YYYY-MM-DD`, one line per change with `**NEW**` / `**UPD**` /
`**FIX**` first, newest version first. `command grep -c '^### ' CHANGELOG.md` prints zero:
the file carries no sub-headings at all.

The text of a changelog entry is written for the person who updated and is not part of
making the code change. An entry that names a control is read against the running app and
not only for grammar, because the English string is the key: a wrong name is faithfully
translated into all seven other languages, and the fix is one key deleted and rewritten in
eight files.

## The disk image window

`Scripts/make-dmg.sh` builds a laid-out window rather than a bare folder. The background
is generated at build time by `Scripts/design/make-dmg-background.swift` and the layout
lives in `Scripts/dmg-settings.py`; the two hold the same slot coordinates seen from
opposite sides, and each says so in its own comment. The reasons for the three drawings,
the ring radius and the chevron's place, the dev mark, and why `dmgbuild` writes the
window instead of Finder are in those two files and the header comments of
`Scripts/make-dmg.sh`.

Two numbers there announce nothing when wrong, and `Scripts/dmg-settings.py` says why at
each: `window_rect` is the *window's*, so it is the background's height plus the title bar,
and `text_size` has a floor below which Finder rejects the settings wholesale, with no
complaint.

A disk image is judged by mounting it and never by reading the script, which always
finishes and always prints something that looks like a result. The mounted volume's Finder
settings file is well over the size of an untouched one when the settings took; a file of
an untouched one's size is the tell that Finder wrote a default and the settings were
lost; the volume carries the custom-icon flag; and a
strict signature verification still passes on the app *inside* the image. A new background
is judged against a composite of the real icons and their real labels and not against the
empty artwork, because Finder writes the item's name under the icon and the first bezel ran
straight through the word.
