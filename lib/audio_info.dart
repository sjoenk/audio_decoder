class AudioInfo {
  final Duration duration;
  final int sampleRate;
  final int channels;
  final int bitRate;
  final String format;

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
