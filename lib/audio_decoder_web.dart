import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

import 'audio_conversion_exception.dart';
import 'audio_decoder_platform_interface.dart';
import 'audio_info.dart';

/// Web platform implementation of audio_decoder using the Web Audio API.
///
/// File-based methods are not supported and throw [UnsupportedError].
/// Use the bytes-based API instead.
class AudioDecoderWeb extends AudioDecoderPlatform {
  /// Creates an [AudioDecoderWeb] instance.
  AudioDecoderWeb();

  /// Registers this implementation as the web platform instance.
  static void registerWith(Registrar registrar) {
    AudioDecoderPlatform.instance = AudioDecoderWeb();
  }

  // --- File-based methods (not supported on web) ---

  @override
  Future<String> convertToWav(String inputPath, String outputPath) {
    throw UnsupportedError(
        'File-based operations are not supported on web. Use convertToWavBytes instead.');
  }

  @override
  Future<String> convertToM4a(String inputPath, String outputPath) {
    throw UnsupportedError(
        'File-based operations are not supported on web. Use convertToM4aBytes instead.');
  }

  @override
  Future<AudioInfo> getAudioInfo(String path) {
    throw UnsupportedError(
        'File-based operations are not supported on web. Use getAudioInfoBytes instead.');
  }

  @override
  Future<String> trimAudio(
      String inputPath, String outputPath, Duration start, Duration end) {
    throw UnsupportedError(
        'File-based operations are not supported on web. Use trimAudioBytes instead.');
  }

  @override
  Future<List<double>> getWaveform(String path, int numberOfSamples) {
    throw UnsupportedError(
        'File-based operations are not supported on web. Use getWaveformBytes instead.');
  }

  // --- Bytes-based methods (Web Audio API) ---

  Future<web.AudioBuffer> _decodeAudioData(Uint8List inputData) async {
    final context = web.AudioContext();
    try {
      // Copy data since decodeAudioData detaches the ArrayBuffer
      final copy = Uint8List.fromList(inputData);
      return await context.decodeAudioData(copy.buffer.toJS).toDart;
    } catch (e) {
      if (e is AudioConversionException) rethrow;
      throw AudioConversionException('Failed to decode audio data: $e');
    } finally {
      context.close();
    }
  }

  Uint8List _encodeWav(web.AudioBuffer buffer,
      {int? startSample, int? endSample}) {
    final sampleRate = buffer.sampleRate.toInt();
    final numChannels = buffer.numberOfChannels;
    final start = startSample ?? 0;
    final end = endSample ?? buffer.length;
    final numFrames = end - start;
    const bitsPerSample = 16;
    final blockAlign = numChannels * bitsPerSample ~/ 8;
    final dataSize = numFrames * blockAlign;
    final fileSize = 44 + dataSize;

    final channels = <Float32List>[];
    for (var ch = 0; ch < numChannels; ch++) {
      final full = buffer.getChannelData(ch).toDart;
      channels.add(full.sublist(start, end));
    }

    final data = ByteData(fileSize);
    var pos = 0;

    void writeString(String s) {
      for (var i = 0; i < s.length; i++) {
        data.setUint8(pos++, s.codeUnitAt(i));
      }
    }

    // RIFF header
    writeString('RIFF');
    data.setUint32(pos, 36 + dataSize, Endian.little);
    pos += 4;
    writeString('WAVE');

    // fmt chunk
    writeString('fmt ');
    data.setUint32(pos, 16, Endian.little);
    pos += 4;
    data.setUint16(pos, 1, Endian.little);
    pos += 2; // PCM
    data.setUint16(pos, numChannels, Endian.little);
    pos += 2;
    data.setUint32(pos, sampleRate, Endian.little);
    pos += 4;
    data.setUint32(pos, sampleRate * blockAlign, Endian.little);
    pos += 4;
    data.setUint16(pos, blockAlign, Endian.little);
    pos += 2;
    data.setUint16(pos, bitsPerSample, Endian.little);
    pos += 2;

    // data chunk
    writeString('data');
    data.setUint32(pos, dataSize, Endian.little);
    pos += 4;

    // Interleaved PCM samples
    for (var i = 0; i < numFrames; i++) {
      for (var ch = 0; ch < numChannels; ch++) {
        final sample =
            (channels[ch][i] * 32767).round().clamp(-32768, 32767);
        data.setInt16(pos, sample, Endian.little);
        pos += 2;
      }
    }

    return data.buffer.asUint8List();
  }

  @override
  Future<Uint8List> convertToWavBytes(
      Uint8List inputData, String formatHint) async {
    try {
      final buffer = await _decodeAudioData(inputData);
      return _encodeWav(buffer);
    } catch (e) {
      if (e is AudioConversionException) rethrow;
      throw AudioConversionException('WAV conversion failed: $e');
    }
  }

  @override
  Future<Uint8List> convertToM4aBytes(
      Uint8List inputData, String formatHint) async {
    throw AudioConversionException(
      'M4A encoding is not supported on web',
      details:
          'Browsers do not provide a reliable AAC/M4A encoding API. Use convertToWavBytes instead.',
    );
  }

  @override
  Future<AudioInfo> getAudioInfoBytes(
      Uint8List inputData, String formatHint) async {
    try {
      final buffer = await _decodeAudioData(inputData);
      final durationMs = (buffer.duration * 1000).round();
      final sampleRate = buffer.sampleRate.toInt();
      final channels = buffer.numberOfChannels;
      final bitRate = buffer.duration > 0
          ? ((inputData.length * 8) / buffer.duration).round()
          : 0;
      return AudioInfo(
        duration: Duration(milliseconds: durationMs),
        sampleRate: sampleRate,
        channels: channels,
        bitRate: bitRate,
        format: formatHint,
      );
    } catch (e) {
      if (e is AudioConversionException) rethrow;
      throw AudioConversionException('Failed to get audio info: $e');
    }
  }

  @override
  Future<Uint8List> trimAudioBytes(Uint8List inputData, String formatHint,
      Duration start, Duration end,
      {String outputFormat = 'wav'}) async {
    if (outputFormat == 'm4a') {
      throw AudioConversionException(
        'M4A encoding is not supported on web',
        details: 'Use outputFormat: "wav" instead.',
      );
    }
    try {
      final buffer = await _decodeAudioData(inputData);
      final sampleRate = buffer.sampleRate;
      final startSample =
          (start.inMilliseconds * sampleRate / 1000).round();
      final endSample = min(
          (end.inMilliseconds * sampleRate / 1000).round(), buffer.length);
      return _encodeWav(buffer,
          startSample: startSample, endSample: endSample);
    } catch (e) {
      if (e is AudioConversionException) rethrow;
      throw AudioConversionException('Trim failed: $e');
    }
  }

  @override
  Future<List<double>> getWaveformBytes(
      Uint8List inputData, String formatHint, int numberOfSamples) async {
    try {
      final buffer = await _decodeAudioData(inputData);
      final channelData = buffer.getChannelData(0).toDart;
      final totalSamples = channelData.length;

      if (totalSamples == 0) {
        return List.filled(numberOfSamples, 0.0);
      }

      final samplesPerWindow = max(1, totalSamples ~/ numberOfSamples);
      final waveform = <double>[];
      var maxRms = 0.0;

      for (var i = 0; i < numberOfSamples; i++) {
        final start = i * totalSamples ~/ numberOfSamples;
        final end = min(start + samplesPerWindow, totalSamples);
        if (start >= totalSamples) break;

        var sumSquares = 0.0;
        for (var j = start; j < end; j++) {
          final s = channelData[j];
          sumSquares += s * s;
        }
        final rms = sqrt(sumSquares / (end - start));
        waveform.add(rms);
        if (rms > maxRms) maxRms = rms;
      }

      final result =
          waveform.map((rms) => maxRms > 0 ? rms / maxRms : 0.0).toList();

      while (result.length < numberOfSamples) {
        result.add(0.0);
      }

      return result;
    } catch (e) {
      if (e is AudioConversionException) rethrow;
      throw AudioConversionException('Waveform extraction failed: $e');
    }
  }
}
