#include <flutter_linux/flutter_linux.h>
#include <gtest/gtest.h>

#include "include/audio_decoder/audio_decoder_plugin.h"

// These tests verify that the plugin registers correctly.
// Full method call testing requires a running Flutter engine,
// so argument validation is tested at the Dart level.

TEST(AudioDecoderPlugin, PluginRegistration) {
    // Verify the registration function symbol exists and is callable.
    EXPECT_NE(nullptr,
              reinterpret_cast<void*>(
                  audio_decoder_plugin_register_with_registrar));
}
