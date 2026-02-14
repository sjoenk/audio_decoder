#ifndef FLUTTER_PLUGIN_AUDIO_DECODER_PLUGIN_H_
#define FLUTTER_PLUGIN_AUDIO_DECODER_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <functional>
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
                           const std::string& outputPath,
                           int targetSampleRate = -1,
                           int targetChannels = -1,
                           int targetBitDepth = -1);
  std::string ConvertToM4a(const std::string& inputPath,
                           const std::string& outputPath);
  flutter::EncodableMap GetAudioInfo(const std::string& path);
  std::string TrimAudio(const std::string& inputPath,
                        const std::string& outputPath,
                        int64_t startMs, int64_t endMs);
  flutter::EncodableList GetWaveform(const std::string& path,
                                     int numberOfSamples);
  void WriteWavHeader(std::ostream& file, uint32_t dataSize,
                      uint32_t sampleRate, uint16_t channels,
                      uint16_t bitsPerSample);

  struct PcmInfo {
      uint32_t sampleRate;
      uint32_t channels;
      uint32_t bitsPerSample;
  };

  /// Streams decoded PCM to a WAV file on disk. On failure the output file
  /// is removed before rethrowing.
  PcmInfo streamPcmToWav(const std::string& inputPath,
                          const std::string& outputPath,
                          int64_t startMs = -1, int64_t endMs = -1,
                          int targetSampleRate = -1,
                          int targetChannels = -1,
                          int targetBitDepth = -1);

  // Streaming decode: calls onChunk for each decoded PCM buffer
  PcmInfo DecodeToPcmStream(
      const std::string& inputPath,
      const std::function<void(const uint8_t*, size_t)>& onChunk,
      int64_t startMs = -1, int64_t endMs = -1,
      int targetSampleRate = -1, int targetChannels = -1,
      int targetBitDepth = -1);

  struct PcmResult {
      std::vector<uint8_t> data;
      uint32_t sampleRate;
      uint32_t channels;
      uint32_t bitsPerSample;
  };
  PcmResult DecodeToPcm(const std::string& inputPath,
                         int64_t startMs = -1, int64_t endMs = -1,
                         int targetSampleRate = -1,
                         int targetChannels = -1,
                         int targetBitDepth = -1);

  // Temp file helpers for bytes-based API
  std::string WriteTempFile(const std::vector<uint8_t>& data,
                            const std::string& extension);
  std::vector<uint8_t> ReadAndDeleteFile(const std::string& path);
};

}  // namespace audio_decoder

#endif  // FLUTTER_PLUGIN_AUDIO_DECODER_PLUGIN_H_
