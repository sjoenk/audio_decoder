import 'dart:typed_data';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'audio_decoder_method_channel.dart';
import 'audio_info.dart';

/// The interface that platform-specific implementations of audio_decoder must
/// extend.
///
/// The `base` modifier ensures platform implementations extend this class
/// rather than implement it, so new methods can be added without breaking
/// existing implementations.
abstract base class AudioDecoderPlatform extends PlatformInterface {
  /// Constructs an [AudioDecoderPlatform].
  AudioDecoderPlatform() : super(token: _token);

  static final Object _token = Object();

  static AudioDecoderPlatform _instance = MethodChannelAudioDecoder();

  /// The current platform-specific implementation.
  static AudioDecoderPlatform get instance => _instance;

  /// Sets the platform-specific implementation to use.
  static set instance(AudioDecoderPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String> convertToWav(String inputPath, String outputPath, {int? sampleRate, int? channels, int? bitDepth}) {
    throw UnimplementedError('convertToWav() has not been implemented.');
  }

  Future<String> convertToM4a(String inputPath, String outputPath) {
    throw UnimplementedError('convertToM4a() has not been implemented.');
  }

  Future<AudioInfo> getAudioInfo(String path) {
    throw UnimplementedError('getAudioInfo() has not been implemented.');
  }

  Future<String> trimAudio(String inputPath, String outputPath, Duration start, Duration end) {
    throw UnimplementedError('trimAudio() has not been implemented.');
  }

  Future<List<double>> getWaveform(String path, int numberOfSamples) {
    throw UnimplementedError('getWaveform() has not been implemented.');
  }

  Future<Uint8List> convertToWavBytes(Uint8List inputData, String formatHint, {int? sampleRate, int? channels, int? bitDepth, bool? includeHeader}) {
    throw UnimplementedError('convertToWavBytes() has not been implemented.');
  }

  Future<Uint8List> convertToM4aBytes(Uint8List inputData, String formatHint) {
    throw UnimplementedError('convertToM4aBytes() has not been implemented.');
  }

  Future<AudioInfo> getAudioInfoBytes(Uint8List inputData, String formatHint) {
    throw UnimplementedError('getAudioInfoBytes() has not been implemented.');
  }

  Future<Uint8List> trimAudioBytes(Uint8List inputData, String formatHint, Duration start, Duration end, {String outputFormat = 'wav'}) {
    throw UnimplementedError('trimAudioBytes() has not been implemented.');
  }

  Future<List<double>> getWaveformBytes(Uint8List inputData, String formatHint, int numberOfSamples) {
    throw UnimplementedError('getWaveformBytes() has not been implemented.');
  }
}
