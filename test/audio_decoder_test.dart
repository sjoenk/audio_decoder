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
}
