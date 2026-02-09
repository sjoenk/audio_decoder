#ifndef FLUTTER_PLUGIN_AUDIO_DECODER_PLUGIN_H_
#define FLUTTER_PLUGIN_AUDIO_DECODER_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace audio_decoder {

class AudioDecoderPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  AudioDecoderPlugin();

  virtual ~AudioDecoderPlugin();

  // Disallow copy and assign.
  AudioDecoderPlugin(const AudioDecoderPlugin&) = delete;
  AudioDecoderPlugin& operator=(const AudioDecoderPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace audio_decoder

#endif  // FLUTTER_PLUGIN_AUDIO_DECODER_PLUGIN_H_
