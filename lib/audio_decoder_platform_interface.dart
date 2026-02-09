import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'audio_decoder_method_channel.dart';

abstract class AudioDecoderPlatform extends PlatformInterface {
  /// Constructs a AudioDecoderPlatform.
  AudioDecoderPlatform() : super(token: _token);

  static final Object _token = Object();

  static AudioDecoderPlatform _instance = MethodChannelAudioDecoder();

  /// The default instance of [AudioDecoderPlatform] to use.
  ///
  /// Defaults to [MethodChannelAudioDecoder].
  static AudioDecoderPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [AudioDecoderPlatform] when
  /// they register themselves.
  static set instance(AudioDecoderPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
