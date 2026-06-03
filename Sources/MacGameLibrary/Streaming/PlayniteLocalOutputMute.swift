import CoreAudio
import Foundation

/// Mutes the default system output while streaming so audio is heard on the phone, not the Mac speakers.
@MainActor
enum PlayniteLocalOutputMute {
    private static var savedMute: (deviceID: AudioDeviceID, wasMuted: UInt32)?
    private static var isMutedForStream = false

    static func setStreamingMuted(_ muted: Bool) {
        if muted {
            guard !isMutedForStream else { return }
            muteDefaultOutput()
            isMutedForStream = true
        } else {
            guard isMutedForStream else { return }
            restoreDefaultOutput()
            isMutedForStream = false
        }
    }

    private static func defaultOutputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != 0 else { return nil }
        return deviceID
    }

    private static func readMute(deviceID: AudioDeviceID) -> UInt32? {
        var mute: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &mute)
        guard status == noErr else { return nil }
        return mute
    }

    private static func writeMute(deviceID: AudioDeviceID, muted: UInt32) {
        var value = muted
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return }
        _ = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &value
        )
    }

    private static func muteDefaultOutput() {
        guard let deviceID = defaultOutputDeviceID() else {
            print("[PlayniteAudio] could not resolve default output device for mute")
            return
        }
        let wasMuted = readMute(deviceID: deviceID) ?? 0
        savedMute = (deviceID, wasMuted)
        writeMute(deviceID: deviceID, muted: 1)
        print("[PlayniteAudio] muted Mac default output for streaming")
    }

    private static func restoreDefaultOutput() {
        guard let saved = savedMute else { return }
        writeMute(deviceID: saved.deviceID, muted: saved.wasMuted)
        savedMute = nil
        print("[PlayniteAudio] restored Mac default output mute state")
    }
}
