import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // «تلاواتي»: the take's PCM → AAC-LC .m4a (core/platform/plugin_voice_recorder.dart).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "YaqeenAacEncoder") {
      let channel = FlutterMethodChannel(name: "com.yaqinbrand.yaqeen/aac", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler(AacEncoder.handle)
    }
  }
}

/// Encodes 16-bit little-endian mono PCM to AAC-LC in an MPEG-4 audio file — contracts
/// `RECORDING_FORMAT` (mono, 16 kHz, 32 kbps) — with the system's own encoder (AVAudioFile).
/// Once per recording, off the main thread; nothing bundled, nothing uploaded.
enum AacEncoder {
  static func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard call.method == "encodePcm16" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let args = call.arguments as? [String: Any],
          let pcm = args["pcm"] as? FlutterStandardTypedData,
          let path = args["path"] as? String
    else {
      result(FlutterError(code: "bad_args", message: "pcm and path are required", details: nil))
      return
    }
    let rate = (args["sampleRate"] as? Int) ?? 16000
    let bitRate = (args["bitRate"] as? Int) ?? 32000
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try encode(pcm.data, path: path, rate: rate, bitRate: bitRate)
        DispatchQueue.main.async { result(nil) }
      } catch {
        try? FileManager.default.removeItem(atPath: path)
        DispatchQueue.main.async {
          result(FlutterError(code: "encode_failed", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private static func encode(_ data: Data, path: String, rate: Int, bitRate: Int) throws {
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? FileManager.default.removeItem(at: url)
    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatMPEG4AAC,
      AVSampleRateKey: rate,
      AVNumberOfChannelsKey: 1,
      AVEncoderBitRateKey: bitRate,
    ]
    guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Double(rate), channels: 1, interleaved: true) else {
      throw NSError(domain: "AacEncoder", code: 1, userInfo: [NSLocalizedDescriptionKey: "no pcm format"])
    }
    let frames = data.count / 2
    guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else {
      throw NSError(domain: "AacEncoder", code: 2, userInfo: [NSLocalizedDescriptionKey: "empty audio"])
    }
    buffer.frameLength = AVAudioFrameCount(frames)
    data.withUnsafeBytes { raw in
      if let src = raw.baseAddress, let dst = buffer.int16ChannelData?[0] {
        memcpy(dst, src, frames * 2)
      }
    }
    // A scope so the file is closed (and its moov written) before the caller reads it.
    do {
      let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatInt16, interleaved: true)
      try file.write(from: buffer)
    }
  }
}
