import AppKit
import Module_Screenshots_Engine

extension ShotToast {
    // MARK: - Share

    /// Asks for the system's Share sheet at the newest shot's thumbnail, as soon as the thumbnail's view is on a
    /// window. The toast holds from the sheet's opening to its end: the lifetime would otherwise close the panel
    /// under the sheet. How the pointer's events go while the sheet is up is not measured.
    func requestShare() {
        wantsShare = true
        attemptShare()
    }

    /// What the sheet shares: the newest shot's file when there is one, else its picture.
    func shareItems() -> [Any]? {
        guard model.refusal == nil, let shot = model.shots.last else { return nil }
        if let file = shot.file { return [file] }
        return shot.full.map { [NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height))] }
    }

    func attemptShare() {
        guard wantsShare, let anchor = model.anchor else { return }
        // One sheet at a time; a second request is the first one's.
        guard picker == nil else { wantsShare = false; return }
        // No sheet over a path that is gone.
        if model.refusal == nil, let file = model.shots.last?.file, !FileManager.default.fileExists(atPath: file.path) {
            wantsShare = false
            return
        }
        guard let items = shareItems() else { return }
        wantsShare = false
        let picker = NSSharingServicePicker(items: items)
        let delegate = PickerDelegate()
        // The end of a sheet that was dismissed or replaced is not the end of the one that stands.
        delegate.ended = { [weak self, weak delegate] in
            guard let self, let delegate, self.pickerDelegate === delegate else { return }
            self.sheetEnded()
        }
        picker.delegate = delegate
        self.picker = picker
        pickerDelegate = delegate
        holds.insert(.sheet)
        picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
    }

    /// The sheet is over, chosen from or cancelled.
    func sheetEnded() {
        holds.remove(.sheet)
        picker = nil
        pickerDelegate = nil
    }

    final class PickerDelegate: NSObject, NSSharingServicePickerDelegate {
        var ended: () -> Void = {}
        func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) { ended() }
    }

    // MARK: - What the capsule does

    /// The full picture of the shot an action is about: held for a shot that was only copied, read back from its
    /// file for a saved one.
    func fullPicture() -> CGImage? {
        guard model.refusal == nil, let shot = model.current else { return nil }
        if let full = shot.full { return full }
        guard let file = shot.file, let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Where every finished shot's full picture is, oldest first: what «Copy All» hands to the session, which reads
    /// the files itself, one at a time.
    func sources() -> [ShotSource] {
        model.shots.compactMap { shot in
            if let full = shot.full { return .picture(full) }
            return shot.file.map { .file($0) }
        }
    }

    /// The picture as a pin, where the thumbnail stands; the shot leaves the window.
    func pin() {
        guard let image = fullPicture(), let shot = model.current,
              let view = model.unfolded ? model.focused : model.anchor, let window = view.window else { return }
        // The picture's own rect: the view is larger than the picture while the capsule is up over a small shot.
        let rect = (view as? ShotDragView)?.pictureFrame ?? view.bounds
        onPin(image, window.convertToScreen(view.convert(rect, to: nil)))
        if model.unfolded { remove(shot.id) } else { dismiss() }
    }
}
