import 'package:eventsource/eventsource.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

class Mercure {
  final String hub_url;
  final String token;
  http.Client client;

  Mercure({@required this.hub_url, this.token, http.Client client})
      : assert(hub_url != null),
        assert(token != null) {
    this.client = client ?? http.Client();
  }

  /// Subscribe to one mercure topic
  StreamSubscription<Event> subscribeTopic(
      {@required String topic,
      @required void onData(Event event),
      Function onError,
      void onDone(),
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
      @required void onData(Event event),
      Function onError,
      void onDone(),
      bool cancelOnError}) {
    String params = topics.map((topic) => 'topic=$topic&').join();
    EventSource.connect('$hub_url?$params', client: this.client)
        .then((eventSource) {
      eventSource.listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);
    });
  }

  /// Publish data in mercure topic
  Future<int> publish({@required String topic, @required String data}) async {
    var response = await http.post(this.hub_url,
        body: {'topic': topic, 'data': data},
        headers: {'Authorization': 'Bearer $token'});
    return response.statusCode;
  }
}
