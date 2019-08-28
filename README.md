Dart library for [dunglas/mercure](https://github.com/dunglas/mercure)


[license](LICENSE).

## Usage

A basic usage example of publish/subscribe :

```dart
import 'package:dart_mercure/dart_mercure.dart';

main() {

  // Token generate with "mercure" JWT_KEY
  String token = "YOUR_JWT_TOKEN";
  String hub_url = "http://MERCURE_HUB_URL/hub";
  String topic = "http://YOUR_TOPIC/FOO";

  Mercure mercure = Mercure(token: token, hub_url: hub_url);

  // Subscribes to topics
  mercure.subscribeTopics(topics: <String> [topic, "ANOTHER_TOPIC"], onData: (Event event) {
    print(event.data);
  });

  // Subscribe to topic
  mercure.subscribeTopic(topic: topic, onData: (Event event) {
    print(event.data);
  });

  // Publish on topic
  mercure.publish(topic: topic, data: "DATA").then((status) {
    if(status == 200) {
      print("Message Sent");
    }
    else {
      print('Message Failed with code : $status');
    }
  });
}

```

## Features and bugs

Please file feature requests and bugs at the [issue tracker](../../../issues).
