#ifndef FLUTTER_PLUGIN_AUDIO_DECODER_PLUGIN_H_
#define FLUTTER_PLUGIN_AUDIO_DECODER_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/encodable_value.h>

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
                                     int numberOfSamples,
                                     const std::string& normalization = "perFile");
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
  PcmInfo StreamPcmToWav(const std::string& inputPath,
                          const std::string& outputPath,
                          int64_t startMs = -1, int64_t endMs = -1,
                          int targetSampleRate = -1,
                          int targetChannels = -1,
                          int targetBitDepth = -1);

  /// Streaming decode: calls onChunk for each decoded PCM buffer. When
  /// onFormat is set it is invoked once with the output format before the
  /// first chunk, so consumers that need the sample rate up front (an encoder,
  /// for instance) do not have to buffer the audio first.
  PcmInfo DecodeToPcmStream(
      const std::string& inputPath,
      const std::function<void(const uint8_t*, size_t)>& onChunk,
      int64_t startMs = -1, int64_t endMs = -1,
      int targetSampleRate = -1, int targetChannels = -1,
      int targetBitDepth = -1,
      const std::function<void(const PcmInfo&)>& onFormat = nullptr);

  // Temp file helpers for bytes-based API
  std::string WriteTempFile(const std::vector<uint8_t>& data,
                            const std::string& extension);
  std::vector<uint8_t> ReadAndDeleteFile(const std::string& path);
};

}  // namespace audio_decoder

#endif  // FLUTTER_PLUGIN_AUDIO_DECODER_PLUGIN_H_
