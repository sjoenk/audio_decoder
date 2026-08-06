#if os(iOS)
import Flutter
import UIKit
#elseif os(macOS)
import Cocoa
import FlutterMacOS
#endif
import AVFoundation

public class AudioDecoderPlugin: NSObject, FlutterPlugin {
    /// Standard RIFF/WAV header size in bytes (no extra chunks).
    private static let wavHeaderSize = 44
    /// Maximum PCM data size for a valid WAV file (~4 GB).
    private static let maxWavDataSize: Int64 = 0xFFFF_FFFF - 36

    public static func register(with registrar: FlutterPluginRegistrar) {
        #if os(iOS)
        let messenger = registrar.messenger()
        #elseif os(macOS)
        let messenger = registrar.messenger
        #endif
        let channel = FlutterMethodChannel(
            name: "audio_decoder",
            binaryMessenger: messenger
        )
        let instance = AudioDecoderPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "convertToWav":
            guard let args = call.arguments as? [String: Any],
                  let inputPath = args["inputPath"] as? String,
                  let outputPath = args["outputPath"] as? String else {
                result(FlutterError(
                    code: "INVALID_ARGUMENTS",
                    message: "inputPath and outputPath are required",
                    details: nil
                ))
                return
            }
            let sampleRate = args["sampleRate"] as? Int
            let channels = args["channels"] as? Int
            let bitDepth = args["bitDepth"] as? Int
            convertToWav(inputPath: inputPath, outputPath: outputPath, sampleRate: sampleRate, channels: channels, bitDepth: bitDepth, result: result)
        case "convertToM4a":
            guard let args = call.arguments as? [String: String],
                  let inputPath = args["inputPath"],
                  let outputPath = args["outputPath"] else {
                result(FlutterError(
                    code: "INVALID_ARGUMENTS",
                    message: "inputPath and outputPath are required",
                    details: nil
                ))
                return
            }
            convertToM4a(inputPath: inputPath, outputPath: outputPath, result: result)
        case "getAudioInfo":
            guard let args = call.arguments as? [String: String],
                  let path = args["path"] else {
                result(FlutterError(
                    code: "INVALID_ARGUMENTS",
                    message: "path is required",
                    details: nil
                ))
                return
            }
            getAudioInfo(path: path, result: result)
        case "trimAudio":
            guard let args = call.arguments as? [String: Any],
                  let inputPath = args["inputPath"] as? String,
                  let outputPath = args["outputPath"] as? String,
                  let startMs = args["startMs"] as? Int,
                  let endMs = args["endMs"] as? Int else {
                result(FlutterError(
                    code: "INVALID_ARGUMENTS",
                    message: "inputPath, outputPath, startMs and endMs are required",
                    details: nil
                ))
                return
            }
            trimAudio(inputPath: inputPath, outputPath: outputPath, startMs: startMs, endMs: endMs, result: result)
        case "getWaveform":
            guard let args = call.arguments as? [String: Any],
                  let path = args["path"] as? String,
                  let numberOfSamples = args["numberOfSamples"] as? Int else {
                result(FlutterError(
                    code: "INVALID_ARGUMENTS",
                    message: "path and numberOfSamples are required",
                    details: nil
                ))
                return
            }
            let normalization = args["normalization"] as? String ?? "perFile"
            getWaveform(path: path, numberOfSamples: numberOfSamples, normalization: normalization, result: result)
        case "convertToWavBytes":
            guard let args = call.arguments as? [String: Any],
                  let inputData = args["inputData"] as? FlutterStandardTypedData,
                  let formatHint = args["formatHint"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "inputData and formatHint are required", details: nil))
                return
            }
            let sampleRate = args["sampleRate"] as? Int
            let channels = args["channels"] as? Int
            let bitDepth = args["bitDepth"] as? Int
            let includeHeader = args["includeHeader"] as? Bool ?? true
            convertToWavBytes(inputData: inputData, formatHint: formatHint, sampleRate: sampleRate, channels: channels, bitDepth: bitDepth, includeHeader: includeHeader, result: result)
        case "convertToM4aBytes":
            guard let args = call.arguments as? [String: Any],
                  let inputData = args["inputData"] as? FlutterStandardTypedData,
                  let formatHint = args["formatHint"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "inputData and formatHint are required", details: nil))
                return
            }
            convertToM4aBytes(inputData: inputData, formatHint: formatHint, result: result)
        case "getAudioInfoBytes":
            guard let args = call.arguments as? [String: Any],
                  let inputData = args["inputData"] as? FlutterStandardTypedData,
                  let formatHint = args["formatHint"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "inputData and formatHint are required", details: nil))
                return
            }
            getAudioInfoBytes(inputData: inputData, formatHint: formatHint, result: result)
        case "trimAudioBytes":
            guard let args = call.arguments as? [String: Any],
                  let inputData = args["inputData"] as? FlutterStandardTypedData,
                  let formatHint = args["formatHint"] as? String,
                  let startMs = args["startMs"] as? Int,
                  let endMs = args["endMs"] as? Int else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "inputData, formatHint, startMs and endMs are required", details: nil))
                return
            }
            let outputFormat = args["outputFormat"] as? String ?? "wav"
            trimAudioBytes(inputData: inputData, formatHint: formatHint, startMs: startMs, endMs: endMs, outputFormat: outputFormat, result: result)
        case "getWaveformBytes":
            guard let args = call.arguments as? [String: Any],
                  let inputData = args["inputData"] as? FlutterStandardTypedData,
                  let formatHint = args["formatHint"] as? String,
                  let numberOfSamples = args["numberOfSamples"] as? Int else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "inputData, formatHint and numberOfSamples are required", details: nil))
                return
            }
            let normalization = args["normalization"] as? String ?? "perFile"
            getWaveformBytes(inputData: inputData, formatHint: formatHint, numberOfSamples: numberOfSamples, normalization: normalization, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Convert to WAV

    private func convertToWav(inputPath: String, outputPath: String, sampleRate: Int?, channels: Int?, bitDepth: Int?, result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.performConversion(inputPath: inputPath, outputPath: outputPath, targetSampleRate: sampleRate, targetChannels: channels, targetBitDepth: bitDepth)
                DispatchQueue.main.async {
                    result(outputPath)
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "CONVERSION_ERROR",
                        message: error.localizedDescription,
                        details: nil
                    ))
                }
            }
        }
    }

    private func performConversion(inputPath: String, outputPath: String, targetSampleRate: Int? = nil, targetChannels: Int? = nil, targetBitDepth: Int? = nil) throws {
        let inputURL = URL(fileURLWithPath: inputPath)
        let outputURL = URL(fileURLWithPath: outputPath)

        let fm = FileManager.default
        if fm.fileExists(atPath: outputPath) {
            try fm.removeItem(at: outputURL)
        }

        let asset = AVURLAsset(url: inputURL)

        guard let assetReader = try? AVAssetReader(asset: asset) else {
            throw NSError(domain: "AudioDecoder", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot create AVAssetReader for \(inputPath)"])
        }

        guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
            throw NSError(domain: "AudioDecoder", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "No audio track found in \(inputPath)"])
        }

        let bitsPerSample = targetBitDepth ?? 16

        var outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: bitsPerSample,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        if let sr = targetSampleRate {
            outputSettings[AVSampleRateKey] = sr
        }
        if let ch = targetChannels {
            outputSettings[AVNumberOfChannelsKey] = ch
        }

        let trackOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        trackOutput.alwaysCopiesSampleData = false
        assetReader.add(trackOutput)

        guard let formatDesc = audioTrack.formatDescriptions.first else {
            throw NSError(domain: "AudioDecoder", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "No format description available"])
        }

        let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(
            formatDesc as! CMAudioFormatDescription
        )!.pointee

        let sampleRate = targetSampleRate ?? Int(asbd.mSampleRate)
        let channels = targetChannels ?? Int(asbd.mChannelsPerFrame)

        guard assetReader.startReading() else {
            throw NSError(domain: "AudioDecoder", code: 3,
                          userInfo: [NSLocalizedDescriptionKey:
                                        "AVAssetReader failed to start: \(assetReader.error?.localizedDescription ?? "unknown")"])
        }

        try streamPcmToWav(
            assetReader: assetReader, trackOutput: trackOutput,
            outputURL: outputURL, sampleRate: sampleRate, channels: channels,
            bitsPerSample: bitsPerSample,
            readerFailedCode: 4, overflowCode: 7, createFileFailedCode: 6)
    }

    // MARK: - Convert to M4A

    private func convertToM4a(inputPath: String, outputPath: String, result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.performM4aConversion(inputPath: inputPath, outputPath: outputPath)
                DispatchQueue.main.async {
                    result(outputPath)
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "CONVERSION_ERROR",
                        message: error.localizedDescription,
                        details: nil
                    ))
                }
            }
        }
    }

    private func performM4aConversion(inputPath: String, outputPath: String) throws {
        let inputURL = URL(fileURLWithPath: inputPath)
        let outputURL = URL(fileURLWithPath: outputPath)

        let fm = FileManager.default
        if fm.fileExists(atPath: outputPath) {
            try fm.removeItem(at: outputURL)
        }

        let asset = AVURLAsset(url: inputURL)

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw NSError(domain: "AudioDecoder", code: 10,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot create export session for \(inputPath)"])
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        let semaphore = DispatchSemaphore(value: 0)
        exportSession.exportAsynchronously {
            semaphore.signal()
        }
        semaphore.wait()

        switch exportSession.status {
        case .completed:
            return
        case .failed:
            throw exportSession.error ?? NSError(domain: "AudioDecoder", code: 11,
                          userInfo: [NSLocalizedDescriptionKey: "Export failed with unknown error"])
        case .cancelled:
            throw NSError(domain: "AudioDecoder", code: 12,
                          userInfo: [NSLocalizedDescriptionKey: "Export was cancelled"])
        default:
            throw NSError(domain: "AudioDecoder", code: 13,
                          userInfo: [NSLocalizedDescriptionKey: "Export ended with unexpected status: \(exportSession.status.rawValue)"])
        }
    }

    // MARK: - Get Audio Info

    private func getAudioInfo(path: String, result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let info = try self.performGetAudioInfo(path: path)
                DispatchQueue.main.async {
                    result(info)
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "INFO_ERROR",
                        message: error.localizedDescription,
                        details: nil
                    ))
                }
            }
        }
    }

    private func performGetAudioInfo(path: String) throws -> [String: Any] {
        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url)

        let durationMs = Int(CMTimeGetSeconds(asset.duration) * 1000)

        guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
            throw NSError(domain: "AudioDecoder", code: 20,
                          userInfo: [NSLocalizedDescriptionKey: "No audio track found in \(path)"])
        }

        guard let formatDesc = audioTrack.formatDescriptions.first else {
            throw NSError(domain: "AudioDecoder", code: 21,
                          userInfo: [NSLocalizedDescriptionKey: "No format description available"])
        }

        let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(
            formatDesc as! CMAudioFormatDescription
        )!.pointee

        let sampleRate = Int(asbd.mSampleRate)
        let channels = Int(asbd.mChannelsPerFrame)
        let bitRate = Int(audioTrack.estimatedDataRate)

        let formatID = asbd.mFormatID
        let format = formatIDToString(formatID)

        return [
            "durationMs": durationMs,
            "sampleRate": sampleRate,
            "channels": channels,
            "bitRate": bitRate,
            "format": format,
        ]
    }

    private func formatIDToString(_ formatID: AudioFormatID) -> String {
        switch formatID {
        case kAudioFormatLinearPCM: return "pcm"
        case kAudioFormatMPEG4AAC: return "aac"
        case kAudioFormatMPEGLayer3: return "mp3"
        case kAudioFormatAppleLossless: return "alac"
        case kAudioFormatFLAC: return "flac"
        case kAudioFormatOpus: return "opus"
        case kAudioFormatAMR: return "amr"
        default:
            let bytes = withUnsafeBytes(of: formatID.bigEndian) { Array($0) }
            if let s = String(bytes: bytes, encoding: .ascii) {
                return s.trimmingCharacters(in: .whitespaces).lowercased()
            }
            return "unknown"
        }
    }

    // MARK: - Trim Audio

    private func trimAudio(inputPath: String, outputPath: String, startMs: Int, endMs: Int, result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.performTrimAudio(inputPath: inputPath, outputPath: outputPath, startMs: startMs, endMs: endMs)
                DispatchQueue.main.async {
                    result(outputPath)
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "TRIM_ERROR",
                        message: error.localizedDescription,
                        details: nil
                    ))
                }
            }
        }
    }

    private func performTrimAudio(inputPath: String, outputPath: String, startMs: Int, endMs: Int) throws {
        let inputURL = URL(fileURLWithPath: inputPath)
        let outputURL = URL(fileURLWithPath: outputPath)
        let outputExt = outputURL.pathExtension.lowercased()

        let fm = FileManager.default
        if fm.fileExists(atPath: outputPath) {
            try fm.removeItem(at: outputURL)
        }

        let asset = AVURLAsset(url: inputURL)
        let startTime = CMTime(value: CMTimeValue(startMs), timescale: 1000)
        let endTime = CMTime(value: CMTimeValue(endMs), timescale: 1000)
        let timeRange = CMTimeRange(start: startTime, end: endTime)

        if outputExt == "m4a" {
            // Use AVAssetExportSession for M4A output
            guard let exportSession = AVAssetExportSession(
                asset: asset,
                presetName: AVAssetExportPresetAppleM4A
            ) else {
                throw NSError(domain: "AudioDecoder", code: 30,
                              userInfo: [NSLocalizedDescriptionKey: "Cannot create export session"])
            }

            exportSession.outputURL = outputURL
            exportSession.outputFileType = .m4a
            exportSession.timeRange = timeRange

            let semaphore = DispatchSemaphore(value: 0)
            exportSession.exportAsynchronously {
                semaphore.signal()
            }
            semaphore.wait()

            if exportSession.status != .completed {
                throw exportSession.error ?? NSError(domain: "AudioDecoder", code: 31,
                              userInfo: [NSLocalizedDescriptionKey: "Trim export failed"])
            }
        } else {
            guard let assetReader = try? AVAssetReader(asset: asset) else {
                throw NSError(domain: "AudioDecoder", code: 32,
                              userInfo: [NSLocalizedDescriptionKey: "Cannot create AVAssetReader"])
            }

            assetReader.timeRange = timeRange

            guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
                throw NSError(domain: "AudioDecoder", code: 33,
                              userInfo: [NSLocalizedDescriptionKey: "No audio track found"])
            }

            let outputSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]

            let trackOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
            trackOutput.alwaysCopiesSampleData = false
            assetReader.add(trackOutput)

            guard let formatDesc = audioTrack.formatDescriptions.first else {
                throw NSError(domain: "AudioDecoder", code: 36,
                              userInfo: [NSLocalizedDescriptionKey: "No format description available"])
            }

            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(
                formatDesc as! CMAudioFormatDescription
            )!.pointee

            let sampleRate = Int(asbd.mSampleRate)
            let channels = Int(asbd.mChannelsPerFrame)

            guard assetReader.startReading() else {
                throw NSError(domain: "AudioDecoder", code: 34,
                              userInfo: [NSLocalizedDescriptionKey: "AVAssetReader failed to start"])
            }

            try streamPcmToWav(
                assetReader: assetReader, trackOutput: trackOutput,
                outputURL: outputURL, sampleRate: sampleRate, channels: channels,
                bitsPerSample: 16,
                readerFailedCode: 35, overflowCode: 38, createFileFailedCode: 37)
        }
    }

    // MARK: - Get Waveform

    private func getWaveform(path: String, numberOfSamples: Int, normalization: String, result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let waveform = try self.performGetWaveform(path: path, numberOfSamples: numberOfSamples, normalization: normalization)
                DispatchQueue.main.async {
                    result(waveform)
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "WAVEFORM_ERROR",
                        message: error.localizedDescription,
                        details: nil
                    ))
                }
            }
        }
    }

    private func performGetWaveform(path: String, numberOfSamples: Int, normalization: String = "perFile") throws -> [Double] {
        // Fail fast on an invalid normalization mode before opening the asset
        // and decoding the PCM samples.
        guard normalization == "perFile" || normalization == "absolute" else {
            throw NSError(
                domain: "AudioDecoder", code: 43,
                userInfo: [NSLocalizedDescriptionKey:
                    "Unknown waveform normalization: \(normalization)"]
            )
        }

        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url)

        guard let assetReader = try? AVAssetReader(asset: asset) else {
            throw NSError(domain: "AudioDecoder", code: 40,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot create AVAssetReader"])
        }

        guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
            throw NSError(domain: "AudioDecoder", code: 41,
                          userInfo: [NSLocalizedDescriptionKey: "No audio track found"])
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        let trackOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        trackOutput.alwaysCopiesSampleData = false
        assetReader.add(trackOutput)

        guard assetReader.startReading() else {
            throw NSError(domain: "AudioDecoder", code: 42,
                          userInfo: [NSLocalizedDescriptionKey: "AVAssetReader failed to start"])
        }

        // RMS energy is folded into the accumulator while decoding, so the whole
        // track never has to be held in memory (#49).
        let accumulator = WaveformAccumulator(numberOfSamples: numberOfSamples)
        while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
            if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                let length = CMBlockBufferGetDataLength(blockBuffer)
                var data = Data(count: length)
                _ = data.withUnsafeMutableBytes { ptr in
                    CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length,
                                               destination: ptr.baseAddress!)
                }
                data.withUnsafeBytes { rawPtr in
                    accumulator.addPcm(rawPtr)
                }
            }
        }

        return accumulator.build(normalization: normalization)
    }

    // MARK: - Temp file helper

    private func writeTempInput(data: FlutterStandardTypedData, formatHint: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "audio_decoder_in_\(ProcessInfo.processInfo.globallyUniqueString).\(formatHint)"
        let url = tempDir.appendingPathComponent(fileName)
        try data.data.write(to: url)
        return url
    }

    private func tempOutputURL(ext: String) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "audio_decoder_out_\(ProcessInfo.processInfo.globallyUniqueString).\(ext)"
        return tempDir.appendingPathComponent(fileName)
    }

    // MARK: - Bytes-based methods

    private func convertToWavBytes(inputData: FlutterStandardTypedData, formatHint: String, sampleRate: Int?, channels: Int?, bitDepth: Int?, includeHeader: Bool = true, result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let tempInputURL = try self.writeTempInput(data: inputData, formatHint: formatHint)
                let tempOutputURL = self.tempOutputURL(ext: "wav")
                defer {
                    try? FileManager.default.removeItem(at: tempInputURL)
                    try? FileManager.default.removeItem(at: tempOutputURL)
                }
                try self.performConversion(inputPath: tempInputURL.path, outputPath: tempOutputURL.path, targetSampleRate: sampleRate, targetChannels: channels, targetBitDepth: bitDepth)
                var outputData = try Data(contentsOf: tempOutputURL)
                // Strip the WAV header to return raw PCM.
                let h = AudioDecoderPlugin.wavHeaderSize
                if !includeHeader && outputData.count >= h {
                    outputData = outputData.subdata(in: h..<outputData.count)
                }
                DispatchQueue.main.async {
                    result(FlutterStandardTypedData(bytes: outputData))
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "CONVERSION_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }

    private func convertToM4aBytes(inputData: FlutterStandardTypedData, formatHint: String, result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let tempInputURL = try self.writeTempInput(data: inputData, formatHint: formatHint)
                let tempOutputURL = self.tempOutputURL(ext: "m4a")
                defer {
                    try? FileManager.default.removeItem(at: tempInputURL)
                    try? FileManager.default.removeItem(at: tempOutputURL)
                }
                try self.performM4aConversion(inputPath: tempInputURL.path, outputPath: tempOutputURL.path)
                let outputData = try Data(contentsOf: tempOutputURL)
                DispatchQueue.main.async {
                    result(FlutterStandardTypedData(bytes: outputData))
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "CONVERSION_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }

    private func getAudioInfoBytes(inputData: FlutterStandardTypedData, formatHint: String, result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let tempInputURL = try self.writeTempInput(data: inputData, formatHint: formatHint)
                defer {
                    try? FileManager.default.removeItem(at: tempInputURL)
                }
                let info = try self.performGetAudioInfo(path: tempInputURL.path)
                DispatchQueue.main.async {
                    result(info)
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "INFO_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }

    private func trimAudioBytes(inputData: FlutterStandardTypedData, formatHint: String, startMs: Int, endMs: Int, outputFormat: String, result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let tempInputURL = try self.writeTempInput(data: inputData, formatHint: formatHint)
                let tempOutputURL = self.tempOutputURL(ext: outputFormat)
                defer {
                    try? FileManager.default.removeItem(at: tempInputURL)
                    try? FileManager.default.removeItem(at: tempOutputURL)
                }
                try self.performTrimAudio(inputPath: tempInputURL.path, outputPath: tempOutputURL.path, startMs: startMs, endMs: endMs)
                let outputData = try Data(contentsOf: tempOutputURL)
                DispatchQueue.main.async {
                    result(FlutterStandardTypedData(bytes: outputData))
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "TRIM_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }

    private func getWaveformBytes(inputData: FlutterStandardTypedData, formatHint: String, numberOfSamples: Int, normalization: String, result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let tempInputURL = try self.writeTempInput(data: inputData, formatHint: formatHint)
                defer {
                    try? FileManager.default.removeItem(at: tempInputURL)
                }
                let waveform = try self.performGetWaveform(path: tempInputURL.path, numberOfSamples: numberOfSamples, normalization: normalization)
                DispatchQueue.main.async {
                    result(waveform)
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "WAVEFORM_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }

    // MARK: - WAV streaming & header helpers

    /// Streams decoded PCM chunks from an AVAssetReader to a WAV file on disk.
    ///
    /// The caller must have already called `assetReader.startReading()` before invoking this method.
    private func streamPcmToWav(
        assetReader: AVAssetReader,
        trackOutput: AVAssetReaderTrackOutput,
        outputURL: URL,
        sampleRate: Int,
        channels: Int,
        bitsPerSample: Int,
        readerFailedCode: Int,
        overflowCode: Int,
        createFileFailedCode: Int
    ) throws {
        let fm = FileManager.default
        let outputPath = outputURL.path

        guard fm.createFile(atPath: outputPath, contents: nil) else {
            throw NSError(domain: "AudioDecoder", code: createFileFailedCode,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot create output file at \(outputPath)"])
        }
        let fileHandle = try FileHandle(forWritingTo: outputURL)
        var success = false
        defer {
            try? fileHandle.close()
            if !success {
                try? fm.removeItem(at: outputURL)
            }
        }

        // Write placeholder WAV header (will be updated after decoding)
        fileHandle.write(buildWavHeader(pcmDataSize: 0,
                                        sampleRate: sampleRate, channels: channels, bitsPerSample: bitsPerSample))

        var totalPcmBytes: Int64 = 0
        while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
            if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                let length = CMBlockBufferGetDataLength(blockBuffer)
                var chunk = Data(count: length)
                _ = chunk.withUnsafeMutableBytes { ptr in
                    CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length,
                                               destination: ptr.baseAddress!)
                }
                totalPcmBytes += Int64(length)
                if totalPcmBytes > AudioDecoderPlugin.maxWavDataSize {
                    throw NSError(domain: "AudioDecoder", code: overflowCode,
                                  userInfo: [NSLocalizedDescriptionKey:
                                                "WAV output exceeds maximum size (~4 GB). Consider splitting the audio into shorter segments."])
                }
                fileHandle.write(chunk)
            }
        }

        if assetReader.status == .failed {
            throw NSError(domain: "AudioDecoder", code: readerFailedCode,
                          userInfo: [NSLocalizedDescriptionKey:
                                        "AVAssetReader failed: \(assetReader.error?.localizedDescription ?? "unknown")"])
        }

        // Seek back and write the final WAV header with the actual data size.
        // The Int cast is safe: totalPcmBytes is validated against maxWavDataSize (< 2^32),
        // so the value always fits within Int on 64-bit Apple platforms.
        fileHandle.seek(toFileOffset: 0)
        fileHandle.write(buildWavHeader(pcmDataSize: Int(totalPcmBytes),
                                        sampleRate: sampleRate, channels: channels, bitsPerSample: bitsPerSample))
        success = true
    }

    private func buildWavHeader(pcmDataSize: Int, sampleRate: Int, channels: Int, bitsPerSample: Int) -> Data {
        let byteRate = sampleRate * channels * (bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)

        var header = Data()
        header.append(contentsOf: [UInt8]("RIFF".utf8))
        header.append(UInt32(36 + pcmDataSize).littleEndianBytes)
        header.append(contentsOf: [UInt8]("WAVE".utf8))
        header.append(contentsOf: [UInt8]("fmt ".utf8))
        header.append(UInt32(16).littleEndianBytes)
        header.append(UInt16(1).littleEndianBytes)
        header.append(UInt16(channels).littleEndianBytes)
        header.append(UInt32(sampleRate).littleEndianBytes)
        header.append(UInt32(byteRate).littleEndianBytes)
        header.append(UInt16(blockAlign).littleEndianBytes)
        header.append(UInt16(bitsPerSample).littleEndianBytes)
        header.append(contentsOf: [UInt8]("data".utf8))
        header.append(UInt32(pcmDataSize).littleEndianBytes)
        return header
    }
}

/// Accumulates RMS energy for a waveform while the audio is still decoding.
///
/// Keeping every decoded sample is not an option — three hours of 44.1 kHz
/// stereo audio is close to a billion samples — so energy is folded into a
/// fixed set of buckets instead. Each bucket covers `samplesPerBucket`
/// consecutive samples; once the arrays are full, adjacent buckets are merged
/// pairwise and the span per bucket doubles. Memory therefore stays bounded
/// regardless of duration, while short inputs (which never trigger a merge) are
/// summarized sample-exact.
///
/// The caller is expected to validate the normalization mode beforehand.
private final class WaveformAccumulator {
    /// Aim for this many buckets per output point so window bounds land close
    /// to a bucket edge, keeping the RMS error negligible once merging kicks in.
    private static let bucketsPerWindow = 256
    private static let minBuckets = 1024
    /// Caps the accumulator at ~4 MB (one Double plus one Int64 per bucket).
    private static let maxBuckets = 262_144

    private let numberOfSamples: Int
    private var sumSquares: [Double]
    private var counts: [Int64]

    /// Number of samples each full bucket covers; doubles on every merge.
    private var samplesPerBucket: Int64 = 1
    private var bucketCount = 0
    private var totalSamples: Int64 = 0
    private var pendingByte: UInt8 = 0
    private var hasPendingByte = false

    init(numberOfSamples: Int) {
        self.numberOfSamples = numberOfSamples
        let target = numberOfSamples * WaveformAccumulator.bucketsPerWindow
        var capacity = min(max(target, WaveformAccumulator.minBuckets),
                           WaveformAccumulator.maxBuckets)
        // An even capacity keeps pairwise merging exact.
        if !capacity.isMultiple(of: 2) { capacity += 1 }
        sumSquares = [Double](repeating: 0, count: capacity)
        counts = [Int64](repeating: 0, count: capacity)
    }

    /// Adds a chunk of interleaved little-endian 16-bit PCM. A sample split
    /// across two chunks is carried over instead of dropped.
    func addPcm(_ bytes: UnsafeRawBufferPointer) {
        var offset = 0
        if hasPendingByte, !bytes.isEmpty {
            add(WaveformAccumulator.sample(low: pendingByte, high: bytes[0]))
            hasPendingByte = false
            offset = 1
        }
        while offset + 1 < bytes.count {
            add(WaveformAccumulator.sample(low: bytes[offset], high: bytes[offset + 1]))
            offset += 2
        }
        if offset < bytes.count {
            pendingByte = bytes[offset]
            hasPendingByte = true
        }
    }

    /// Builds the normalized waveform from everything accumulated so far.
    func build(normalization: String) -> [Double] {
        if totalSamples == 0 {
            return Array(repeating: 0.0, count: numberOfSamples)
        }

        let windowSize = max(1, totalSamples / Int64(numberOfSamples))
        var waveform = [Double]()
        var maxRms = 0.0

        for i in 0..<numberOfSamples {
            let start = Int64(i) * totalSamples / Int64(numberOfSamples)
            if start >= totalSamples { break }
            let end = min(start + windowSize, totalSamples)

            let rms = sqrt(sumSquaresIn(start: start, end: end) / Double(end - start))
            waveform.append(rms)
            if rms > maxRms { maxRms = rms }
        }

        // Scale to 0.0-1.0 according to the requested normalization mode.
        // Samples are signed 16-bit PCM with range [-32768, 32767], so the
        // absolute mode divides by the max magnitude (32768) to keep the
        // result inside [0.0, 1.0] even when a window is filled with -32768.
        // (normalization is already validated up front.)
        if normalization == "absolute" {
            waveform = waveform.map { $0 / 32768.0 }
        } else if maxRms > 0 {
            waveform = waveform.map { $0 / maxRms }
        }

        // Pad if the audio was shorter than the requested resolution.
        while waveform.count < numberOfSamples {
            waveform.append(0.0)
        }

        return waveform
    }

    private static func sample(low: UInt8, high: UInt8) -> Int16 {
        Int16(bitPattern: UInt16(low) | (UInt16(high) << 8))
    }

    private func add(_ sample: Int16) {
        if bucketCount == 0 || counts[bucketCount - 1] >= samplesPerBucket {
            if bucketCount == counts.count { mergeAdjacentBuckets() }
            bucketCount += 1
            sumSquares[bucketCount - 1] = 0
            counts[bucketCount - 1] = 0
        }
        let value = Double(sample)
        sumSquares[bucketCount - 1] += value * value
        counts[bucketCount - 1] += 1
        totalSamples += 1
    }

    /// Halves the resolution so more samples fit in the same arrays.
    private func mergeAdjacentBuckets() {
        var dst = 0
        var src = 0
        while src < bucketCount {
            sumSquares[dst] = sumSquares[src] + sumSquares[src + 1]
            counts[dst] = counts[src] + counts[src + 1]
            dst += 1
            src += 2
        }
        bucketCount = dst
        samplesPerBucket *= 2
    }

    /// Sum of squares over the sample range `[start, end)`.
    private func sumSquaresIn(start: Int64, end: Int64) -> Double {
        var sum = 0.0
        // Every bucket but the last is full, so bucket b starts at
        // b * samplesPerBucket.
        var bucket = Int(start / samplesPerBucket)
        while bucket < bucketCount {
            let bucketStart = Int64(bucket) * samplesPerBucket
            if bucketStart >= end { break }
            let bucketEnd = bucketStart + counts[bucket]
            let overlap = min(end, bucketEnd) - max(start, bucketStart)
            if overlap > 0 {
                if overlap >= counts[bucket] {
                    sum += sumSquares[bucket]
                } else {
                    // Partial overlap: assume the energy is spread evenly
                    // across the bucket.
                    sum += sumSquares[bucket] * Double(overlap) / Double(counts[bucket])
                }
            }
            bucket += 1
        }
        return sum
    }
}

private extension UInt32 {
    var littleEndianBytes: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
    }
}

private extension UInt16 {
    var littleEndianBytes: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt16>.size)
    }
}
