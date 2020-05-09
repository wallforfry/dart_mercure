import 'package:dart_mercure/src/dart_mercure_auth_client.dart';
import 'package:eventsource/eventsource.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

class Mercure {
  final String hub_url;
  final String token;
  final http.Client _client;

  Mercure({@required this.hub_url, @required this.token})
      : assert(hub_url != null),
        assert(token != null),
        _client = AuthClient(token, http.Client());

  /// Subscribe to one mercure topic
  StreamSubscription<Event> subscribeTopic(
      {@required String topic,
      @required void Function(Event event) onData,
      Function onError,
      void Function() onDone,
      bool cancelOnError}) {
    subscribeTopics(
        topics: <String>[topic],
        onData: onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError);
  }

  /// Subscribe to a list of mercure topics
  StreamSubscription<Event> subscribeTopics(
      {@required List<String> topics,
      @required void Function(Event event) onData,
      Function onError,
      void Function() onDone,
      bool cancelOnError}) {
    var params = topics.map((topic) => 'topic=$topic&').join();
    EventSource.connect('$hub_url?$params', client: _client).then((eventSource) {
      eventSource.listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);
    });
  }

  /// Publish data in mercure topic
  Future<int> publish({@required String topic, @required String data}) async {
    var response = await _client.post(hub_url,
        body: {'topic': topic, 'data': data});
    return response.statusCode;
  }
}
