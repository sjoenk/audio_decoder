import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Read a little-endian uint16 from [bytes] at [offset].
int readUint16LE(Uint8List bytes, int offset) => bytes[offset] | (bytes[offset + 1] << 8);

/// Read a little-endian uint32 from [bytes] at [offset].
int readUint32LE(Uint8List bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24);

/// Build a synthetic mono 16-bit PCM WAV with [frameCount] frames and a
/// non-silent sawtooth waveform.
///
/// Used to exercise long-file code paths on device without bundling a large
/// asset in the repository.
Uint8List buildPcmWav({required int frameCount, int sampleRate = 44100}) {
  const channels = 1;
  const bytesPerSample = 2; // 16-bit
  final dataSize = frameCount * channels * bytesPerSample;
  final bytes = Uint8List(44 + dataSize);
  final view = ByteData.view(bytes.buffer);

  bytes.setRange(0, 4, 'RIFF'.codeUnits);
  view.setUint32(4, 36 + dataSize, Endian.little);
  bytes.setRange(8, 12, 'WAVE'.codeUnits);
  bytes.setRange(12, 16, 'fmt '.codeUnits);
  view.setUint32(16, 16, Endian.little);
  view.setUint16(20, 1, Endian.little); // PCM
  view.setUint16(22, channels, Endian.little);
  view.setUint32(24, sampleRate, Endian.little);
  view.setUint32(28, sampleRate * channels * bytesPerSample, Endian.little);
  view.setUint16(32, channels * bytesPerSample, Endian.little);
  view.setUint16(34, 16, Endian.little);
  bytes.setRange(36, 40, 'data'.codeUnits);
  view.setUint32(40, dataSize, Endian.little);

  // Sawtooth payload so every window has a non-zero RMS.
  for (var i = 0; i < frameCount; i++) {
    view.setInt16(44 + i * bytesPerSample, ((i * 137) % 65536) - 32768, Endian.little);
  }
  return bytes;
}

/// Write a synthetic mono 16-bit PCM WAV of [frameCount] frames to [path] in
/// blocks, without ever holding the whole payload in memory.
///
/// Long-file tests need inputs of a few hundred megabytes; building those as a
/// single [Uint8List] (like [buildPcmWav] does) would make the test itself run
/// out of memory before it reaches the plugin.
Future<void> writePcmWavFile({
  required String path,
  required int frameCount,
  int sampleRate = 44100,
  int framesPerBlock = 1 << 16,
}) async {
  const channels = 1;
  const bytesPerSample = 2; // 16-bit
  final dataSize = frameCount * channels * bytesPerSample;

  final header = buildPcmWav(frameCount: 0, sampleRate: sampleRate);
  ByteData.view(header.buffer).setUint32(4, 36 + dataSize, Endian.little);
  ByteData.view(header.buffer).setUint32(40, dataSize, Endian.little);

  final sink = File(path).openWrite();
  try {
    sink.add(header);

    final block = Uint8List(framesPerBlock * bytesPerSample);
    final blockView = ByteData.view(block.buffer);
    var written = 0;
    while (written < frameCount) {
      final frames = (frameCount - written).clamp(0, framesPerBlock);
      for (var i = 0; i < frames; i++) {
        // Same sawtooth payload as buildPcmWav, so every window has a
        // non-zero RMS.
        blockView.setInt16(
          i * bytesPerSample,
          (((written + i) * 137) % 65536) - 32768,
          Endian.little,
        );
      }
      sink.add(Uint8List.sublistView(block, 0, frames * bytesPerSample));
      written += frames;
    }
  } finally {
    await sink.close();
  }
}

/// Validate the WAV header structure of [bytes] and return a map with
/// the parsed header fields.
Map<String, int> validateWavHeader(Uint8List bytes) {
  expect(
    bytes.length,
    greaterThan(44),
    reason: 'WAV file must be larger than 44-byte header',
  );
  expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
  expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
  expect(String.fromCharCodes(bytes.sublist(12, 16)), 'fmt ');

  final audioFormat = readUint16LE(bytes, 20);
  expect(audioFormat, 1, reason: 'Audio format should be PCM (1)');

  final channels = readUint16LE(bytes, 22);
  final sampleRate = readUint32LE(bytes, 24);
  final bitsPerSample = readUint16LE(bytes, 34);

  expect(channels, greaterThan(0));
  expect(sampleRate, greaterThan(0));
  expect(bitsPerSample, greaterThan(0));

  return {
    'channels': channels,
    'sampleRate': sampleRate,
    'bitsPerSample': bitsPerSample,
  };
}
