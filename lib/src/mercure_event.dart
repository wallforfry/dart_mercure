/// An update received from a Mercure hub.
final class MercureEvent {
  /// Creates an update as the hub would deliver it.
  const MercureEvent({required this.data, this.id, this.type = 'message'});

  /// The update ID, used to resume a subscription with `Last-Event-ID`.
  final String? id;

  /// The SSE event type, `message` unless the publisher set one.
  final String type;

  /// The update payload.
  final String data;

  @override
  bool operator ==(Object other) =>
      other is MercureEvent &&
      other.id == id &&
      other.type == type &&
      other.data == data;

  @override
  int get hashCode => Object.hash(id, type, data);

  @override
  String toString() => 'MercureEvent(id: $id, type: $type, data: $data)';
}
