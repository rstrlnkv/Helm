# What is deliberately not here

**No external dependency.** `Package.swift` declares no `dependencies:` array,
and the third-party artwork (the flags, the palette's objects) is vendored with its attribution in `NOTICE.md`. A
utility that removes files and asks for Full Disk Access is read by the person
installing it, and every dependency is a thing he has to be told about.

**No sandbox and no privileged helper.** `Resources/HelmApp/` carries an
`Info.plist` and no entitlements file, and `command grep -rn 'NSXPCConnection'
Sources` prints nothing. The modules reach `/Library`, `/etc/sudoers.d` and other
applications' bundles; a sandbox would have to be perforated until it meant
nothing, and a privileged helper is a second binary to sign, install, update and
take back — taking back what one binary changed is already
ARCHITECTURE.md § Giving everything back.

**No transport between the parts.** The host and the modules are one process and
talk through `Sources/HelmContract`, so there is no version to negotiate and no
wire compatibility to keep across a release. The `Data` payload of
`EngineCommand`/`EngineEvent` (`Sources/HelmContract/EngineMessage.swift`) only
erases a type for one generic call site and never reaches a socket, a pipe or a
second binary.

**No back-deployment.** The package declares `.macOS("26.0")` and the shipped
bundle is arm64 only. Supporting an older system means the ports grow a second path each, and there
is no second machine to prove that path on.
