import 'dart:async';
import 'dart:convert';

/// A unit decoded from a `text/event-stream` body.
sealed class SseFrame {}

/// A dispatched event, carrying the last event ID seen so far.
final class SseEvent implements SseFrame {
  /// Creates a dispatched event.
  const SseEvent({
    required this.lastEventId,
    required this.type,
    required this.data,
  });

  /// The last event ID seen on the stream, `null` if none was ever sent.
  final String? lastEventId;

  /// The event type, `message` by default.
  final String type;

  /// The data lines of the event, joined with line feeds.
  final String data;
}

/// An event ID set by a block that carried no data, which updates the last
/// event ID without dispatching an event.
final class SseLastEventId implements SseFrame {
  /// Creates a last event ID update.
  const SseLastEventId(this.lastEventId);

  /// The new last event ID; empty when the server reset it.
  final String lastEventId;
}

/// A reconnection delay requested by the server.
final class SseRetry implements SseFrame {
  /// Creates a reconnection delay request.
  const SseRetry(this.delay);

  /// The delay to wait before reconnecting.
  final Duration delay;
}

/// Decodes a byte stream following the WHATWG event stream interpretation
/// rules: https://html.spec.whatwg.org/multipage/server-sent-events.html
///
/// Parsing goes through `expand` rather than an `async*` generator: a
/// generator suspended in `await for` did not complete its cancellation
/// (observed on Dart 3.10.4), which left subscriptions hanging. The byte order
/// mark the specification strips is already removed by `Utf8Decoder`, which
/// replaces malformed bytes with U+FFFD as the specification requires.
final StreamTransformer<List<int>, SseFrame> sseDecoder =
    StreamTransformer.fromBind((bytes) {
      final parser = _SseParser();
      return bytes
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .expand(parser.parseLine);
    });

final RegExp _digits = RegExp(r'^\d+$');

/// The specification sets no upper bound on `retry`. Capping it keeps a broken
/// or hostile hub from overflowing `int` (which ended the subscription) or
/// `Duration` (a negative delay, which reconnected in a tight loop).
const Duration maxReconnectionDelay = Duration(days: 1);

Duration _reconnectionDelay(String digits) {
  final milliseconds = int.tryParse(digits);
  return milliseconds == null ||
          milliseconds > maxReconnectionDelay.inMilliseconds
      ? maxReconnectionDelay
      : Duration(milliseconds: milliseconds);
}

/// Holds the per-stream buffers the event stream format accumulates between
/// blank lines.
final class _SseParser {
  List<String> _data = [];
  String _type = '';
  String? _lastEventId;
  bool _blockHasId = false;

  /// Comment lines (`:` first) need no branch: their field name is empty, so
  /// the switch ignores them.
  List<SseFrame> parseLine(String line) {
    if (line.isEmpty) return _dispatch();

    final (field, value) = _splitField(line);
    switch (field) {
      case 'data':
        _data = [..._data, value];
      case 'event':
        _type = value;
      case 'id' when !value.contains('\u0000'):
        _lastEventId = value;
        _blockHasId = true;
      case 'retry' when _digits.hasMatch(value):
        return [SseRetry(_reconnectionDelay(value))];
    }
    return const [];
  }

  List<SseFrame> _dispatch() {
    final lastEventId = _lastEventId;
    final List<SseFrame> frames = switch ((_data.isEmpty, _blockHasId)) {
      (false, _) => [
        SseEvent(
          lastEventId: lastEventId,
          type: _type.isEmpty ? 'message' : _type,
          data: _data.join('\n'),
        ),
      ],
      (true, true) when lastEventId != null => [SseLastEventId(lastEventId)],
      _ => const [],
    };
    _data = [];
    _type = '';
    _blockHasId = false;
    return frames;
  }
}

(String, String) _splitField(String line) {
  final colon = line.indexOf(':');
  if (colon == -1) return (line, '');
  final value = line.substring(colon + 1);
  return (
    line.substring(0, colon),
    value.startsWith(' ') ? value.substring(1) : value,
  );
}
