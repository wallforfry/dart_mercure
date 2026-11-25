@Tags(['integration'])
library;

import 'dart:async';
import 'dart:io';

import 'package:dart_mercure/dart_mercure.dart';
import 'package:test/test.dart';

String requiredEnv(String name) =>
    Platform.environment[name] ??
    (throw StateError('$name must be set to run the integration tests'));

void main() {
  final hubUrl = Uri.parse(requiredEnv('MERCURE_HUB_URL'));
  final jwt = requiredEnv('MERCURE_JWT');
  const topic = 'https://example.com/dart_mercure/integration';

  test('delivers a published update to a subscriber', () async {
    final mercure = Mercure(
      hubUrl: hubUrl,
      publisherToken: jwt,
      subscriberToken: jwt,
    );
    addTearDown(mercure.close);

    final received = Completer<MercureEvent>();
    final errors = <Object>[];
    final subscription = mercure
        .subscribe(const [TopicMatcher.exact(topic)])
        .listen((event) {
          if (!received.isCompleted) received.complete(event);
        }, onError: errors.add);
    addTearDown(subscription.cancel);

    // The hub drops updates published before the subscriber is registered,
    // and nothing signals that registration, so publish until one arrives.
    final publications = <Future<String>>[];
    final ticker = Timer.periodic(const Duration(milliseconds: 200), (tick) {
      publications.add(
        mercure.publish(topics: [topic], data: 'ping-${tick.tick}'),
      );
    });

    final MercureEvent event;
    try {
      event = await received.future.timeout(const Duration(seconds: 10));
    } finally {
      ticker.cancel();
      expect(errors, isEmpty, reason: 'subscription errors');
    }
    final publishedIds = await Future.wait(publications);
    expect(event.data, startsWith('ping-'));
    expect(publishedIds, contains(event.id));
  });

  test('reports a rejected publication', () async {
    final mercure = Mercure(hubUrl: hubUrl, publisherToken: '${jwt}x');
    addTearDown(mercure.close);

    await expectLater(
      mercure.publish(topics: [topic], data: 'nope'),
      throwsA(
        isA<MercurePublishException>().having(
          (e) => e.statusCode,
          'statusCode',
          401,
        ),
      ),
    );
  });

  test('ends a subscription the hub refuses', () async {
    final mercure = Mercure(hubUrl: hubUrl, subscriberToken: '${jwt}x');
    addTearDown(mercure.close);

    await expectLater(
      mercure.subscribe(const [TopicMatcher.exact(topic)]),
      emitsInOrder([
        emitsError(
          isA<MercureSubscribeException>().having(
            (e) => e.statusCode,
            'statusCode',
            401,
          ),
        ),
        emitsDone,
      ]),
    );
  });
}
