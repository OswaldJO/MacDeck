import AVFoundation
import Network
import UIKit
import VideoToolbox

/// Full-screen H.264 player for Playnite `PNV1` frames.
final class PlayniteVideoViewController: UIViewController {
  private let host: String
  private let port: UInt16
  private var connection: NWConnection?
  private let displayLayer = AVSampleBufferDisplayLayer()
  private var formatDescription: CMFormatDescription?
  private var decompressionSession: VTDecompressionSession?

  init(host: String, port: UInt16) {
    self.host = host
    self.port = port
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    displayLayer.videoGravity = .resizeAspect
    displayLayer.frame = view.bounds
    view.layer.addSublayer(displayLayer)
    startConnection()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    displayLayer.frame = view.bounds
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    connection?.cancel()
    connection = nil
    if let session = decompressionSession {
      VTDecompressionSessionInvalidate(session)
    }
  }

  private func startConnection() {
    connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
    connection?.stateUpdateHandler = { [weak self] state in
      if case .ready = state {
        self?.receiveHeader()
      }
    }
    connection?.start(queue: .global(qos: .userInitiated))
  }

  private func receiveHeader() {
    connection?.receive(minimumIncompleteLength: 13, maximumLength: 13) { [weak self] data, _, _, _ in
      guard let self, let data, data.count == 13 else { return }
      let magic = data.withUnsafeBytes { $0.load(as: UInt32.self) }
      guard magic == PlayniteVideoFrameFormat.magic else {
        self.receiveHeader()
        return
      }
      let length = data.withUnsafeBytes { ptr in
        ptr.load(fromByteOffset: 4, as: UInt32.self)
      }
      let flags = data[8]
      let isKeyframe = (flags & 0x1) != 0
      self.connection?.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { payload, _, _, _ in
        guard let payload else { return }
        self.decodeAnnexB(payload, isKeyframe: isKeyframe)
        self.receiveHeader()
      }
    }
  }

  private func decodeAnnexB(_ data: Data, isKeyframe: Bool) {
    if isKeyframe || formatDescription == nil {
      formatDescription = Self.formatDescription(from: data)
      if let formatDescription {
        var session: VTDecompressionSession?
        let attrs: [NSString: Any] = [
          kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
        ]
        VTDecompressionSessionCreate(
          allocator: kCFAllocatorDefault,
          formatDescription: formatDescription,
          decoderSpecification: nil,
          imageBufferAttributes: attrs as CFDictionary,
          outputCallback: nil,
          decompressionSessionOut: &session
        )
        decompressionSession = session
      }
    }

    guard let formatDescription, let session = decompressionSession else { return }
    var blockBuffer: CMBlockBuffer?
    data.withUnsafeBytes { raw in
      guard let base = raw.baseAddress else { return }
      CMBlockBufferCreateWithMemoryBlock(
        allocator: kCFAllocatorDefault,
        memoryBlock: UnsafeMutableRawPointer(mutating: base),
        blockLength: data.count,
        blockAllocator: kCFAllocatorNull,
        customBlockSource: nil,
        offsetToData: 0,
        dataLength: data.count,
        flags: 0,
        blockBufferOut: &blockBuffer
      )
    }
    guard let blockBuffer else { return }
    var sampleBuffer: CMSampleBuffer?
    var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
    CMSampleBufferCreate(
      allocator: kCFAllocatorDefault,
      dataBuffer: blockBuffer,
      dataReady: true,
      makeDataReadyCallback: nil,
      refcon: nil,
      formatDescription: formatDescription,
      sampleCount: 1,
      sampleTimingEntryCount: 1,
      sampleTimingArray: &timing,
      sampleSizeEntryCount: 0,
      sampleSizeArray: nil,
      sampleBufferOut: &sampleBuffer
    )
    guard let sampleBuffer else { return }

    var decodeInfo = VTDecodeInfoFlags()
    VTDecompressionSessionDecodeFrame(
      session,
      sampleBuffer: sampleBuffer,
      flags: [],
      infoFlagsOut: &decodeInfo
    ) { _, _, imageBuffer, _, _ in
      guard let imageBuffer else { return }
      var timingInfo = CMSampleTimingInfo()
      var newSample: CMSampleBuffer?
      var formatDesc: CMVideoFormatDescription?
      CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: imageBuffer, formatDescriptionOut: &formatDesc)
      guard let formatDesc else { return }
      CMSampleBufferCreateForImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: imageBuffer,
        dataReady: true,
        makeDataReadyCallback: nil,
        refcon: nil,
        formatDescription: formatDesc,
        sampleTiming: &timingInfo,
        sampleBufferOut: &newSample
      )
      guard let newSample else { return }
      DispatchQueue.main.async {
        if self.displayLayer.isReadyForMoreMediaData {
          self.displayLayer.enqueue(newSample)
        }
      }
    }
  }

  private static func formatDescription(from annexB: Data) -> CMFormatDescription? {
    let nalUnits = extractNALUs(annexB)
    guard let sps = nalUnits.first(where: { ($0.first ?? 0) & 0x1F == 7 }),
          let pps = nalUnits.first(where: { ($0.first ?? 0) & 0x1F == 8 }) else { return nil }
    var description: CMFormatDescription?
    sps.withUnsafeBytes { spsRaw in
      pps.withUnsafeBytes { ppsRaw in
        guard let spsBase = spsRaw.baseAddress?.assumingMemoryBound(to: UInt8.self),
              let ppsBase = ppsRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
        let pointers = [spsBase, ppsBase]
        let sizes = [sps.count, pps.count]
        pointers.withUnsafeBufferPointer { ptr in
          sizes.withUnsafeBufferPointer { sizePtr in
            CMVideoFormatDescriptionCreateFromH264ParameterSets(
              allocator: kCFAllocatorDefault,
              parameterSetCount: 2,
              parameterSetPointers: ptr.baseAddress!,
              parameterSetSizes: sizePtr.baseAddress!,
              nalUnitHeaderLength: 4,
              formatDescriptionOut: &description
            )
          }
        }
      }
    }
    return description
  }

  private static func extractNALUs(_ data: Data) -> [Data] {
    var units: [Data] = []
    var i = 0
    let bytes = [UInt8](data)
    func startIndex(_ from: Int) -> Int? {
      var j = from
      while j + 3 < bytes.count {
        if bytes[j] == 0, bytes[j + 1] == 0, bytes[j + 2] == 1 { return j + 3 }
        if j + 4 < bytes.count, bytes[j] == 0, bytes[j + 1] == 0, bytes[j + 2] == 0, bytes[j + 3] == 1 { return j + 4 }
        j += 1
      }
      return nil
    }
    while let start = startIndex(i) {
      var end = start
      while end < bytes.count {
        if end + 3 < bytes.count, bytes[end] == 0, bytes[end + 1] == 0, bytes[end + 2] == 1 { break }
        if end + 4 < bytes.count, bytes[end] == 0, bytes[end + 1] == 0, bytes[end + 2] == 0, bytes[end + 3] == 1 { break }
        end += 1
      }
      units.append(Data(bytes[start..<end]))
      i = end
    }
    return units
  }
}

enum PlayniteVideoFrameFormat {
  static let magic: UInt32 = 0x3156_4E50
}
