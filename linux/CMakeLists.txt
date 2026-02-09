# The Flutter tooling requires that developers have CMake 3.14 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.14)

# Project-level configuration.
set(PROJECT_NAME "audio_decoder")
project(${PROJECT_NAME} LANGUAGES CXX)

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# This value is used when generating builds using this plugin, so it must
# not be changed.
set(PLUGIN_NAME "audio_decoder_plugin")

# Find GStreamer dependencies.
find_package(PkgConfig REQUIRED)
pkg_check_modules(GSTREAMER REQUIRED
  gstreamer-1.0
  gstreamer-audio-1.0
  gstreamer-pbutils-1.0
  gstreamer-app-1.0
)

# Any new source files that you add to the plugin should be added here.
list(APPEND PLUGIN_SOURCES
  "audio_decoder_plugin.cc"
)

# Define the plugin library target. Its name must not be changed (see comment
# on PLUGIN_NAME above).
add_library(${PLUGIN_NAME} SHARED
  "include/audio_decoder/audio_decoder_plugin.h"
  ${PLUGIN_SOURCES}
)

# Apply a standard set of build settings that are configured in the
# application-level CMakeLists.txt. This can be removed for plugins that want
# full control over build settings.
apply_standard_settings(${PLUGIN_NAME})

# Symbols are hidden by default to reduce the chance of accidental conflicts
# between plugins. This should not be removed; any symbols that should be
# exported should be explicitly exported with the FLUTTER_PLUGIN_EXPORT macro.
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

# Source include directories and library dependencies. Add any plugin-specific
# dependencies here.
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_include_directories(${PLUGIN_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}"
  ${GSTREAMER_INCLUDE_DIRS})
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter
  ${GSTREAMER_LIBRARIES})
target_compile_options(${PLUGIN_NAME} PRIVATE ${GSTREAMER_CFLAGS_OTHER})

# List of absolute paths to libraries that should be bundled with the plugin.
set(audio_decoder_bundled_libraries
  ""
  PARENT_SCOPE
)

# === Tests ===
if(${include_${PROJECT_NAME}_tests})
set(TEST_RUNNER "${PROJECT_NAME}_test")
enable_testing()

include(FetchContent)
FetchContent_Declare(
  googletest
  URL https://github.com/google/googletest/archive/release-1.11.0.zip
)
set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
set(INSTALL_GTEST OFF CACHE BOOL "Disable installation of googletest" FORCE)
FetchContent_MakeAvailable(googletest)

add_executable(${TEST_RUNNER}
  test/audio_decoder_plugin_test.cc
  ${PLUGIN_SOURCES}
)
apply_standard_settings(${TEST_RUNNER})
target_include_directories(${TEST_RUNNER} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}"
  ${GSTREAMER_INCLUDE_DIRS})
target_link_libraries(${TEST_RUNNER} PRIVATE flutter
  ${GSTREAMER_LIBRARIES})
target_link_libraries(${TEST_RUNNER} PRIVATE gtest_main gmock)
target_compile_options(${TEST_RUNNER} PRIVATE ${GSTREAMER_CFLAGS_OTHER})

include(GoogleTest)
gtest_discover_tests(${TEST_RUNNER})
endif()
