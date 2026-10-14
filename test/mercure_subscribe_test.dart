import 'dart:async';
import 'dart:convert';

import 'package:dart_mercure/dart_mercure.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

final hubUrl = Uri.parse('https://hub.test/.well-known/mercure');

http.StreamedResponse eventStream(Stream<String> body, {int status = 200}) =>
    http.StreamedResponse(
      body.map(utf8.encode),
      status,
      headers: {'content-type': 'text/event-stream; charset=utf-8'},
    );

Mercure mercureWith(
  Future<http.StreamedResponse> Function(http.BaseRequest request) handler, {
  String? subscriberToken,
}) => Mercure(
  hubUrl: hubUrl,
  subscriberToken: subscriberToken,
  defaultRetry: Duration.zero,
  client: MockClient.streaming((request, _) => handler(request)),
);

void main() {
  test('sends topics and credentials, then emits updates', () async {
    final requests = <http.BaseRequest>[];
    final mercure = mercureWith((request) async {
      requests.add(request);
      return eventStream(
        Stream.fromIterable([
          'id: 1\ndata: first\n\n',
          'id: 2\nevent: custom\ndata: second\n\n',
        ]),
      );
    }, subscriberToken: 'sub-jwt');

    final events = await mercure
        .subscribe(const [
          TopicMatcher.urlPattern('https://example.com/books/:id'),
          TopicMatcher.exact('b c'),
          TopicMatcher.exact('*'),
        ])
        .take(2)
        .toList();

    expect(events, const [
      MercureEvent(id: '1', data: 'first'),
      MercureEvent(id: '2', type: 'custom', data: 'second'),
    ]);
    final request = requests.single;
    expect(request.method, 'GET');
    expect(request.url.queryParametersAll, {
      'match_urlpattern': ['https://example.com/books/:id'],
      'match': ['b c', '*'],
    });
    expect(request.headers['Authorization'], 'Bearer sub-jwt');
    expect(request.headers['Accept'], 'text/event-stream');
    expect(request.headers, isNot(contains('Last-Event-ID')));
  });

  test('resumes from the initial lastEventId', () async {
    late http.BaseRequest sent;
    final mercure = mercureWith((request) async {
      sent = request;
      return eventStream(Stream.value('data: x\n\n'));
    });

    await mercure.subscribe(const [
      TopicMatcher.exact('t'),
    ], lastEventId: 'urn:uuid:9').first;

    expect(sent.headers['Last-Event-ID'], 'urn:uuid:9');
  });

  test(
    'reconnects after the stream ends and resumes from the last ID',
    () async {
      final requests = <http.BaseRequest>[];
      final mercure = mercureWith((request) async {
        requests.add(request);
        return eventStream(
          Stream.value(
            requests.length == 1
                ? 'retry: 1\nid: 1\ndata: first\n\n'
                : 'id: 2\ndata: second\n\n',
          ),
        );
      });

      final events = await mercure
          .subscribe(const [TopicMatcher.exact('t')])
          .take(2)
          .toList();

      expect(events.map((e) => e.data), ['first', 'second']);
      expect(requests, hasLength(2));
      expect(requests.last.headers['Last-Event-ID'], '1');
    },
  );

  test('reports a connection failure without ending the stream', () async {
    var attempts = 0;
    final mercure = mercureWith((_) async {
      attempts++;
      if (attempts == 1) throw http.ClientException('connection refused');
      return eventStream(Stream.value('data: back\n\n'));
    });

    final errors = <Object>[];
    final event = Completer<MercureEvent>();
    final subscription = mercure
        .subscribe(const [TopicMatcher.exact('t')])
        .listen(event.complete, onError: errors.add);

    expect((await event.future).data, 'back');
    expect(errors.single, isA<http.ClientException>());
    await subscription.cancel();
  });

  test('ends with MercureSubscribeException when the hub refuses', () async {
    var attempts = 0;
    final mercure = mercureWith((_) async {
      attempts++;
      return eventStream(Stream.value('Unauthorized'), status: 401);
    });

    await expectLater(
      mercure.subscribe(const [TopicMatcher.exact('t')]),
      emitsInOrder([
        emitsError(
          isA<MercureSubscribeException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.message, 'message', contains('Unauthorized')),
        ),
        emitsDone,
      ]),
    );
    expect(attempts, 1);
  });

  test('ends with MercureSubscribeException on a non-SSE response', () async {
    final mercure = Mercure(
      hubUrl: hubUrl,
      client: MockClient((_) async => http.Response('<html>', 200)),
    );

    await expectLater(
      mercure.subscribe(const [TopicMatcher.exact('t')]),
      emitsInOrder([emitsError(isA<MercureSubscribeException>()), emitsDone]),
    );
  });

  test('disconnects without reconnecting once cancelled', () async {
    var attempts = 0;
    final body = StreamController<String>();
    addTearDown(body.close);
    final mercure = mercureWith((_) async {
      attempts++;
      return eventStream(body.stream);
    });

    final received = Completer<MercureEvent>();
    final subscription = mercure
        .subscribe(const [TopicMatcher.exact('t')])
        .listen(received.complete);
    body.add('data: x\n\n');
    await received.future;

    await subscription.cancel();

    expect(body.hasListener, isFalse);
    expect(attempts, 1);
  });

  test('rejects no matchers or more than 100', () {
    final mercure = mercureWith((_) async => eventStream(Stream.value('')));

    expect(() => mercure.subscribe(const []), throwsArgumentError);
    expect(
      () => mercure.subscribe(
        List.generate(101, (i) => TopicMatcher.exact('t$i')),
      ),
      throwsArgumentError,
    );
  });
}
