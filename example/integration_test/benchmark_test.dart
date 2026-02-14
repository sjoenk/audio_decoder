import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:audio_decoder/audio_decoder.dart';

/// Benchmark test that measures conversion speed for large audio files.
///
/// These tests are **skipped by default** unless the large test assets are
/// bundled. To run them:
///
/// 1. Place large audio files in `example/assets/`:
///    - `test_large.mp3` (e.g. 5-10 min, ~10-20 MB)
///    - `test_large.m4a` (same content, AAC encoded)
///    - `test_large.wav` (same content, uncompressed PCM)
///
/// 2. Uncomment the `test_large.*` entries in `example/pubspec.yaml`:
///    ```yaml
///    assets:
///      - assets/test_large.m4a
///      - assets/test_large.mp3
///      - assets/test_large.wav
///    ```
///
/// 3. Run the benchmark:
///    ```sh
///    cd example
///    flutter test integration_test/benchmark_test.dart -d <device-id>
///    ```
///
/// Results are printed to stdout during the test run.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String mp3Path;
  late String m4aPath;
  late String wavPath;
  var assetsAvailable = false;
  final results = <String>[];

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('audio_decoder_bench_');

    // Try loading the large assets. If they are not bundled, all tests
    // in this file will be skipped gracefully.
    try {
      mp3Path = await _copyAsset('test_large.mp3', tempDir);
      m4aPath = await _copyAsset('test_large.m4a', tempDir);
      wavPath = await _copyAsset('test_large.wav', tempDir);
      assetsAvailable = true;
    } catch (_) {
      // Assets not bundled — tests will be skipped.
    }
  });

  tearDownAll(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  String outputPath(String name, String ext) =>
      '${tempDir.path}/${name}_output.$ext';

  void record(String label, int ms, int outputBytes) {
    final mb = (outputBytes / 1024 / 1024).toStringAsFixed(1);
    final line = '$label: $ms ms (output: $mb MB)';
    results.add(line);
    // ignore: avoid_print
    print(line);
  }

  // ── Benchmark: convertToWav (default, no params) ───────────────────

  group('Benchmark: convertToWav (default)', () {
    testWidgets('MP3 → WAV', (WidgetTester tester) async {
      if (!assetsAvailable) {
        markTestSkipped('test_large.* assets not bundled');
        return;
      }
      final out = outputPath('bench_mp3', 'wav');

      final sw = Stopwatch()..start();
      await AudioDecoder.convertToWav(mp3Path, out);
      sw.stop();

      final size = await File(out).length();
      record('MP3 → WAV (default)', sw.elapsedMilliseconds, size);
    });

    testWidgets('M4A → WAV', (WidgetTester tester) async {
      if (!assetsAvailable) {
        markTestSkipped('test_large.* assets not bundled');
        return;
      }
      final out = outputPath('bench_m4a', 'wav');

      final sw = Stopwatch()..start();
      await AudioDecoder.convertToWav(m4aPath, out);
      sw.stop();

      final size = await File(out).length();
      record('M4A → WAV (default)', sw.elapsedMilliseconds, size);
    });
  });

  // ── Benchmark: streaming path (channel/bitdepth only) ──────────────

  group('Benchmark: streaming path', () {
    testWidgets('MP3 → WAV mono', (WidgetTester tester) async {
      if (!assetsAvailable) {
        markTestSkipped('test_large.* assets not bundled');
        return;
      }
      final out = outputPath('bench_stream_mono', 'wav');

      final sw = Stopwatch()..start();
      await AudioDecoder.convertToWav(mp3Path, out, channels: 1);
      sw.stop();

      final size = await File(out).length();
      record('MP3 → WAV (mono)', sw.elapsedMilliseconds, size);
    });

    testWidgets('MP3 → WAV 24bit', (WidgetTester tester) async {
      if (!assetsAvailable) {
        markTestSkipped('test_large.* assets not bundled');
        return;
      }
      final out = outputPath('bench_stream_24bit', 'wav');

      final sw = Stopwatch()..start();
      await AudioDecoder.convertToWav(mp3Path, out, bitDepth: 24);
      sw.stop();

      final size = await File(out).length();
      record('MP3 → WAV (24bit)', sw.elapsedMilliseconds, size);
    });
  });

  // ── Benchmark: convertToM4a ────────────────────────────────────────

  group('Benchmark: convertToM4a', () {
    testWidgets('WAV → M4A', (WidgetTester tester) async {
      if (!assetsAvailable) {
        markTestSkipped('test_large.* assets not bundled');
        return;
      }
      final out = outputPath('bench_wav_m4a', 'm4a');

      final sw = Stopwatch()..start();
      await AudioDecoder.convertToM4a(wavPath, out);
      sw.stop();

      final size = await File(out).length();
      record('WAV → M4A', sw.elapsedMilliseconds, size);
    });
  });
}

/// Copy a bundled asset to [dir] and return the file path.
Future<String> _copyAsset(String name, Directory dir) async {
  final data = await rootBundle.load('assets/$name');
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(data.buffer.asUint8List());
  return file.path;
}
