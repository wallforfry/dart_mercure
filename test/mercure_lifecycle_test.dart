import 'dart:async';
import 'dart:io';

import 'package:dart_mercure/dart_mercure.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'support/mock_hub.dart';

/// Serves one event, then holds every connection open until the test ends.
Future<HttpServer> openHub() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) {
    request.response
      ..headers.contentType = ContentType('text', 'event-stream')
      ..bufferOutput = false
      ..write('id: 1\ndata: hello\n\n');
    unawaited(request.response.flush());
  });
  addTearDown(() => server.close(force: true));
  return server;
}

void main() {
  test('disconnects without reconnecting once cancelled', () async {
    var attempts = 0;
    final body = StreamController<String>();
    addTearDown(body.close);
    final mercure = mercureWith((_) async {
      attempts++;
      return eventStream(body.stream);
    });

    final received = Completer<MercureEvent>();
    final subscription = mercure.subscribe(anyTopic).listen(received.complete);
    body.add('data: x\n\n');
    await received.future;

    await subscription.cancel();

    expect(body.hasListener, isFalse);
    expect(attempts, 1);
  });

  test('cancels while the connection is still pending', () async {
    final pending = Completer<http.StreamedResponse>();
    final lateBody = StreamController<String>();
    addTearDown(lateBody.close);
    final mercure = mercureWith((_) => pending.future);

    final subscription = mercure.subscribe(anyTopic).listen((_) {});
    await pumpEventQueue();
    await subscription.cancel();
    pending.complete(eventStream(lateBody.stream));
    await pumpEventQueue();

    expect(lateBody.hasListener, isFalse);
  });

  test(
    'cancels while waiting to reconnect',
    () async {
      var attempts = 0;
      final mercure = mercureWith((_) async {
        attempts++;
        return eventStream(Stream.value('data: x\n\n'));
      }, defaultRetry: const Duration(hours: 1));

      final received = Completer<MercureEvent>();
      final subscription = mercure
          .subscribe(anyTopic)
          .listen(received.complete);
      await received.future;
      await pumpEventQueue();

      await subscription.cancel();

      expect(attempts, 1);
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );

  test('close() ends open subscriptions of its own client', () async {
    final server = await openHub();
    final mercure = Mercure(
      hubUrl: Uri.parse('http://127.0.0.1:${server.port}/.well-known/mercure'),
      defaultRetry: const Duration(milliseconds: 10),
    );

    final errors = <Object>[];
    final done = Completer<void>();
    final received = Completer<MercureEvent>();
    mercure
        .subscribe(anyTopic)
        .listen(received.complete, onError: errors.add, onDone: done.complete);
    expect((await received.future).data, 'hello');

    mercure.close();

    await done.future.timeout(const Duration(seconds: 2));
    expect(errors, isEmpty);
  });

  test('close() ends subscriptions without closing a caller client', () async {
    final body = StreamController<String>();
    addTearDown(body.close);
    final mercure = mercureWith((_) async => eventStream(body.stream));

    final done = Completer<void>();
    mercure.subscribe(anyTopic).listen((_) {}, onDone: done.complete);
    await pumpEventQueue();

    mercure.close();

    await done.future.timeout(const Duration(seconds: 2));
    expect(body.hasListener, isFalse);
  });

  test('refuses to publish or subscribe once closed', () {
    final mercure = mercureWith((_) async => eventStream(Stream.value('')))
      ..close();

    expect(() => mercure.subscribe(anyTopic), throwsStateError);
    expect(() => mercure.publish(topics: ['t'], data: 'd'), throwsStateError);
  });
}
