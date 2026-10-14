import 'package:http/http.dart' as http;

import 'mercure_event.dart';
import 'mercure_exception.dart';
import 'subscription.dart';
import 'topic_matcher.dart';

/// A client for one Mercure hub.
final class Mercure {
  /// Creates a client for the hub at [hubUrl], usually
  /// `https://example.com/.well-known/mercure`.
  ///
  /// [publisherToken] and [subscriberToken] are JWTs sent as bearer tokens;
  /// omit [subscriberToken] for anonymous subscriptions. A [client] passed in
  /// stays owned by the caller and is not closed by [close].
  Mercure({
    required this.hubUrl,
    this.publisherToken,
    this.subscriberToken,
    this.defaultRetry = const Duration(seconds: 3),
    http.Client? client,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  /// The hub endpoint.
  final Uri hubUrl;

  /// The JWT authorizing [publish], if any.
  final String? publisherToken;

  /// The JWT authorizing [subscribe], if any.
  final String? subscriberToken;

  /// The reconnection delay used until the hub sends its own.
  final Duration defaultRetry;

  final http.Client _client;
  final bool _ownsClient;

  /// Publishes [data] to [topics] and returns the update ID assigned by the
  /// hub. The first topic is canonical, the others are alternates.
  ///
  /// Throws a [MercurePublishException] if the hub rejects the update.
  Future<String> publish({
    required List<String> topics,
    required String data,
    String? id,
    bool private = false,
    String? type,
    Duration? retry,
  }) async {
    _ensureTopics(topics);
    final body = Uri(
      queryParameters: {
        'topic': topics,
        'data': data,
        'id': ?id,
        if (private) 'private': 'on',
        'type': ?type,
        if (retry != null) 'retry': '${retry.inMilliseconds}',
      },
    ).query;
    final response = await _client.post(
      hubUrl,
      headers: {
        ..._authorization(publisherToken),
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: body,
    );
    if (response.statusCode != 200) {
      throw MercurePublishException(
        'Hub rejected the update (${response.statusCode}): ${response.body}',
        statusCode: response.statusCode,
      );
    }
    return response.body;
  }

  /// Subscribes to the topics selected by [matchers] (between 1 and 100).
  ///
  /// The returned stream reconnects on its own and resumes after the last
  /// received update, or after [lastEventId] for the first connection; pass
  /// `earliest` to ask for every update the hub still holds. Connection
  /// failures arrive as non-fatal [http.ClientException] errors, so listen
  /// with `onError` rather than `await for` to keep receiving updates. A
  /// refusal by the hub arrives as a [MercureSubscribeException] and ends the
  /// stream. Cancel the subscription to disconnect.
  Stream<MercureEvent> subscribe(
    List<TopicMatcher> matchers, {
    String? lastEventId,
  }) => subscriptionStream(
    client: _client,
    uri: hubUrl.replace(
      queryParameters: {
        ...hubUrl.queryParametersAll,
        ...matcherQueryParameters(matchers),
      },
    ),
    headers: _authorization(subscriberToken),
    retry: defaultRetry,
    lastEventId: lastEventId,
  );

  /// Closes the HTTP client if this instance created it, which also ends
  /// every open subscription.
  void close() {
    if (_ownsClient) _client.close();
  }
}

Map<String, String> _authorization(String? token) =>
    token == null ? const {} : {'Authorization': 'Bearer $token'};

void _ensureTopics(List<String> topics) {
  if (topics.isEmpty) {
    throw ArgumentError.value(topics, 'topics', 'must not be empty');
  }
}
