// This is a basic Flutter integration test.
//
// Since integration tests run in a full Flutter application, they can interact
// with the host side of a plugin implementation, unlike Dart unit tests.
//
// For more information about Flutter integration tests, please see
// https://flutter.dev/to/integration-testing

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:audio_decoder/audio_decoder.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('needsConversion test', (WidgetTester tester) async {
    expect(AudioDecoder.needsConversion('test.mp3'), true);
    expect(AudioDecoder.needsConversion('test.wav'), false);
  });

  testWidgets('convertToWavBytes with header returns valid WAV', (WidgetTester tester) async {
    final mp3Bytes = (await rootBundle.load('assets/test_tone.mp3')).buffer.asUint8List();
    final wavBytes = await AudioDecoder.convertToWavBytes(mp3Bytes, formatHint: 'mp3');

    // Should start with RIFF header
    expect(wavBytes.length, greaterThan(44));
    expect(String.fromCharCodes(wavBytes.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wavBytes.sublist(8, 12)), 'WAVE');
  });

  testWidgets('convertToWavBytes without header returns raw PCM', (WidgetTester tester) async {
    final mp3Bytes = (await rootBundle.load('assets/test_tone.mp3')).buffer.asUint8List();
    final wavBytes = await AudioDecoder.convertToWavBytes(mp3Bytes, formatHint: 'mp3');
    final pcmBytes = await AudioDecoder.convertToWavBytes(mp3Bytes, formatHint: 'mp3', includeHeader: false);

    // PCM should be exactly 44 bytes smaller than the WAV version
    expect(pcmBytes.length, wavBytes.length - 44);
    // Should NOT start with RIFF
    expect(String.fromCharCodes(pcmBytes.sublist(0, 4)), isNot('RIFF'));
    // PCM data should match the WAV data after the header
    expect(pcmBytes, wavBytes.sublist(44));
  });
}
