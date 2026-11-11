# Giving everything back

A reset is not a deletion first. Helm can change four things outside its own two
folders, each only if the person switches it on, and three of them are given back:

- the passwordless `pmset` rule Keep Awake's closed-lid option writes under
  `/etc/sudoers.d` — taken back by the module that put it there
  (`KeepAwakeEngine.willDisable`), through `sudo -n` when the rule permits its own
  withdrawal and otherwise through an administrator dialog the person can decline.
  The reset does not wait for the answer; a rule that stays is reported by Keep
  Awake's page on the next launch, not by the reset;
- the login items Leftovers switched off with `launchctl disable`
  (`Sources/Modules/Leftovers/Engine/SystemPorts.swift`) — switched back on from the
  module's own record of what it disabled;
- Helm's own registration in the login-item database
  (`LoginItem.setEnabled` in `Sources/HelmApp/LoginItem.swift`) — unregistered as a step
  of the plan, because the application registered it and no module owns it;
- ownership of `/opt/homebrew`, changed by the in-app Homebrew installer
  (`installBrew`, in `Sources/Modules/Homebrew/Engine/HomebrewEngine.swift`). **This one is
  not given back.** Helm does not record who owned the tree before, and handing it
  back to root would leave a `brew` that cannot install anything without `sudo`
  — the ownership is what Homebrew needs, and it is what Homebrew's own
  installer does on any Mac.

The launchd give-back has an edge that cannot be closed from here: a label the
person disabled themselves *after* Helm disabled it is indistinguishable from
Helm's own, so it is switched back on too.

Keychain items stay: the two seal keys `com.helm.app` / `settings-seal`
(`Sources/HelmRuntime/SettingsSealKey.swift`) and `com.helm.autopilot` / `rule-seal` (Helm Dev: `dev-rule-seal`),
and the counter `com.helm.autopilot` / `rule-seq` (Helm Dev: `dev-rule-seq`).
`KeychainSealKey` can read and create and not delete, and a delete on an ad-hoc-signed
bundle costs a modal dialog for each. By the time the reset reaches them the preferences
domain is gone, so what they sealed no longer exists: what remains of a key is 32 bytes the next
launch reads as its own.

The VPN module's cached credentials (`com.helm.vpn`, accounts `<uuid>.ss` and
`<uuid>.pw`, `Sources/Modules/VPN/Engine/SystemPorts.swift`) are not a step of the
plan, and they do not stay either: the reset trashes the marker
`CredentialCachePurge` keeps in Helm's Application Support folder, so the next launch with
the module on deletes every item of that service once more and the next connect reads the System
keychain again.

The steps are `ResetPlan.Step` — `handBackWhatIsOutsideHelm`, `giveBackTheLoginItem`,
`trashHelmsOwnFolders`, `forgetPreferences`, `relaunch` — and `ResetPlan.order` is that
order as a value; the doc comments on the first two steps say why they sit where they do,
and `Sources/HelmApp/ResetEverything.swift` carries them out. `ResetPlan.roots` names the
two folders: Helm's Application Support directory (`HelmSupport.path`) and
`~/Library/Logs/Helm`. `ResetEverything.run` does nothing, and logs why, while an engine says
`standsIn` (`ModuleEngine`): a stand-in has nothing to hand back, and the reset would forget the
settings that say the real module ran.
