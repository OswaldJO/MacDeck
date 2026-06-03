import AppKit
import AudioToolbox
import CoreMedia
import Foundation

#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif

/// ScreenCaptureKit capture → H.264 encoder callback.
final class PlayniteDisplayCapture: NSObject, @unchecked Sendable {
    typealias EncodedHandler = @Sendable (Data, Bool, UInt16, UInt16) -> Void
    typealias AudioHandler = @Sendable (Data, UInt16, UInt8) -> Void

    private let encoder: PlayniteH264Encoder
    private let audioHandler: AudioHandler?
    #if canImport(ScreenCaptureKit)
    private var stream: SCStream?
    #endif
    private let queue = DispatchQueue(label: "com.playnite.display-capture", qos: .userInitiated)

    init(encodedHandler: @escaping EncodedHandler, audioHandler: AudioHandler? = nil) {
        encoder = PlayniteH264Encoder(handler: encodedHandler)
        self.audioHandler = audioHandler
        super.init()
    }

    func start(width: Int, height: Int, fps: Int) async throws {
        #if canImport(ScreenCaptureKit)
        try encoder.prepare(width: Int32(width), height: Int32(height), fps: Int32(fps))

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw NSError(domain: "PlayniteDisplayCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: "No display to capture"])
        }
        PlayniteStreamDisplayContext.update(for: display.displayID)

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(fps, 1)))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true
        if audioHandler != nil {
            config.capturesAudio = true
            config.sampleRate = 48_000
            config.channelCount = 2
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if audioHandler != nil {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        }
        try await stream.startCapture()
        self.stream = stream
        #else
        throw NSError(domain: "PlayniteDisplayCapture", code: 2, userInfo: [NSLocalizedDescriptionKey: "ScreenCaptureKit unavailable"])
        #endif
    }

    func requestKeyframe() {
        encoder.requestKeyframe()
    }

    func stop() async {
        #if canImport(ScreenCaptureKit)
        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
        #endif
        encoder.invalidate()
    }
}

#if canImport(ScreenCaptureKit)
extension PlayniteDisplayCapture: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard CMSampleBufferIsValid(sampleBuffer) else { return }
        switch outputType {
        case .screen:
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            encoder.encode(pixelBuffer: pixelBuffer, presentationTime: pts)
        case .audio:
            guard let audioHandler,
                  let pcm = Self.extractPCM16(from: sampleBuffer) else { return }
            Self.audioBuffersSeen += 1
            if Self.audioBuffersSeen == 1 {
                print("[PlayniteAudio] first capture buffer bytes=\(pcm.data.count) \(pcm.sampleRate)Hz ch=\(pcm.channels)")
            }
            audioHandler(pcm.data, pcm.sampleRate, pcm.channels)
        default:
            break
        }
    }

    private struct PCM16 {
        let data: Data
        let sampleRate: UInt16
        let channels: UInt8
    }

    private nonisolated(unsafe) static var audioBuffersSeen = 0
    private nonisolated(unsafe) static var loggedAudioFormatFailure = false

    private static func extractPCM16(from sampleBuffer: CMSampleBuffer) -> PCM16? {
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(format) else { return nil }
        let asbd = asbdPtr.pointee
        let channels = UInt8(max(1, min(Int(asbd.mChannelsPerFrame), 2)))
        let sampleRate = UInt16(min(max(asbd.mSampleRate, 8_000), 96_000))

        if let pcm = extractPCM16FromBlockBuffer(sampleBuffer, asbd: asbd, sampleRate: sampleRate, channels: channels) {
            return pcm
        }
        if let pcm = extractPCM16FromAudioBufferList(sampleBuffer, asbd: asbd, sampleRate: sampleRate, channels: channels) {
            return pcm
        }

        if !loggedAudioFormatFailure {
            loggedAudioFormatFailure = true
            print(
                "[PlayniteAudio] unsupported sample layout flags=\(asbd.mFormatFlags) " +
                    "bits=\(asbd.mBitsPerChannel) bytesPerFrame=\(asbd.mBytesPerFrame)"
            )
        }
        return nil
    }

    private static func extractPCM16FromBlockBuffer(
        _ sampleBuffer: CMSampleBuffer,
        asbd: AudioStreamBasicDescription,
        sampleRate: UInt16,
        channels: UInt8
    ) -> PCM16? {
        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(
            block,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        ) == noErr, let dataPointer, length > 0 else { return nil }
        return pcm16(fromRawBytes: dataPointer, byteCount: length, asbd: asbd, sampleRate: sampleRate, channels: channels)
    }

    private static func extractPCM16FromAudioBufferList(
        _ sampleBuffer: CMSampleBuffer,
        asbd: AudioStreamBasicDescription,
        sampleRate: UInt16,
        channels: UInt8
    ) -> PCM16? {
        guard CMSampleBufferGetNumSamples(sampleBuffer) > 0 else { return nil }

        var audioBufferList = AudioBufferList()
        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }

        let buffers = UnsafeMutableAudioBufferListPointer(&audioBufferList)
        var combined = Data()
        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            let byteCount = Int(buffer.mDataByteSize)
            guard byteCount > 0 else { continue }
            combined.append(data.assumingMemoryBound(to: UInt8.self), count: byteCount)
        }
        guard !combined.isEmpty else { return nil }

        return combined.withUnsafeBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: Int8.self) else { return nil }
            return pcm16(
                fromRawBytes: base,
                byteCount: combined.count,
                asbd: asbd,
                sampleRate: sampleRate,
                channels: channels
            )
        }
    }

    private static func pcm16(
        fromRawBytes dataPointer: UnsafePointer<Int8>,
        byteCount: Int,
        asbd: AudioStreamBasicDescription,
        sampleRate: UInt16,
        channels: UInt8
    ) -> PCM16? {
        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isInt16 = asbd.mBitsPerChannel == 16 && !isFloat

        if isInt16 {
            return PCM16(data: Data(bytes: dataPointer, count: byteCount), sampleRate: sampleRate, channels: channels)
        }

        if isFloat {
            let sampleCount = byteCount / MemoryLayout<Float>.size
            var out = Data(count: sampleCount * MemoryLayout<Int16>.size)
            out.withUnsafeMutableBytes { dest in
                guard let destBase = dest.baseAddress?.assumingMemoryBound(to: Int16.self) else { return }
                let src = dataPointer.withMemoryRebound(to: Float.self, capacity: sampleCount) { $0 }
                for i in 0 ..< sampleCount {
                    let clamped = max(-1.0, min(1.0, src[i]))
                    destBase[i] = Int16(clamped * 32767.0)
                }
            }
            return PCM16(data: out, sampleRate: sampleRate, channels: channels)
        }

        return nil
    }
}
#endif
