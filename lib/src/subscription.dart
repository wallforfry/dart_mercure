import 'dart:async';

import 'package:http/http.dart' as http;

import 'mercure_event.dart';
import 'mercure_exception.dart';
import 'sse_decoder.dart';

/// Opens a single-subscription stream that keeps one connection to [uri]
/// alive, reconnecting after [retry] (or the delay the hub sends) and resuming
/// from the last received event ID.
///
/// Connection failures are reported as non-fatal [http.ClientException]
/// errors; a refusal by the hub is reported as a [MercureSubscribeException]
/// and closes the stream.
Stream<MercureEvent> subscriptionStream({
  required http.Client client,
  required Uri uri,
  required Map<String, String> headers,
  required Duration retry,
  String? lastEventId,
}) {
  final cancelled = Completer<void>();
  late final StreamController<MercureEvent> controller;
  Future<void>? connection;

  controller = StreamController<MercureEvent>(
    onListen: () {
      connection = _connectLoop(
        client: client,
        uri: uri,
        headers: headers,
        retry: retry,
        lastEventId: lastEventId,
        cancelled: cancelled.future,
        sink: controller,
      ).whenComplete(() => unawaited(controller.close()));
    },
    onCancel: () {
      if (!cancelled.isCompleted) cancelled.complete();
      return connection;
    },
  );
  return controller.stream;
}

Future<void> _connectLoop({
  required http.Client client,
  required Uri uri,
  required Map<String, String> headers,
  required Duration retry,
  required String? lastEventId,
  required Future<void> cancelled,
  required StreamSink<MercureEvent> sink,
}) async {
  var resumeFrom = lastEventId;
  var delay = retry;
  var isCancelled = false;
  unawaited(cancelled.then((_) => isCancelled = true));

  while (!isCancelled) {
    final resume = resumeFrom;
    try {
      final request = http.AbortableRequest('GET', uri, abortTrigger: cancelled)
        ..headers.addAll({
          ...headers,
          'Accept': 'text/event-stream',
          'Cache-Control': 'no-cache',
          if (resume != null && resume.isNotEmpty) 'Last-Event-ID': resume,
        });
      final response = await client.send(request);
      await _ensureEventStream(response);
      await _forwardUntil(response.stream.transform(sseDecoder), cancelled, (
        frame,
      ) {
        switch (frame) {
          case SseEvent():
            resumeFrom = frame.lastEventId;
            sink.add(
              MercureEvent(
                id: (frame.lastEventId?.isEmpty ?? true)
                    ? null
                    : frame.lastEventId,
                type: frame.type,
                data: frame.data,
              ),
            );
          case SseRetry(delay: final requested):
            delay = requested;
        }
      });
    } on http.RequestAbortedException {
      return;
    } on MercureSubscribeException catch (error, stackTrace) {
      sink.addError(error, stackTrace);
      return;
    } on http.ClientException catch (error, stackTrace) {
      sink.addError(error, stackTrace);
    } catch (error, stackTrace) {
      sink.addError(error, stackTrace);
      return;
    }
    if (!isCancelled) await _sleep(delay, cancelled);
  }
}

Future<void> _ensureEventStream(http.StreamedResponse response) async {
  if (response.statusCode != 200) {
    final body = await response.stream.bytesToString();
    throw MercureSubscribeException(
      'Hub refused the subscription (${response.statusCode}): $body',
      statusCode: response.statusCode,
    );
  }
  final mediaType = response.headers['content-type']
      ?.split(';')
      .first
      .trim()
      .toLowerCase();
  if (mediaType != 'text/event-stream') {
    await response.stream.drain<void>();
    throw MercureSubscribeException(
      'Hub answered with "$mediaType" instead of text/event-stream',
      statusCode: response.statusCode,
    );
  }
}

/// Listens to [frames] until they end or [cancelled] completes. An abortable
/// request already stops the body on cancellation, but not every client
/// honours the abort trigger (`MockClient` leaves it to the handler).
Future<void> _forwardUntil(
  Stream<SseFrame> frames,
  Future<void> cancelled,
  void Function(SseFrame frame) onFrame,
) async {
  final finished = Completer<void>();
  final subscription = frames.listen(
    onFrame,
    onError: finished.completeError,
    onDone: finished.complete,
    cancelOnError: true,
  );
  try {
    await Future.any([finished.future, cancelled]);
  } finally {
    await subscription.cancel();
  }
}

Future<void> _sleep(Duration delay, Future<void> cancelled) {
  final woken = Completer<void>();
  final timer = Timer(delay, woken.complete);
  unawaited(
    cancelled.then((_) {
      timer.cancel();
      if (!woken.isCompleted) woken.complete();
    }),
  );
  return woken.future;
}
