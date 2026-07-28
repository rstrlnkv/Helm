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

## measure-motion.swift

What an animation actually does, frame by frame, out of a screen recording:
change between consecutive frames over a crop of the part that moves. A smooth
move is a bell; every defect is a spike, and the shapes are named in
ARCHITECTURE.md § Dev loop. Five defects in the disk ring were found with it and
none of them was visible by watching.

```bash
B=$(osascript -e 'tell application "System Events" to tell process "Helm" to get {position, size} of window 1')
screencapture -v -V 12 -x -R"$(echo $B | tr -d ' ')" /tmp/clip.mov
swift Scripts/design/measure-motion.swift /tmp/clip.mov 16.6 0.17 0.57 0.32 0.91
```
