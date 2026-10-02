# Giving everything back

A reset is not a deletion first. Helm can change four things outside its own two
folders, each only if the person switches it on, and three of them are given back:

- the passwordless `pmset` rule Keep Awake's closed-lid option writes under
  `/etc/sudoers.d` — taken back by the module that put it there
  (`KeepAwakeEngine.willDisable`), through an administrator dialog the person can
  decline, in which case the rule stays and Helm says so rather than reporting a
  reset that did not happen;
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

Two keychain keys stay: `com.helm.app` / `settings-seal`
(`Sources/HelmRuntime/SettingsSealKey.swift`) and `com.helm.autopilot` / `rule-seal`.
`KeychainSealKey` can read and create and not delete, and a delete on an ad-hoc-signed
bundle costs a modal dialog for each. By the time the reset reaches them the preferences
domain is gone, so what they sealed no longer exists: what remains is 32 bytes the next
launch reads as its own.

The steps are `ResetPlan.Step` — `handBackWhatIsOutsideHelm`, `giveBackTheLoginItem`,
`trashHelmsOwnFolders`, `forgetPreferences`, `relaunch` — and `ResetPlan.order` is that
order as a value; the doc comments on the first two steps say why they sit where they do,
and `Sources/HelmApp/ResetEverything.swift` carries them out. `ResetPlan.roots` names the
two folders: Helm's Application Support directory (`HelmSupport.path`) and
`~/Library/Logs/Helm`.
