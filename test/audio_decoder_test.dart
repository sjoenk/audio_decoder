import 'package:flutter_test/flutter_test.dart';
import 'package:audio_decoder/audio_decoder.dart';
import 'package:audio_decoder/audio_decoder_platform_interface.dart';
import 'package:audio_decoder/audio_decoder_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockAudioDecoderPlatform
    with MockPlatformInterfaceMixin
    implements AudioDecoderPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final AudioDecoderPlatform initialPlatform = AudioDecoderPlatform.instance;

  test('$MethodChannelAudioDecoder is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelAudioDecoder>());
  });

  test('getPlatformVersion', () async {
    AudioDecoder audioDecoderPlugin = AudioDecoder();
    MockAudioDecoderPlatform fakePlatform = MockAudioDecoderPlatform();
    AudioDecoderPlatform.instance = fakePlatform;

    expect(await audioDecoderPlugin.getPlatformVersion(), '42');
  });
}
