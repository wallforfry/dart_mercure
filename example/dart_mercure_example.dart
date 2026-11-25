import 'dart:io';

import 'package:dart_mercure/dart_mercure.dart';

/// Subscribes to a topic, publishes one update to it, prints what comes back,
/// then disconnects.
///
/// Expects `MERCURE_HUB_URL` and `MERCURE_JWT` (a JWT allowed to publish and
/// subscribe) in the environment.
Future<void> main() async {
  final mercure = Mercure(
    hubUrl: Uri.parse(Platform.environment['MERCURE_HUB_URL']!),
    publisherToken: Platform.environment['MERCURE_JWT'],
    subscriberToken: Platform.environment['MERCURE_JWT'],
  );
  const topic = 'https://example.com/books/1';

  final subscription = mercure
      .subscribe(const [TopicMatcher.exact(topic)])
      .listen(
        (event) => print('Received ${event.id}: ${event.data}'),
        onError: (Object error) => print('Subscription error: $error'),
      );

  // Give the hub a moment to register the subscriber before publishing.
  await Future<void>.delayed(const Duration(seconds: 1));
  try {
    final id = await mercure.publish(topics: [topic], data: '{"status":"ok"}');
    print('Published $id');
  } on MercurePublishException catch (error) {
    print('Publish failed: $error');
  }

  await Future<void>.delayed(const Duration(seconds: 1));
  await subscription.cancel();
  mercure.close();
}
