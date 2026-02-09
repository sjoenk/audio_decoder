import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:audio_decoder/audio_decoder.dart';
import 'package:audio_decoder/audio_decoder_platform_interface.dart';
import 'package:audio_decoder/audio_decoder_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockAudioDecoderPlatform with MockPlatformInterfaceMixin implements AudioDecoderPlatform {
  @override
  Future<String> convertToWav(String inputPath, String outputPath) => Future.value(outputPath);

  @override
  Future<String> convertToM4a(String inputPath, String outputPath) => Future.value(outputPath);

  @override
  Future<AudioInfo> getAudioInfo(String path) => Future.value(
    const AudioInfo(
      duration: Duration(seconds: 5),
      sampleRate: 44100,
      channels: 2,
      bitRate: 128000,
      format: 'mp3',
    ),
  );

  @override
  Future<String> trimAudio(String inputPath, String outputPath, Duration start, Duration end) =>
      Future.value(outputPath);

  @override
  Future<List<double>> getWaveform(String path, int numberOfSamples) => Future.value(List.filled(numberOfSamples, 0.5));

  @override
  Future<Uint8List> convertToWavBytes(Uint8List inputData, String formatHint) =>
      Future.value(Uint8List.fromList([0x52, 0x49, 0x46, 0x46])); // RIFF header stub

  @override
  Future<Uint8List> convertToM4aBytes(Uint8List inputData, String formatHint) =>
      Future.value(Uint8List.fromList([0x00, 0x00, 0x00, 0x20])); // ftyp header stub

  @override
  Future<AudioInfo> getAudioInfoBytes(Uint8List inputData, String formatHint) => Future.value(
    const AudioInfo(
      duration: Duration(seconds: 3),
      sampleRate: 48000,
      channels: 1,
      bitRate: 192000,
      format: 'mp3',
    ),
  );

  @override
  Future<Uint8List> trimAudioBytes(Uint8List inputData, String formatHint, Duration start, Duration end, {String outputFormat = 'wav'}) =>
      Future.value(Uint8List.fromList([0x52, 0x49, 0x46, 0x46]));

  @override
  Future<List<double>> getWaveformBytes(Uint8List inputData, String formatHint, int numberOfSamples) =>
      Future.value(List.filled(numberOfSamples, 0.7));
}

void main() {
  final AudioDecoderPlatform initialPlatform = AudioDecoderPlatform.instance;

  test('$MethodChannelAudioDecoder is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelAudioDecoder>());
  });

  test('convertToWav delegates to platform', () async {
    MockAudioDecoderPlatform fakePlatform = MockAudioDecoderPlatform();
    AudioDecoderPlatform.instance = fakePlatform;

    expect(
      await AudioDecoder.convertToWav('/input/test.mp3', '/output/test.wav'),
      '/output/test.wav',
    );
  });

  test('convertToM4a delegates to platform', () async {
    MockAudioDecoderPlatform fakePlatform = MockAudioDecoderPlatform();
    AudioDecoderPlatform.instance = fakePlatform;

    expect(
      await AudioDecoder.convertToM4a('/input/test.wav', '/output/test.m4a'),
      '/output/test.m4a',
    );
  });

  test('getAudioInfo delegates to platform', () async {
    MockAudioDecoderPlatform fakePlatform = MockAudioDecoderPlatform();
    AudioDecoderPlatform.instance = fakePlatform;

    final info = await AudioDecoder.getAudioInfo('/path/to/test.mp3');
    expect(info.duration, const Duration(seconds: 5));
    expect(info.sampleRate, 44100);
    expect(info.channels, 2);
    expect(info.bitRate, 128000);
    expect(info.format, 'mp3');
  });

  test('trimAudio delegates to platform', () async {
    MockAudioDecoderPlatform fakePlatform = MockAudioDecoderPlatform();
    AudioDecoderPlatform.instance = fakePlatform;

    expect(
      await AudioDecoder.trimAudio(
        '/input/test.mp3',
        '/output/trimmed.wav',
        const Duration(seconds: 1),
        const Duration(seconds: 3),
      ),
      '/output/trimmed.wav',
    );
  });

  test('getWaveform delegates to platform', () async {
    MockAudioDecoderPlatform fakePlatform = MockAudioDecoderPlatform();
    AudioDecoderPlatform.instance = fakePlatform;

    final waveform = await AudioDecoder.getWaveform('/path/to/test.mp3', numberOfSamples: 50);
    expect(waveform.length, 50);
    expect(waveform.first, 0.5);
  });

  group('needsConversion', () {
    test('returns false for .wav files', () {
      expect(AudioDecoder.needsConversion('/path/to/file.wav'), false);
      expect(AudioDecoder.needsConversion('/path/to/FILE.WAV'), false);
      expect(AudioDecoder.needsConversion('/path/to/file.wave'), false);
    });

    test('returns true for MP3 files', () {
      expect(AudioDecoder.needsConversion('/path/to/file.mp3'), true);
    });

    test('returns true for M4A files', () {
      expect(AudioDecoder.needsConversion('/path/to/file.m4a'), true);
    });

    test('returns true for AAC files', () {
      expect(AudioDecoder.needsConversion('/path/to/file.aac'), true);
    });

    test('returns true for all supported formats', () {
      for (final ext in AudioDecoder.supportedExtensions) {
        expect(
          AudioDecoder.needsConversion('/path/to/file$ext'),
          true,
          reason: 'Expected true for $ext',
        );
      }
    });

    test('returns false for unknown extensions', () {
      expect(AudioDecoder.needsConversion('/path/to/file.xyz'), false);
      expect(AudioDecoder.needsConversion('/path/to/file.txt'), false);
    });
  });

  group('bytes API', () {
    late MockAudioDecoderPlatform fakePlatform;

    setUp(() {
      fakePlatform = MockAudioDecoderPlatform();
      AudioDecoderPlatform.instance = fakePlatform;
    });

    test('convertToWavBytes delegates to platform', () async {
      final input = Uint8List.fromList([1, 2, 3]);
      final result = await AudioDecoder.convertToWavBytes(input, formatHint: 'mp3');
      expect(result, isNotEmpty);
      expect(result[0], 0x52); // 'R' from RIFF
    });

    test('convertToM4aBytes delegates to platform', () async {
      final input = Uint8List.fromList([1, 2, 3]);
      final result = await AudioDecoder.convertToM4aBytes(input, formatHint: 'wav');
      expect(result, isNotEmpty);
      expect(result[0], 0x00);
    });

    test('getAudioInfoBytes delegates to platform', () async {
      final input = Uint8List.fromList([1, 2, 3]);
      final info = await AudioDecoder.getAudioInfoBytes(input, formatHint: 'mp3');
      expect(info.duration, const Duration(seconds: 3));
      expect(info.sampleRate, 48000);
      expect(info.channels, 1);
      expect(info.bitRate, 192000);
      expect(info.format, 'mp3');
    });

    test('trimAudioBytes delegates to platform', () async {
      final input = Uint8List.fromList([1, 2, 3]);
      final result = await AudioDecoder.trimAudioBytes(
        input,
        formatHint: 'mp3',
        start: const Duration(seconds: 1),
        end: const Duration(seconds: 2),
      );
      expect(result, isNotEmpty);
    });

    test('getWaveformBytes delegates to platform', () async {
      final input = Uint8List.fromList([1, 2, 3]);
      final waveform = await AudioDecoder.getWaveformBytes(
        input,
        formatHint: 'mp3',
        numberOfSamples: 30,
      );
      expect(waveform.length, 30);
      expect(waveform.first, 0.7);
    });
  });
}
