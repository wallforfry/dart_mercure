import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'mercure_event.dart';
import 'mercure_exception.dart';
import 'sse_decoder.dart';
import 'stop_signal.dart';

/// Opens a single-subscription stream that keeps one connection to [uri]
/// alive, reconnecting after [retry] (or the delay the hub sends) and resuming
/// from the last received event ID.
///
/// Connection failures and 5xx responses are reported as non-fatal
/// [http.ClientException] errors; a refusal by the hub is reported as a
/// [MercureSubscribeException] and ends the stream, as does any other error.
/// The stream also ends, without error, once [closing] stops.
Stream<MercureEvent> subscriptionStream({
  required http.Client client,
  required Uri uri,
  required Map<String, String> headers,
  required Duration retry,
  required StopSignal closing,
  String? lastEventId,
}) {
  final signal = StopSignal();
  late final StreamController<MercureEvent> controller;
  Future<void>? connection;

  controller = StreamController<MercureEvent>(
    onListen: () {
      final detach = closing.onStop(signal.stop);
      connection =
          _connectLoop(
            client: client,
            uri: uri,
            headers: headers,
            retry: retry,
            lastEventId: lastEventId,
            signal: signal,
            sink: controller,
          ).whenComplete(() {
            detach();
            unawaited(controller.close());
          });
    },
    onCancel: () {
      signal.stop();
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
  required StopSignal signal,
  required StreamSink<MercureEvent> sink,
}) async {
  var resumeFrom = lastEventId;
  var delay = retry;

  while (!signal.isStopped) {
    final resume = resumeFrom;
    final abort = Completer<void>();
    final detachAbort = signal.onStop(abort.complete);
    try {
      final request =
          http.AbortableRequest('GET', uri, abortTrigger: abort.future)
            ..headers.addAll({
              ...headers,
              'Accept': 'text/event-stream',
              'Cache-Control': 'no-cache',
              if (resume != null && resume.isNotEmpty) 'Last-Event-ID': resume,
            });
      final response = await _sendUnlessStopped(client, request, signal);
      if (response == null) return;
      if (!await _acceptEventStream(response, signal)) return;
      await _forwardUntil(response.stream.transform(sseDecoder), signal, (
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
    } finally {
      detachAbort();
    }
    await _sleep(delay, signal);
  }
}

/// Returns `null` when [signal] stops before the response headers: not every
/// client honours the abort trigger, so the late response is discarded.
Future<http.StreamedResponse?> _sendUnlessStopped(
  http.Client client,
  http.BaseRequest request,
  StopSignal signal,
) {
  final result = Completer<http.StreamedResponse?>();
  final detach = signal.onStop(() {
    if (!result.isCompleted) result.complete(null);
  });
  client
      .send(request)
      .then(
        (response) {
          detach();
          if (result.isCompleted) {
            unawaited(response.stream.listen(null).cancel());
          } else {
            result.complete(response);
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          detach();
          if (!result.isCompleted) result.completeError(error, stackTrace);
        },
      );
  return result.future;
}

/// Throws unless [response] is an event stream, or returns `false` when
/// [signal] stops while an error body is being read.
Future<bool> _acceptEventStream(
  http.StreamedResponse response,
  StopSignal signal,
) async {
  final status = response.statusCode;
  if (status != 200) {
    final chunks = <List<int>>[];
    await _forwardUntil(response.stream, signal, chunks.add);
    if (signal.isStopped) return false;
    final body = utf8.decode([
      for (final chunk in chunks) ...chunk,
    ], allowMalformed: true);
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
    unawaited(response.stream.listen(null).cancel());
    throw MercureSubscribeException(
      'Hub answered with "$mediaType" instead of text/event-stream',
      statusCode: status,
    );
  }
  return true;
}

/// Listens to [events] until they end or [signal] stops. An abortable request
/// already stops the body, but not every client honours the abort trigger
/// (`MockClient` leaves it to the handler), and a client closed by
/// `Mercure.close()` fails the body before the abort lands.
Future<void> _forwardUntil<T>(
  Stream<T> events,
  StopSignal signal,
  void Function(T event) onEvent,
) async {
  final finished = Completer<void>();
  void finish() {
    if (!finished.isCompleted) finished.complete();
  }

  final subscription = events.listen(
    onEvent,
    onError: (Object error, StackTrace stackTrace) {
      if (!finished.isCompleted) finished.completeError(error, stackTrace);
    },
    onDone: finish,
    cancelOnError: true,
  );
  final detach = signal.onStop(finish);
  try {
    await finished.future;
  } finally {
    detach();
    await subscription.cancel();
  }
}

Future<void> _sleep(Duration delay, StopSignal signal) {
  final woken = Completer<void>();
  late final void Function() detach;
  final timer = Timer(delay, () {
    detach();
    woken.complete();
  });
  detach = signal.onStop(() {
    timer.cancel();
    if (!woken.isCompleted) woken.complete();
  });
  return woken.future;
}
