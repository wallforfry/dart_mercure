import 'package:dart_mercure/dart_mercure.dart';

main() {
  // Token generate with "mercure" JWT_KEY
  String token =
      "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJtZXJjdXJlIjp7InN1YnNjcmliZSI6WyIqIl0sInB1Ymxpc2giOlsiKiJdfX0.Gfj3BFrSOFhyFN0hPOYg-Pe4dfYWOKq7QJiMWYC2Z_k";
  String hub_url = "http://mercure/hub";
  String topic = "http://mercure/test";

  Mercure mercure = Mercure(token: token, hub_url: hub_url);
  mercure.subscribeTopics(
      topics: <String>[topic, "2"],
      onData: (Event event) {
        print(event.data);
      });

  mercure.subscribeTopic(
      topic: topic,
      onData: (Event event) {
        print(event.data);
      });

  mercure.publish(topic: topic, data: "DATA").then((status) {
    if (status == 200) {
      print("Message Sent");
    } else {
      print('Message Failed with code : $status');
    }
  });
}
