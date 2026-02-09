
import 'audio_decoder_platform_interface.dart';

class AudioDecoder {
  Future<String?> getPlatformVersion() {
    return AudioDecoderPlatform.instance.getPlatformVersion();
  }
}
