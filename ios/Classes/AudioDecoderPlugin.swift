import Flutter
import UIKit
import AVFoundation

public class AudioDecoderPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "audio_decoder",
            binaryMessenger: registrar.messenger()
        )
        let instance = AudioDecoderPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "convertToWav":
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
            convertToWav(inputPath: inputPath, outputPath: outputPath, result: result)
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
            getWaveform(path: path, numberOfSamples: numberOfSamples, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Convert to WAV

    private func convertToWav(inputPath: String, outputPath: String, result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.performConversion(inputPath: inputPath, outputPath: outputPath)
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

    private func performConversion(inputPath: String, outputPath: String) throws {
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
            throw NSError(domain: "AudioDecoder", code: 3,
                          userInfo: [NSLocalizedDescriptionKey:
                                        "AVAssetReader failed to start: \(assetReader.error?.localizedDescription ?? "unknown")"])
        }

        var pcmData = Data()
        while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
            if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                let length = CMBlockBufferGetDataLength(blockBuffer)
                var data = Data(count: length)
                data.withUnsafeMutableBytes { ptr in
                    CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length,
                                               destination: ptr.baseAddress!)
                }
                pcmData.append(data)
            }
        }

        if assetReader.status == .failed {
            throw NSError(domain: "AudioDecoder", code: 4,
                          userInfo: [NSLocalizedDescriptionKey:
                                        "AVAssetReader failed: \(assetReader.error?.localizedDescription ?? "unknown")"])
        }

        guard let formatDesc = audioTrack.formatDescriptions.first else {
            throw NSError(domain: "AudioDecoder", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "No format description available"])
        }

        let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(
            formatDesc as! CMAudioFormatDescription
        )!.pointee

        let sampleRate = Int(asbd.mSampleRate)
        let channels = Int(asbd.mChannelsPerFrame)
        let bitsPerSample = 16

        try writeWavFile(outputURL: outputURL, pcmData: pcmData,
                         sampleRate: sampleRate, channels: channels, bitsPerSample: bitsPerSample)
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
            // Decode trimmed range to PCM and write WAV
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

            guard assetReader.startReading() else {
                throw NSError(domain: "AudioDecoder", code: 34,
                              userInfo: [NSLocalizedDescriptionKey: "AVAssetReader failed to start"])
            }

            var pcmData = Data()
            while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
                if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                    let length = CMBlockBufferGetDataLength(blockBuffer)
                    var data = Data(count: length)
                    data.withUnsafeMutableBytes { ptr in
                        CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length,
                                                   destination: ptr.baseAddress!)
                    }
                    pcmData.append(data)
                }
            }

            if assetReader.status == .failed {
                throw NSError(domain: "AudioDecoder", code: 35,
                              userInfo: [NSLocalizedDescriptionKey: "AVAssetReader failed"])
            }

            guard let formatDesc = audioTrack.formatDescriptions.first else {
                throw NSError(domain: "AudioDecoder", code: 36,
                              userInfo: [NSLocalizedDescriptionKey: "No format description available"])
            }

            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(
                formatDesc as! CMAudioFormatDescription
            )!.pointee

            let sampleRate = Int(asbd.mSampleRate)
            let channels = Int(asbd.mChannelsPerFrame)

            try writeWavFile(outputURL: outputURL, pcmData: pcmData,
                             sampleRate: sampleRate, channels: channels, bitsPerSample: 16)
        }
    }

    // MARK: - Get Waveform

    private func getWaveform(path: String, numberOfSamples: Int, result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let waveform = try self.performGetWaveform(path: path, numberOfSamples: numberOfSamples)
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

    private func performGetWaveform(path: String, numberOfSamples: Int) throws -> [Double] {
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

        // Read all PCM samples
        var allSamples = [Int16]()
        while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
            if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                let length = CMBlockBufferGetDataLength(blockBuffer)
                var data = Data(count: length)
                data.withUnsafeMutableBytes { ptr in
                    CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length,
                                               destination: ptr.baseAddress!)
                }
                data.withUnsafeBytes { rawPtr in
                    let samples = rawPtr.bindMemory(to: Int16.self)
                    allSamples.append(contentsOf: samples)
                }
            }
        }

        if allSamples.isEmpty {
            return Array(repeating: 0.0, count: numberOfSamples)
        }

        // Compute RMS per window
        let samplesPerWindow = max(1, allSamples.count / numberOfSamples)
        var waveform = [Double]()
        var maxRms = 0.0

        for i in 0..<numberOfSamples {
            let start = i * allSamples.count / numberOfSamples
            let end = min(start + samplesPerWindow, allSamples.count)
            if start >= allSamples.count { break }

            var sumSquares: Double = 0
            for j in start..<end {
                let sample = Double(allSamples[j])
                sumSquares += sample * sample
            }
            let rms = sqrt(sumSquares / Double(end - start))
            waveform.append(rms)
            if rms > maxRms { maxRms = rms }
        }

        // Normalize to 0.0-1.0
        if maxRms > 0 {
            waveform = waveform.map { $0 / maxRms }
        }

        // Pad if needed
        while waveform.count < numberOfSamples {
            waveform.append(0.0)
        }

        return waveform
    }

    // MARK: - WAV writing helper

    private func writeWavFile(outputURL: URL, pcmData: Data,
                              sampleRate: Int, channels: Int, bitsPerSample: Int) throws {
        let byteRate = sampleRate * channels * (bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)

        var wavData = Data()
        wavData.append(contentsOf: [UInt8]("RIFF".utf8))
        wavData.append(UInt32(36 + pcmData.count).littleEndianBytes)
        wavData.append(contentsOf: [UInt8]("WAVE".utf8))
        wavData.append(contentsOf: [UInt8]("fmt ".utf8))
        wavData.append(UInt32(16).littleEndianBytes)
        wavData.append(UInt16(1).littleEndianBytes)
        wavData.append(UInt16(channels).littleEndianBytes)
        wavData.append(UInt32(sampleRate).littleEndianBytes)
        wavData.append(UInt32(byteRate).littleEndianBytes)
        wavData.append(UInt16(blockAlign).littleEndianBytes)
        wavData.append(UInt16(bitsPerSample).littleEndianBytes)
        wavData.append(contentsOf: [UInt8]("data".utf8))
        wavData.append(UInt32(pcmData.count).littleEndianBytes)
        wavData.append(pcmData)

        try wavData.write(to: outputURL)
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
