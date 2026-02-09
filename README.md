# audio_decoder

[![pub package](https://img.shields.io/pub/v/audio_decoder.svg)](https://pub.dev/packages/audio_decoder)

A lightweight Flutter plugin for converting, trimming, and analyzing audio files using native platform APIs. No FFmpeg dependency required.

## Features

- Convert MP3, M4A, AAC, FLAC, OGG, WMA, AIFF, and more to WAV
- Convert any audio format to M4A (AAC) — compressed output
- Get audio metadata (duration, sample rate, channels, bit rate, format)
- Trim audio files to a specific time range
- Extract waveform amplitude data for visualization
- **Bytes API** — work with in-memory audio (`Uint8List`) without file paths
- Uses native platform APIs — no bundled codecs or heavy dependencies
- Supports Android, iOS, macOS, Windows, Linux, and Web
- Minimal app size impact (~500KB vs ~15-30MB for FFmpeg)

## Platform APIs

| Platform | Native API |
|----------|------------|
| iOS | AVFoundation (AVAssetReader) |
| macOS | AVFoundation (AVAssetReader) |
| Android | MediaExtractor + MediaCodec |
| Windows | Media Foundation (IMFSourceReader) |
| Linux | GStreamer |
| Web | Web Audio API |

## Getting started

Add `audio_decoder` to your `pubspec.yaml`:

```yaml
dependencies:
  audio_decoder: ^0.4.0
```

Or install via the command line:

```sh
flutter pub add audio_decoder
```

No additional setup is needed — the plugin uses built-in platform APIs.

On **Linux**, GStreamer is required (pre-installed on most distributions). If needed:

```sh
sudo apt install libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev gstreamer1.0-plugins-good gstreamer1.0-plugins-bad
```

## Usage

```dart
import 'package:audio_decoder/audio_decoder.dart';

// Convert to WAV (lossless)
final wavPath = await AudioDecoder.convertToWav(
  '/path/to/song.mp3',
  '/path/to/output.wav',
);

// Convert to M4A (AAC compressed)
final m4aPath = await AudioDecoder.convertToM4a(
  '/path/to/song.wav',
  '/path/to/output.m4a',
);

// Check if a file needs conversion
if (AudioDecoder.needsConversion('song.mp3')) {
  // ...
}
```

### Get audio info

```dart
final info = await AudioDecoder.getAudioInfo('/path/to/song.mp3');
print(info.duration);   // Duration(seconds: 183)
print(info.sampleRate); // 44100
print(info.channels);   // 2
print(info.bitRate);    // 320000
print(info.format);     // "mp3"
```

### Trim audio

```dart
// Trim to a specific time range — output format is based on file extension
final trimmed = await AudioDecoder.trimAudio(
  '/path/to/song.mp3',
  '/path/to/clip.wav',         // .wav or .m4a
  Duration(seconds: 10),       // start
  Duration(seconds: 30),       // end
);
```

### Get waveform

```dart
// Extract normalized amplitude data (0.0–1.0) for visualization
final waveform = await AudioDecoder.getWaveform(
  '/path/to/song.mp3',
  numberOfSamples: 100,
);
// waveform = [0.12, 0.45, 0.87, 0.23, ...]
```

### Bytes API (in-memory)

Work directly with audio bytes — no file paths needed. Ideal for network responses, Flutter assets, or other in-memory sources.

```dart
import 'dart:typed_data';

// Load audio bytes from any source
final Uint8List mp3Bytes = await fetchFromNetwork();

// Convert bytes to WAV
final wavBytes = await AudioDecoder.convertToWavBytes(
  mp3Bytes,
  formatHint: 'mp3',
);

// Get metadata from bytes
final info = await AudioDecoder.getAudioInfoBytes(
  mp3Bytes,
  formatHint: 'mp3',
);

// Trim audio bytes
final trimmed = await AudioDecoder.trimAudioBytes(
  mp3Bytes,
  formatHint: 'mp3',
  start: Duration(seconds: 10),
  end: Duration(seconds: 30),
);

// Extract waveform from bytes
final waveform = await AudioDecoder.getWaveformBytes(
  mp3Bytes,
  formatHint: 'mp3',
  numberOfSamples: 100,
);
```

The `formatHint` parameter tells the native decoder what format the bytes are in (e.g., `'mp3'`, `'m4a'`, `'wav'`, `'aac'`).

### Error handling

```dart
try {
  await AudioDecoder.convertToWav(inputPath, outputPath);
} on AudioConversionException catch (e) {
  print('Conversion failed: ${e.message}');
}
```

## Supported formats

The `needsConversion` helper recognizes these extensions:

`.mp3` `.m4a` `.aac` `.mp4` `.ogg` `.oga` `.opus` `.flac` `.wma` `.aiff` `.aif` `.amr` `.caf` `.alac` `.webm`

The native decoders may support additional formats. You can always call `convertToWav` directly on any file — it will throw an `AudioConversionException` if the platform cannot decode it.

## Output formats

### WAV
- PCM signed 16-bit little-endian
- Original sample rate and channel count preserved
- Standard 44-byte RIFF/WAVE header

### M4A
- AAC-LC encoding at 128 kbps
- Original sample rate and channel count preserved
- MPEG-4 container

## Platform requirements

| Platform | Minimum version |
|----------|----------------|
| iOS | 13.0 |
| macOS | 10.13 |
| Android | API 24 |
| Windows | 7+ |
| Linux | GStreamer 1.0+ |
| Web | Modern browser with Web Audio API |

### Web limitations

- **File-based methods** (`convertToWav`, `convertToM4a`, `getAudioInfo`, `trimAudio`, `getWaveform`) are not available on web. Use the bytes-based API instead.
- **M4A encoding** is not supported on web — browsers do not provide a reliable AAC/M4A encoding API. Use `convertToWavBytes` instead.
- **Trimming** output is always WAV on web.

## License

See [LICENSE](LICENSE) for details.
