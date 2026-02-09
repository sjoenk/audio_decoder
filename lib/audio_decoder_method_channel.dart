import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'audio_conversion_exception.dart';
import 'audio_decoder_platform_interface.dart';
import 'audio_info.dart';

class MethodChannelAudioDecoder extends AudioDecoderPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('audio_decoder');

  @override
  Future<String> convertToWav(String inputPath, String outputPath) async {
    try {
      final result = await methodChannel.invokeMethod<String>(
        'convertToWav',
        {'inputPath': inputPath, 'outputPath': outputPath},
      );
      if (result == null) {
        throw AudioConversionException('Native conversion returned null');
      }
      return result;
    } on PlatformException catch (e) {
      throw AudioConversionException(
        e.message ?? 'Unknown conversion error',
        details: e.details?.toString(),
      );
    }
  }

  @override
  Future<String> convertToM4a(String inputPath, String outputPath) async {
    try {
      final result = await methodChannel.invokeMethod<String>(
        'convertToM4a',
        {'inputPath': inputPath, 'outputPath': outputPath},
      );
      if (result == null) {
        throw AudioConversionException('Native conversion returned null');
      }
      return result;
    } on PlatformException catch (e) {
      throw AudioConversionException(
        e.message ?? 'Unknown conversion error',
        details: e.details?.toString(),
      );
    }
  }

  @override
  Future<AudioInfo> getAudioInfo(String path) async {
    try {
      final result = await methodChannel.invokeMapMethod<String, dynamic>(
        'getAudioInfo',
        {'path': path},
      );
      if (result == null) {
        throw AudioConversionException('Native getAudioInfo returned null');
      }
      return AudioInfo(
        duration: Duration(milliseconds: result['durationMs'] as int),
        sampleRate: result['sampleRate'] as int,
        channels: result['channels'] as int,
        bitRate: result['bitRate'] as int,
        format: result['format'] as String,
      );
    } on PlatformException catch (e) {
      throw AudioConversionException(
        e.message ?? 'Unknown error',
        details: e.details?.toString(),
      );
    }
  }

  @override
  Future<String> trimAudio(String inputPath, String outputPath, Duration start, Duration end) async {
    try {
      final result = await methodChannel.invokeMethod<String>(
        'trimAudio',
        {
          'inputPath': inputPath,
          'outputPath': outputPath,
          'startMs': start.inMilliseconds,
          'endMs': end.inMilliseconds,
        },
      );
      if (result == null) {
        throw AudioConversionException('Native trimAudio returned null');
      }
      return result;
    } on PlatformException catch (e) {
      throw AudioConversionException(
        e.message ?? 'Unknown error',
        details: e.details?.toString(),
      );
    }
  }

  @override
  Future<List<double>> getWaveform(String path, int numberOfSamples) async {
    try {
      final result = await methodChannel.invokeListMethod<double>(
        'getWaveform',
        {'path': path, 'numberOfSamples': numberOfSamples},
      );
      if (result == null) {
        throw AudioConversionException('Native getWaveform returned null');
      }
      return result;
    } on PlatformException catch (e) {
      throw AudioConversionException(
        e.message ?? 'Unknown error',
        details: e.details?.toString(),
      );
    }
  }
}
