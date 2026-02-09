#ifndef FLUTTER_PLUGIN_AUDIO_DECODER_PLUGIN_H_
#define FLUTTER_PLUGIN_AUDIO_DECODER_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>
#include <string>
#include <fstream>
#include <vector>

namespace audio_decoder {

class AudioDecoderPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  AudioDecoderPlugin();
  virtual ~AudioDecoderPlugin();

  AudioDecoderPlugin(const AudioDecoderPlugin&) = delete;
  AudioDecoderPlugin& operator=(const AudioDecoderPlugin&) = delete;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 private:
  std::string ConvertToWav(const std::string& inputPath,
                           const std::string& outputPath);
  std::string ConvertToM4a(const std::string& inputPath,
                           const std::string& outputPath);
  flutter::EncodableMap GetAudioInfo(const std::string& path);
  std::string TrimAudio(const std::string& inputPath,
                        const std::string& outputPath,
                        int64_t startMs, int64_t endMs);
  flutter::EncodableList GetWaveform(const std::string& path,
                                     int numberOfSamples);
  void WriteWavHeader(std::ofstream& file, uint32_t dataSize,
                      uint32_t sampleRate, uint16_t channels,
                      uint16_t bitsPerSample);
  // Helper: decode audio to PCM using IMFSourceReader
  struct PcmResult {
      std::vector<uint8_t> data;
      uint32_t sampleRate;
      uint32_t channels;
      uint32_t bitsPerSample;
  };
  PcmResult DecodeToPcm(const std::string& inputPath,
                         int64_t startMs = -1, int64_t endMs = -1);

  // Temp file helpers for bytes-based API
  std::string WriteTempFile(const std::vector<uint8_t>& data,
                            const std::string& extension);
  std::vector<uint8_t> ReadAndDeleteFile(const std::string& path);
};

}  // namespace audio_decoder

#endif  // FLUTTER_PLUGIN_AUDIO_DECODER_PLUGIN_H_
