#include <flutter/method_call.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <gtest/gtest.h>
#include <windows.h>

#include <memory>
#include <string>
#include <variant>

#include "audio_decoder_plugin.h"

namespace audio_decoder {
namespace test {

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResultFunctions;

}  // namespace

TEST(AudioDecoderPlugin, UnknownMethodReturnsNotImplemented) {
  AudioDecoderPlugin plugin;
  bool not_implemented = false;
  plugin.HandleMethodCall(
      MethodCall("unknownMethod", std::make_unique<EncodableValue>()),
      std::make_unique<MethodResultFunctions<>>(
          nullptr, nullptr,
          [&not_implemented]() { not_implemented = true; }));

  EXPECT_TRUE(not_implemented);
}

TEST(AudioDecoderPlugin, ConvertToWavMissingArgsReturnsError) {
  AudioDecoderPlugin plugin;
  std::string error_code;
  plugin.HandleMethodCall(
      MethodCall("convertToWav", std::make_unique<EncodableValue>()),
      std::make_unique<MethodResultFunctions<>>(
          nullptr,
          [&error_code](const std::string& code, const std::string&,
                        const EncodableValue*) { error_code = code; },
          nullptr));

  EXPECT_EQ(error_code, "INVALID_ARGUMENTS");
}

TEST(AudioDecoderPlugin, ConvertToM4aMissingArgsReturnsError) {
  AudioDecoderPlugin plugin;
  std::string error_code;
  plugin.HandleMethodCall(
      MethodCall("convertToM4a", std::make_unique<EncodableValue>()),
      std::make_unique<MethodResultFunctions<>>(
          nullptr,
          [&error_code](const std::string& code, const std::string&,
                        const EncodableValue*) { error_code = code; },
          nullptr));

  EXPECT_EQ(error_code, "INVALID_ARGUMENTS");
}

TEST(AudioDecoderPlugin, ConvertToWavMissingPathsReturnsError) {
  AudioDecoderPlugin plugin;
  std::string error_code;
  // Pass a map with only inputPath, missing outputPath
  EncodableMap args;
  args[EncodableValue("inputPath")] = EncodableValue("test.mp3");
  plugin.HandleMethodCall(
      MethodCall("convertToWav",
                 std::make_unique<EncodableValue>(args)),
      std::make_unique<MethodResultFunctions<>>(
          nullptr,
          [&error_code](const std::string& code, const std::string&,
                        const EncodableValue*) { error_code = code; },
          nullptr));

  EXPECT_EQ(error_code, "INVALID_ARGUMENTS");
}

TEST(AudioDecoderPlugin, ConvertToWavBytesMissingArgsReturnsError) {
  AudioDecoderPlugin plugin;
  std::string error_code;
  plugin.HandleMethodCall(
      MethodCall("convertToWavBytes", std::make_unique<EncodableValue>()),
      std::make_unique<MethodResultFunctions<>>(
          nullptr,
          [&error_code](const std::string& code, const std::string&,
                        const EncodableValue*) { error_code = code; },
          nullptr));

  EXPECT_EQ(error_code, "INVALID_ARGUMENTS");
}

TEST(AudioDecoderPlugin, ConvertToM4aBytesMissingArgsReturnsError) {
  AudioDecoderPlugin plugin;
  std::string error_code;
  plugin.HandleMethodCall(
      MethodCall("convertToM4aBytes", std::make_unique<EncodableValue>()),
      std::make_unique<MethodResultFunctions<>>(
          nullptr,
          [&error_code](const std::string& code, const std::string&,
                        const EncodableValue*) { error_code = code; },
          nullptr));

  EXPECT_EQ(error_code, "INVALID_ARGUMENTS");
}

TEST(AudioDecoderPlugin, GetAudioInfoBytesMissingArgsReturnsError) {
  AudioDecoderPlugin plugin;
  std::string error_code;
  plugin.HandleMethodCall(
      MethodCall("getAudioInfoBytes", std::make_unique<EncodableValue>()),
      std::make_unique<MethodResultFunctions<>>(
          nullptr,
          [&error_code](const std::string& code, const std::string&,
                        const EncodableValue*) { error_code = code; },
          nullptr));

  EXPECT_EQ(error_code, "INVALID_ARGUMENTS");
}

TEST(AudioDecoderPlugin, TrimAudioBytesMissingArgsReturnsError) {
  AudioDecoderPlugin plugin;
  std::string error_code;
  plugin.HandleMethodCall(
      MethodCall("trimAudioBytes", std::make_unique<EncodableValue>()),
      std::make_unique<MethodResultFunctions<>>(
          nullptr,
          [&error_code](const std::string& code, const std::string&,
                        const EncodableValue*) { error_code = code; },
          nullptr));

  EXPECT_EQ(error_code, "INVALID_ARGUMENTS");
}

TEST(AudioDecoderPlugin, GetWaveformBytesMissingArgsReturnsError) {
  AudioDecoderPlugin plugin;
  std::string error_code;
  plugin.HandleMethodCall(
      MethodCall("getWaveformBytes", std::make_unique<EncodableValue>()),
      std::make_unique<MethodResultFunctions<>>(
          nullptr,
          [&error_code](const std::string& code, const std::string&,
                        const EncodableValue*) { error_code = code; },
          nullptr));

  EXPECT_EQ(error_code, "INVALID_ARGUMENTS");
}

}  // namespace test
}  // namespace audio_decoder
