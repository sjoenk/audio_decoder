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
