import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'audio_conversion_exception.dart';
import 'audio_decoder_platform_interface.dart';
import 'audio_info.dart';

/// Platform implementation of audio_decoder that uses a method channel to
/// communicate with native platform code.
class MethodChannelAudioDecoder extends AudioDecoderPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('audio_decoder');

  @override
  Future<String> convertToWav(String inputPath, String outputPath, {int? sampleRate, int? channels, int? bitDepth}) async {
    try {
      final args = <String, dynamic>{
        'inputPath': inputPath,
        'outputPath': outputPath,
      };
      if (sampleRate != null) args['sampleRate'] = sampleRate;
      if (channels != null) args['channels'] = channels;
      if (bitDepth != null) args['bitDepth'] = bitDepth;
      final result = await methodChannel.invokeMethod<String>(
        'convertToWav',
        args,
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

  @override
  Future<Uint8List> convertToWavBytes(Uint8List inputData, String formatHint, {int? sampleRate, int? channels, int? bitDepth, bool? includeHeader}) async {
    try {
      final args = <String, dynamic>{
        'inputData': inputData,
        'formatHint': formatHint,
      };
      if (sampleRate != null) args['sampleRate'] = sampleRate;
      if (channels != null) args['channels'] = channels;
      if (bitDepth != null) args['bitDepth'] = bitDepth;
      if (includeHeader != null && includeHeader == false) args['includeHeader'] = false;
      final result = await methodChannel.invokeMethod<Uint8List>(
        'convertToWavBytes',
        args,
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
  Future<Uint8List> convertToM4aBytes(Uint8List inputData, String formatHint) async {
    try {
      final result = await methodChannel.invokeMethod<Uint8List>(
        'convertToM4aBytes',
        {'inputData': inputData, 'formatHint': formatHint},
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
  Future<AudioInfo> getAudioInfoBytes(Uint8List inputData, String formatHint) async {
    try {
      final result = await methodChannel.invokeMapMethod<String, dynamic>(
        'getAudioInfoBytes',
        {'inputData': inputData, 'formatHint': formatHint},
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
  Future<Uint8List> trimAudioBytes(Uint8List inputData, String formatHint, Duration start, Duration end, {String outputFormat = 'wav'}) async {
    try {
      final result = await methodChannel.invokeMethod<Uint8List>(
        'trimAudioBytes',
        {
          'inputData': inputData,
          'formatHint': formatHint,
          'startMs': start.inMilliseconds,
          'endMs': end.inMilliseconds,
          'outputFormat': outputFormat,
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
  Future<List<double>> getWaveformBytes(Uint8List inputData, String formatHint, int numberOfSamples) async {
    try {
      final result = await methodChannel.invokeListMethod<double>(
        'getWaveformBytes',
        {'inputData': inputData, 'formatHint': formatHint, 'numberOfSamples': numberOfSamples},
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
