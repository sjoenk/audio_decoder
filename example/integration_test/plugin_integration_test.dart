import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:audio_decoder/audio_decoder.dart';

import 'test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ── Helpers ──────────────────────────────────────────────────────────

  late Directory tempDir;

  setUpAll(() {
    if (Platform.isAndroid) {
      // On Android `systemTemp` is the app's code_cache directory. Android
      // clears cache directories (code_cache included) after a fresh install
      // and whenever storage runs low, which makes files — and even the
      // directory itself — disappear halfway through a run. The app's files
      // directory is never cleared by the platform.
      tempDir = Directory('${Directory.systemTemp.parent.path}/files/audio_decoder_test')..createSync(recursive: true);
    } else {
      tempDir = Directory.systemTemp.createTempSync('audio_decoder_test_');
    }
  });

  tearDownAll(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  /// Copy a bundled asset to a temp file and return its path.
  Future<String> copyAssetToTemp(String assetName) async {
    final data = await rootBundle.load('assets/$assetName');
    final file = File('${tempDir.path}/$assetName');
    await file.writeAsBytes(data.buffer.asUint8List());
    return file.path;
  }

  /// Build a temp output path with the given [extension] (e.g. 'wav').
  String tempOutputPath(String name, String extension) => '${tempDir.path}/${name}_output.$extension';

  // ── 1. convertToWav ─────────────────────────────────────────────────

  group('convertToWav', () {
    testWidgets('MP3 → WAV produces valid WAV file', (
      WidgetTester tester,
    ) async {
      final inputPath = await copyAssetToTemp('test_tone.mp3');
      final outputPath = tempOutputPath('mp3_to_wav', 'wav');

      final result = await AudioDecoder.convertToWav(inputPath, outputPath);

      final outputFile = File(result);
      expect(await outputFile.exists(), isTrue);
      final bytes = await outputFile.readAsBytes();

      final header = validateWavHeader(bytes);
      expect(header['sampleRate'], greaterThan(0));
      expect(header['channels'], anyOf(1, 2));
      expect(header['bitsPerSample'], anyOf(8, 16, 24, 32));

      // Validate reasonable file size:
      // expectedSize ≈ duration × sampleRate × channels × bytesPerSample + 44
      // For a short tone the WAV should be at least a few KB
      expect(bytes.length, greaterThan(1000));
    });

    testWidgets('M4A → WAV produces valid WAV file', (
      WidgetTester tester,
    ) async {
      final inputPath = await copyAssetToTemp('test_tone.m4a');
      final outputPath = tempOutputPath('m4a_to_wav', 'wav');

      final result = await AudioDecoder.convertToWav(inputPath, outputPath);

      final outputFile = File(result);
      expect(await outputFile.exists(), isTrue);
      final bytes = await outputFile.readAsBytes();

      final header = validateWavHeader(bytes);
      expect(header['sampleRate'], greaterThan(0));
      expect(header['channels'], anyOf(1, 2));
      expect(header['bitsPerSample'], anyOf(8, 16, 24, 32));
      expect(bytes.length, greaterThan(1000));
    });
  });

  // ── 2. convertToWav with parameters ─────────────────────────────────

  group('convertToWav with parameters', () {
    testWidgets('forces sampleRate, channels, and bitDepth', (
      WidgetTester tester,
    ) async {
      final inputPath = await copyAssetToTemp('test_tone.mp3');
      final outputPath = tempOutputPath('mp3_params', 'wav');

      const targetSampleRate = 22050;
      const targetChannels = 1;
      const targetBitDepth = 16;

      await AudioDecoder.convertToWav(
        inputPath,
        outputPath,
        sampleRate: targetSampleRate,
        channels: targetChannels,
        bitDepth: targetBitDepth,
      );

      final bytes = await File(outputPath).readAsBytes();
      final header = validateWavHeader(bytes);

      expect(header['sampleRate'], targetSampleRate);
      expect(header['channels'], targetChannels);
      expect(header['bitsPerSample'], targetBitDepth);
    });
  });

  // ── 2b. Streaming path (no resampling) ────────────────────────────
  // When only channels and/or bitDepth are specified (no sampleRate),
  // the streaming path writes PCM chunks directly to disk via
  // RandomAccessFile instead of buffering the full output in memory.

  group('convertToWav streaming path', () {
    testWidgets('channel conversion only (stereo → mono) uses streaming path', (
      WidgetTester tester,
    ) async {
      final inputPath = await copyAssetToTemp('test_tone.mp3');
      final outputPath = tempOutputPath('stream_mono', 'wav');

      await AudioDecoder.convertToWav(inputPath, outputPath, channels: 1);

      final bytes = await File(outputPath).readAsBytes();
      final header = validateWavHeader(bytes);

      expect(header['channels'], 1);
      // sampleRate should be preserved from source (no resampling)
      final sourceInfo = await AudioDecoder.getAudioInfo(inputPath);
      expect(header['sampleRate'], sourceInfo.sampleRate);
    });

    testWidgets('bit depth conversion only (16 → 24 bit) uses streaming path', (
      WidgetTester tester,
    ) async {
      final inputPath = await copyAssetToTemp('test_tone.mp3');
      final outputPath = tempOutputPath('stream_24bit', 'wav');

      await AudioDecoder.convertToWav(inputPath, outputPath, bitDepth: 24);

      final bytes = await File(outputPath).readAsBytes();
      final header = validateWavHeader(bytes);

      expect(header['bitsPerSample'], 24);
      final sourceInfo = await AudioDecoder.getAudioInfo(inputPath);
      expect(header['sampleRate'], sourceInfo.sampleRate);
    });

    testWidgets('channel + bit depth conversion without resampling', (
      WidgetTester tester,
    ) async {
      final inputPath = await copyAssetToTemp('test_tone.mp3');
      final outputPath = tempOutputPath('stream_mono_24bit', 'wav');

      await AudioDecoder.convertToWav(
        inputPath,
        outputPath,
        channels: 1,
        bitDepth: 24,
      );

      final bytes = await File(outputPath).readAsBytes();
      final header = validateWavHeader(bytes);

      expect(header['channels'], 1);
      expect(header['bitsPerSample'], 24);
      final sourceInfo = await AudioDecoder.getAudioInfo(inputPath);
      expect(header['sampleRate'], sourceInfo.sampleRate);
    });

    testWidgets('WAV header data size matches actual PCM payload', (
      WidgetTester tester,
    ) async {
      final inputPath = await copyAssetToTemp('test_tone.mp3');
      final outputPath = tempOutputPath('stream_header_check', 'wav');

      await AudioDecoder.convertToWav(inputPath, outputPath);

      final bytes = await File(outputPath).readAsBytes();
      validateWavHeader(bytes);

      // The data chunk size at offset 40 should equal totalFileSize - 44
      final dataChunkSize = readUint32LE(bytes, 40);
      expect(
        dataChunkSize,
        bytes.length - 44,
        reason: 'WAV data chunk size should match actual PCM payload',
      );

      // The RIFF chunk size at offset 4 should equal totalFileSize - 8
      final riffChunkSize = readUint32LE(bytes, 4);
      expect(
        riffChunkSize,
        bytes.length - 8,
        reason: 'RIFF chunk size should equal file size minus 8',
      );
    });
  });

  // ── 3. convertToM4a ─────────────────────────────────────────────────

  group('convertToM4a', () {
    testWidgets('WAV → M4A produces non-empty output', (
      WidgetTester tester,
    ) async {
      final inputPath = await copyAssetToTemp('test_tone.wav');
      final outputPath = tempOutputPath('wav_to_m4a', 'm4a');

      final result = await AudioDecoder.convertToM4a(inputPath, outputPath);

      final outputFile = File(result);
      expect(await outputFile.exists(), isTrue);
      final size = await outputFile.length();
      expect(size, greaterThan(0));
    });

    testWidgets('long file converts without exhausting memory (regression #49)', (
      WidgetTester tester,
    ) async {
      // The decoder used to collect every PCM chunk before encoding started,
      // so peak memory grew with the audio duration: three hours of 44.1 kHz
      // stereo decodes to ~1.9 GB of PCM, well past the Android per-app heap
      // limit. Decoding and encoding now run interleaved.
      //
      // Three minutes (~16 MB of PCM, thousands of chunks) is a compromise:
      // software codecs on an emulator run at roughly real time, so the
      // hundreds of megabytes it would take to actually hit the old heap
      // ceiling would make this test run for half an hour. What it does cover
      // is that a long chunk sequence still streams through end to end.
      const frameCount = 44100 * 60 * 3;
      final inputPath = '${tempDir.path}/long_tone_m4a_input.wav';
      await writePcmWavFile(path: inputPath, frameCount: frameCount);
      final outputPath = tempOutputPath('long_wav_to_m4a', 'm4a');

      final result = await AudioDecoder.convertToM4a(inputPath, outputPath);

      final outputFile = File(result);
      expect(await outputFile.exists(), isTrue);
      expect(await outputFile.length(), greaterThan(0));

      final info = await AudioDecoder.getAudioInfo(result);
      expect(
        info.duration.inSeconds,
        greaterThanOrEqualTo(175),
        reason: 'Encoded output should cover the full input duration',
      );

      await File(inputPath).delete();
    }, timeout: const Timeout(Duration(minutes: 10)));
  });

  // ── 4. getAudioInfo ─────────────────────────────────────────────────

  group('getAudioInfo', () {
    for (final asset in ['test_tone.mp3', 'test_tone.m4a', 'test_tone.wav']) {
      testWidgets('returns realistic metadata for $asset', (
        WidgetTester tester,
      ) async {
        final inputPath = await copyAssetToTemp(asset);
        final info = await AudioDecoder.getAudioInfo(inputPath);

        expect(
          info.duration.inMilliseconds,
          greaterThan(0),
          reason: '$asset duration should be > 0',
        );
        expect(
          info.sampleRate,
          greaterThan(0),
          reason: '$asset sampleRate should be > 0',
        );
        expect(
          info.channels,
          anyOf(1, 2),
          reason: '$asset channels should be 1 or 2',
        );
      });
    }
  });

  // ── 5. trimAudio ────────────────────────────────────────────────────

  group('trimAudio', () {
    testWidgets('trimmed output is shorter than original', (
      WidgetTester tester,
    ) async {
      final inputPath = await copyAssetToTemp('test_tone.mp3');

      // First convert to WAV to have a baseline
      final fullWavPath = tempOutputPath('trim_full', 'wav');
      await AudioDecoder.convertToWav(inputPath, fullWavPath);
      final fullInfo = await AudioDecoder.getAudioInfo(fullWavPath);

      // Trim to 0.2s – 0.8s
      final trimmedPath = tempOutputPath('trim_partial', 'wav');
      await AudioDecoder.trimAudio(
        inputPath,
        trimmedPath,
        const Duration(milliseconds: 200),
        const Duration(milliseconds: 800),
      );

      final trimmedFile = File(trimmedPath);
      expect(await trimmedFile.exists(), isTrue);

      final trimmedInfo = await AudioDecoder.getAudioInfo(trimmedPath);
      expect(
        trimmedInfo.duration.inMilliseconds,
        lessThan(fullInfo.duration.inMilliseconds),
        reason: 'Trimmed duration should be shorter than the original',
      );

      final trimmedSize = await trimmedFile.length();
      final fullSize = await File(fullWavPath).length();
      expect(
        trimmedSize,
        lessThan(fullSize),
        reason: 'Trimmed file should be smaller than the full file',
      );
    });
  });

  // ── 6. getWaveform ──────────────────────────────────────────────────

  group('getWaveform', () {
    testWidgets('returns correct number of normalized samples', (
      WidgetTester tester,
    ) async {
      final inputPath = await copyAssetToTemp('test_tone.mp3');

      const sampleCount = 200;
      final waveform = await AudioDecoder.getWaveform(
        inputPath,
        numberOfSamples: sampleCount,
      );

      expect(waveform.length, sampleCount);
      for (final sample in waveform) {
        expect(
          sample,
          greaterThanOrEqualTo(0.0),
          reason: 'Waveform sample should be >= 0.0',
        );
        expect(
          sample,
          lessThanOrEqualTo(1.0),
          reason: 'Waveform sample should be <= 1.0',
        );
      }
    });

    testWidgets(
      'absolute normalization preserves cross-file loudness differences',
      (WidgetTester tester) async {
        final inputPath = await copyAssetToTemp('test_tone.mp3');

        const sampleCount = 200;
        final perFile = await AudioDecoder.getWaveform(
          inputPath,
          numberOfSamples: sampleCount,
        );
        final absolute = await AudioDecoder.getWaveform(
          inputPath,
          numberOfSamples: sampleCount,
          normalization: WaveformNormalization.absolute,
        );

        expect(absolute.length, sampleCount);
        for (final sample in absolute) {
          expect(sample, greaterThanOrEqualTo(0.0));
          expect(sample, lessThanOrEqualTo(1.0));
        }

        // perFile is rescaled so its loudest window equals 1.0;
        // absolute is divided by the int16 max magnitude (32768), so its
        // peak should be <= the perFile peak. They should not be identical.
        final perFilePeak = perFile.reduce((a, b) => a > b ? a : b);
        final absolutePeak = absolute.reduce((a, b) => a > b ? a : b);
        expect(absolutePeak, lessThanOrEqualTo(perFilePeak + 1e-9));
        expect(
          absolutePeak,
          lessThan(perFilePeak),
          reason:
              'absolute peak should be strictly smaller than perFile peak '
              'unless the source happens to be at full scale',
        );
      },
    );

    testWidgets('long file does not overflow window offsets (regression #45)', (
      WidgetTester tester,
    ) async {
      // A multi-minute file decodes to millions of PCM samples. With 32-bit
      // window arithmetic the offset `i * totalSamples` exceeds Int.MAX_VALUE
      // and wraps to a negative index, crashing on Android with an
      // IndexOutOfBoundsException. 3M mono frames is enough to push the last
      // windows past the 32-bit limit (999 * 3_000_000 ≈ 3.0e9 > 2.15e9).
      final inputPath = '${tempDir.path}/long_tone.wav';
      await File(inputPath).writeAsBytes(buildPcmWav(frameCount: 3000000));

      const sampleCount = 1000;
      final waveform = await AudioDecoder.getWaveform(
        inputPath,
        numberOfSamples: sampleCount,
      );

      expect(waveform.length, sampleCount);
      for (final sample in waveform) {
        expect(sample, greaterThanOrEqualTo(0.0));
        expect(sample, lessThanOrEqualTo(1.0));
      }
    });
  });

  // ── 7. Bytes API ────────────────────────────────────────────────────

  group('Bytes API', () {
    testWidgets('convertToWavBytes returns valid WAV', (
      WidgetTester tester,
    ) async {
      final mp3Bytes = (await rootBundle.load(
        'assets/test_tone.mp3',
      )).buffer.asUint8List();
      final wavBytes = await AudioDecoder.convertToWavBytes(
        mp3Bytes,
        formatHint: 'mp3',
      );

      validateWavHeader(wavBytes);
    });

    testWidgets('convertToWavBytes without header returns raw PCM', (
      WidgetTester tester,
    ) async {
      final mp3Bytes = (await rootBundle.load(
        'assets/test_tone.mp3',
      )).buffer.asUint8List();
      final wavBytes = await AudioDecoder.convertToWavBytes(
        mp3Bytes,
        formatHint: 'mp3',
      );
      final pcmBytes = await AudioDecoder.convertToWavBytes(
        mp3Bytes,
        formatHint: 'mp3',
        includeHeader: false,
      );

      expect(pcmBytes.length, wavBytes.length - 44);
      expect(String.fromCharCodes(pcmBytes.sublist(0, 4)), isNot('RIFF'));
      expect(pcmBytes, wavBytes.sublist(44));
    });

    testWidgets('convertToWavBytes with parameters reflects in header', (
      WidgetTester tester,
    ) async {
      final mp3Bytes = (await rootBundle.load(
        'assets/test_tone.mp3',
      )).buffer.asUint8List();
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

    testWidgets('getAudioInfoBytes returns realistic metadata', (
      WidgetTester tester,
    ) async {
      final mp3Bytes = (await rootBundle.load(
        'assets/test_tone.mp3',
      )).buffer.asUint8List();
      final info = await AudioDecoder.getAudioInfoBytes(
        mp3Bytes,
        formatHint: 'mp3',
      );

      expect(info.duration.inMilliseconds, greaterThan(0));
      expect(info.sampleRate, greaterThan(0));
      expect(info.channels, anyOf(1, 2));
    });

    testWidgets('trimAudioBytes produces shorter output', (
      WidgetTester tester,
    ) async {
      final mp3Bytes = (await rootBundle.load(
        'assets/test_tone.mp3',
      )).buffer.asUint8List();

      final fullWavBytes = await AudioDecoder.convertToWavBytes(
        mp3Bytes,
        formatHint: 'mp3',
      );
      final trimmedBytes = await AudioDecoder.trimAudioBytes(
        mp3Bytes,
        formatHint: 'mp3',
        start: const Duration(milliseconds: 200),
        end: const Duration(milliseconds: 800),
      );

      expect(trimmedBytes.length, greaterThan(0));
      expect(
        trimmedBytes.length,
        lessThan(fullWavBytes.length),
        reason: 'Trimmed bytes should be smaller than full conversion',
      );
    });

    testWidgets('getWaveformBytes returns normalized samples', (
      WidgetTester tester,
    ) async {
      final mp3Bytes = (await rootBundle.load(
        'assets/test_tone.mp3',
      )).buffer.asUint8List();

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

    testWidgets(
      'getWaveformBytes with absolute normalization yields lower peak',
      (WidgetTester tester) async {
        final mp3Bytes = (await rootBundle.load(
          'assets/test_tone.mp3',
        )).buffer.asUint8List();

        const sampleCount = 150;
        final perFile = await AudioDecoder.getWaveformBytes(
          mp3Bytes,
          formatHint: 'mp3',
          numberOfSamples: sampleCount,
        );
        final absolute = await AudioDecoder.getWaveformBytes(
          mp3Bytes,
          formatHint: 'mp3',
          numberOfSamples: sampleCount,
          normalization: WaveformNormalization.absolute,
        );

        expect(absolute.length, sampleCount);
        for (final sample in absolute) {
          expect(sample, greaterThanOrEqualTo(0.0));
          expect(sample, lessThanOrEqualTo(1.0));
        }

        final perFilePeak = perFile.reduce((a, b) => a > b ? a : b);
        final absolutePeak = absolute.reduce((a, b) => a > b ? a : b);
        expect(absolutePeak, lessThan(perFilePeak));
      },
    );
  });

  // ── 8. Error handling ───────────────────────────────────────────────

  group('Error handling', () {
    testWidgets('non-existent file path throws AudioConversionException', (
      WidgetTester tester,
    ) async {
      final bogusPath = '${Directory.systemTemp.path}/does_not_exist.mp3';
      final outputPath = tempOutputPath('error_test', 'wav');

      await expectLater(
        AudioDecoder.convertToWav(bogusPath, outputPath),
        throwsA(isA<AudioConversionException>()),
      );
    });

    testWidgets('invalid/corrupt bytes throw AudioConversionException', (
      WidgetTester tester,
    ) async {
      final garbage = Uint8List.fromList(List.filled(256, 0xFF));

      await expectLater(
        AudioDecoder.convertToWavBytes(garbage, formatHint: 'mp3'),
        throwsA(isA<AudioConversionException>()),
      );
    });

    testWidgets('getAudioInfo on non-existent file throws', (
      WidgetTester tester,
    ) async {
      final bogusPath = '${Directory.systemTemp.path}/no_such_file.wav';

      await expectLater(
        AudioDecoder.getAudioInfo(bogusPath),
        throwsA(isA<AudioConversionException>()),
      );
    });
  });

  // ── Legacy: needsConversion (pure Dart) ─────────────────────────────

  testWidgets('needsConversion test', (WidgetTester tester) async {
    expect(AudioDecoder.needsConversion('test.mp3'), true);
    expect(AudioDecoder.needsConversion('test.wav'), false);
  });
}
