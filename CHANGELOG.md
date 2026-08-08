## 0.8.2

* **Fix `OutOfMemoryError` on Android for long recordings** (#49) — `convertToM4a` collected the entire decoded track before encoding started, so a three hour file needed ~1.9 GB of PCM in memory and crashed on the Android heap limit. Decoding and AAC encoding now run interleaved, keeping peak memory independent of the audio duration.
  * `trimAudio` no longer buffers the trimmed range either (both the M4A and the WAV output path stream to disk), on Android and Windows.
  * `getWaveform` / `getWaveformBytes` fold RMS energy into a bounded set of buckets while decoding instead of collecting every sample — the old Android path stored boxed `Short` values (~16 bytes per sample) and ran out of memory well before an hour of audio. Implemented on Android, iOS, macOS, Linux and Windows.
  * For files long enough to exceed the bucket resolution the waveform is now approximated: values stay within ~0.001 of the previous result for regular material, while an extremely short and loud transient can spread into one neighbouring window.
* Windows: `trimAudio` no longer decodes the input twice for WAV output.
* Android: M4A timestamps are derived from the running frame count instead of accumulated per-buffer deltas, which drifted on long recordings; the encoder, muxer and extractor are now released on failure and a partially written output file is removed.

## 0.8.1

* **Fix `IndexOutOfBoundsException` on Android for long files** (#45) — `getWaveform` / `getWaveformBytes` crashed on medium-to-large audio (e.g. a 5-minute MP3) because the per-window offset `i * totalSamples` overflowed a 32-bit `Int` and wrapped to a negative index. The window bounds are now computed with 64-bit arithmetic.
* **Web: file-based methods reject their `Future` instead of throwing synchronously** — `convertToWav`, `convertToM4a`, `getAudioInfo`, `trimAudio`, and `getWaveform` are unsupported on web; the `UnsupportedError` is now delivered through the returned `Future`, so `await` / `.catchError` handle it consistently.
* Example app: file-based actions are disabled on web with an explanatory note, since they rely on `dart:io` (use the bytes-based API instead).

## 0.8.0

* **`WaveformNormalization` option** — opt into absolute amplitude scaling on `getWaveform` / `getWaveformBytes` to preserve loudness differences between tracks (useful for music apps that show several songs side by side).
  * `WaveformNormalization.perFile` (default) keeps the existing 0.7.x behavior: each waveform is rescaled so its loudest window equals 1.0.
  * `WaveformNormalization.absolute` divides by the maximum signed 16-bit PCM magnitude (32768), so a quiet recording stays visibly quieter than a loud one.
  * Implemented across all platforms: Android, iOS/macOS, Linux, Windows, Web.
* Validate `numberOfSamples` (`> 0`) on the public Dart API before dispatching to the platform.
* Fix cross-platform build failures (contributed by @navidicted):
  * **Linux**: add the missing forward `typedef`s for `G_DEFINE_TYPE` so the plugin compiles with GCC 15.2.1.
  * **Windows**: parenthesize `std::min` / `std::max` to avoid the MSVC `min`/`max` macro clash, cast `MF_SOURCE_READER_MEDIASOURCE` to `DWORD`, include `<cctype>` and `<flutter/encodable_value.h>`, and fix a `std::tolower` data-loss warning.

## 0.7.4

* **Swift Package Manager support** for iOS and macOS — plugin can now be consumed via SPM in addition to CocoaPods.
* Add Apple privacy manifest (`PrivacyInfo.xcprivacy`) for iOS 17+ compliance.
* Restyle example app waveform widget with responsive `AspectRatio` layout.
* Replace pub.dev screenshot with package logo.
* Documentation and code cleanup (formatter unification, constant extraction, CHANGELOG correction).

## 0.7.3

* **Documentation & presentation improvements** (no API changes)
  * Added screenshot of example app with waveform visualization for pub.dev.
  * Redesigned example app with Material 3 design system (color-coded status, modern buttons, gradient waveform).
  * Enhanced code documentation with helpful comments at all API call sites.
  * Added pub.dev quality badges (license, pub points, likes) to README.

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
* Consolidate duplicate iOS/macOS Swift plugin code into shared source under `darwin/audio_decoder/Sources/audio_decoder/`.

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
