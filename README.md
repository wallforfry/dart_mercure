Dart library for [dunglas/mercure](https://github.com/dunglas/mercure)

[![pipeline status](https://gitlab.com/wallforfry/dart_mercure/badges/master/pipeline.svg)](https://gitlab.com/wallforfry/dart_mercure/commits/master)
![Dart CI](https://github.com/wallforfry/dart_mercure/workflows/Dart%20CI/badge.svg)
[![pub package](https://img.shields.io/pub/v/dart_mercure.svg)](https://pub.dev/packages/dart_mercure)

- This library allow to communicate with dunglas/mercure.
- You can publish and subscribe to topic on Mercure Hub. 
- It can be easily integrate with other package for create firebase like notification system.

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

Please file feature requests and bugs at the issue tracker
