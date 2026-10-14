## 1.0.0

Rewrite for Dart 3 and Mercure 1.x hubs. Breaking changes:

- Requires Dart 3.8 and `package:http` 1.5 or later; `package:eventsource` and `package:meta` are
  no longer dependencies.
- `Mercure` takes `hubUrl` as a `Uri` and separate `publisherToken` and `subscriberToken`; the
  `token` and `hub_url` parameters are gone.
- `subscribeTopic` and `subscribeTopics` are replaced by `subscribe`, which takes `TopicMatcher`s
  and returns a `Stream<MercureEvent>`. Cancelling the stream subscription disconnects.
- `publish` takes a list of `topics`, returns the update ID assigned by the hub and throws a
  `MercurePublishException` instead of returning the HTTP status.
- `Event` from `package:eventsource` is no longer exported; updates are `MercureEvent`s.

New:

- `publish` accepts `id`, `private`, `type` and `retry`.
- Subscriptions reconnect after a lost connection, honour the hub's `retry` delay and resume with
  `Last-Event-ID`; `lastEventId` sets the starting point.
- Subscriptions refused by the hub end with a `MercureSubscribeException`.

## 0.2.1
- #5 fix: use the new default path in README.md
- Use new default path in example

## 0.2.0
- #3 feat: use JWT for topic subscription

## 0.1.2
- Update Readme
- Move to Github

## 0.1.1
- Update package description
- Clean code with dartfmt

## 0.1.0
- Initial version
