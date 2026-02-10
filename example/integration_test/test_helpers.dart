import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Read a little-endian uint16 from [bytes] at [offset].
int readUint16LE(Uint8List bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8);

/// Read a little-endian uint32 from [bytes] at [offset].
int readUint32LE(Uint8List bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);

/// Validate the WAV header structure of [bytes] and return a map with
/// the parsed header fields.
Map<String, int> validateWavHeader(Uint8List bytes) {
  expect(bytes.length, greaterThan(44),
      reason: 'WAV file must be larger than 44-byte header');
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
