#include "include/audio_decoder/audio_decoder_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "audio_decoder_plugin.h"

void AudioDecoderPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  audio_decoder::AudioDecoderPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
