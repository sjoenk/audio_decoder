import 'dart:typed_data';

import 'audio_decoder_platform_interface.dart';
import 'audio_info.dart';

export 'audio_conversion_exception.dart';
export 'audio_info.dart';

/// A lightweight audio decoder and converter using native platform APIs.
///
/// Provides static methods for converting, trimming, analyzing, and extracting
/// waveform data from audio files and in-memory audio bytes.
class AudioDecoder {
  /// Converts an audio file (MP3, M4A, AAC, etc.) to WAV format.
  ///
  /// [inputPath] is the absolute path to the source audio file.
  /// [outputPath] is the absolute path where the WAV file will be written.
  /// [sampleRate] optionally sets the output sample rate (e.g., 44100). Defaults to source sample rate.
  /// [channels] optionally sets the number of output channels (e.g., 1 for mono, 2 for stereo). Defaults to source channels.
  /// [bitDepth] optionally sets the output bit depth (e.g., 16, 24). Defaults to 16.
  ///
  /// Returns the output path on success.
  /// Throws [AudioConversionException] on failure.
  static Future<String> convertToWav(
    String inputPath,
    String outputPath, {
    int? sampleRate,
    int? channels,
    int? bitDepth,
  }) {
    return AudioDecoderPlatform.instance.convertToWav(inputPath, outputPath, sampleRate: sampleRate, channels: channels, bitDepth: bitDepth);
  }

  /// Converts an audio file (MP3, WAV, FLAC, etc.) to M4A (AAC) format.
  ///
  /// [inputPath] is the absolute path to the source audio file.
  /// [outputPath] is the absolute path where the M4A file will be written.
  ///
  /// Returns the output path on success.
  /// Throws [AudioConversionException] on failure.
  static Future<String> convertToM4a(String inputPath, String outputPath) {
    return AudioDecoderPlatform.instance.convertToM4a(inputPath, outputPath);
  }

  /// Returns metadata about the audio file at [path].
  ///
  /// Includes duration, sample rate, channel count, bit rate, and format.
  /// Throws [AudioConversionException] if the file cannot be read.
  static Future<AudioInfo> getAudioInfo(String path) {
    return AudioDecoderPlatform.instance.getAudioInfo(path);
  }

  /// Trims the audio file to the specified time range.
  ///
  /// [inputPath] is the absolute path to the source audio file.
  /// [outputPath] is the absolute path where the trimmed file will be written.
  /// The output format is determined by the file extension (.wav or .m4a).
  /// [start] and [end] define the time range to extract.
  ///
  /// Returns the output path on success.
  /// Throws [AudioConversionException] on failure.
  static Future<String> trimAudio(
    String inputPath,
    String outputPath,
    Duration start,
    Duration end,
  ) {
    return AudioDecoderPlatform.instance.trimAudio(inputPath, outputPath, start, end);
  }

  /// Extracts waveform amplitude data from the audio file.
  ///
  /// Returns a list of [numberOfSamples] normalized amplitude values (0.0–1.0).
  /// Useful for rendering waveform visualizations.
  ///
  /// Throws [AudioConversionException] if the file cannot be decoded.
  static Future<List<double>> getWaveform(
    String path, {
    int numberOfSamples = 100,
  }) {
    return AudioDecoderPlatform.instance.getWaveform(path, numberOfSamples);
  }

  /// Known audio extensions that can be converted to WAV.
  ///
  /// The native decoders may support additional formats beyond this list.
  /// You can always call [convertToWav] directly — it will throw an
  /// [AudioConversionException] if the platform cannot decode the file.
  static const supportedExtensions = {
    '.mp3',
    '.m4a',
    '.aac',
    '.mp4',
    '.ogg',
    '.oga',
    '.opus',
    '.flac',
    '.wma',
    '.aiff',
    '.aif',
    '.amr',
    '.caf',
    '.alac',
    '.webm',
  };

  /// Returns true if the file at [path] needs conversion to WAV.
  ///
  /// Returns `false` for files that are already WAV. Returns `true` for
  /// known audio formats in [supportedExtensions]. Returns `false` for
  /// unknown extensions (you can still try [convertToWav] directly).
  static bool needsConversion(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.wav') || lower.endsWith('.wave')) {
      return false;
    }
    return supportedExtensions.any((ext) => lower.endsWith(ext));
  }

  /// Converts audio bytes to WAV format.
  ///
  /// [inputData] is the raw bytes of the source audio file.
  /// [formatHint] indicates the input format (e.g., 'mp3', 'm4a', 'aac').
  /// [sampleRate] optionally sets the output sample rate (e.g., 44100). Defaults to source sample rate.
  /// [channels] optionally sets the number of output channels (e.g., 1 for mono, 2 for stereo). Defaults to source channels.
  /// [bitDepth] optionally sets the output bit depth (e.g., 16, 24). Defaults to 16.
  /// [includeHeader] when true (default), returns a complete WAV file with the
  /// 44-byte RIFF/WAV header. When false, returns only raw interleaved PCM data.
  ///
  /// Returns the WAV file bytes (or raw PCM bytes if [includeHeader] is false).
  /// Throws [AudioConversionException] on failure.
  static Future<Uint8List> convertToWavBytes(
    Uint8List inputData, {
    required String formatHint,
    int? sampleRate,
    int? channels,
    int? bitDepth,
    bool includeHeader = true,
  }) {
    return AudioDecoderPlatform.instance.convertToWavBytes(inputData, formatHint,
        sampleRate: sampleRate, channels: channels, bitDepth: bitDepth,
        includeHeader: includeHeader);
  }

  /// Converts audio bytes to M4A (AAC) format.
  ///
  /// [inputData] is the raw bytes of the source audio file.
  /// [formatHint] indicates the input format (e.g., 'mp3', 'wav', 'flac').
  ///
  /// Returns the M4A file bytes.
  /// Throws [AudioConversionException] on failure.
  static Future<Uint8List> convertToM4aBytes(Uint8List inputData, {required String formatHint}) {
    return AudioDecoderPlatform.instance.convertToM4aBytes(inputData, formatHint);
  }

  /// Returns metadata about the audio data in [inputData].
  ///
  /// [formatHint] indicates the input format (e.g., 'mp3', 'm4a').
  /// Includes duration, sample rate, channel count, bit rate, and format.
  /// Throws [AudioConversionException] if the data cannot be read.
  static Future<AudioInfo> getAudioInfoBytes(Uint8List inputData, {required String formatHint}) {
    return AudioDecoderPlatform.instance.getAudioInfoBytes(inputData, formatHint);
  }

  /// Trims audio bytes to the specified time range.
  ///
  /// [inputData] is the raw bytes of the source audio file.
  /// [formatHint] indicates the input format (e.g., 'mp3', 'm4a').
  /// [start] and [end] define the time range to extract.
  /// [outputFormat] determines the output encoding ('wav' or 'm4a').
  ///
  /// Returns the trimmed audio bytes.
  /// Throws [AudioConversionException] on failure.
  static Future<Uint8List> trimAudioBytes(
    Uint8List inputData, {
    required String formatHint,
    required Duration start,
    required Duration end,
    String outputFormat = 'wav',
  }) {
    return AudioDecoderPlatform.instance.trimAudioBytes(inputData, formatHint, start, end, outputFormat: outputFormat);
  }

  /// Extracts waveform amplitude data from audio bytes.
  ///
  /// [inputData] is the raw bytes of the source audio file.
  /// [formatHint] indicates the input format (e.g., 'mp3', 'm4a').
  /// Returns a list of [numberOfSamples] normalized amplitude values (0.0–1.0).
  ///
  /// Throws [AudioConversionException] if the data cannot be decoded.
  static Future<List<double>> getWaveformBytes(
    Uint8List inputData, {
    required String formatHint,
    int numberOfSamples = 100,
  }) {
    return AudioDecoderPlatform.instance.getWaveformBytes(inputData, formatHint, numberOfSamples);
  }
}
