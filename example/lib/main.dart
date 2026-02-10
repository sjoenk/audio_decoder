import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audio_decoder/audio_decoder.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _status = 'Ready - tap a button to test audio operations.';
  bool _busy = false;
  List<double>? _waveform;

  Future<String> _copyAssetToTemp(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    final dir = Directory.systemTemp;
    final file = File('${dir.path}/${assetPath.split('/').last}');
    await file.writeAsBytes(data.buffer.asUint8List());
    return file.path;
  }

  Future<void> _convertToWav(String assetPath) async {
    if (_busy) return;

    final ext = assetPath.split('.').last.toUpperCase();

    setState(() {
      _busy = true;
      _status = 'Converting $ext to WAV...';
    });

    try {
      final inputPath = await _copyAssetToTemp(assetPath);
      final inputSize = File(inputPath).lengthSync();
      final baseName = assetPath
          .split('/')
          .last
          .replaceAll(RegExp(r'\.[^.]+$'), '');

      final outputPath =
          '${Directory.systemTemp.path}/${baseName}_converted.wav';
      final result = await AudioDecoder.convertToWav(inputPath, outputPath);
      final outputSize = await File(result).length();

      setState(() {
        _status =
            'Converted $ext → WAV\n\n'
            'Input: ${assetPath.split('/').last} ($inputSize bytes)\n'
            'Output: ${result.split('/').last}\n'
            'Size: ${(outputSize / 1024).toStringAsFixed(1)} KB';
      });
    } on AudioConversionException catch (e) {
      setState(() => _status = 'Conversion failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _convertToM4a(String assetPath) async {
    if (_busy) return;

    final ext = assetPath.split('.').last.toUpperCase();

    setState(() {
      _busy = true;
      _status = 'Converting $ext to M4A...';
    });

    try {
      final inputPath = await _copyAssetToTemp(assetPath);
      final inputSize = File(inputPath).lengthSync();
      final baseName = assetPath
          .split('/')
          .last
          .replaceAll(RegExp(r'\.[^.]+$'), '');

      final outputPath =
          '${Directory.systemTemp.path}/${baseName}_converted.m4a';
      final result = await AudioDecoder.convertToM4a(inputPath, outputPath);
      final outputSize = await File(result).length();

      setState(() {
        _status =
            'Converted $ext → M4A\n\n'
            'Input: ${assetPath.split('/').last} ($inputSize bytes)\n'
            'Output: ${result.split('/').last}\n'
            'Size: ${(outputSize / 1024).toStringAsFixed(1)} KB';
      });
    } on AudioConversionException catch (e) {
      setState(() => _status = 'Conversion failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _getAudioInfo(String assetPath) async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _status = 'Getting audio info...';
    });

    try {
      final inputPath = await _copyAssetToTemp(assetPath);
      final info = await AudioDecoder.getAudioInfo(inputPath);

      setState(() {
        _status =
            'Audio Info: ${assetPath.split('/').last}\n\n'
            'Duration: ${info.duration.inMilliseconds} ms\n'
            'Sample rate: ${info.sampleRate} Hz\n'
            'Channels: ${info.channels}\n'
            'Bit rate: ${info.bitRate} bps\n'
            'Format: ${info.format}';
      });
    } on AudioConversionException catch (e) {
      setState(() => _status = 'Get info failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _trimAudio(String assetPath) async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _status = 'Trimming audio (0.2s - 0.8s)...';
    });

    try {
      final inputPath = await _copyAssetToTemp(assetPath);
      final inputSize = File(inputPath).lengthSync();
      final outputPath = '${Directory.systemTemp.path}/trimmed.wav';
      final result = await AudioDecoder.trimAudio(
        inputPath,
        outputPath,
        const Duration(milliseconds: 200),
        const Duration(milliseconds: 800),
      );
      final outputSize = await File(result).length();

      setState(() {
        _status =
            'Trimmed ${assetPath.split('/').last} (0.2s-0.8s)\n\n'
            'Input: $inputSize bytes\n'
            'Output: ${result.split('/').last}\n'
            'Size: ${(outputSize / 1024).toStringAsFixed(1)} KB';
      });
    } on AudioConversionException catch (e) {
      setState(() => _status = 'Trim failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<Uint8List> _loadAssetBytes(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    return data.buffer.asUint8List();
  }

  Future<void> _convertToWavBytes(String assetPath) async {
    if (_busy) return;

    final ext = assetPath.split('.').last;

    setState(() {
      _busy = true;
      _status = 'Converting ${ext.toUpperCase()} → WAV (bytes API)...';
    });

    try {
      final inputBytes = await _loadAssetBytes(assetPath);
      final wavBytes = await AudioDecoder.convertToWavBytes(
        inputBytes,
        formatHint: ext,
      );

      setState(() {
        _status =
            'Bytes API: ${ext.toUpperCase()} → WAV\n\n'
            'Input: ${assetPath.split('/').last} (${inputBytes.length} bytes)\n'
            'Output: ${wavBytes.length} bytes\n'
            'Size: ${(wavBytes.length / 1024).toStringAsFixed(1)} KB';
      });
    } on AudioConversionException catch (e) {
      setState(() => _status = 'Bytes conversion failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _convertToRawPcmBytes(String assetPath) async {
    if (_busy) return;

    final ext = assetPath.split('.').last;

    setState(() {
      _busy = true;
      _status = 'Converting ${ext.toUpperCase()} → raw PCM (bytes API)...';
    });

    try {
      final inputBytes = await _loadAssetBytes(assetPath);
      final wavBytes = await AudioDecoder.convertToWavBytes(
        inputBytes,
        formatHint: ext,
      );
      final pcmBytes = await AudioDecoder.convertToWavBytes(
        inputBytes,
        formatHint: ext,
        includeHeader: false,
      );

      setState(() {
        _status =
            'Bytes API: ${ext.toUpperCase()} → raw PCM\n\n'
            'Input: ${assetPath.split('/').last} (${inputBytes.length} bytes)\n'
            'WAV output: ${wavBytes.length} bytes (with header)\n'
            'PCM output: ${pcmBytes.length} bytes (headerless)\n'
            'Header stripped: ${wavBytes.length - pcmBytes.length} bytes';
      });
    } on AudioConversionException catch (e) {
      setState(() => _status = 'Raw PCM conversion failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _getAudioInfoBytes(String assetPath) async {
    if (_busy) return;

    final ext = assetPath.split('.').last;

    setState(() {
      _busy = true;
      _status = 'Getting audio info (bytes API)...';
    });

    try {
      final inputBytes = await _loadAssetBytes(assetPath);
      final info = await AudioDecoder.getAudioInfoBytes(
        inputBytes,
        formatHint: ext,
      );

      setState(() {
        _status =
            'Bytes API Info: ${assetPath.split('/').last}\n\n'
            'Duration: ${info.duration.inMilliseconds} ms\n'
            'Sample rate: ${info.sampleRate} Hz\n'
            'Channels: ${info.channels}\n'
            'Bit rate: ${info.bitRate} bps\n'
            'Format: ${info.format}';
      });
    } on AudioConversionException catch (e) {
      setState(() => _status = 'Bytes info failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _trimAudioBytes(String assetPath) async {
    if (_busy) return;

    final ext = assetPath.split('.').last;

    setState(() {
      _busy = true;
      _status = 'Trimming audio (0.2s - 0.8s, bytes API)...';
    });

    try {
      final inputBytes = await _loadAssetBytes(assetPath);
      final trimmedBytes = await AudioDecoder.trimAudioBytes(
        inputBytes,
        formatHint: ext,
        start: const Duration(milliseconds: 200),
        end: const Duration(milliseconds: 800),
      );

      setState(() {
        _status =
            'Bytes API: Trimmed (0.2s-0.8s)\n\n'
            'Input: ${assetPath.split('/').last} (${inputBytes.length} bytes)\n'
            'Output: ${trimmedBytes.length} bytes\n'
            'Size: ${(trimmedBytes.length / 1024).toStringAsFixed(1)} KB';
      });
    } on AudioConversionException catch (e) {
      setState(() => _status = 'Bytes trim failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _getWaveformBytes(String assetPath) async {
    if (_busy) return;

    final ext = assetPath.split('.').last;

    setState(() {
      _busy = true;
      _waveform = null;
      _status = 'Extracting waveform (bytes API)...';
    });

    try {
      final inputBytes = await _loadAssetBytes(assetPath);
      final waveform = await AudioDecoder.getWaveformBytes(
        inputBytes,
        formatHint: ext,
        numberOfSamples: 800,
      );

      setState(() {
        _waveform = waveform;
        _status = 'Bytes API: Waveform (${waveform.length} samples)';
      });
    } on AudioConversionException catch (e) {
      setState(() => _status = 'Bytes waveform failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _getWaveform(String assetPath) async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _waveform = null;
      _status = 'Extracting waveform...';
    });

    try {
      final inputPath = await _copyAssetToTemp(assetPath);
      final waveform = await AudioDecoder.getWaveform(
        inputPath,
        numberOfSamples: 800,
      );

      setState(() {
        _waveform = waveform;
        _status = 'Waveform (${waveform.length} samples)';
      });
    } on AudioConversionException catch (e) {
      setState(() => _status = 'Waveform failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Audio Decoder Example')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              if (_waveform != null) ...[
                const SizedBox(height: 12),
                Container(
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: CustomPaint(
                    size: const Size(double.infinity, 120),
                    painter: _WaveformPainter(_waveform!),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              const Text(
                'Conversion',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _busy
                    ? null
                    : () => _convertToWav('assets/test_tone.mp3'),
                child: const Text('Convert MP3 → WAV'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _busy
                    ? null
                    : () => _convertToWav('assets/test_tone.m4a'),
                child: const Text('Convert M4A → WAV'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _busy
                    ? null
                    : () => _convertToM4a('assets/test_tone.wav'),
                child: const Text('Convert WAV → M4A'),
              ),
              const SizedBox(height: 20),
              const Text(
                'Info & Analysis',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _busy
                    ? null
                    : () => _getAudioInfo('assets/test_tone.mp3'),
                child: const Text('Get Audio Info (MP3)'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _busy
                    ? null
                    : () => _getWaveform('assets/test_tone.mp3'),
                child: const Text('Get Waveform (MP3)'),
              ),
              const SizedBox(height: 20),
              const Text('Trim', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _busy
                    ? null
                    : () => _trimAudio('assets/test_tone.mp3'),
                child: const Text('Trim MP3 (0.2s - 0.8s) → WAV'),
              ),
              const SizedBox(height: 20),
              const Text(
                'Bytes API (in-memory)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _busy
                    ? null
                    : () => _convertToWavBytes('assets/test_tone.mp3'),
                child: const Text('Convert MP3 → WAV (bytes)'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _busy
                    ? null
                    : () => _convertToRawPcmBytes('assets/test_tone.mp3'),
                child: const Text('Convert MP3 → raw PCM (bytes)'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _busy
                    ? null
                    : () => _getAudioInfoBytes('assets/test_tone.mp3'),
                child: const Text('Get Audio Info (bytes)'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _busy
                    ? null
                    : () => _trimAudioBytes('assets/test_tone.mp3'),
                child: const Text('Trim MP3 (0.2s - 0.8s, bytes)'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _busy
                    ? null
                    : () => _getWaveformBytes('assets/test_tone.mp3'),
                child: const Text('Get Waveform (bytes)'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> waveform;

  _WaveformPainter(this.waveform);

  @override
  void paint(Canvas canvas, Size size) {
    if (waveform.isEmpty) return;

    final barWidth = size.width / waveform.length;
    final midY = size.height / 2;
    final paint = Paint()..color = Colors.blueAccent;

    for (int i = 0; i < waveform.length; i++) {
      final barHeight = waveform[i] * midY;
      final x = i * barWidth;
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(x + barWidth / 2, midY),
          width: barWidth * 0.8,
          height: barHeight * 2,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      oldDelegate.waveform != waveform;
}
