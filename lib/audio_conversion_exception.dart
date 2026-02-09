/// Exception thrown when an audio conversion or analysis operation fails.
///
/// Contains a human-readable [message] and optional [details] from the
/// native platform.
class AudioConversionException implements Exception {
  /// A human-readable description of the error.
  final String message;

  /// Optional platform-specific details about the failure.
  final String? details;

  /// Creates an [AudioConversionException] with the given [message] and
  /// optional [details].
  AudioConversionException(this.message, {this.details});

  @override
  String toString() => 'AudioConversionException: $message${details != null ? ' ($details)' : ''}';
}
