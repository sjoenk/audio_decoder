## 0.7.2

* **Android: streaming resampling** — replace in-memory resampling with chunk-based streaming to avoid OOM on large files.
* Fix trailing sample loss when EOS arrives on an empty MediaCodec buffer.
* Pre-allocate resampler output buffer instead of using `ByteArrayOutputStream` to reduce GC pressure.
* Cap maximum target sample rate at 384 kHz to prevent pathological allocations.
* Add `MAX_WAV_DATA_SIZE` validation to the resampler flush path.

## 0.7.1

* Fix iOS build failure (`Module 'audio_decoder' not found`) when used as a pub dependency.
* Use `sharedDarwinSource` for shared iOS/macOS podspec resolution.
* Remove orphaned platform-specific podspec files.

## 0.7.0

* **Streaming WAV conversion** — decoded PCM chunks are now streamed directly to disk during WAV conversion, significantly reducing peak memory usage for large files.
  * Implemented on Android, iOS, macOS, Linux, and Windows.
* Add Dart-level input validation for `convertToWav` and `convertToWavBytes` parameters.
  * `sampleRate`, `channels`, and `bitDepth` are validated before calling native code, throwing `ArgumentError` for invalid values.
* Consolidate duplicate iOS/macOS Swift plugin code into shared source under `darwin/Classes/`.

## 0.6.0

* Add `includeHeader` parameter to `convertToWavBytes` (default `true`).
* When `false`, returns only raw interleaved PCM data without the 44-byte RIFF/WAV header.
* Useful for real-time audio pipelines, direct hardware interfaces, and custom audio processing.
* Supported on all platforms: Android, iOS, macOS, Windows, Linux, and Web.
* Add Dart 3 class modifiers to all library classes.
* `AudioDecoderPlatform` is now `abstract base class` — enforces extension over implementation.
* `MethodChannelAudioDecoder`, `AudioDecoderWeb`, `AudioDecoder`, `AudioConversionException`, and `AudioInfo` are now `final class` — prevents unintended subclassing.

## 0.5.0

* Add optional `sampleRate`, `channels`, and `bitDepth` parameters to `convertToWav` and `convertToWavBytes`.
* Control output sample rate (e.g., 44100, 22050), channel count (1 for mono, 2 for stereo), and bit depth (8, 16, 24, 32).
* When omitted, defaults to the source sample rate/channels and 16-bit depth.
* Supported on all platforms: Android, iOS, macOS, Windows, Linux, and Web.

## 0.4.0

* Add web support using the Web Audio API.
* Bytes-based methods (`convertToWavBytes`, `getAudioInfoBytes`, `trimAudioBytes`, `getWaveformBytes`) are fully supported on web.
* File-based methods throw `UnsupportedError` on web — use the bytes API instead.
* M4A encoding is not available on web (browser limitation).

## 0.3.0

* Add Linux support using GStreamer.
* All file-based and bytes-based methods are now available on Linux.
* Requires GStreamer 1.0+ (pre-installed on most Linux distributions).

## 0.2.0

* Add bytes-based API for in-memory audio processing — no file paths needed.
  * `convertToWavBytes` — convert audio bytes to WAV format.
  * `convertToM4aBytes` — convert audio bytes to M4A format.
  * `getAudioInfoBytes` — retrieve metadata from audio bytes.
  * `trimAudioBytes` — trim audio bytes to a time range.
  * `getWaveformBytes` — extract waveform data from audio bytes.
* All bytes methods accept a `formatHint` parameter to indicate the input format.
* Ideal for network responses, Flutter assets, and other in-memory audio sources.

## 0.1.0

* Initial release of `audio_decoder`.
* Convert audio files to WAV format (`convertToWav`) — supports MP3, M4A, AAC, OGG, OPUS, FLAC, WMA, AIFF, AMR, CAF, ALAC, and WebM.
* Convert audio files to M4A/AAC format (`convertToM4a`).
* Retrieve audio metadata (`getAudioInfo`) — duration, sample rate, channels, bit rate, and format.
* Trim audio files to a specific time range (`trimAudio`).
* Extract waveform amplitude data for visualizations (`getWaveform`).
* Platform support: Android, iOS, macOS, and Windows.
* Typed exception handling via `AudioConversionException`.
