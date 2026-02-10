import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:audio_decoder/audio_decoder.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ── Helpers ──────────────────────────────────────────────────────────

  int readUint16LE(Uint8List bytes, int offset) =>
      bytes[offset] | (bytes[offset + 1] << 8);

  int readUint32LE(Uint8List bytes, int offset) =>
      bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);

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

  Future<Uint8List> loadAsset(String name) async {
    final data = await rootBundle.load('assets/$name');
    return data.buffer.asUint8List();
  }

  // ── convertToWavBytes ───────────────────────────────────────────────

  group('convertToWavBytes', () {
    testWidgets('MP3 → WAV bytes produces valid WAV',
        (WidgetTester tester) async {
      final mp3Bytes = await loadAsset('test_tone.mp3');
      final wavBytes =
          await AudioDecoder.convertToWavBytes(mp3Bytes, formatHint: 'mp3');

      validateWavHeader(wavBytes);
    });

    testWidgets('M4A → WAV bytes produces valid WAV',
        (WidgetTester tester) async {
      final m4aBytes = await loadAsset('test_tone.m4a');
      final wavBytes =
          await AudioDecoder.convertToWavBytes(m4aBytes, formatHint: 'm4a');

      validateWavHeader(wavBytes);
    });

    testWidgets('without header returns raw PCM',
        (WidgetTester tester) async {
      final mp3Bytes = await loadAsset('test_tone.mp3');
      final wavBytes =
          await AudioDecoder.convertToWavBytes(mp3Bytes, formatHint: 'mp3');
      final pcmBytes = await AudioDecoder.convertToWavBytes(mp3Bytes,
          formatHint: 'mp3', includeHeader: false);

      expect(pcmBytes.length, wavBytes.length - 44);
      expect(String.fromCharCodes(pcmBytes.sublist(0, 4)), isNot('RIFF'));
      expect(pcmBytes, wavBytes.sublist(44));
    });

    testWidgets('with parameters reflects in header',
        (WidgetTester tester) async {
      final mp3Bytes = await loadAsset('test_tone.mp3');
      final wavBytes = await AudioDecoder.convertToWavBytes(
        mp3Bytes,
        formatHint: 'mp3',
        sampleRate: 22050,
        channels: 1,
        bitDepth: 16,
      );

      final header = validateWavHeader(wavBytes);
      expect(header['sampleRate'], 22050);
      expect(header['channels'], 1);
      expect(header['bitsPerSample'], 16);
    });
  });

  // ── getAudioInfoBytes ───────────────────────────────────────────────

  group('getAudioInfoBytes', () {
    for (final entry in {'test_tone.mp3': 'mp3', 'test_tone.m4a': 'm4a'}.entries) {
      testWidgets('returns realistic metadata for ${entry.key}',
          (WidgetTester tester) async {
        final bytes = await loadAsset(entry.key);
        final info =
            await AudioDecoder.getAudioInfoBytes(bytes, formatHint: entry.value);

        expect(info.duration.inMilliseconds, greaterThan(0));
        expect(info.sampleRate, greaterThan(0));
        expect(info.channels, anyOf(1, 2));
      });
    }
  });

  // ── trimAudioBytes ──────────────────────────────────────────────────

  group('trimAudioBytes', () {
    testWidgets('trimmed output is smaller than full conversion',
        (WidgetTester tester) async {
      final mp3Bytes = await loadAsset('test_tone.mp3');

      final fullWav =
          await AudioDecoder.convertToWavBytes(mp3Bytes, formatHint: 'mp3');
      final trimmed = await AudioDecoder.trimAudioBytes(
        mp3Bytes,
        formatHint: 'mp3',
        start: const Duration(milliseconds: 200),
        end: const Duration(milliseconds: 800),
      );

      expect(trimmed.length, greaterThan(0));
      expect(trimmed.length, lessThan(fullWav.length));
    });
  });

  // ── getWaveformBytes ────────────────────────────────────────────────

  group('getWaveformBytes', () {
    testWidgets('returns correct number of normalized samples',
        (WidgetTester tester) async {
      final mp3Bytes = await loadAsset('test_tone.mp3');

      const sampleCount = 150;
      final waveform = await AudioDecoder.getWaveformBytes(
        mp3Bytes,
        formatHint: 'mp3',
        numberOfSamples: sampleCount,
      );

      expect(waveform.length, sampleCount);
      for (final sample in waveform) {
        expect(sample, greaterThanOrEqualTo(0.0));
        expect(sample, lessThanOrEqualTo(1.0));
      }
    });
  });

  // ── Error handling ──────────────────────────────────────────────────

  group('Error handling', () {
    testWidgets('corrupt bytes throw AudioConversionException',
        (WidgetTester tester) async {
      final garbage = Uint8List.fromList(List.filled(256, 0xFF));

      expect(
        () => AudioDecoder.convertToWavBytes(garbage, formatHint: 'mp3'),
        throwsA(isA<AudioConversionException>()),
      );
    });

    testWidgets('convertToM4aBytes throws on web',
        (WidgetTester tester) async {
      final mp3Bytes = await loadAsset('test_tone.mp3');

      expect(
        () => AudioDecoder.convertToM4aBytes(mp3Bytes, formatHint: 'mp3'),
        throwsA(isA<AudioConversionException>()),
      );
    });

    testWidgets('file-based convertToWav throws UnsupportedError',
        (WidgetTester tester) async {
      expect(
        () => AudioDecoder.convertToWav('/fake/input.mp3', '/fake/output.wav'),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });

  // ── needsConversion (pure Dart) ─────────────────────────────────────

  testWidgets('needsConversion test', (WidgetTester tester) async {
    expect(AudioDecoder.needsConversion('test.mp3'), true);
    expect(AudioDecoder.needsConversion('test.wav'), false);
  });
}
