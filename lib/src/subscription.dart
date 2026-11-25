import 'dart:async';

import 'package:http/http.dart' as http;

import 'mercure_event.dart';
import 'mercure_exception.dart';
import 'sse_decoder.dart';

/// Opens a single-subscription stream that keeps one connection to [uri]
/// alive, reconnecting after [retry] (or the delay the hub sends) and resuming
/// from the last received event ID.
///
/// Connection failures and 5xx responses are reported as non-fatal
/// [http.ClientException] errors; a refusal by the hub is reported as a
/// [MercureSubscribeException] and ends the stream, as does any other error.
/// The stream also ends, without error, once [closed] completes.
Stream<MercureEvent> subscriptionStream({
  required http.Client client,
  required Uri uri,
  required Map<String, String> headers,
  required Duration retry,
  required Future<void> closed,
  String? lastEventId,
}) {
  final stopped = Completer<void>();
  void stop() {
    if (!stopped.isCompleted) stopped.complete();
  }

  late final StreamController<MercureEvent> controller;
  Future<void>? connection;

  controller = StreamController<MercureEvent>(
    onListen: () {
      unawaited(closed.then((_) => stop()));
      connection = _connectLoop(
        client: client,
        uri: uri,
        headers: headers,
        retry: retry,
        lastEventId: lastEventId,
        stopped: stopped.future,
        sink: controller,
      ).whenComplete(() => unawaited(controller.close()));
    },
    onCancel: () {
      stop();
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
  required Future<void> stopped,
  required StreamSink<MercureEvent> sink,
}) async {
  var resumeFrom = lastEventId;
  var delay = retry;
  var isStopped = false;
  unawaited(stopped.then((_) => isStopped = true));

  while (!isStopped) {
    final resume = resumeFrom;
    try {
      final request = http.AbortableRequest('GET', uri, abortTrigger: stopped)
        ..headers.addAll({
          ...headers,
          'Accept': 'text/event-stream',
          'Cache-Control': 'no-cache',
          if (resume != null && resume.isNotEmpty) 'Last-Event-ID': resume,
        });
      final response = await _sendUnlessStopped(client, request, stopped);
      if (response == null) return;
      await _ensureEventStream(response);
      await _forwardUntil(response.stream.transform(sseDecoder), stopped, (
        frame,
      ) {
        switch (frame) {
          case SseEvent(:final lastEventId, :final type, :final data):
            resumeFrom = lastEventId ?? resumeFrom;
            final id = resumeFrom;
            sink.add(
              MercureEvent(
                id: (id == null || id.isEmpty) ? null : id,
                type: type,
                data: data,
              ),
            );
          case SseLastEventId(:final lastEventId):
            resumeFrom = lastEventId;
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
    if (!isStopped) await _sleep(delay, stopped);
  }
}

/// Returns `null` when [stopped] completes before the response headers: not
/// every client honours the abort trigger, so the late response is discarded.
Future<http.StreamedResponse?> _sendUnlessStopped(
  http.Client client,
  http.BaseRequest request,
  Future<void> stopped,
) async {
  final sent = client.send(request);
  final response = await Future.any([sent, stopped.then((_) => null)]);
  if (response == null) {
    unawaited(
      sent.then(
        (late) => late.stream.listen(null).cancel(),
        onError: (Object _) {},
      ),
    );
  }
  return response;
}

Future<void> _ensureEventStream(http.StreamedResponse response) async {
  final status = response.statusCode;
  if (status != 200) {
    final body = await response.stream.bytesToString();
    // Deliberate deviation from EventSource, which gives up on any non-200:
    // a hub restarting behind a proxy answers 502 or 503 for a moment.
    if (status >= 500) {
      throw http.ClientException(
        'Hub unavailable ($status): $body',
        response.request?.url,
      );
    }
    throw MercureSubscribeException(
      'Hub refused the subscription ($status): $body',
      statusCode: status,
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
      statusCode: status,
    );
  }
}

/// Listens to [frames] until they end or [stopped] completes. An abortable
/// request already stops the body, but not every client honours the abort
/// trigger (`MockClient` leaves it to the handler).
Future<void> _forwardUntil(
  Stream<SseFrame> frames,
  Future<void> stopped,
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
    await Future.any([finished.future, stopped]);
  } finally {
    await subscription.cancel();
  }
}

Future<void> _sleep(Duration delay, Future<void> stopped) {
  final woken = Completer<void>();
  final timer = Timer(delay, woken.complete);
  unawaited(
    stopped.then((_) {
      timer.cancel();
      if (!woken.isCompleted) woken.complete();
    }),
  );
  return woken.future;
}
