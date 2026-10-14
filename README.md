# dart_mercure

[![CI](https://github.com/wallforfry/dart_mercure/actions/workflows/ci.yml/badge.svg)](https://github.com/wallforfry/dart_mercure/actions/workflows/ci.yml)
[![pub package](https://img.shields.io/pub/v/dart_mercure.svg)](https://pub.dev/packages/dart_mercure)

Publish and subscribe to a [Mercure](https://mercure.rocks) hub from Dart.

- Publishes public and private updates, with alternate topics, custom IDs, event types and retry
  hints.
- Subscribes with exact or URL Pattern matchers and returns a plain Dart `Stream`.
- Reconnects on its own and resumes from the last received update with `Last-Event-ID`.
- Depends on `package:http` only.

Supports Mercure 1.x hubs. Hubs older than 1.0 select topics with a `topic` query parameter that
this package no longer sends.

Runs on the Dart VM and Flutter for Android, iOS, Linux, macOS and Windows. The web is not declared
as a supported platform because subscriptions have not been tested in a browser.

## Usage

```dart
import 'package:dart_mercure/dart_mercure.dart';

Future<void> main() async {
  final mercure = Mercure(
    hubUrl: Uri.parse('https://example.com/.well-known/mercure'),
    publisherToken: publisherJwt,
    subscriberToken: subscriberJwt,
  );

  final subscription = mercure
      .subscribe(const [
        TopicMatcher.exact('https://example.com/books/1'),
        TopicMatcher.urlPattern('https://example.com/users/:id'),
      ])
      .listen(
        (event) => print('${event.id}: ${event.data}'),
        onError: (Object error) => print('Connection problem: $error'),
      );

  final id = await mercure.publish(
    topics: ['https://example.com/books/1'],
    data: '{"status": "checked out"}',
  );
  print('Published $id');

  await subscription.cancel();
  mercure.close();
}
```

### Tokens

Both tokens are sent as `Authorization: Bearer` headers. Mercure 1.x expects OAuth 2.0 access
tokens (RFC 9068, `typ: at+jwt`) whose grants are listed in `authorization_details`. See the
[authorization documentation](https://mercure.rocks/docs/concepts/authorization). Leave
`subscriberToken` out for anonymous subscriptions.

### Errors

`publish` throws a `MercurePublishException` carrying the HTTP status when the hub rejects an
update.

A subscription stream reports two kinds of errors:

- `ClientException` for a lost or failed connection. The stream stays open and reconnects after the
  delay the hub requested, or `defaultRetry` (3 seconds) until it sends one. `await for` stops at
  the first error, so use `listen` with `onError` to keep receiving updates.
- `MercureSubscribeException` when the hub refuses the subscription (for example a 401) or does not
  answer with `text/event-stream`. The stream then ends.

### Resuming

Pass `lastEventId` to receive the updates published after a known one, or `earliest` for every
update the hub still holds:

```dart
mercure.subscribe(const [TopicMatcher.exact('https://example.com/books/1')],
    lastEventId: 'urn:uuid:5e94c686-2c0b-4f9b-958c-92ccc3bbb4eb');
```

## Running the tests

Unit tests need nothing else:

```sh
dart test -x integration
```

Integration tests need a hub. With Docker:

```sh
docker run -d --rm --name mercure -p 8080:80 -e SERVER_NAME=':80' \
  -e MERCURE_PUBLISHER_JWT_KEY=test-only-mercure-key-0123456789abcdef \
  -e MERCURE_SUBSCRIBER_JWT_KEY=test-only-mercure-key-0123456789abcdef \
  dunglas/mercure:v1.1.2
export MERCURE_HUB_URL=http://localhost:8080/.well-known/mercure
export MERCURE_JWT=$(tool/test_jwt.sh test-only-mercure-key-0123456789abcdef \
  https://localhost "$MERCURE_HUB_URL")
dart test -t integration
```

The integration tests fail when `MERCURE_HUB_URL` or `MERCURE_JWT` is missing.

## Features and bugs

Please file feature requests and bugs at the
[issue tracker](https://github.com/wallforfry/dart_mercure/issues).

## License

[MIT](LICENSE)
