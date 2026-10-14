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
/// (observed on Dart 3.10.4), which left subscriptions hanging.
final StreamTransformer<List<int>, SseFrame> sseDecoder =
    StreamTransformer.fromBind((bytes) {
      final parser = _SseParser();
      return bytes
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .expand(parser.parseLine);
    });

final RegExp _digits = RegExp(r'^\d+$');

/// Holds the per-stream buffers the event stream format accumulates between
/// blank lines.
final class _SseParser {
  List<String> _data = [];
  String _type = '';
  String? _lastEventId;
  bool _isFirstLine = true;

  List<SseFrame> parseLine(String rawLine) {
    final line = _isFirstLine && rawLine.startsWith('\uFEFF')
        ? rawLine.substring(1)
        : rawLine;
    _isFirstLine = false;

    if (line.isEmpty) return _dispatch();
    if (line.startsWith(':')) return const [];

    final (field, value) = _splitField(line);
    switch (field) {
      case 'data':
        _data = [..._data, value];
      case 'event':
        _type = value;
      case 'id' when !value.contains('\u0000'):
        _lastEventId = value;
      case 'retry' when _digits.hasMatch(value):
        return [SseRetry(Duration(milliseconds: int.parse(value)))];
    }
    return const [];
  }

  List<SseFrame> _dispatch() {
    final frames = _data.isEmpty
        ? const <SseFrame>[]
        : [
            SseEvent(
              lastEventId: _lastEventId,
              type: _type.isEmpty ? 'message' : _type,
              data: _data.join('\n'),
            ),
          ];
    _data = [];
    _type = '';
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
