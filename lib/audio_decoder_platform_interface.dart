import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'audio_decoder_method_channel.dart';
import 'audio_info.dart';

abstract class AudioDecoderPlatform extends PlatformInterface {
  AudioDecoderPlatform() : super(token: _token);

  static final Object _token = Object();

  static AudioDecoderPlatform _instance = MethodChannelAudioDecoder();

  static AudioDecoderPlatform get instance => _instance;

  static set instance(AudioDecoderPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String> convertToWav(String inputPath, String outputPath) {
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
}
