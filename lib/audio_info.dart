/// Metadata about an audio file or audio data.
///
/// Returned by [AudioDecoder.getAudioInfo] and [AudioDecoder.getAudioInfoBytes].
class AudioInfo {
  /// Total duration of the audio.
  final Duration duration;

  /// Sample rate in Hz (e.g., 44100, 48000).
  final int sampleRate;

  /// Number of audio channels (1 = mono, 2 = stereo).
  final int channels;

  /// Bit rate in bits per second (e.g., 128000 for 128 kbps).
  final int bitRate;

  /// Audio format identifier (e.g., 'mp3', 'm4a', 'wav').
  final String format;

  /// Creates an [AudioInfo] with the given metadata.
  const AudioInfo({
    required this.duration,
    required this.sampleRate,
    required this.channels,
    required this.bitRate,
    required this.format,
  });

  @override
  String toString() =>
      'AudioInfo(duration: $duration, sampleRate: $sampleRate, '
      'channels: $channels, bitRate: $bitRate, format: $format)';
}
