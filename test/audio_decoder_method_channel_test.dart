import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audio_decoder/audio_decoder_method_channel.dart';
import 'package:audio_decoder/audio_conversion_exception.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelAudioDecoder platform = MethodChannelAudioDecoder();
  const MethodChannel channel = MethodChannel('audio_decoder');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('convertToWav sends correct arguments and returns path', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      MethodCall methodCall,
    ) async {
      expect(methodCall.method, 'convertToWav');
      expect(methodCall.arguments, {
        'inputPath': '/input/test.mp3',
        'outputPath': '/output/test.wav',
      });
      return '/output/test.wav';
    });

    expect(
      await platform.convertToWav('/input/test.mp3', '/output/test.wav'),
      '/output/test.wav',
    );
  });

  test('convertToWav throws AudioConversionException on PlatformException', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      MethodCall methodCall,
    ) async {
      throw PlatformException(
        code: 'CONVERSION_ERROR',
        message: 'File not found',
      );
    });

    expect(
      () => platform.convertToWav('/input/missing.mp3', '/output/test.wav'),
      throwsA(isA<AudioConversionException>()),
    );
  });

  test('convertToM4a sends correct arguments and returns path', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      MethodCall methodCall,
    ) async {
      expect(methodCall.method, 'convertToM4a');
      expect(methodCall.arguments, {
        'inputPath': '/input/test.wav',
        'outputPath': '/output/test.m4a',
      });
      return '/output/test.m4a';
    });

    expect(
      await platform.convertToM4a('/input/test.wav', '/output/test.m4a'),
      '/output/test.m4a',
    );
  });

  test('getAudioInfo sends correct arguments and returns AudioInfo', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      MethodCall methodCall,
    ) async {
      expect(methodCall.method, 'getAudioInfo');
      expect(methodCall.arguments, {'path': '/input/test.mp3'});
      return <String, dynamic>{
        'durationMs': 5000,
        'sampleRate': 44100,
        'channels': 2,
        'bitRate': 128000,
        'format': 'mp3',
      };
    });

    final info = await platform.getAudioInfo('/input/test.mp3');
    expect(info.duration, const Duration(seconds: 5));
    expect(info.sampleRate, 44100);
    expect(info.channels, 2);
    expect(info.bitRate, 128000);
    expect(info.format, 'mp3');
  });

  test('trimAudio sends correct arguments and returns path', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      MethodCall methodCall,
    ) async {
      expect(methodCall.method, 'trimAudio');
      expect(methodCall.arguments, {
        'inputPath': '/input/test.mp3',
        'outputPath': '/output/trimmed.wav',
        'startMs': 1000,
        'endMs': 3000,
      });
      return '/output/trimmed.wav';
    });

    expect(
      await platform.trimAudio(
        '/input/test.mp3',
        '/output/trimmed.wav',
        const Duration(seconds: 1),
        const Duration(seconds: 3),
      ),
      '/output/trimmed.wav',
    );
  });

  test('getWaveform sends correct arguments and returns list', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      MethodCall methodCall,
    ) async {
      expect(methodCall.method, 'getWaveform');
      expect(methodCall.arguments, {
        'path': '/input/test.mp3',
        'numberOfSamples': 50,
      });
      return List<double>.filled(50, 0.5);
    });

    final waveform = await platform.getWaveform('/input/test.mp3', 50);
    expect(waveform.length, 50);
    expect(waveform.first, 0.5);
  });

  test('convertToWav throws when native returns null', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      MethodCall methodCall,
    ) async {
      return null;
    });

    expect(
      () => platform.convertToWav('/input/test.mp3', '/output/test.wav'),
      throwsA(isA<AudioConversionException>()),
    );
  });

  test('getAudioInfo throws on PlatformException', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      MethodCall methodCall,
    ) async {
      throw PlatformException(
        code: 'INFO_ERROR',
        message: 'File not found',
      );
    });

    expect(
      () => platform.getAudioInfo('/input/missing.mp3'),
      throwsA(isA<AudioConversionException>()),
    );
  });
}
