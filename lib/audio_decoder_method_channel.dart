import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'audio_decoder_platform_interface.dart';

/// An implementation of [AudioDecoderPlatform] that uses method channels.
class MethodChannelAudioDecoder extends AudioDecoderPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('audio_decoder');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
