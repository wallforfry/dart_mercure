/// A failure reported by a Mercure hub.
sealed class MercureException implements Exception {
  const MercureException(this.message, {this.statusCode});

  /// What went wrong, including the hub's response body when it sent one.
  final String message;

  /// The HTTP status returned by the hub, if a response was received.
  final int? statusCode;

  @override
  String toString() => '$runtimeType: $message';
}

/// The hub rejected a publication.
final class MercurePublishException extends MercureException {
  /// Creates the exception for a rejected publication.
  const MercurePublishException(super.message, {super.statusCode});
}

/// The hub refused a subscription; the subscription is not retried.
final class MercureSubscribeException extends MercureException {
  /// Creates the exception for a refused subscription.
  const MercureSubscribeException(super.message, {super.statusCode});
}
