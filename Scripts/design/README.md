# Looking at it, instead of imagining it

`shoot.sh <module> <WxH> <out.png>` opens Helm's settings window at a given
size on a given page and photographs it, cropped to the window.

```bash
bash Scripts/package-app.sh
bash Scripts/design/shoot.sh disk 1060x700 /tmp/disk.png
bash Scripts/design/shoot.sh disk 860x540  /tmp/disk-narrow.png
```

It needs the env-gated hook in `AppDelegate` (`HELM_DEBUG_SHOT`), which is
**not** committed — `grep -r HELM_DEBUG Sources/` must come back clean. Add it
for the session, take the pictures, take it out again:

```swift
if let shot = ProcessInfo.processInfo.environment["HELM_DEBUG_SHOT"] {
    let parts = shot.split(separator: ":")
    let size = parts.count > 1 ? parts[1].split(separator: "x").compactMap { Double($0) } : []
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
        self?.statusController?.debugShowSettings(
            selecting: parts.first.map(String.init),
            size: size.count == 2 ? NSSize(width: size[0], height: size[1])
                                  : NSSize(width: 1060, height: 700))
    }
}
```

The window opens behind whatever is frontmost, so the script raises it before
capturing — without that it photographs your editor, which is how the first
attempt at this went.

See also `Scripts/layout/` for measuring what a layout *needs*, before
deciding what it should look like.
