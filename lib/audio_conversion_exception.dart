class AudioConversionException implements Exception {
  final String message;
  final String? details;

  AudioConversionException(this.message, {this.details});

  @override
  String toString() => 'AudioConversionException: $message${details != null ? ' ($details)' : ''}';
}
