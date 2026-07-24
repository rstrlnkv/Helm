import CoreAudio
import AudioToolbox
import Foundation

/// Publishes audio events: output-device switches (AirPods connecting) and
/// volume changes on the current output device. CoreAudio listeners fire on
/// the main queue; events flow through the island's TTL mechanism.
final class IslandAudioSource: @unchecked Sendable {
    private let onDeviceEvent: @MainActor (String, String) -> Void
    private let onVolumeEvent: @MainActor (String, String) -> Void
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var deviceBlock: AudioObjectPropertyListenerBlock?
    private var volumeBlock: AudioObjectPropertyListenerBlock?
    /// Set on init so the device already connected at launch isn't announced.
    private var announcedInitial = false

    private static func makeDefaultOutputAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
    }
    private static func makeVolumeAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
    }

    init(onDeviceEvent: @escaping @MainActor (String, String) -> Void,
         onVolumeEvent: @escaping @MainActor (String, String) -> Void) {
        self.onDeviceEvent = onDeviceEvent
        self.onVolumeEvent = onVolumeEvent

        let deviceBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.defaultDeviceChanged()
        }
        self.deviceBlock = deviceBlock
        var outAddr = Self.makeDefaultOutputAddress()
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                            &outAddr, .main, deviceBlock)
        attachVolumeListener(to: Self.currentDefaultDevice())
        announcedInitial = true
    }

    func stop() {
        if let deviceBlock {
            var outAddr = Self.makeDefaultOutputAddress()
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                                   &outAddr, .main, deviceBlock)
        }
        detachVolumeListener()
    }

    // MARK: - Device switches

    private func defaultDeviceChanged() {
        let newDevice = Self.currentDefaultDevice()
        guard newDevice != device else { return }
        attachVolumeListener(to: newDevice)
        guard announcedInitial, newDevice != kAudioObjectUnknown,
              let name = Self.deviceName(newDevice) else { return }
        let symbol = Self.isBluetooth(newDevice) ? "airpods.gen3" : "speaker.wave.2"
        Task { @MainActor in self.onDeviceEvent(name, symbol) }
    }

    // MARK: - Volume

    private func attachVolumeListener(to newDevice: AudioObjectID) {
        detachVolumeListener()
        device = newDevice
        var volAddr = Self.makeVolumeAddress()
        guard newDevice != kAudioObjectUnknown,
              AudioObjectHasProperty(newDevice, &volAddr) else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.volumeChanged()
        }
        volumeBlock = block
        AudioObjectAddPropertyListenerBlock(newDevice, &volAddr, .main, block)
    }

    private func detachVolumeListener() {
        if let volumeBlock, device != kAudioObjectUnknown {
            var volAddr = Self.makeVolumeAddress()
            AudioObjectRemovePropertyListenerBlock(device, &volAddr, .main, volumeBlock)
        }
        volumeBlock = nil
    }

    private func volumeChanged() {
        guard device != kAudioObjectUnknown else { return }
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var volAddr = Self.makeVolumeAddress()
        guard AudioObjectGetPropertyData(device, &volAddr, 0, nil, &size, &volume) == noErr
        else { return }
        let percent = Int((volume * 100).rounded())
        let symbol = percent == 0 ? "speaker.slash" : percent < 50 ? "speaker.wave.1" : "speaker.wave.2"
        Task { @MainActor in self.onVolumeEvent("\(percent)%", symbol) }
    }

    // MARK: - CoreAudio helpers

    private static func currentDefaultDevice() -> AudioObjectID {
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var outAddr = makeDefaultOutputAddress()
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                   &outAddr, 0, nil, &size, &id)
        return id
    }

    private static func deviceName(_ id: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr,
              let cf = name?.takeRetainedValue() else { return nil }
        return cf as String
    }

    private static func isBluetooth(_ id: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport) == noErr
        else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth
            || transport == kAudioDeviceTransportTypeBluetoothLE
    }
}
