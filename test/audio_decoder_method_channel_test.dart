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
      expect(methodCall.arguments['inputPath'], '/input/test.mp3');
      expect(methodCall.arguments['outputPath'], '/output/test.wav');
      return '/output/test.wav';
    });

    expect(
      await platform.convertToWav('/input/test.mp3', '/output/test.wav'),
      '/output/test.wav',
    );
  });

  test('convertToWav sends optional parameters when provided', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      MethodCall methodCall,
    ) async {
      expect(methodCall.method, 'convertToWav');
      expect(methodCall.arguments['inputPath'], '/input/test.mp3');
      expect(methodCall.arguments['outputPath'], '/output/test.wav');
      expect(methodCall.arguments['sampleRate'], 44100);
      expect(methodCall.arguments['channels'], 1);
      expect(methodCall.arguments['bitDepth'], 24);
      return '/output/test.wav';
    });

    expect(
      await platform.convertToWav('/input/test.mp3', '/output/test.wav',
          sampleRate: 44100, channels: 1, bitDepth: 24),
      '/output/test.wav',
    );
  });

  test('convertToWav omits null optional parameters', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      MethodCall methodCall,
    ) async {
      expect(methodCall.method, 'convertToWav');
      expect(methodCall.arguments.containsKey('sampleRate'), false);
      expect(methodCall.arguments.containsKey('channels'), false);
      expect(methodCall.arguments.containsKey('bitDepth'), false);
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

  group('bytes API', () {
    final testInput = Uint8List.fromList([1, 2, 3, 4]);

    test('convertToWavBytes sends correct arguments and returns bytes', () async {
      final wavBytes = Uint8List.fromList([0x52, 0x49, 0x46, 0x46]);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        MethodCall methodCall,
      ) async {
        expect(methodCall.method, 'convertToWavBytes');
        expect(methodCall.arguments['formatHint'], 'mp3');
        expect(methodCall.arguments['inputData'], isA<Uint8List>());
        return wavBytes;
      });

      final result = await platform.convertToWavBytes(testInput, 'mp3');
      expect(result, wavBytes);
    });

    test('convertToM4aBytes sends correct arguments and returns bytes', () async {
      final m4aBytes = Uint8List.fromList([0x00, 0x00, 0x00, 0x20]);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        MethodCall methodCall,
      ) async {
        expect(methodCall.method, 'convertToM4aBytes');
        expect(methodCall.arguments['formatHint'], 'wav');
        expect(methodCall.arguments['inputData'], isA<Uint8List>());
        return m4aBytes;
      });

      final result = await platform.convertToM4aBytes(testInput, 'wav');
      expect(result, m4aBytes);
    });

    test('getAudioInfoBytes sends correct arguments and returns AudioInfo', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        MethodCall methodCall,
      ) async {
        expect(methodCall.method, 'getAudioInfoBytes');
        expect(methodCall.arguments['formatHint'], 'mp3');
        expect(methodCall.arguments['inputData'], isA<Uint8List>());
        return <String, dynamic>{
          'durationMs': 3000,
          'sampleRate': 48000,
          'channels': 1,
          'bitRate': 192000,
          'format': 'mp3',
        };
      });

      final info = await platform.getAudioInfoBytes(testInput, 'mp3');
      expect(info.duration, const Duration(seconds: 3));
      expect(info.sampleRate, 48000);
      expect(info.channels, 1);
      expect(info.bitRate, 192000);
      expect(info.format, 'mp3');
    });

    test('trimAudioBytes sends correct arguments and returns bytes', () async {
      final trimmed = Uint8List.fromList([5, 6, 7]);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        MethodCall methodCall,
      ) async {
        expect(methodCall.method, 'trimAudioBytes');
        expect(methodCall.arguments['formatHint'], 'mp3');
        expect(methodCall.arguments['startMs'], 1000);
        expect(methodCall.arguments['endMs'], 3000);
        expect(methodCall.arguments['outputFormat'], 'wav');
        expect(methodCall.arguments['inputData'], isA<Uint8List>());
        return trimmed;
      });

      final result = await platform.trimAudioBytes(
        testInput, 'mp3',
        const Duration(seconds: 1), const Duration(seconds: 3),
      );
      expect(result, trimmed);
    });

    test('getWaveformBytes sends correct arguments and returns list', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        MethodCall methodCall,
      ) async {
        expect(methodCall.method, 'getWaveformBytes');
        expect(methodCall.arguments['formatHint'], 'mp3');
        expect(methodCall.arguments['numberOfSamples'], 50);
        expect(methodCall.arguments['inputData'], isA<Uint8List>());
        return List<double>.filled(50, 0.7);
      });

      final waveform = await platform.getWaveformBytes(testInput, 'mp3', 50);
      expect(waveform.length, 50);
      expect(waveform.first, 0.7);
    });

    test('convertToWavBytes throws AudioConversionException on PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        MethodCall methodCall,
      ) async {
        throw PlatformException(code: 'CONVERSION_ERROR', message: 'Failed');
      });

      expect(
        () => platform.convertToWavBytes(testInput, 'mp3'),
        throwsA(isA<AudioConversionException>()),
      );
    });

    test('convertToWavBytes throws when native returns null', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        MethodCall methodCall,
      ) async {
        return null;
      });

      expect(
        () => platform.convertToWavBytes(testInput, 'mp3'),
        throwsA(isA<AudioConversionException>()),
      );
    });

    test('convertToWavBytes sends optional parameters when provided', () async {
      final wavBytes = Uint8List.fromList([0x52, 0x49, 0x46, 0x46]);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        MethodCall methodCall,
      ) async {
        expect(methodCall.method, 'convertToWavBytes');
        expect(methodCall.arguments['sampleRate'], 22050);
        expect(methodCall.arguments['channels'], 1);
        expect(methodCall.arguments['bitDepth'], 8);
        return wavBytes;
      });

      final result = await platform.convertToWavBytes(testInput, 'mp3',
          sampleRate: 22050, channels: 1, bitDepth: 8);
      expect(result, wavBytes);
    });
  });
}
